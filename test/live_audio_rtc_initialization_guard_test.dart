import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/live_audio_rtc_initialization_guard.dart';

void main() {
  test('successful initialization keeps later attempts available', () async {
    final guard = LiveAudioRtcInitializationGuard();
    var attempts = 0;

    await guard.initialize(() async {
      attempts += 1;
    });
    await guard.initialize(() async {
      attempts += 1;
    });

    expect(attempts, 2);
    expect(guard.requiresProcessRestart, isFalse);
  });

  test('timeout requires a process restart', () async {
    final guard = LiveAudioRtcInitializationGuard();

    await expectLater(
      guard.initialize(
        () => Completer<void>().future,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<LiveAudioRtcInitializationException>()),
    );

    expect(guard.requiresProcessRestart, isTrue);
  });

  test(
    'does not retry poisoned native initialization in same process',
    () async {
      final guard = LiveAudioRtcInitializationGuard();
      var attempts = 0;

      await expectLater(
        guard.initialize(() {
          attempts += 1;
          return Completer<void>().future;
        }, timeout: const Duration(milliseconds: 10)),
        throwsA(isA<LiveAudioRtcInitializationException>()),
      );
      await expectLater(
        guard.initialize(() async {
          attempts += 1;
        }),
        throwsA(isA<LiveAudioRtcInitializationException>()),
      );

      expect(attempts, 1);
    },
  );

  test('ordinary initialization errors remain retryable', () async {
    final guard = LiveAudioRtcInitializationGuard();
    final error = StateError('initialize failed');

    await expectLater(
      guard.initialize(() => Future<void>.error(error)),
      throwsA(same(error)),
    );
    await guard.initialize(() async {});

    expect(guard.requiresProcessRestart, isFalse);
  });
}
