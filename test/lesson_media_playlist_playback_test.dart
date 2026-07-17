import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/services/lesson_media_playback.dart';
import 'package:my_new_app/services/lesson_media_playlist_playback.dart';

List<LessonMediaSegment> twoPartLessonSegments() {
  return [
    LessonMediaSegment(
      id: 'audio-part',
      order: 0,
      mediaType: 'audio',
      url: 'https://example.com/audio.mp3',
      durationSec: 90,
    ),
    LessonMediaSegment(
      id: 'video-part',
      order: 1,
      mediaType: 'video',
      url: 'https://example.com/video.mp4',
      durationSec: 90,
    ),
  ];
}

LessonMediaPlaylistPlayback createTrackingPlaylistPlayback({
  List<LessonMediaPlayback>? audioPlayers,
  List<LessonMediaPlayback>? videoPlayers,
}) {
  final audioPool =
      audioPlayers ?? <LessonMediaPlayback>[FakeLessonMediaPlayback()];
  final videoPool =
      videoPlayers ?? <LessonMediaPlayback>[FakeLessonMediaPlayback()];
  var audioIndex = 0;
  var videoIndex = 0;

  return LessonMediaPlaylistPlayback(
    playbackFactory: ({required bool isAudio}) {
      if (isAudio) {
        final player = audioPool[audioIndex.clamp(0, audioPool.length - 1)];
        audioIndex += 1;
        return player;
      }
      final player = videoPool[videoIndex.clamp(0, videoPool.length - 1)];
      videoIndex += 1;
      return player;
    },
  );
}

