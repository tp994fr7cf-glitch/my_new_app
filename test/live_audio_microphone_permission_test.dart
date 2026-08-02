import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/live_audio_microphone_permission.dart';

void main() {
  test('continues when microphone permission is granted', () async {
    await ensureLiveAudioMicrophonePermission(request: () async => true);
  });

  test('stops before broadcast when microphone permission is denied', () async {
    await expectLater(
      ensureLiveAudioMicrophonePermission(request: () async => false),
      throwsA(isA<LiveAudioMicrophonePermissionException>()),
    );
  });
}
