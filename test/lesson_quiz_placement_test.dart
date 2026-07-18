import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_playback_mode.dart';
import 'package:my_new_app/models/lesson_quiz_placement.dart';
import 'package:my_new_app/models/lesson_timed_anchor.dart';

void main() {
  const segmentA = LessonMediaSegment(
    id: 'a',
    order: 0,
    title: '導入',
    durationSec: 10,
  );
  const segmentB = LessonMediaSegment(
    id: 'b',
    order: 1,
    title: '演習',
    durationSec: 20,
  );
  const draftSegment = LessonMediaSegment(
    id: 'draft',
    order: 2,
    title: '下書き',
    durationSec: 30,
  );
  const lesson = CourseLesson(
    title: 'レッスン',
    duration: '30秒',
    mediaSegments: [segmentA, segmentB, draftSegment],
    publishedSegmentIds: ['a', 'b'],
    playbackMode: LessonPlaybackMode.independentSingle,
  );
  const quiz = LessonQuiz(
    question: '問題',
    choices: ['A', 'B'],
    correctChoiceIndex: 0,
  );

  LessonEvent event({
    String id = 'quiz',
    String segmentId = 'a',
    int timestampSec = 0,
    LessonTimedAnchorType anchorType = LessonTimedAnchorType.segment,
    int quizVersion = 1,
    LessonQuiz? lessonQuiz,
  }) {
    return LessonEvent(
      id: id,
      lessonNumber: 1,
      timestampSec: timestampSec,
      type: 'quiz',
      quiz: lessonQuiz ?? quiz,
      anchorType: anchorType,
      segmentId: anchorType == LessonTimedAnchorType.segment ? segmentId : null,
      quizVersion: quizVersion,
    );
  }

  test('new quiz defaults to first published part and excludes draft', () {
    expect(defaultQuizSegmentId(lesson), 'a');
    expect(
      lesson.effectivePublishedMediaSegments.map((segment) => segment.id),
      ['a', 'b'],
    );
  });

  test('validates local bounds and rejects draft segment ids', () {
    expect(
      () => validateQuizPlacement(
        event: event(segmentId: 'b', timestampSec: 19),
        lesson: lesson,
        allowLegacyGlobal: false,
      ),
      returnsNormally,
    );
    expect(
      () => validateQuizPlacement(
        event: event(segmentId: 'b', timestampSec: 20),
        lesson: lesson,
        allowLegacyGlobal: false,
      ),
      throwsA(
        isA<QuizPlacementException>().having(
          (error) => error.message,
          'message',
          '表示タイミングは選択したパートの0秒以上、20秒未満で入力してください。',
        ),
      ),
    );
    expect(
      () => validateQuizPlacement(
        event: event(segmentId: 'draft'),
        lesson: lesson,
        allowLegacyGlobal: false,
      ),
      throwsA(isA<QuizPlacementException>()),
    );
  });

  test('legacy global quiz remains valid only when explicitly allowed', () {
    final legacy = event(anchorType: LessonTimedAnchorType.global);
    expect(
      () => validateQuizPlacement(event: legacy, lesson: lesson),
      returnsNormally,
    );
    expect(
      () => validateQuizPlacement(
        event: legacy,
        lesson: lesson,
        allowLegacyGlobal: false,
      ),
      throwsA(isA<QuizPlacementException>()),
    );
  });

  test('merge uses latest events and preserves concurrent other lessons', () {
    final otherLessonQuiz = LessonEvent(
      id: 'other-latest',
      lessonNumber: 2,
      timestampSec: 3,
      type: 'quiz',
      quiz: quiz,
    );
    final nonQuiz = LessonEvent(
      id: 'rule-like-event',
      lessonNumber: 1,
      timestampSec: 1,
      type: 'notice',
    );

    final merged = mergeLessonQuizEvents(
      latestEvents: [
        event(id: 'old'),
        otherLessonQuiz,
        nonQuiz,
      ],
      lessonNumber: 1,
      replacementQuizEvents: [event(id: 'replacement')],
      lesson: lesson,
    );

    expect(merged.map((item) => item.id), [
      'other-latest',
      'rule-like-event',
      'replacement',
    ]);
  });

  test('three-way merge increments exactly once from the latest version', () {
    final base = event(quizVersion: 7);
    final local = event(timestampSec: 1, quizVersion: 99);

    final merged = mergeLessonQuizEvents(
      latestEvents: [base],
      baseEvents: [base],
      lessonNumber: 1,
      replacementQuizEvents: [local],
      lesson: lesson,
    );

    expect(merged.single.timestampSec, 1);
    expect(merged.single.quizVersion, 8);
  });

  test('three-way merge rejects concurrent edits to the same quiz', () {
    final base = event(quizVersion: 2);
    final latest = event(
      quizVersion: 3,
      lessonQuiz: const LessonQuiz(
        question: '別画面の変更',
        choices: ['A', 'B'],
        correctChoiceIndex: 0,
      ),
    );
    final local = event(
      timestampSec: 1,
      lessonQuiz: const LessonQuiz(
        question: 'この画面の変更',
        choices: ['A', 'B'],
        correctChoiceIndex: 0,
      ),
    );

    expect(
      () => mergeLessonQuizEvents(
        latestEvents: [latest],
        baseEvents: [base],
        lessonNumber: 1,
        replacementQuizEvents: [local],
        lesson: lesson,
      ),
      throwsA(
        isA<QuizPlacementException>().having(
          (error) => error.message,
          'message',
          quizConcurrentConflictMessage,
        ),
      ),
    );
  });

  test('three-way merge preserves concurrent additions and deletions', () {
    final retained = event(id: 'retained');
    final concurrentlyDeleted = event(id: 'deleted');
    final deletedByBoth = event(id: 'deleted-by-both');
    final concurrentlyAdded = event(id: 'added', segmentId: 'b');

    final merged = mergeLessonQuizEvents(
      latestEvents: [retained, concurrentlyAdded],
      baseEvents: [retained, concurrentlyDeleted, deletedByBoth],
      lessonNumber: 1,
      replacementQuizEvents: [retained, concurrentlyDeleted],
      lesson: lesson,
    );

    expect(merged.map((item) => item.id).toSet(), {'retained', 'added'});
  });

  test('independent due time is local to active part A or B', () {
    final quizA = event(id: 'a-quiz', segmentId: 'a', timestampSec: 5);
    final quizB = event(id: 'b-quiz', segmentId: 'b', timestampSec: 5);

    expect(
      isLessonQuizDue(
        event: quizA,
        lesson: lesson,
        independentPlayback: true,
        activeSegmentId: 'a',
        currentLocalPositionSec: 5,
        currentGlobalPositionSec: 5,
      ),
      isTrue,
    );
    expect(
      isLessonQuizDue(
        event: quizB,
        lesson: lesson,
        independentPlayback: true,
        activeSegmentId: 'a',
        currentLocalPositionSec: 9,
        currentGlobalPositionSec: 9,
      ),
      isFalse,
    );
    expect(
      isLessonQuizDue(
        event: quizB,
        lesson: lesson,
        independentPlayback: true,
        activeSegmentId: 'b',
        currentLocalPositionSec: 4,
        currentGlobalPositionSec: 14,
      ),
      isFalse,
    );
  });

  test('continuous due time resolves segment B onto global timeline', () {
    final quizB = event(segmentId: 'b', timestampSec: 5);
    expect(
      isLessonQuizDue(
        event: quizB,
        lesson: lesson,
        independentPlayback: false,
        activeSegmentId: 'a',
        currentLocalPositionSec: 9,
        currentGlobalPositionSec: 14,
      ),
      isFalse,
    );
    expect(
      isLessonQuizDue(
        event: quizB,
        lesson: lesson,
        independentPlayback: false,
        activeSegmentId: 'b',
        currentLocalPositionSec: 5,
        currentGlobalPositionSec: 15,
      ),
      isTrue,
    );
  });

  test('edited content increments version and changes learner answer key', () {
    final original = event(quizVersion: 2);
    final edited = LessonEvent(
      id: original.id,
      lessonNumber: 1,
      timestampSec: 1,
      type: 'quiz',
      quiz: quiz,
      anchorType: LessonTimedAnchorType.segment,
      segmentId: 'a',
      quizVersion: original.quizVersion,
    );

    expect(quizVersionForEdit(original: original, edited: edited), 3);
    expect(event(quizVersion: 1).quizAnswerKey, 'quiz');
    expect(event(quizVersion: 3).quizAnswerKey, 'quiz:v3');
  });

  test('quiz version defaults to one and is persisted', () {
    final legacyMap = event().toMap()..remove('quizVersion');

    expect(LessonEvent.fromMap(legacyMap).quizVersion, 1);
    expect(event(quizVersion: 4).toMap()['quizVersion'], 4);
  });

  test('part anchor and quiz version survive serialization round-trip', () {
    final original = event(
      id: 'round-trip',
      segmentId: 'b',
      timestampSec: 7,
      quizVersion: 3,
    ).withResolvedGlobalTimestamp(lesson.mediaTimeline);

    final restored = LessonEvent.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.anchorType, LessonTimedAnchorType.segment);
    expect(restored.segmentId, 'b');
    expect(restored.timestampSec, 7);
    expect(restored.globalTimestampSec, 17);
    expect(restored.quizVersion, 3);
    expect(restored.quiz?.question, quiz.question);
  });
}
