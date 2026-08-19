import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/lesson_whiteboard_board_set.dart';

class LessonMaterialStorageException implements Exception {
  const LessonMaterialStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PickedLessonPdf {
  PickedLessonPdf({
    required this.fileName,
    required this.bytes,
    required this.document,
  });

  final String fileName;
  final Uint8List bytes;
  final PdfDocument document;

  Future<void> dispose() => document.dispose();
}

class PickedLessonImage {
  const PickedLessonImage({
    required this.fileName,
    required this.bytes,
    required this.contentType,
    required this.aspectRatio,
  });

  final String fileName;
  final Uint8List bytes;
  final String contentType;
  final double aspectRatio;
}

class LessonMaterialUploadResult {
  const LessonMaterialUploadResult({
    required this.backgrounds,
    required this.titles,
  });

  final List<LessonWhiteboardBoardBackground> backgrounds;
  final List<String> titles;
}

typedef LessonPdfDocumentOpener =
    Future<PdfDocument> Function(Uint8List bytes, String sourceName);

class LessonMaterialStorageService {
  const LessonMaterialStorageService({
    this.filePicker,
    this.pdfDocumentOpener,
    this.pdfPickerProcessingTimeout = const Duration(seconds: 20),
    this.pdfBytesReadTimeout = const Duration(seconds: 20),
    this.pdfDocumentOpenTimeout = const Duration(seconds: 20),
  });

  static const int maxBytes = 50 * 1024 * 1024;
  static const List<String> imageExtensions = ['jpg', 'jpeg', 'png', 'webp'];
  static int _assetSequence = 0;

  final FilePicker? filePicker;
  final LessonPdfDocumentOpener? pdfDocumentOpener;
  final Duration pdfPickerProcessingTimeout;
  final Duration pdfBytesReadTimeout;
  final Duration pdfDocumentOpenTimeout;

  Future<PickedLessonPdf?> pickPdf() async {
    debugPrint('[LessonMaterialPdf] Opening the system file picker.');
    final processingStarted = Completer<void>();
    final resultFuture = (filePicker ?? FilePicker.platform).pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: false,
      onFileLoading: (status) {
        debugPrint('[LessonMaterialPdf] File picker status: ${status.name}.');
        if (status == FilePickerStatus.picking &&
            !processingStarted.isCompleted) {
          processingStarted.complete();
        }
      },
    );
    final result = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? await Future.any<FilePickerResult?>([
            resultFuture,
            processingStarted.future.then<FilePickerResult?>(
              (_) => Future<FilePickerResult?>.delayed(
                pdfPickerProcessingTimeout,
                () => throw const LessonMaterialStorageException(
                  'PDFの受け取りに時間がかかっています。'
                  'アプリを開き直してから、もう一度お試しください。',
                ),
              ),
            ),
          ])
        : await resultFuture;
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final file = result.files.single;
    _validateSize(file.size);
    debugPrint(
      '[LessonMaterialPdf] File picker completed (${file.size} bytes).',
    );
    final bytes = await _readPlatformFile(file).timeout(
      pdfBytesReadTimeout,
      onTimeout: () => throw const LessonMaterialStorageException(
        '端末からPDFを読み込めませんでした。'
        'アプリを開き直してから、もう一度お試しください。',
      ),
    );
    debugPrint('[LessonMaterialPdf] PDF bytes loaded (${bytes.length} bytes).');
    return _openPdfFromBytes(fileName: file.name, bytes: bytes);
  }

  Future<PickedLessonPdf> openPdfFromStorage({
    required String storagePath,
    required String fileName,
  }) async {
    final bytes = await _downloadStorageBytes(storagePath);
    return _openPdfFromBytes(fileName: fileName, bytes: bytes);
  }

  Future<PickedLessonImage> openImageFromStorage({
    required String storagePath,
    required String fileName,
  }) async {
    final bytes = await _downloadStorageBytes(storagePath);
    final resolvedName = _fileExtension(fileName).isNotEmpty
        ? fileName
        : '$fileName.${_fileExtension(storagePath)}';
    return _imageFromBytes(resolvedName, bytes);
  }

