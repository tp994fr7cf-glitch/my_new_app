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

  test('waits for presenter role confirmation before sending data', () async {
    final backend = _FakeLiveAudioRtcBackend();
    final controller = LiveAudioProbeRtcController(
      refreshToken: () async => _credentials,
      createBackend: () => backend,
    );
    await controller.join(_subscriberCredentials);

    var applyCompleted = false;
    final applying = controller
        .applyCredentials(_credentials)
        .whenComplete(() => applyCompleted = true);
    await Future<void>.delayed(Duration.zero);

    expect(backend.calls, contains('setClientRole:true'));
    expect(applyCompleted, isFalse);
    expect(backend.calls, isNot(contains('createDataStream')));

    backend.emitClientRoleChanged(true);
    await applying;
    expect(backend.calls, contains('createDataStream'));

    await controller.sendWhiteboardMessage(
      const LiveAudioProbeMessage(
        kind: LiveAudioProbeMessageKind.boardSwitch,
        boardId: 'board-1',
        timestampSec: 1,
      ),
    );
    expect(backend.sentMessages, hasLength(1));
    await controller.dispose();
  });

  test(
    'ignores an in-flight send failure while leaving presenter role',
    () async {
      final sendGate = Completer<void>();
      final backend = _FakeLiveAudioRtcBackend()
        ..nextSendGate = sendGate
        ..nextSendError = StateError('Agora sendStreamMessage failed: -9');
      final controller = LiveAudioProbeRtcController(
        refreshToken: () async => _subscriberCredentials,
        createBackend: () => backend,
      );
      await controller.join(_credentials);

      final send = controller.sendWhiteboardMessage(
        const LiveAudioProbeMessage(
          kind: LiveAudioProbeMessageKind.boardSwitch,
          boardId: 'board-1',
          timestampSec: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final applying = controller.applyCredentials(_subscriberCredentials);

      sendGate.complete();
      await send;
      for (var attempt = 0; attempt < 10; attempt += 1) {
        if (backend.calls.contains('setClientRole:false')) {
          break;
        }
        await Future<void>.delayed(Duration.zero);
      }
      backend.emitClientRoleChanged(false);
      await applying;

      expect(backend.calls, contains('setClientRole:false'));
      await controller.dispose();
    },
  );

  test('silences playback without unsubscribing from remote audio', () async {
    final backend = _FakeLiveAudioRtcBackend();
    final controller = LiveAudioProbeRtcController(
      refreshToken: () async => _credentials,
      createBackend: () => backend,
    );
    await controller.join(_credentials);

    await controller.setLiveAudioMuted(true);
    await controller.setLiveAudioMuted(false);

    expect(backend.playbackVolumes, [0, 100]);
    await controller.dispose();
  });

  test('reads the Agora NTP wall clock from the active RTC engine', () async {
    final backend = _FakeLiveAudioRtcBackend();
    final controller = LiveAudioProbeRtcController(
      refreshToken: () async => _credentials,
      createBackend: () => backend,
    );
    await controller.join(_credentials);

    expect(await controller.getNtpWallTimeInMs(), 1785775079412);
    await controller.dispose();
  });

  test('waits for the first captured Agora audio frame time', () async {
    final backend = _FakeLiveAudioRtcBackend();
    final controller = LiveAudioProbeRtcController(
      refreshToken: () async => _credentials,
      createBackend: () => backend,
    );
    await controller.join(_credentials);

    final timestamp = controller.waitForAudioCaptureStartNtpTimeInMs(
      timeout: const Duration(milliseconds: 200),
      pollInterval: const Duration(milliseconds: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    backend.audioCaptureStartNtpMs = 1785775078123;

    expect(await timestamp, 1785775078123);
    await controller.dispose();
  });

  test('waits for the existing RTC connection to recover', () async {
    final backend = _FakeLiveAudioRtcBackend();
    final controller = LiveAudioProbeRtcController(
      refreshToken: () async => _credentials,
      createBackend: () => backend,
    );
    await controller.join(_credentials);
    backend.connected = false;

    final recovered = controller.waitUntilConnected(
      timeout: const Duration(milliseconds: 200),
      pollInterval: const Duration(milliseconds: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    backend.connected = true;

    expect(await recovered, isTrue);
    await controller.dispose();
  });

  test('data timeout does not overwrite a reconnecting RTC state', () async {
    final backend = _FakeLiveAudioRtcBackend();
    final controller = LiveAudioProbeRtcController(
      refreshToken: () async => _credentials,
      createBackend: () => backend,
    );
    final statuses = <LiveAudioProbeRtcStatus>[];
    final subscription = controller.statuses.listen(statuses.add);
    await controller.join(_credentials);

    backend.emitConnectionInterrupted();
    backend.emitStreamMessageTimeout();
    await Future<void>.delayed(Duration.zero);

    expect(statuses.last.state, LiveAudioProbeRtcState.reconnecting);
    expect(statuses.last.message, contains('117'));
    await subscription.cancel();
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

const _subscriberCredentials = LiveAudioProbeCredentials(
  appId: 'test-app-id',
  channelName: 'test-channel',
  rtcUid: 42,
  token: 'subscriber-token',
  permission: LiveAudioProbePermission.subscriber,
  expiresInSec: 3600,
);

class _FakeLiveAudioRtcBackend implements LiveAudioRtcBackend {
  final calls = <String>[];
  final sentMessages = <Uint8List>[];
  final playbackVolumes = <int>[];
  Completer<void>? nextSendGate;
  Object? nextSendError;
  int concurrentSends = 0;
  int maximumConcurrentSends = 0;
  bool connected = true;
  int? audioCaptureStartNtpMs;
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
  Future<bool> isConnected() async => connected;

  @override
  Future<int> getNtpWallTimeInMs() async => 1785775079412;

  @override
  Future<int?> getAudioCaptureStartNtpTimeInMs() async =>
      audioCaptureStartNtpMs;

  @override
  Future<int> createDataStream() async {
    calls.add('createDataStream');
    return 5;
  }

  @override
  Future<void> renewToken(String token) async {}

  @override
  Future<void> updateMediaOptions({required bool canPublish}) async {
    calls.add('updateMediaOptions:$canPublish');
  }

  @override
  Future<void> muteLocalAudioStream(bool muted) async {}

  @override
  Future<void> adjustPlaybackSignalVolume(int volume) async {
    playbackVolumes.add(volume);
  }

  @override
  Future<void> sendStreamMessage(int streamId, Uint8List data) async {
    concurrentSends += 1;
    if (concurrentSends > maximumConcurrentSends) {
      maximumConcurrentSends = concurrentSends;
    }
    sentMessages.add(Uint8List.fromList(data));
    final gate = nextSendGate;
    nextSendGate = null;
    final error = nextSendError;
    nextSendError = null;
    try {
      await gate?.future;
      if (error != null) {
        throw error;
      }
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

  void emitConnectionInterrupted() {
    connected = false;
    _handler.onConnectionInterrupted?.call();
  }

  void emitStreamMessageTimeout() {
    _handler.onStreamMessageError?.call('117', 0);
  }

  void emitClientRoleChanged(bool canPublish) {
    _handler.onClientRoleChanged?.call(canPublish);
  }
}
