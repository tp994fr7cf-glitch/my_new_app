import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/services/live_audio_probe_message.dart';
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

  test('paces sends and keeps only the latest queued stroke point', () async {
    final firstSendGate = Completer<void>();
    final backend = _FakeLiveAudioRtcBackend()..nextSendGate = firstSendGate;
    final controller = LiveAudioProbeRtcController(
      refreshToken: () async => _credentials,
      createBackend: () => backend,
      dataStreamSendInterval: const Duration(milliseconds: 10),
    );
    await controller.join(_credentials);

    final stopwatch = Stopwatch()..start();
    final sends = [
      controller.sendWhiteboardMessage(
        const LiveAudioProbeMessage(
          kind: LiveAudioProbeMessageKind.strokeStart,
          strokeId: 'stroke-1',
          timestampSec: 1,
        ),
      ),
      controller.sendWhiteboardMessage(
        const LiveAudioProbeMessage(
          kind: LiveAudioProbeMessageKind.strokePoint,
          strokeId: 'stroke-1',
          timestampSec: 1.01,
          point: WhiteboardPoint(x: 0.1, y: 0.1),
        ),
      ),
      controller.sendWhiteboardMessage(
        const LiveAudioProbeMessage(
          kind: LiveAudioProbeMessageKind.strokePoint,
          strokeId: 'stroke-1',
          timestampSec: 1.02,
          point: WhiteboardPoint(x: 0.2, y: 0.2),
        ),
      ),
      controller.sendWhiteboardMessage(
        const LiveAudioProbeMessage(
          kind: LiveAudioProbeMessageKind.strokePoint,
          strokeId: 'stroke-1',
          timestampSec: 1.03,
          point: WhiteboardPoint(x: 0.3, y: 0.3),
        ),
      ),
      controller.sendWhiteboardMessage(
        const LiveAudioProbeMessage(
          kind: LiveAudioProbeMessageKind.strokeEnd,
          strokeId: 'stroke-1',
          timestampSec: 1.04,
          point: WhiteboardPoint(x: 0.4, y: 0.4),
        ),
      ),
    ];

    await Future<void>.delayed(Duration.zero);
    expect(backend.sentMessages, hasLength(1));
    firstSendGate.complete();
    await Future.wait(sends);
    stopwatch.stop();

    final decoded = backend.sentMessages
        .map(LiveAudioProbeMessage.tryDecode)
        .whereType<LiveAudioProbeMessage>()
        .toList();
    expect(decoded.map((message) => message.kind), [
      LiveAudioProbeMessageKind.strokeStart,
      LiveAudioProbeMessageKind.strokePoint,
      LiveAudioProbeMessageKind.strokeEnd,
    ]);
    expect(decoded[1].point?.x, 0.3);
    expect(backend.maximumConcurrentSends, 1);
    expect(
      stopwatch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 20)),
    );

    await controller.dispose();
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
  final sentMessages = <Uint8List>[];
  Completer<void>? nextSendGate;
  int concurrentSends = 0;
  int maximumConcurrentSends = 0;
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
  Future<void> sendStreamMessage(int streamId, Uint8List data) async {
    concurrentSends += 1;
    if (concurrentSends > maximumConcurrentSends) {
      maximumConcurrentSends = concurrentSends;
    }
    sentMessages.add(Uint8List.fromList(data));
    final gate = nextSendGate;
    nextSendGate = null;
    try {
      await gate?.future;
    } finally {
      concurrentSends -= 1;
    }
  }

  @override
  Future<void> leave() async {
    calls.add('leave');
  }

  @override
  Future<void> release() async {
    calls.add('release');
  }
}