  Future<List<PickedLessonImage>> pickImageFiles({
    required int maximumCount,
  }) async {
    if (maximumCount <= 0) {
      return const [];
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: imageExtensions,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) {
      return const [];
    }
    if (result.files.length > maximumCount) {
      throw LessonMaterialStorageException('追加できる画像は残り$maximumCount枚です。');
    }
    return Future.wait(result.files.map(_platformFileToImage));
  }

  Future<List<PickedLessonImage>> pickGalleryImages({
    required int maximumCount,
  }) async {
    if (maximumCount <= 0) {
      return const [];
    }
    final files = await ImagePicker().pickMultiImage(
      limit: maximumCount,
      requestFullMetadata: false,
    );
    return Future.wait(
      files.map((file) async {
        final bytes = await file.readAsBytes();
        _validateSize(bytes.length);
        return _imageFromBytes(file.name, bytes);
      }),
    );
  }

  Future<LessonMaterialUploadResult> uploadSelectedPdfPages({
    required String courseId,
    required String lessonId,
    required PickedLessonPdf pickedPdf,
    required List<int> selectedPageNumbers,
  }) async {
    _validateUploadContext(courseId: courseId, lessonId: lessonId);
    final pages = selectedPageNumbers.toSet().toList()..sort();
    if (pages.isEmpty) {
      throw const LessonMaterialStorageException('共有するページを選んでください。');
    }
    if (pages.length > maxLessonWhiteboardBoards ||
        pages.any(
          (pageNumber) =>
              pageNumber < 1 || pageNumber > pickedPdf.document.pages.length,
        )) {
      throw const LessonMaterialStorageException('PDFのページ選択が不正です。');
    }

    final assetId = _newAssetId();
    final sharedDocument = await PdfDocument.createNew(
      sourceName: '$assetId-selected.pdf',
    );
    Uint8List sharedBytes;
    try {
      sharedDocument.pages = [
        for (final pageNumber in pages)
          pickedPdf.document.pages[pageNumber - 1],
      ];
      sharedBytes = await sharedDocument.encodePdf();
    } finally {
      await sharedDocument.dispose();
    }
    _validateSize(sharedBytes.length);

    final sourcePath = _materialPath(
      courseId: courseId,
      lessonId: lessonId,
      assetId: assetId,
      relativePath: 'source/original.pdf',
    );
    final sharedPath = _materialPath(
      courseId: courseId,
      lessonId: lessonId,
      assetId: assetId,
      relativePath: 'shared/selected.pdf',
    );
    await _uploadSourceAndShared(
      sourcePath: sourcePath,
      sourceBytes: pickedPdf.bytes,
      sourceContentType: 'application/pdf',
      sharedPath: sharedPath,
      sharedBytes: sharedBytes,
      sharedContentType: 'application/pdf',
      metadata: {
        'courseId': courseId,
        'lessonId': lessonId,
        'assetId': assetId,
        'originalFileName': pickedPdf.fileName,
        'selectedPages': pages.join(','),
      },
    );

    return LessonMaterialUploadResult(
      backgrounds: [
        for (final entry in pages.indexed)
          LessonWhiteboardBoardBackground(
            assetId: assetId,
            storagePath: sharedPath,
            mediaType: lessonWhiteboardBackgroundPdf,
            pageNumber: entry.$1 + 1,
            aspectRatio: _pdfPageAspectRatio(
              pickedPdf.document.pages[entry.$2 - 1],
            ),
          ),
      ],
      titles: [for (final pageNumber in pages) 'PDF $pageNumberページ'],
    );
  }

