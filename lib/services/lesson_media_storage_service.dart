import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'lesson_media_file_picker.dart' as platform_picker;
import 'lesson_media_file_picker_error.dart';
import 'lesson_media_upload_stub.dart'
    if (dart.library.io) 'lesson_media_upload_io.dart'
    as platform_upload;

class LessonMediaStorageException implements Exception {
  LessonMediaStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LessonMediaUploadResult {
  const LessonMediaUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.contentType,
    required this.fileName,
  });

  final String downloadUrl;
  final String storagePath;
  final String contentType;
  final String fileName;
}

class LessonMediaStorageService {
  const LessonMediaStorageService();

  static const int maxBytes = 100 * 1024 * 1024;
  static const List<String> audioExtensions = ['mp3', 'm4a', 'aac', 'wav'];
  static const List<String> videoExtensions = ['mp4', 'webm', 'mov'];

  Reference lessonMediaRef({
    required String courseId,
    int? lessonNumber,
    String? lessonId,
    required String segmentId,
    required String fileName,
  }) {
    final lessonStorageKey = _lessonStorageKey(
      lessonNumber: lessonNumber,
      lessonId: lessonId,
    );
    return FirebaseStorage.instance.ref(
      'courseMedia/$courseId/lessons/$lessonStorageKey/segments/$segmentId/$fileName',
    );
  }

  String storagePath({
    required String courseId,
    int? lessonNumber,
    String? lessonId,
    required String segmentId,
    required String fileName,
  }) {
    final lessonStorageKey = _lessonStorageKey(
      lessonNumber: lessonNumber,
      lessonId: lessonId,
    );
    return 'courseMedia/$courseId/lessons/$lessonStorageKey/segments/$segmentId/$fileName';
  }

  List<String> allowedExtensionsForMediaType(String mediaType) {
    return mediaType == 'audio' ? audioExtensions : videoExtensions;
  }

  String contentTypeForExtension(String extension) {
    return switch (extension.toLowerCase()) {
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'mp4' => 'video/mp4',
      'webm' => 'video/webm',
      'mov' => 'video/quicktime',
      _ => 'application/octet-stream',
    };
  }

  String mediaTypeLabel(String mediaType) {
    return mediaType == 'audio' ? '音声' : '動画';
  }

  FileType pickerTypeForMediaType(String mediaType) {
    return mediaType == 'audio' ? FileType.audio : FileType.video;
  }

  Future<PlatformFile?> pickLessonMediaFile({required String mediaType}) async {
    final allowedExtensions = allowedExtensionsForMediaType(mediaType);
    final mediaLabel = mediaTypeLabel(mediaType);
    PlatformFile? pickedFile;
    try {
      pickedFile = await platform_picker.pickLessonMediaFileForPlatform(
        mediaLabel: mediaLabel,
        allowedExtensions: allowedExtensions,
        pickerType: pickerTypeForMediaType(mediaType),
        maxBytes: maxBytes,
      );
    } on LessonMediaFilePickerException catch (error) {
      throw LessonMediaStorageException(error.message);
    }
    if (pickedFile == null) {
      return null;
    }

    _validatePickedFile(pickedFile: pickedFile, mediaType: mediaType);
    return pickedFile;
  }

  void cancelActiveFilePicker() {
    platform_picker.cancelLessonMediaFilePickerForPlatform();
  }

