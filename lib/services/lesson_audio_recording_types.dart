import 'package:file_picker/file_picker.dart';

abstract interface class LessonAudioRecordingController {
  Future<bool> hasPermission();

  Future<void> start();

  Future<void> pause();

  Future<void> resume();

  Future<PlatformFile?> stop();

  Future<void> cancel();

  Future<void> deleteRecording(PlatformFile file);

  Future<void> dispose();
}