  Future<LessonMaterialUploadResult> uploadImages({
    required String courseId,
    required String lessonId,
    required List<PickedLessonImage> images,
  }) async {
    _validateUploadContext(courseId: courseId, lessonId: lessonId);
    if (images.isEmpty) {
      return const LessonMaterialUploadResult(backgrounds: [], titles: []);
    }
    final backgrounds = <LessonWhiteboardBoardBackground>[];
    final titles = <String>[];
    for (final pickedImage in images) {
      final assetId = _newAssetId();
      final extension = _extensionForContentType(pickedImage.contentType);
      final sourcePath = _materialPath(
        courseId: courseId,
        lessonId: lessonId,
        assetId: assetId,
        relativePath: 'source/original.$extension',
      );
      final sharedPath = _materialPath(
        courseId: courseId,
        lessonId: lessonId,
        assetId: assetId,
        relativePath: 'shared/image.$extension',
      );
      await _uploadSourceAndShared(
        sourcePath: sourcePath,
        sourceBytes: pickedImage.bytes,
        sourceContentType: pickedImage.contentType,
        sharedPath: sharedPath,
        sharedBytes: pickedImage.bytes,
        sharedContentType: pickedImage.contentType,
        metadata: {
          'courseId': courseId,
          'lessonId': lessonId,
          'assetId': assetId,
          'originalFileName': pickedImage.fileName,
        },
      );
      backgrounds.add(
        LessonWhiteboardBoardBackground(
          assetId: assetId,
          storagePath: sharedPath,
          mediaType: lessonWhiteboardBackgroundImage,
          aspectRatio: pickedImage.aspectRatio,
        ),
      );
      titles.add(pickedImage.fileName);
    }
    return LessonMaterialUploadResult(backgrounds: backgrounds, titles: titles);
  }

  Future<void> deleteMaterialAsset(
    LessonWhiteboardBoardBackground background,
  ) async {
    final marker = '/materials/${background.assetId}/';
    final markerIndex = background.storagePath.indexOf(marker);
    if (!background.storagePath.startsWith('courseMedia/') || markerIndex < 0) {
      return;
    }
    final assetRoot = background.storagePath.substring(
      0,
      markerIndex + marker.length,
    );
    final result = await FirebaseStorage.instance.ref(assetRoot).listAll();
    await Future.wait(result.items.map((item) => item.delete()));
    for (final prefix in result.prefixes) {
      final nested = await prefix.listAll();
      await Future.wait(nested.items.map((item) => item.delete()));
    }
  }

  Future<PickedLessonImage> _platformFileToImage(PlatformFile file) async {
    _validateSize(file.size);
    return _imageFromBytes(file.name, await _readPlatformFile(file));
  }

