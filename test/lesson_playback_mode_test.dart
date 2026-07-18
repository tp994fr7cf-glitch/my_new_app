import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_playback_mode.dart';
import 'package:my_new_app/models/lesson_timed_anchor.dart';

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
      expect(CourseLesson.fromMap(lesson.toMap()).publishedSegmentIds, isEmpty);
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

    test('present malformed publication metadata fails closed', () {
      final lesson = CourseLesson.fromMap({
        'title': 'Malformed',
        'duration': '30秒',
        'mediaSegments': segments.map((segment) => segment.toMap()).toList(),
        'playbackMode': 42,
        'publishedSegmentIds': 'not-a-list',
        'contentRevision': double.nan,
        'unknownFutureField': Object(),
      });

      expect(lesson.playbackMode, LessonPlaybackMode.continuous);
      expect(lesson.hasValidPublishedSegmentIdsMetadata, isFalse);
      expect(lesson.publishedSegmentIds, isEmpty);
      expect(lesson.lockedSegmentIds, {'a', 'b'});
      expect(lesson.effectivePublishedMediaSegments, isEmpty);
      expect(lesson.contentRevision, 1);
    });

    test(
      'repairs duplicate segment IDs without publishing ambiguous drafts',
      () {
        final lesson = CourseLesson.fromMap({
          'title': 'Duplicate IDs',
          'duration': '30秒',
          'mediaSegments': [
            segments.first.toMap(),
            segments.last.toMap()..['id'] = 'a',
            segments.last.toMap()..['id'] = '   ',
          ],
          'publishedSegmentIds': ['a', 'a', '', 'stale'],
        });

        expect(
          lesson.mediaSegments.map((segment) => segment.id).toSet(),
          hasLength(3),
        );
        expect(
          lesson.mediaSegments.every((segment) => segment.id.trim().isNotEmpty),
          isTrue,
        );
        expect(lesson.hasValidPublishedSegmentIdsMetadata, isFalse);
        expect(lesson.publishedSegmentIds, isEmpty);
        expect(lesson.lockedSegmentIds, hasLength(3));
        expect(lesson.effectivePublishedMediaSegments, isEmpty);
      },
    );

    test(
      'legacy duplicate segment IDs remain visible with stable repaired IDs',
      () {
        final data = {
          'title': 'Legacy duplicates',
          'duration': '30秒',
          'mediaSegments': [
            segments.first.toMap(),
            segments.last.toMap()..['id'] = 'a',
          ],
        };

        final first = CourseLesson.fromMap(data);
        final second = CourseLesson.fromMap(data);

        expect(first.mediaSegments.map((segment) => segment.id), hasLength(2));
        expect(
          first.mediaSegments.map((segment) => segment.id),
          second.mediaSegments.map((segment) => segment.id),
        );
        expect(first.effectivePublishedMediaSegments, hasLength(2));
      },
    );
  });

  test('Course preserves a valid top-level lesson content version', () {
    final course = Course.fromMap({
      'lessonContentVersion': 7,
      'lessons': <Object>[],
    });
    final malformed = Course.fromMap({
      'lessonContentVersion': 'bad',
      'lessons': <Object>[],
    });

    expect(course.lessonContentVersion, 7);
    expect(course.toFirestore()['lessonContentVersion'], 7);
    expect(malformed.lessonContentVersion, 0);
    expect(malformed.toFirestore(), isNot(contains('lessonContentVersion')));
  });

  group('LessonEvent migration', () {
    test('malformed optional anchor fields and quiz version are safe', () {
      final event = LessonEvent.fromMap({
        'id': 'legacy-quiz',
        'lessonNumber': 1,
        'timestampSec': 3,
        'type': 'quiz',
        'anchorType': 7,
        'segmentId': false,
        'globalTimestampSec': double.infinity,
        'quizVersion': double.nan,
        'unknownFutureField': true,
      });

      expect(event.anchorType, LessonTimedAnchorType.global);
      expect(event.segmentId, isNull);
      expect(event.globalTimestampSec, isNull);
      expect(event.quizVersion, 1);
      expect(LessonEvent.fromMap(event.toMap()).quizVersion, 1);
    });

    test('non-positive quiz versions fall back to the legacy version', () {
      expect(LessonEvent.fromMap({'quizVersion': 0}).quizVersion, 1);
      expect(LessonEvent.fromMap({'quizVersion': -8}).quizVersion, 1);
      expect(LessonEvent.fromMap({'quizVersion': 2147483648}).quizVersion, 1);
    });
  });
}
