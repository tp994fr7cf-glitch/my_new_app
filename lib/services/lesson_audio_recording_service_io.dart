import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'lesson_audio_recording_types.dart';

LessonAudioRecordingController createPlatformLessonAudioRecordingController() {
  return DeviceLessonAudioRecordingController();
}

class DeviceLessonAudioRecordingController
    implements LessonAudioRecordingController {
  DeviceLessonAudioRecordingController({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  static const RecordConfig _recordConfig = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 96000,
    sampleRate: 44100,
    numChannels: 1,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
  );

  final AudioRecorder _recorder;
  String? _activePath;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final directory = await getTemporaryDirectory();
    final recordingDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}lesson_recordings',
    );
    await recordingDirectory.create(recursive: true);
    final fileName =
        'lesson_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final path = '${recordingDirectory.path}${Platform.pathSeparator}$fileName';
    _activePath = path;
    await _recorder.start(_recordConfig, path: path);
  }

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<PlatformFile?> stop() async {
    final stoppedPath = await _recorder.stop();
    final path = stoppedPath ?? _activePath;
    _activePath = null;
    if (path == null || path.isEmpty) {
      return null;
    }
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final size = await file.length();
    return PlatformFile(
      name: path.split(Platform.pathSeparator).last,
      path: path,
      size: size,
    );
  }

  @override
  Future<void> cancel() async {
    final path = _activePath;
    _activePath = null;
    await _recorder.cancel();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  @override
  Future<void> deleteRecording(PlatformFile file) async {
    final path = file.path;
    if (path == null || path.isEmpty) {
      return;
    }
    final recordedFile = File(path);
    if (await recordedFile.exists()) {
      await recordedFile.delete();
    }
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
