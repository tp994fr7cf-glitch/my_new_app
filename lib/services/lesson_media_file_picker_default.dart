import 'package:file_picker/file_picker.dart';

Future<PlatformFile?> pickLessonMediaFileForPlatform({
  required String mediaLabel,
  required List<String> allowedExtensions,
  required FileType pickerType,
  required int maxBytes,
}) async {
  final pickResult = await FilePicker.platform.pickFiles(
    type: pickerType,
    allowMultiple: false,
    withData: false,
    dialogTitle: '$mediaLabelファイルを選択',
  );
  if (pickResult == null || pickResult.files.isEmpty) {
    return null;
  }
  return pickResult.files.single;
}

void cancelLessonMediaFilePickerForPlatform() {}
