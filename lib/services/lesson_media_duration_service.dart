import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';

class LessonMediaDurationService {
  const LessonMediaDurationService();

  Future<int?> detectDurationSec(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final player = AudioPlayer();
    try {
      final duration = await player.setAudioSource(
        AudioSource.uri(
          Uri.dataFromBytes(bytes, mimeType: _mimeTypeForFileName(file.name)),
        ),
      );
      final seconds = duration?.inSeconds ?? player.duration?.inSeconds ?? 0;
      return seconds > 0 ? seconds : null;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  String _mimeTypeForFileName(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return 'application/octet-stream';
    }
    return switch (fileName.substring(dotIndex + 1).toLowerCase()) {
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
}
