import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/live_audio_probe_rtc.dart';
import 'package:my_new_app/services/live_audio_probe_service.dart';
import 'package:my_new_app/services/live_audio_rtc_backend.dart';

void main() {
  test('joins and releases through the injected RTC backend', () async {
    final backend = _FakeLiveAudioRtcBackend();
    final controller = LiveAudioProbeRtcController(
      refreshToken: () async => _credentials,
      createBackend: () => backend,
    );

    await controller.join(_credentials);

    expect(backend.calls, [
      'initialize',
      'enableAudio',
      'setClientRole:true',
      'join:true',
      'createDataStream',
    ]);

    await controller.dispose();

    expect(backend.calls, containsAllInOrder(['leave', 'release']));
  });
}

const _credentials = LiveAudioProbeCredentials(
  appId: 'test-app-id',
  channelName: 'test-channel',
  rtcUid: 42,
  token: 'test-token',
  permission: LiveAudioProbePermission.publisher,
  expiresInSec: 3600,
);

class _FakeLiveAudioRtcBackend implements LiveAudioRtcBackend {
  final calls = <String>[];
  LiveAudioRtcEventHandler _handler = const LiveAudioRtcEventHandler();

  @override
  void setEventHandler(LiveAudioRtcEventHandler handler) {
    _handler = handler;
  }

  @override
  Future<void> initialize(String appId) async {
    calls.add('initialize');
  }

  @override
  Future<void> enableAudio() async {
    calls.add('enableAudio');
  }

  @override
  Future<void> setClientRole({required bool canPublish}) async {
    calls.add('setClientRole:$canPublish');
  }

  @override
  Future<void> join({
    required String token,
    required String channelName,
    required int uid,
    required bool canPublish,
  }) async {
    calls.add('join:$canPublish');
    _handler.onJoined?.call();
  }

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<int> createDataStream() async {
    calls.add('createDataStream');
    return 5;
  }

  @override
  Future<void> renewToken(String token) async {}

  @override
  Future<void> updateMediaOptions({required bool canPublish}) async {}

  @override
  Future<void> muteLocalAudioStream(bool muted) async {}

  @override
  Future<void> muteAllRemoteAudioStreams(bool muted) async {}

  @override
  Future<void> sendStreamMessage(int streamId, Uint8List data) async {}

  @override
  Future<void> leave() async {
    calls.add('leave');
  }

  @override
  Future<void> release() async {
    calls.add('release');
  }
}