  Future<LessonMediaUploadResult> uploadLessonMediaFile({
    required String courseId,
    int? lessonNumber,
    String? lessonId,
    required String segmentId,
    required String mediaType,
    required PlatformFile pickedFile,
    void Function(double progress)? onProgress,
  }) async {
    if (Firebase.apps.isEmpty) {
      throw LessonMediaStorageException('Firebase が初期化されていません。');
    }
    if (FirebaseAuth.instance.currentUser == null) {
      throw LessonMediaStorageException('ログインが必要です。');
    }
    if (courseId.isEmpty) {
      throw LessonMediaStorageException('講座IDがないためアップロードできません。');
    }
    final lessonStorageKey = _lessonStorageKey(
      lessonNumber: lessonNumber,
      lessonId: lessonId,
    );
    if (segmentId.trim().isEmpty) {
      throw LessonMediaStorageException('パートIDが不正です。');
    }

    _validatePickedFile(pickedFile: pickedFile, mediaType: mediaType);

    final originalName = pickedFile.name.trim();
    final extension = _fileExtension(originalName);
    final contentType = contentTypeForExtension(extension);
    final storedFileName =
        '${DateTime.now().millisecondsSinceEpoch}_$originalName';
    final ref = lessonMediaRef(
      courseId: courseId,
      lessonNumber: lessonNumber,
      lessonId: lessonId,
      segmentId: segmentId,
      fileName: storedFileName,
    );
    final metadata = SettableMetadata(
      contentType: contentType,
      customMetadata: {
        'courseId': courseId,
        'lessonStorageKey': lessonStorageKey,
        'segmentId': segmentId,
        'mediaType': mediaType,
        'originalFileName': originalName,
      },
    );

    final uploadTask = _startUpload(
      ref: ref,
      file: pickedFile,
      metadata: metadata,
    );
    final progressSubscription = onProgress == null
        ? null
        : uploadTask.snapshotEvents.listen((snapshot) {
            final totalBytes = snapshot.totalBytes;
            if (totalBytes <= 0) {
              return;
            }
            onProgress(snapshot.bytesTransferred / totalBytes);
          }, onError: (_) {});

    try {
      await uploadTask;
    } finally {
      await progressSubscription?.cancel();
    }
    final downloadUrl = await ref.getDownloadURL();

    return LessonMediaUploadResult(
      downloadUrl: downloadUrl,
      storagePath: storagePath(
        courseId: courseId,
        lessonNumber: lessonNumber,
        lessonId: lessonId,
        segmentId: segmentId,
        fileName: storedFileName,
      ),
      contentType: contentType,
      fileName: originalName,
    );
  }

  /// Deletes a previously uploaded file given its download URL.
  ///
  /// Used to clean up storage when a media part is removed or replaced with
  /// a new upload. This is best-effort: a missing file (already deleted, or
  /// never actually uploaded, e.g. a URL that isn't a Storage URL) is
  /// silently ignored so cleanup never blocks the caller's main action.
  Future<void> deleteFileAtUrl(String url) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || Firebase.apps.isEmpty) {
      return;
    }
    try {
      final ref = FirebaseStorage.instance.refFromURL(trimmedUrl);
      await ref.delete();
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') {
        return;
      }
      rethrow;
    }
  }

  Future<LessonMediaUploadResult?> pickAndUploadLessonMedia({
    required String courseId,
    int? lessonNumber,
    String? lessonId,
    required String segmentId,
    required String mediaType,
    void Function(double progress)? onProgress,
  }) async {
    final pickedFile = await pickLessonMediaFile(mediaType: mediaType);
    if (pickedFile == null) {
      return null;
    }
    return uploadLessonMediaFile(
      courseId: courseId,
      lessonNumber: lessonNumber,
      lessonId: lessonId,
      segmentId: segmentId,
      mediaType: mediaType,
      pickedFile: pickedFile,
      onProgress: onProgress,
    );
  }

  String _lessonStorageKey({int? lessonNumber, String? lessonId}) {
    final normalizedId = lessonId?.trim() ?? '';
    if (normalizedId.isNotEmpty) {
      if (normalizedId.contains('/')) {
        throw LessonMediaStorageException('レッスンIDが不正です。');
      }
      return normalizedId;
    }
    if (lessonNumber == null || lessonNumber <= 0) {
      throw LessonMediaStorageException('レッスンIDまたは番号が不正です。');
    }
    return '$lessonNumber';
  }

  void _validatePickedFile({
    required PlatformFile pickedFile,
    required String mediaType,
  }) {
    final allowedExtensions = allowedExtensionsForMediaType(mediaType);
    final originalName = pickedFile.name.trim();
    if (originalName.isEmpty) {
      throw LessonMediaStorageException('ファイル名を取得できませんでした。');
    }

    final extension = _fileExtension(originalName);
    if (!allowedExtensions.contains(extension)) {
      throw LessonMediaStorageException(
        '${mediaTypeLabel(mediaType)}ファイル（${allowedExtensions.join(' / ')}）を選んでください。',
      );
    }

    final fileSize = pickedFile.size;
    if (fileSize <= 0) {
      throw LessonMediaStorageException('ファイルサイズを取得できませんでした。');
    }
    if (fileSize > maxBytes) {
      throw LessonMediaStorageException('ファイルサイズは100MB以下にしてください。');
    }
  }

  UploadTask _startUpload({
    required Reference ref,
    required PlatformFile file,
    required SettableMetadata metadata,
  }) {
    final bytes = file.bytes;
    if (bytes != null) {
      return ref.putData(bytes, metadata);
    }
    final path = file.path;
    if (!kIsWeb && path != null && path.isNotEmpty) {
      return platform_upload.putPlatformFile(ref, path, metadata);
    }
    throw LessonMediaStorageException('ファイルを読み取れませんでした。');
  }

  String _fileExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dotIndex + 1).toLowerCase();
  }
}
