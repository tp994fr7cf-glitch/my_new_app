import 'package:just_audio/just_audio.dart';

import 'lesson_audio_recording_types.dart';
import 'lesson_audio_recording_service_stub.dart'
    if (dart.library.io) 'lesson_audio_recording_service_io.dart'
    as platform;

export 'lesson_audio_recording_types.dart';

LessonAudioRecordingController createLessonAudioRecordingController() {
  return platform.createPlatformLessonAudioRecordingController();
}

abstract interface class LessonAudioPreviewController {
  bool get isPlaying;

  Stream<bool> get playingStream;

  Future<Duration?> load(String path);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> dispose();
}

LessonAudioPreviewController createLessonAudioPreviewController() {
  return JustAudioLessonAudioPreviewController();
}

class JustAudioLessonAudioPreviewController
    implements LessonAudioPreviewController {
  final AudioPlayer _player = AudioPlayer();

  @override
  bool get isPlaying => _player.playing;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Future<Duration?> load(String path) => _player.setFilePath(path);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
