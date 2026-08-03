import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/live_audio_rtc_connection_confirmation.dart';

void main() {
  test('accepts native connected state when callback is missing', () async {
    var probes = 0;

    await confirmLiveAudioRtcConnection(
      joinCommand: Completer<void>().future,
      callbackSignal: Completer<void>().future,
      isConnected: () async => ++probes >= 2,
      timeout: const Duration(milliseconds: 200),
      pollInterval: Duration.zero,
      probeTimeout: const Duration(milliseconds: 20),
    );

    expect(probes, 2);
  });

  test('accepts callback when state probe is not connected', () async {
    final callback = Completer<void>();
    Timer.run(callback.complete);

    await confirmLiveAudioRtcConnection(
      joinCommand: Future<void>.value(),
      callbackSignal: callback.future,
      isConnected: () async => false,
      timeout: const Duration(milliseconds: 200),
      pollInterval: const Duration(milliseconds: 1),
      probeTimeout: const Duration(milliseconds: 20),
    );
  });

  test('surfaces a join command error', () async {
    final error = StateError('join failed');

    await expectLater(
      confirmLiveAudioRtcConnection(
        joinCommand: Future<void>.error(error),
        callbackSignal: Completer<void>().future,
        isConnected: () async => false,
        timeout: const Duration(milliseconds: 200),
        pollInterval: Duration.zero,
        probeTimeout: const Duration(milliseconds: 20),
      ),
      throwsA(same(error)),
    );
  });

  test('times out when neither signal confirms connection', () async {
    await expectLater(
      confirmLiveAudioRtcConnection(
        joinCommand: Completer<void>().future,
        callbackSignal: Completer<void>().future,
        isConnected: () async => false,
        timeout: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 1),
        probeTimeout: const Duration(milliseconds: 5),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
