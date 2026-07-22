import 'package:file_picker/file_picker.dart';

import 'lesson_audio_recording_types.dart';

LessonAudioRecordingController createPlatformLessonAudioRecordingController() {
  return _UnsupportedLessonAudioRecordingController();
}

class _UnsupportedLessonAudioRecordingController
    implements LessonAudioRecordingController {
  UnsupportedError _unsupported() {
    return UnsupportedError('この端末では音声録音を利用できません。');
  }

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<void> start() async => throw _unsupported();

  @override
  Future<void> pause() async => throw _unsupported();

  @override
  Future<void> resume() async => throw _unsupported();

  @override
  Future<PlatformFile?> stop() async => null;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> deleteRecording(PlatformFile file) async {}

  @override
  Future<void> dispose() async {}
}
