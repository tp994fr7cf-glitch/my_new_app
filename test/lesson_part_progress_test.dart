import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_part_progress.dart';
import 'package:my_new_app/models/lesson_playback_mode.dart';

void main() {
  test('reconcile retains historical completion and resume metadata', () {
    final progress = reconcileLessonPartProgress(
      requiredCurrentSegmentIds: const ['current', 'new'],
      completedSegmentIds: const ['removed', 'current'],
      retainedResumePositionsSec: const {
        'removed': 12.5,
        'current': 9,
        'new': 3.5,
      },
    );

    expect(progress.completedSegmentIds, {'removed', 'current'});
    expect(progress.historicalCompletedSegmentIds, {'removed'});
    expect(progress.resumePositionsSec['removed'], 12.5);
    expect(progress.isPartCompleted('new'), isFalse);
  });

  test('newly appended current parts remain incomplete', () {
    final progress = LessonPartProgress.reconcile(
      requiredCurrentSegmentIds: const ['a', 'b', 'appended'],
      completedSegmentIds: const ['a', 'b'],
    );

    expect(progress.currentParts.map((part) => part.isCompleted), [
      true,
      true,
      false,
    ]);
    expect(progress.allCurrentPartsCompleted, isFalse);
  });

  test('independent modes require every current part for completion', () {
    final incomplete = LessonPartProgress.reconcile(
      requiredCurrentSegmentIds: const ['a', 'b'],
      completedSegmentIds: const ['a'],
    );
    final complete = LessonPartProgress.reconcile(
      requiredCurrentSegmentIds: const ['a', 'b'],
      completedSegmentIds: const ['historical', 'a', 'b'],
    );

    expect(
      incomplete.isLessonCompleted(
        playbackMode: LessonPlaybackMode.independentSingle,
      ),
      isFalse,
    );
    expect(
      complete.isLessonCompleted(
        playbackMode: LessonPlaybackMode.independentPanels,
      ),
      isTrue,
    );
    expect(
      complete.isLessonCompleted(playbackMode: LessonPlaybackMode.continuous),
      isFalse,
    );
    expect(
      incomplete.isLessonCompleted(
        playbackMode: LessonPlaybackMode.continuous,
        continuousLessonCompleted: true,
      ),
      isTrue,
    );
  });

  test(
    'completed parts resume at zero and incomplete parts use saved position',
    () {
      final progress = LessonPartProgress.reconcile(
        requiredCurrentSegmentIds: const ['last-completed', 'incomplete'],
        completedSegmentIds: const ['last-completed'],
        retainedResumePositionsSec: const {
          'last-completed': 28,
          'incomplete': 14.5,
        },
      );

      expect(progress.resumePositionSecForPart('last-completed'), 0);
      expect(progress.resumePositionSecForPart('incomplete'), 14.5);
      expect(progress.resumePositionSecForPart('unknown'), 0);
    },
  );

  test('legacy independent sessions keep whole-lesson completion behavior', () {
    expect(
      lessonSessionRepresentsCompleted(
        data: const {'status': 'completed', 'cycleCompleted': true},
        playbackMode: LessonPlaybackMode.independentSingle,
        requiredCurrentSegmentIds: const ['a', 'b'],
      ),
      isTrue,
    );
  });

  test('part metadata reopens completion after a part is appended', () {
    final oldCompletedSession = {
      'status': 'completed',
      'requiredMediaSegmentIds': ['a', 'b'],
      'completedMediaSegmentIds': ['a', 'b'],
      'contentRevision': 1,
      'playbackMode': 'independentSingle',
    };

    expect(
      lessonSessionRepresentsCompleted(
        data: oldCompletedSession,
        playbackMode: LessonPlaybackMode.independentSingle,
        requiredCurrentSegmentIds: const ['a', 'b'],
      ),
      isTrue,
    );
    expect(
      lessonSessionRepresentsCompleted(
        data: oldCompletedSession,
        playbackMode: LessonPlaybackMode.independentSingle,
        requiredCurrentSegmentIds: const ['a', 'b', 'appended'],
      ),
      isFalse,
    );
  });

  test('malformed optional session progress fields are ignored safely', () {
    expect(parseLessonSessionSegmentIds('not-a-list'), isEmpty);
    expect(parseLessonSessionSegmentIds([null, 3, '', '   ', 'valid']), {
      'valid',
    });
    expect(
      parseLessonSessionResumePositions({
        'valid': 4.5,
        'negative': -2,
        'nan': double.nan,
        'infinite': double.infinity,
        'wrong': '4',
        5: 9,
      }),
      {'valid': 4.5, 'negative': 0},
    );
    expect(
      lessonSessionRepresentsCompleted(
        data: const {
          'status': 'completed',
          'completedMediaSegmentIds': 'not-a-list',
          'unknownFutureField': true,
        },
        playbackMode: LessonPlaybackMode.independentPanels,
        requiredCurrentSegmentIds: const ['a'],
      ),
      isFalse,
    );
  });

  test('session sanitization retains verified completion history only', () {
    final progress = LessonPartProgress.fromSessionData(
      data: {
        'requiredMediaSegmentIds': ['historical', 'current'],
        'completedMediaSegmentIds': ['historical', 'current', 'injected', ' '],
        'mediaSegmentResumePositionsSec': {
          'historical': 8,
          'current': 4,
          'new': 2.5,
          'injected': 99,
        },
      },
      requiredCurrentSegmentIds: const ['current', 'new'],
    );

    expect(progress.completedSegmentIds, {'historical', 'current'});
    expect(progress.historicalCompletedSegmentIds, {'historical'});
    expect(progress.completedSegmentIdsForPersistence, [
      'historical',
      'current',
    ]);
    expect(progress.resumePositionsSec, {'current': 4, 'new': 2.5});
    expect(progress.resumePositionsSecForPersistence, {'new': 2.5});
  });

  test('non-finite in-memory resume positions are never persisted', () {
    final progress = LessonPartProgress(
      requiredSegmentIds: const ['a', 'b'],
      completedSegmentIds: const [],
      resumePositionsSec: const {'a': double.nan, 'b': double.infinity},
    );

    expect(progress.resumePositionsSec, isEmpty);
    expect(progress.resumePositionsSecForPersistence, isEmpty);
  });

  test('first completion history wins over later completion timestamps', () {
    final first = DateTime.utc(2026, 1, 1);
    final later = DateTime.utc(2026, 2, 1);

    expect(
      firstLessonCompletionTimestamp({
        'firstCompletedAt': first,
        'completedAt': later,
      }),
      same(first),
    );
    expect(firstLessonCompletionTimestamp({'completedAt': first}), same(first));
    expect(firstLessonCompletionTimestamp(const {}), isNull);
  });
}
