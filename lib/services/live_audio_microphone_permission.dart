import 'package:record/record.dart';

typedef LiveAudioMicrophonePermissionRequest = Future<bool> Function();

class LiveAudioMicrophonePermissionException implements Exception {
  const LiveAudioMicrophonePermissionException();

  @override
  String toString() => 'ライブ配信にはマイクの許可が必要です。端末の設定からマイクを許可してください。';
}

Future<void> ensureLiveAudioMicrophonePermission({
  LiveAudioMicrophonePermissionRequest? request,
}) async {
  final granted = request == null
      ? await _requestPlatformMicrophonePermission()
      : await request();
  if (!granted) {
    throw const LiveAudioMicrophonePermissionException();
  }
}

Future<bool> _requestPlatformMicrophonePermission() async {
  final recorder = AudioRecorder();
  try {
    return await recorder.hasPermission();
  } finally {
    await recorder.dispose();
  }
}
