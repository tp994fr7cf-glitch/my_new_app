import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_playback_mode.dart';

void main() {
  group('LessonPlaybackMode', () {
    test('uses stable storage values and Japanese labels', () {
      for (final mode in LessonPlaybackMode.values) {
        expect(LessonPlaybackMode.fromStorage(mode.toStorage()), mode);
        expect(mode.displayLabel, isNotEmpty);
      }
      expect(LessonPlaybackMode.continuous.displayLabel, '一貫再生');
      expect(LessonPlaybackMode.independentSingle.displayLabel, '独立再生（単一画面）');
      expect(LessonPlaybackMode.independentPanels.displayLabel, '独立再生（独立画面）');
    });

    test('missing and unknown storage values fall back to continuous', () {
      expect(
        LessonPlaybackMode.fromStorage(null),
        LessonPlaybackMode.continuous,
      );
      expect(
        LessonPlaybackMode.fromStorage('futureMode'),
        LessonPlaybackMode.continuous,
      );
    });
  });

  group('CourseLesson publication fields', () {
    const segments = [
      LessonMediaSegment(
        id: 'a',
        order: 0,
        url: 'https://example.com/a.mp4',
        durationSec: 10,
      ),
      LessonMediaSegment(
        id: 'b',
        order: 1,
        mediaType: 'audio',
        url: 'https://example.com/b.mp3',
        durationSec: 20,
      ),
    ];

    test('legacy missing publication field locks every current segment', () {
      final lesson = CourseLesson.fromMap({
        'title': 'Legacy',
        'duration': '30秒',
        'mediaSegments': segments.map((segment) => segment.toMap()).toList(),
      });

      expect(lesson.playbackMode, LessonPlaybackMode.continuous);
      expect(lesson.contentRevision, 1);
      expect(lesson.publishedSegmentIds, ['a', 'b']);
      expect(lesson.lockedSegmentIds, {'a', 'b'});
      expect(
        lesson.effectivePublishedMediaSegments.map((segment) => segment.id),
        ['a', 'b'],
      );
      expect(lesson.totalMediaDurationSec, 30);
      expect(lesson.hasAudioSegment, isTrue);
    });

    test('explicit empty publication field publishes and locks nothing', () {
      final lesson = CourseLesson.fromMap({
        'title': 'Draft',
        'duration': '30秒',
        'mediaSegments': segments.map((segment) => segment.toMap()).toList(),
        'publishedSegmentIds': <String>[],
      });

      expect(lesson.lockedSegmentIds, isEmpty);
      expect(lesson.effectivePublishedMediaSegments, isEmpty);
      expect(lesson.hasMedia, isFalse);
      expect(lesson.totalMediaDurationSec, 0);
    });

    test('serialization persists explicit publication values', () {
      const lesson = CourseLesson(
        title: 'Parts',
        duration: '30秒',
        mediaSegments: segments,
        playbackMode: LessonPlaybackMode.independentPanels,
        publishedSegmentIds: ['a'],
        contentRevision: 4,
      );

      final map = lesson.toMap();
      expect(map['playbackMode'], 'independentPanels');
      expect(map['publishedSegmentIds'], ['a']);
      expect(map['contentRevision'], 4);

      final restored = CourseLesson.fromMap(map);
      expect(restored.playbackMode, LessonPlaybackMode.independentPanels);
      expect(restored.lockedSegmentIds, {'a'});
      expect(restored.contentRevision, 4);
    });

    test('copyWith snapshots legacy locks before adding a draft tail', () {
      final legacy = CourseLesson(
        title: 'Legacy',
        duration: '10秒',
        mediaSegments: [segments.first],
      );
      final changed = legacy.copyWith(mediaSegments: segments);

      expect(changed.lockedSegmentIds, {'a'});
      expect(changed.toMap()['publishedSegmentIds'], ['a']);
    });

    test('legacy mediaUrl produces the same segment id on every parse', () {
      final data = {
        'title': 'Legacy URL',
        'duration': '10秒',
        'mediaUrl': 'https://example.com/video.mp4',
        'mediaType': 'video',
        'mediaDurationSec': 10,
      };

      final first = CourseLesson.fromMap(data);
      final second = CourseLesson.fromMap(data);

      expect(first.mediaSegments.single.id, second.mediaSegments.single.id);
      expect(first.mediaSegments.single.id, startsWith('legacy_'));
      expect(first.lockedSegmentIds, {first.mediaSegments.single.id});
    });
  });
}
