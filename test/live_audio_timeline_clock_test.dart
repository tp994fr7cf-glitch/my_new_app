import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/live_audio_timeline_clock.dart';

void main() {
  test('accepts Agora NTP near the trusted Functions server clock', () {
    expect(
      isPlausibleLiveAudioNtpSample(
        ntpWallTimeMs: 1785836063200,
        sampleElapsedUs: 5000000,
        trustedAnchorMs: 1785836059000,
        trustedAnchorElapsedUs: 1000000,
      ),
      isTrue,
    );
  });

  test('rejects a positive but unsynchronized Agora NTP sample', () {
    expect(
      isPlausibleLiveAudioNtpSample(
        ntpWallTimeMs: 123456789,
        sampleElapsedUs: 5000000,
        trustedAnchorMs: 1785836059000,
        trustedAnchorElapsedUs: 1000000,
      ),
      isFalse,
    );
  });

  test('server clock fallback keeps the first session timeline moving', () {
    const sessionStartedAtMs = 1785836058628;
    const trustedAnchorMs = 1785836059000;
    const trustedAnchorElapsedUs = 1000000;
    const currentElapsedUs = 33000000;

    expect(
      isPlausibleLiveAudioNtpSample(
        ntpWallTimeMs: 123456789,
        sampleElapsedUs: 5000000,
        trustedAnchorMs: trustedAnchorMs,
        trustedAnchorElapsedUs: trustedAnchorElapsedUs,
      ),
      isFalse,
    );
    expect(
      resolveLiveAudioSessionElapsedSec(
        sessionStartedAtMs: sessionStartedAtMs,
        localNowMs: 0,
        currentElapsedUs: currentElapsedUs,
        synchronizedAnchorMs: trustedAnchorMs,
        synchronizedAnchorElapsedUs: trustedAnchorElapsedUs,
      ),
      closeTo(32.372, 0.000001),
    );
  });

  test('waits for consecutive stable Agora NTP samples', () async {
    final samples = <int?>[123456789, 1000003, 1000005, 1000007];
    var sampleIndex = 0;
    var elapsedUs = 0;

    final result = await confirmLiveAudioNtpClock(
      sampleNtpWallTimeMs: () async => samples[sampleIndex++],
      currentElapsedUs: () {
        elapsedUs += 1000;
        return elapsedUs;
      },
      trustedAnchorMs: 1000000,
      trustedAnchorElapsedUs: 0,
      timeout: const Duration(seconds: 1),
      pollInterval: Duration.zero,
    );

    expect(result.confirmed, isTrue);
    expect(result.attempts, 4);
    expect(result.rejectedSamples, 1);
    expect(result.anchorMs, 1000007);
    expect(result.anchorElapsedUs, 7500);
  });

  test('restarts confirmation after an unstable NTP anchor', () async {
    final samples = <int?>[1000001, 1000203, 1000005, 1000007, 1000009];
    var sampleIndex = 0;
    var elapsedUs = 0;

    final result = await confirmLiveAudioNtpClock(
      sampleNtpWallTimeMs: () async => samples[sampleIndex++],
      currentElapsedUs: () {
        elapsedUs += 1000;
        return elapsedUs;
      },
      trustedAnchorMs: 1000000,
      trustedAnchorElapsedUs: 0,
      timeout: const Duration(seconds: 1),
      pollInterval: Duration.zero,
      maximumStableAnchorSkewMs: 100,
    );

    expect(result.confirmed, isTrue);
    expect(result.attempts, 5);
  });

  test('times out instead of accepting an unsynchronized NTP clock', () async {
    var elapsedUs = 0;

    final result = await confirmLiveAudioNtpClock(
      sampleNtpWallTimeMs: () async => 123456789,
      currentElapsedUs: () {
        elapsedUs += 1000;
        return elapsedUs;
      },
      trustedAnchorMs: 1785836059000,
      trustedAnchorElapsedUs: 0,
      timeout: Duration.zero,
      pollInterval: Duration.zero,
    );

    expect(result.confirmed, isFalse);
    expect(result.attempts, 1);
    expect(result.rejectedSamples, 1);
  });

  test('shared timeline events require a confirmed NTP clock', () {
    expect(
      canEmitLiveAudioTimelineEvents(
        canPublish: true,
        sessionIsActive: true,
        ntpClockConfirmed: false,
      ),
      isFalse,
    );
    expect(
      canEmitLiveAudioTimelineEvents(
        canPublish: true,
        sessionIsActive: true,
        ntpClockConfirmed: true,
      ),
      isTrue,
    );
  });

  test('uses Agora NTP time as the live whiteboard clock', () {
    expect(
      resolveLiveAudioSessionElapsedSec(
        sessionStartedAtMs: 100000,
        localNowMs: 110000,
        currentElapsedUs: 3500000,
        synchronizedAnchorMs: 108000,
        synchronizedAnchorElapsedUs: 1500000,
      ),
      10,
    );
  });

  test('falls back to the device clock before Agora NTP is available', () {
    expect(
      resolveLiveAudioSessionElapsedSec(
        sessionStartedAtMs: 100000,
        localNowMs: 104250,
        currentElapsedUs: 1000000,
      ),
      4.25,
    );
  });

  test('uses the monotonic connection clock without a session start', () {
    expect(
      resolveLiveAudioSessionElapsedSec(
        sessionStartedAtMs: 0,
        localNowMs: 0,
        currentElapsedUs: 2250000,
      ),
      2.25,
    );
  });

  test('never returns a negative session position', () {
    expect(
      resolveLiveAudioSessionElapsedSec(
        sessionStartedAtMs: 100000,
        localNowMs: 99000,
        currentElapsedUs: 0,
      ),
      0,
    );
  });
}
