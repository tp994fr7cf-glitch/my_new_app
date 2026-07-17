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

    expect(
      progress.currentParts.map((part) => part.isCompleted),
      [true, true, false],
    );
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
      complete.isLessonCompleted(
        playbackMode: LessonPlaybackMode.continuous,
      ),
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

  test('completed parts resume at zero and incomplete parts use saved position', () {
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
  });
}
