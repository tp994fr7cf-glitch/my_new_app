import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/lesson_media_playback.dart';

void main() {
  test(
    'audio play command completes without waiting for playback to stop',
    () async {
      // just_audio's play Future stays pending until pause/stop/completion.
      // The app-level play command must still finish as soon as playback has
      // been started, or a video-to-audio switch holds the playlist seek lock.
      final playbackUntilStopped = Completer<void>();
      var started = false;

      await AudioLessonMediaPlayback.completePlayCommandOnStart(
        playbackUntilStopped: playbackUntilStopped.future,
        onStarted: () {
          started = true;
        },
        onError: (_, __) {},
      ).timeout(const Duration(milliseconds: 100));

      expect(started, isTrue);
      expect(
        playbackUntilStopped.isCompleted,
        isFalse,
        reason: 'The underlying playback should still be running.',
      );

      playbackUntilStopped.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('fake audio playback emits monotonic positions while playing', () async {
    final player = FakeLessonMediaPlayback();
    final positions = <Duration>[];
    final sub = player.positionStream.listen(positions.add);

    await player.open(Uri.parse('https://example.com/audio.mp3'));
    await player.play();
    await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 500));
    await player.pause();
    await sub.cancel();

    expect(positions.length, greaterThan(1));
    for (var index = 1; index < positions.length; index++) {
      expect(
        positions[index].inMilliseconds,
        greaterThanOrEqualTo(positions[index - 1].inMilliseconds),
      );
    }
  });

  test('wall clock fake reports sub-second position between stream ticks', () async {
    final player = WallClockFakeLessonMediaPlayback();
    await player.open(Uri.parse('https://example.com/audio.mp3'));
    await player.play();

    final startMs = player.position.inMilliseconds;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final midMs = player.position.inMilliseconds;

    expect(midMs - startMs, greaterThan(150));
    await player.pause();
  });

  group('shouldSuppressVideoPlayingUpdate', () {
    test('suppresses isPlaying=false caused by buffering', () {
      expect(
        shouldSuppressVideoPlayingUpdate(isPlaying: false, isBuffering: true),
        isTrue,
        reason:
            'A momentary buffering stall (e.g. right after a rewind) '
            'should not be treated as the user pausing playback.',
      );
    });

    test('does not suppress a genuine pause while not buffering', () {
      expect(
        shouldSuppressVideoPlayingUpdate(isPlaying: false, isBuffering: false),
        isFalse,
        reason: 'A real pause (or natural end-of-video) must still be reported.',
      );
    });

    test('never suppresses isPlaying=true, buffering or not', () {
      expect(
        shouldSuppressVideoPlayingUpdate(isPlaying: true, isBuffering: true),
        isFalse,
      );
      expect(
        shouldSuppressVideoPlayingUpdate(isPlaying: true, isBuffering: false),
        isFalse,
      );
    });
  });
}
