import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/live_audio_timeline_clock.dart';

void main() {
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
