import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/lesson_material_storage_service.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('picks a PDF without loading duplicate native bytes', () async {
    final picker = _FakePdfFilePicker(
      result: FilePickerResult([
        PlatformFile(
          name: 'lesson.pdf',
          size: 4,
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
      ]),
    );
    final service = LessonMaterialStorageService(
      filePicker: picker,
      pdfDocumentOpener: (_, _) => Completer<PdfDocument>().future,
      pdfDocumentOpenTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      service.pickPdf(),
      throwsA(
        isA<LessonMaterialStorageException>().having(
          (error) => error.message,
          'message',
          contains('PDFの解析に時間がかかりすぎています'),
        ),
      ),
    );

    expect(picker.requestedWithData, isFalse);
  });

  test('times out when Android never returns a processed PDF', () async {
    final picker = _FakePdfFilePicker(neverCompletes: true);
    final service = LessonMaterialStorageService(
      filePicker: picker,
      pdfPickerProcessingTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      service.pickPdf(),
      throwsA(
        isA<LessonMaterialStorageException>().having(
          (error) => error.message,
          'message',
          contains('PDFの受け取りに時間がかかっています'),
        ),
      ),
    );
  });
}

class _FakePdfFilePicker extends FilePicker {
  _FakePdfFilePicker({this.result, this.neverCompletes = false});

  final FilePickerResult? result;
  final bool neverCompletes;
  bool? requestedWithData;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) {
    requestedWithData = withData;
    onFileLoading?.call(FilePickerStatus.picking);
    if (neverCompletes) {
      return Completer<FilePickerResult?>().future;
    }
    onFileLoading?.call(FilePickerStatus.done);
    return Future<FilePickerResult?>.value(result);
  }
}
