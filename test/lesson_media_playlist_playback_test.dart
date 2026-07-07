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
  final audioPool = audioPlayers ?? <LessonMediaPlayback>[FakeLessonMediaPlayback()];
  final videoPool = videoPlayers ?? <LessonMediaPlayback>[FakeLessonMediaPlayback()];
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
  test('openSegments preloads the next segment into the pooled player', () async {
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
  });

  test('seekGlobal across segments reuses the preloaded player without reopening',
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
  });

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

  test('revisiting a prepared video segment resets to the requested start position',
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
  });

  test('auto advance after rewinding to audio starts video from zero', () async {
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
  });

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
        reason: 'pause-seek-play should keep global position moving after rewind',
      );
      expect(playback.liveGlobalPositionSec, greaterThan(31));
    },
  );

  test('cross-segment activation emits global position before segment index',
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
  });

  test('cross-segment seek resumes playback after switching completes', () async {
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
  });

  test('liveGlobalPositionSec advances between one-second audio stream ticks',
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
  });

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
}

class _ThrowingOpenFakeLessonMediaPlayback extends FakeLessonMediaPlayback {
  @override
  Future<void> open(Uri url) async {
    throw LessonMediaLoadException('preload failed for test');
  }
}