  PickedLessonImage _imageFromBytes(String fileName, Uint8List bytes) {
    final decoded = image_lib.decodeImage(bytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw const LessonMaterialStorageException('画像を読み込めませんでした。');
    }
    final contentType = switch (_fileExtension(fileName)) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw const LessonMaterialStorageException(
        'JPG・PNG・WebP画像を選んでください。',
      ),
    };
    return PickedLessonImage(
      fileName: fileName,
      bytes: bytes,
      contentType: contentType,
      aspectRatio: decoded.width / decoded.height,
    );
  }

  Future<Uint8List> _readPlatformFile(PlatformFile file) async {
    final bytes = file.bytes ?? await file.xFile.readAsBytes();
    _validateSize(bytes.length);
    return bytes;
  }

  Future<PickedLessonPdf> _openPdfFromBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    _validateSize(bytes.length);
    try {
      debugPrint('[LessonMaterialPdf] Opening the PDF document.');
      final opening =
          pdfDocumentOpener?.call(bytes, fileName) ??
          PdfDocument.openData(bytes, sourceName: fileName);
      late final PdfDocument document;
      try {
        document = await opening.timeout(pdfDocumentOpenTimeout);
      } on TimeoutException {
        unawaited(
          opening
              .then<void>((lateDocument) => lateDocument.dispose())
              .catchError((_) {}),
        );
        throw const LessonMaterialStorageException(
          'PDFの解析に時間がかかりすぎています。'
          'アプリを開き直してから、もう一度お試しください。',
        );
      }
      if (document.pages.isEmpty) {
        await document.dispose();
        throw const LessonMaterialStorageException('ページがないPDFは追加できません。');
      }
      debugPrint(
        '[LessonMaterialPdf] PDF document opened '
        '(${document.pages.length} pages).',
      );
      return PickedLessonPdf(
        fileName: fileName,
        bytes: bytes,
        document: document,
      );
    } catch (error) {
      if (error is LessonMaterialStorageException) {
        rethrow;
      }
      throw const LessonMaterialStorageException(
        'PDFを開けませんでした。パスワード付きPDFや破損したPDFは追加できません。',
      );
    }
  }

  Future<Uint8List> _downloadStorageBytes(String storagePath) async {
    if (storagePath.trim().isEmpty ||
        !storagePath.startsWith('courseMedia/') ||
        storagePath.contains('..')) {
      throw const LessonMaterialStorageException('資料の保存場所が不正です。');
    }
    if (Firebase.apps.isEmpty) {
      throw const LessonMaterialStorageException('Firebase が初期化されていません。');
    }
    try {
      final data = await FirebaseStorage.instance
          .ref(storagePath)
          .getData(maxBytes);
      if (data == null) {
        throw const LessonMaterialStorageException('保存済み資料を読み込めませんでした。');
      }
      _validateSize(data.length);
      return data;
    } on LessonMaterialStorageException {
      rethrow;
    } catch (_) {
      throw const LessonMaterialStorageException(
        '保存済み資料を読み込めませんでした。時間をおいて再度お試しください。',
      );
    }
  }

  Future<void> _uploadSourceAndShared({
    required String sourcePath,
    required Uint8List sourceBytes,
    required String sourceContentType,
    required String sharedPath,
    required Uint8List sharedBytes,
    required String sharedContentType,
    required Map<String, String> metadata,
  }) async {
    final sourceRef = FirebaseStorage.instance.ref(sourcePath);
    final sharedRef = FirebaseStorage.instance.ref(sharedPath);
    try {
      await sourceRef.putData(
        sourceBytes,
        SettableMetadata(
          contentType: sourceContentType,
          customMetadata: {...metadata, 'visibility': 'teacher'},
        ),
      );
      await sharedRef.putData(
        sharedBytes,
        SettableMetadata(
          contentType: sharedContentType,
          customMetadata: {...metadata, 'visibility': 'learners'},
        ),
      );
    } catch (_) {
      await Future.wait([
        sourceRef.delete().catchError((_) {}),
        sharedRef.delete().catchError((_) {}),
      ]);
      rethrow;
    }
  }

  void _validateUploadContext({
    required String courseId,
    required String lessonId,
  }) {
    if (Firebase.apps.isEmpty) {
      throw const LessonMaterialStorageException('Firebase が初期化されていません。');
    }
    if (FirebaseAuth.instance.currentUser == null) {
      throw const LessonMaterialStorageException('ログインが必要です。');
    }
    if (courseId.trim().isEmpty ||
        courseId.contains('/') ||
        lessonId.trim().isEmpty ||
        lessonId.contains('/')) {
      throw const LessonMaterialStorageException('講座またはレッスンのIDが不正です。');
    }
  }

  void _validateSize(int size) {
    if (size <= 0) {
      throw const LessonMaterialStorageException('空のファイルは追加できません。');
    }
    if (size > maxBytes) {
      throw const LessonMaterialStorageException('PDF・画像は1ファイル50MB以下にしてください。');
    }
  }

  double _pdfPageAspectRatio(PdfPage page) {
    final rotated = page.rotation.index.isOdd;
    final width = rotated ? page.height : page.width;
    final height = rotated ? page.width : page.height;
    return width / height;
  }

  String _materialPath({
    required String courseId,
    required String lessonId,
    required String assetId,
    required String relativePath,
  }) {
    return 'courseMedia/$courseId/lessons/$lessonId/materials/'
        '$assetId/$relativePath';
  }

  String _newAssetId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    return 'material-$micros-${_assetSequence++}';
  }

  String _extensionForContentType(String contentType) {
    return switch (contentType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => throw const LessonMaterialStorageException('画像形式が不正です。'),
    };
  }

  String _fileExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot + 1).toLowerCase();
  }
}
