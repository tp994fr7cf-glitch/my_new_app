import 'course.dart';
import 'lesson_timed_anchor.dart';

class QuizPlacementException implements Exception {
  const QuizPlacementException(this.message);

  final String message;

  @override
  String toString() => message;
}

String? defaultQuizSegmentId(CourseLesson lesson) {
  final segments = lesson.effectivePublishedMediaSegments;
  return segments.isEmpty ? null : segments.first.id;
}

void validateQuizPlacement({
  required LessonEvent event,
  required CourseLesson lesson,
  bool allowLegacyGlobal = true,
}) {
  if (event.timestampSec < 0) {
    throw const QuizPlacementException('表示タイミングは0秒以上で入力してください。');
  }

  if (event.anchorType == LessonTimedAnchorType.global) {
    if (!allowLegacyGlobal &&
        lesson.effectivePublishedMediaSegments.isNotEmpty) {
      throw const QuizPlacementException('公開済みのパートを選択してください。');
    }
    return;
  }

  final segmentId = event.segmentId;
  if (segmentId == null || segmentId.isEmpty) {
    throw const QuizPlacementException('公開済みのパートを選択してください。');
  }

  final segment = lesson.mediaTimeline.segmentById(segmentId);
  if (segment == null) {
    throw const QuizPlacementException(
      '選択したパートは公開されていません。最新の公開済みパートを選び直してください。',
    );
  }
  if (event.timestampSec > segment.durationSec) {
    throw QuizPlacementException(
      '表示タイミングは選択したパートの0〜${segment.durationSec}秒で入力してください。',
    );
  }
}

List<LessonEvent> mergeLessonQuizEvents({
  required List<LessonEvent> latestEvents,
  required int lessonNumber,
  required List<LessonEvent> replacementQuizEvents,
  required CourseLesson lesson,
}) {
  final otherEvents = latestEvents.where(
    (event) => event.lessonNumber != lessonNumber || !event.isQuiz,
  );
  final sortedReplacements = List<LessonEvent>.from(replacementQuizEvents)
    ..sort(
      (a, b) => a
          .resolveGlobalTimestampSec(lesson.mediaTimeline)
          .compareTo(b.resolveGlobalTimestampSec(lesson.mediaTimeline)),
    );
  return [...otherEvents, ...sortedReplacements];
}

int quizVersionForEdit({
  required LessonEvent? original,
  required LessonEvent edited,
}) {
  if (original == null) {
    return 1;
  }
  return _sameQuizContentAndAnchor(original, edited)
      ? original.quizVersion
      : original.quizVersion + 1;
}

bool isLessonQuizDue({
  required LessonEvent event,
  required CourseLesson lesson,
  required bool independentPlayback,
  required String? activeSegmentId,
  required double currentLocalPositionSec,
  required int currentGlobalPositionSec,
}) {
  if (independentPlayback &&
      event.anchorType == LessonTimedAnchorType.segment) {
    return event.segmentId == activeSegmentId &&
        event.timestampSec <= currentLocalPositionSec;
  }
  return event.resolveGlobalTimestampSec(lesson.mediaTimeline) <=
      currentGlobalPositionSec;
}

bool _sameQuizContentAndAnchor(LessonEvent a, LessonEvent b) {
  final aQuiz = a.quiz;
  final bQuiz = b.quiz;
  if (aQuiz == null || bQuiz == null) {
    return aQuiz == bQuiz;
  }
  return a.anchorType == b.anchorType &&
      a.segmentId == b.segmentId &&
      a.timestampSec == b.timestampSec &&
      aQuiz.question == bQuiz.question &&
      _listsEqual(aQuiz.choices, bQuiz.choices) &&
      aQuiz.correctChoiceIndex == bQuiz.correctChoiceIndex &&
      aQuiz.explanation == bQuiz.explanation;
}

bool _listsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