void main() {
  test(
    'does not preload an adjacent segment into the active same-type slot',
    () async {
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        videoPlayers: [videoPlayer],
      );
      final segments = [
        LessonMediaSegment(
          id: 'video-a',
          order: 0,
          url: 'https://example.com/a.mp4',
          durationSec: 30,
        ),
        LessonMediaSegment(
          id: 'video-b',
          order: 1,
          url: 'https://example.com/b.mp4',
          durationSec: 30,
        ),
      ];

      await playback.openSegments(segments);
      await Future<void>.delayed(Duration.zero);

      expect(videoPlayer.openedUrls.map((url) => url.toString()), [
        'https://example.com/a.mp4',
      ]);

      await playback.seekToSegmentIndex(1, localStartSec: 7);

      expect(videoPlayer.openedUrls.map((url) => url.toString()), [
        'https://example.com/a.mp4',
        'https://example.com/b.mp4',
      ]);
      expect(playback.currentSegmentIndex, 1);
      expect(playback.globalPositionSec, closeTo(37, 0.01));
      expect(videoPlayer.position, const Duration(seconds: 7));
    },
  );

  test(
    'openSegments preloads the next segment into the pooled player',
    () async {
      final audioPlayer = FakeLessonMediaPlayback();
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments(twoPartLessonSegments());
      await Future<void>.delayed(Duration.zero);

      expect(audioPlayer.openedUrls.map((url) => url.toString()), [
        'https://example.com/audio.mp3',
      ]);
      expect(videoPlayer.openedUrls.map((url) => url.toString()), [
        'https://example.com/video.mp4',
      ]);
      expect(playback.currentSegmentIndex, 0);
      expect(playback.isReady, isTrue);
    },
  );

  test(
    'seekGlobal across segments reuses the preloaded player without reopening',
    () async {
      final audioPlayer = FakeLessonMediaPlayback();
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments(twoPartLessonSegments());
      await Future<void>.delayed(Duration.zero);

      await playback.seekGlobal(95);

      expect(playback.currentSegmentIndex, 1);
      expect(videoPlayer.openedUrls, hasLength(1));
      expect(playback.globalPositionSec, closeTo(95, 0.01));
    },
  );

  test('seekGlobal coalesces overlapping seeks to the latest target', () async {
    final audioPlayer = FakeLessonMediaPlayback(
      openDelay: const Duration(milliseconds: 40),
    );
    final videoPlayer = FakeLessonMediaPlayback(
      openDelay: const Duration(milliseconds: 40),
    );
    final playback = createTrackingPlaylistPlayback(
      audioPlayers: [audioPlayer],
      videoPlayers: [videoPlayer],
    );

    await playback.openSegments(twoPartLessonSegments());
    await Future<void>.delayed(Duration.zero);

    final firstSeek = playback.seekGlobal(10);
    final secondSeek = playback.seekGlobal(100);
    await Future.wait([firstSeek, secondSeek]);

    expect(playback.currentSegmentIndex, 1);
    expect(playback.globalPositionSec, closeTo(100, 0.01));
    expect(videoPlayer.openedUrls, hasLength(1));
  });

  test('queued seek futures wait until the latest target is applied', () async {
    final audioPlayer = FakeLessonMediaPlayback(
      seekDelay: const Duration(milliseconds: 50),
    );
    final playback = createTrackingPlaylistPlayback(
      audioPlayers: [audioPlayer],
    );
    await playback.openSegments(twoPartLessonSegments());
    await Future<void>.delayed(Duration.zero);

    final firstSeek = playback.seekGlobal(10);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    var queuedSeekCompleted = false;
    final queuedSeek = playback.seekGlobal(20).then((_) {
      queuedSeekCompleted = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 65));
    expect(
      queuedSeekCompleted,
      isFalse,
      reason: 'the queued future must not complete after only the first seek',
    );

    await Future.wait([firstSeek, queuedSeek]);
    expect(playback.globalPositionSec, closeTo(20, 0.01));
    expect(audioPlayer.position, const Duration(seconds: 20));
  });

  test(
    'openSegments waits for an in-flight seek before replacing players',
    () async {
      final oldAudioPlayer = FakeLessonMediaPlayback(
        seekDelay: const Duration(milliseconds: 50),
      );
      final newAudioPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [oldAudioPlayer, newAudioPlayer],
      );
      await playback.openSegments(twoPartLessonSegments());
      await Future<void>.delayed(Duration.zero);

      final seek = playback.seekGlobal(10);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      var reopenCompleted = false;
      final reopen = playback
          .openSegments([
            LessonMediaSegment(
              id: 'replacement',
              order: 0,
              mediaType: 'audio',
              url: 'https://example.com/replacement.mp3',
              durationSec: 15,
            ),
          ])
          .then((_) {
            reopenCompleted = true;
          });

      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(
        reopenCompleted,
        isFalse,
        reason: 'the old native seek must settle before its player is disposed',
      );

      await Future.wait([seek, reopen]);
      expect(playback.currentSegment?.id, 'replacement');
      expect(playback.currentSegmentIndex, 0);
      expect(playback.globalPositionSec, 0);
      expect(
        newAudioPlayer.openedUrls.single.toString(),
        'https://example.com/replacement.mp3',
      );
    },
  );

  test(
    'natural audio completion advances even when playing=false arrives first',
    () async {
      final audioPlayer = FakeLessonMediaPlayback(
        totalDuration: const Duration(seconds: 2),
      );
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );
      await playback.openSegments([
        LessonMediaSegment(
          id: 'audio',
          order: 0,
          mediaType: 'audio',
          url: 'https://example.com/audio.mp3',
          durationSec: 2,
        ),
        LessonMediaSegment(
          id: 'video',
          order: 1,
          url: 'https://example.com/video.mp4',
          durationSec: 10,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      await playback.play();

      await audioPlayer.simulateNaturalCompletion(emitStoppedFirst: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(playback.currentSegmentIndex, 1);
      expect(playback.isPlaying, isTrue);
      expect(videoPlayer.isPlaying, isTrue);
    },
  );

  test('user pause at the exact end does not auto-advance', () async {
    final audioPlayer = FakeLessonMediaPlayback(
      totalDuration: const Duration(seconds: 2),
    );
    final playback = createTrackingPlaylistPlayback(
      audioPlayers: [audioPlayer],
    );
    await playback.openSegments([
      LessonMediaSegment(
        id: 'first',
        order: 0,
        mediaType: 'audio',
        url: 'https://example.com/first.mp3',
        durationSec: 2,
      ),
      LessonMediaSegment(
        id: 'second',
        order: 1,
        mediaType: 'audio',
        url: 'https://example.com/second.mp3',
        durationSec: 2,
      ),
    ]);
    await playback.play();

    await playback.seekToSegmentIndex(0, localStartSec: 2);
    await playback.pause();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(playback.currentSegmentIndex, 0);
    expect(playback.isPlaying, isFalse);
  });

  test('small near-end seek does not auto-advance', () async {
    final audioPlayer = FakeLessonMediaPlayback(
      totalDuration: const Duration(seconds: 2),
    );
    final videoPlayer = FakeLessonMediaPlayback();
    final playback = createTrackingPlaylistPlayback(
      audioPlayers: [audioPlayer],
      videoPlayers: [videoPlayer],
    );
    await playback.openSegments([
      LessonMediaSegment(
        id: 'audio',
        order: 0,
        mediaType: 'audio',
        url: 'https://example.com/audio.mp3',
        durationSec: 2,
      ),
      LessonMediaSegment(
        id: 'video',
        order: 1,
        url: 'https://example.com/video.mp4',
        durationSec: 10,
      ),
    ]);
    await playback.play();

    await playback.seekGlobal(1.96);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(playback.currentSegmentIndex, 0);
    expect(playback.isPlaying, isTrue);
  });

  test(
    'playing stream suppresses duplicate native and command emissions',
    () async {
      final audioPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
      );
      await playback.openSegments(twoPartLessonSegments());
      final states = <bool>[];
      final subscription = playback.playingStream.listen(states.add);

      await playback.play();
      audioPlayer.emitPlayingState(true);
      await Future<void>.delayed(Duration.zero);
      await playback.pause();
      audioPlayer.emitPlayingState(false);
      await Future<void>.delayed(Duration.zero);

      expect(states, [true, false]);
      await subscription.cancel();
    },
  );

  test(
    'URL-less published parts are skipped while later media still opens',
    () async {
      final audioPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
      );

      await playback.openSegments([
        LessonMediaSegment(
          id: 'missing',
          order: 0,
          mediaType: 'audio',
          title: 'Missing upload',
          durationSec: 30,
        ),
        LessonMediaSegment(
          id: 'valid',
          order: 1,
          mediaType: 'audio',
          url: 'https://example.com/valid.mp3',
          durationSec: 10,
        ),
      ]);

      expect(playback.hasSegments, isTrue);
      expect(playback.isReady, isTrue);
      expect(playback.currentSegment?.id, 'valid');
      expect(playback.totalDurationSec, 10);
      expect(
        audioPlayer.openedUrls.single.toString(),
        'https://example.com/valid.mp3',
      );
    },
  );

  test('auto advance switches to the preloaded next segment', () async {
    final audioPlayer = FakeLessonMediaPlayback(
      naturalEndPosition: const Duration(seconds: 2),
    );
    final videoPlayer = FakeLessonMediaPlayback();
    final playback = createTrackingPlaylistPlayback(
      audioPlayers: [audioPlayer],
      videoPlayers: [videoPlayer],
    );

    await playback.openSegments([
      LessonMediaSegment(
        id: 'audio-part',
        order: 0,
        mediaType: 'audio',
        url: 'https://example.com/audio.mp3',
        durationSec: 2,
      ),
      LessonMediaSegment(
        id: 'video-part',
        order: 1,
        mediaType: 'video',
        url: 'https://example.com/video.mp4',
        durationSec: 90,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    await playback.play();

    await Future<void>.delayed(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);

    expect(playback.currentSegmentIndex, 1);
    expect(playback.isPlaying, isTrue);
    expect(videoPlayer.openedUrls, hasLength(1));
  });

  test(
    'revisiting a prepared video segment resets to the requested start position',
    () async {
      final audioPlayer = FakeLessonMediaPlayback();
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments(twoPartLessonSegments());
      await Future<void>.delayed(Duration.zero);

      await playback.seekGlobal(100);
      expect(playback.currentSegmentIndex, 1);
      expect(videoPlayer.position, const Duration(seconds: 10));

      await playback.seekGlobal(40);
      expect(playback.currentSegmentIndex, 0);

      await playback.seekGlobal(90);
      expect(playback.currentSegmentIndex, 1);
      expect(videoPlayer.position, Duration.zero);
      expect(playback.globalPositionSec, closeTo(90, 0.01));
    },
  );

  test(
    'auto advance after rewinding to audio starts video from zero',
    () async {
      final audioPlayer = FakeLessonMediaPlayback(
        naturalEndPosition: const Duration(seconds: 2),
      );
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments([
        LessonMediaSegment(
          id: 'audio-part',
          order: 0,
          mediaType: 'audio',
          url: 'https://example.com/audio.mp3',
          durationSec: 2,
        ),
        LessonMediaSegment(
          id: 'video-part',
          order: 1,
          mediaType: 'video',
          url: 'https://example.com/video.mp4',
          durationSec: 90,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      await playback.seekGlobal(12);
      expect(videoPlayer.position, const Duration(seconds: 10));

      await playback.seekGlobal(0);
      await playback.play();
      await Future<void>.delayed(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);

      expect(playback.currentSegmentIndex, 1);
      expect(videoPlayer.position, Duration.zero);
    },
  );

  test(
    'rewind from video to audio while playing keeps updating global position',
    () async {
      final audioPlayer = FakeLessonMediaPlayback();
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments(twoPartLessonSegments());
      await Future<void>.delayed(Duration.zero);

      await playback.seekGlobal(100);
      await playback.play();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final positions = <double>[];
      final sub = playback.globalPositionStream.listen(positions.add);

      await playback.seekGlobal(30);
      await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 500));
      await sub.cancel();

      expect(playback.currentSegmentIndex, 0);
      expect(playback.isPlaying, isTrue);
      expect(
        positions.where((position) => position >= 31).length,
        greaterThan(0),
        reason:
            'pause-seek-play should keep global position moving after rewind',
      );
      expect(playback.liveGlobalPositionSec, greaterThan(31));
    },
  );

  test(
    'cross-segment activation emits global position before segment index',
    () async {
      final audioPlayer = FakeLessonMediaPlayback();
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments(twoPartLessonSegments());
      await Future<void>.delayed(Duration.zero);
      await playback.seekGlobal(100);

      final events = <String>[];
      final positionSub = playback.globalPositionStream.listen(
        (position) => events.add('pos:${position.toStringAsFixed(0)}'),
      );
      final segmentSub = playback.segmentIndexStream.listen(
        (index) => events.add('seg:$index'),
      );

      await playback.seekGlobal(30);
      await Future<void>.delayed(Duration.zero);

      await positionSub.cancel();
      await segmentSub.cancel();

      final lastSegmentEventIndex = events.lastIndexWhere(
        (event) => event.startsWith('seg:'),
      );
      expect(lastSegmentEventIndex, greaterThan(0));
      expect(events[lastSegmentEventIndex - 1], startsWith('pos:'));
    },
  );

  test(
    'cross-segment seek resumes playback after switching completes',
    () async {
      final audioPlayer = FakeLessonMediaPlayback();
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments(twoPartLessonSegments());
      await Future<void>.delayed(Duration.zero);
      await playback.seekGlobal(100);
      await playback.play();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      await playback.seekGlobal(30);
      await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 500));

      expect(playback.currentSegmentIndex, 0);
      expect(playback.isPlaying, isTrue);
      expect(playback.liveGlobalPositionSec, greaterThan(31));
    },
  );

  test(
    'liveGlobalPositionSec advances between one-second audio stream ticks',
    () async {
      final audioPlayer = WallClockFakeLessonMediaPlayback();
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments(twoPartLessonSegments());
      await playback.play();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(playback.globalPositionSec, 0);
      expect(playback.liveGlobalPositionSec, greaterThan(0.15));
    },
  );

  test(
    'seeking from audio to video while playing does not flash the stale audio position',
    () async {
      // Mirrors AudioLessonMediaPlayback.pause(), which republishes its
      // last known (pre-seek) position as a side effect of pausing.
      final audioPlayer = FakeLessonMediaPlayback(
        republishPositionOnPause: true,
      );
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments(twoPartLessonSegments());
      await Future<void>.delayed(Duration.zero);
      await playback.play();
      await audioPlayer.seek(const Duration(seconds: 45));

      final positions = <double>[];
      final sub = playback.globalPositionStream.listen(positions.add);

      await playback.seekGlobal(100);
      await sub.cancel();

      // None of the positions emitted while switching to the video segment
      // should regress back into the audio segment (below 90s); the stale
      // position pause() republishes must be ignored while the switch is
      // in progress.
      expect(positions.where((position) => position < 90), isEmpty);
      expect(playback.currentSegmentIndex, 1);
      expect(playback.isPlaying, isTrue);
    },
  );

  test(
    'a failed cross-segment seek does not permanently block future seeks',
    () async {
      final audioPlayer = FakeLessonMediaPlayback();
      final videoPlayer = _ThrowingOpenFakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments(twoPartLessonSegments());
      await Future<void>.delayed(Duration.zero);
      await playback.play();

      await expectLater(playback.seekGlobal(100), throwsA(anything));

      // A failed segment activation must not leave seekGlobal permanently
      // stuck (e.g. via a never-reset in-progress flag).
      await playback.seekGlobal(10);
      expect(playback.currentSegmentIndex, 0);
      expect(playback.globalPositionSec, closeTo(10, 0.01));
    },
  );

  test(
    'preloading a segment that is already prepared does not reposition it',
    () async {
      final audioPlayer = FakeLessonMediaPlayback();
      final videoPlayer = FakeLessonMediaPlayback();
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments(twoPartLessonSegments());
      await Future<void>.delayed(Duration.zero);
      await playback.play();

      // Switch audio -> video (real activation, wants to land at 10s local).
      await playback.seekGlobal(100);
      expect(videoPlayer.seekCallsSec, [10.0]);

      // Switch back video -> audio. Activating audio preloads video again
      // as the "next" segment. That preload must not reposition video: it
      // is already open and sitting at a meaningful position (10s), and
      // resetting it to 0 here serves no preloading purpose while risking
      // a race with a future real seek back into video.
      await playback.seekGlobal(30);
      await Future<void>.delayed(Duration.zero);
      expect(videoPlayer.seekCallsSec, [10.0]);
    },
  );

  test(
    'repeated audio/video round trips while playing always land on the requested segment',
    () async {
      final audioPlayer = FakeLessonMediaPlayback();
      // A real seek takes measurable time; delay video's seek() so an
      // unwanted concurrent seek (e.g. a stale preload repositioning this
      // same player) would have a real window to race against it.
      final videoPlayer = FakeLessonMediaPlayback(
        seekDelay: const Duration(milliseconds: 50),
      );
      final playback = createTrackingPlaylistPlayback(
        audioPlayers: [audioPlayer],
        videoPlayers: [videoPlayer],
      );

      await playback.openSegments(twoPartLessonSegments());
      await Future<void>.delayed(Duration.zero);
      await playback.play();

      // audio -> video -> audio -> video, all while continuously playing,
      // reproducing the reported repeat-switch failure.
      await playback.seekGlobal(100);
      expect(playback.currentSegmentIndex, 1);
      expect(playback.isPlaying, isTrue);

      await playback.seekGlobal(30);
      expect(playback.currentSegmentIndex, 0);
      expect(playback.isPlaying, isTrue);

      await playback.seekGlobal(120);
      expect(playback.currentSegmentIndex, 1);
      expect(playback.isPlaying, isTrue);
      expect(playback.globalPositionSec, closeTo(120, 0.01));

      // Only the two explicit switches into video should have ever
      // repositioned it; no stray preload-triggered seek (e.g. back to 0)
      // should have snuck in between them.
      expect(videoPlayer.seekCallsSec, [10.0, 30.0]);

      // Same-segment (audio-to-audio) seeks must also still work right
      // after a round trip through video, matching the report that even
      // unrelated seeks stopped working once this happened.
      await playback.seekGlobal(30);
      expect(playback.currentSegmentIndex, 0);
      await playback.seekGlobal(60);
      expect(playback.currentSegmentIndex, 0);
      expect(playback.globalPositionSec, closeTo(60, 0.01));
    },
  );

  test('a pause() that arrives while a cross-segment seek is in flight is '
      'honored once the switch settles, instead of being overridden by a '
      'stale "was playing" snapshot', () async {
    final audioPlayer = FakeLessonMediaPlayback();
    // Give the video segment's seek a real delay, so pause() below has a
    // genuine window to land while `_activateSegment` for the video
    // segment is still in flight (mirroring what real native players do).
    final videoPlayer = FakeLessonMediaPlayback(
      seekDelay: const Duration(milliseconds: 50),
    );
    final playback = createTrackingPlaylistPlayback(
      audioPlayers: [audioPlayer],
      videoPlayers: [videoPlayer],
    );

    await playback.openSegments(twoPartLessonSegments());
    await Future<void>.delayed(Duration.zero);
    await playback.play();
    expect(playback.isPlaying, isTrue);

    // Start a cross-segment seek into video while playing (this captures
    // "was playing" as true internally), but don't await it yet.
    final seekFuture = playback.seekGlobal(100);

    // While that switch is still resolving (video's seek() is delayed),
    // the user taps pause. Without the fix, this direct pause() would
    // race the switch's own pause-old/activate-new/resume-if-needed
    // sequence and get silently overridden by the stale "was playing"
    // snapshot once the switch finishes, forcing playback to resume
    // against the user's actual request.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await playback.pause();

    await seekFuture;

    expect(playback.currentSegmentIndex, 1);
    expect(
      playback.isPlaying,
      isFalse,
      reason:
          'the pause requested mid-switch must win over the pre-switch '
          '"was playing" snapshot',
    );
    expect(videoPlayer.isPlaying, isFalse);
  });

  test('a pause() that arrives while a same-segment seek is in flight still '
      'takes effect immediately, instead of being silently lost', () async {
    // Regression test: an earlier fix for the cross-segment race
    // (above) deferred play()/pause() taps entirely while any seek was
    // in flight, relying on the switch itself to apply them once
    // settled. That worked for cross-segment switches (which go through
    // `_activateSegment`), but a same-segment seek never does, so a
    // deferred tap landing during one was silently dropped forever -
    // making the pause button appear to "stop responding" after any
    // slider drag within the current part. play()/pause() must always
    // take effect the instant they're called, with no such window.
    final audioPlayer = FakeLessonMediaPlayback(
      seekDelay: const Duration(milliseconds: 50),
    );
    final videoPlayer = FakeLessonMediaPlayback();
    final playback = createTrackingPlaylistPlayback(
      audioPlayers: [audioPlayer],
      videoPlayers: [videoPlayer],
    );

    await playback.openSegments(twoPartLessonSegments());
    await Future<void>.delayed(Duration.zero);
    await playback.play();
    expect(playback.isPlaying, isTrue);

    // A same-segment seek (still within the audio part): this never
    // calls `_activateSegment`.
    final seekFuture = playback.seekGlobal(30);

    // While that seek's delayed native seek() is still resolving, the
    // user taps pause.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await playback.pause();

    expect(
      playback.isPlaying,
      isFalse,
      reason: 'pause() must take effect immediately, not be deferred',
    );
    expect(audioPlayer.isPlaying, isFalse);

    await seekFuture;

    expect(playback.currentSegmentIndex, 0);
    expect(playback.isPlaying, isFalse);
  });

  test('a play() that arrives while a segment switch is in flight is honored '
      'even if the switch itself was not going to resume playback', () async {
    final audioPlayer = FakeLessonMediaPlayback();
    final videoPlayer = FakeLessonMediaPlayback(
      seekDelay: const Duration(milliseconds: 50),
    );
    final playback = createTrackingPlaylistPlayback(
      audioPlayers: [audioPlayer],
      videoPlayers: [videoPlayer],
    );

    await playback.openSegments(twoPartLessonSegments());
    await Future<void>.delayed(Duration.zero);
    expect(playback.isPlaying, isFalse);

    // Tap a specific part while paused (e.g. the "part navigation"
    // buttons): this switches segments without asking for playback to
    // resume on its own.
    final seekFuture = playback.seekToSegmentIndex(1);

    // While that switch is still resolving, the user taps play.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await playback.play();

    await seekFuture;

    expect(playback.currentSegmentIndex, 1);
    expect(
      playback.isPlaying,
      isTrue,
      reason: 'the play requested mid-switch must be honored once it settles',
    );
    expect(videoPlayer.isPlaying, isTrue);
  });
}

class _ThrowingOpenFakeLessonMediaPlayback extends FakeLessonMediaPlayback {
  @override
  Future<void> open(Uri url) async {
    throw LessonMediaLoadException('preload failed for test');
  }
}
