import 'course.dart';
import 'lesson_timed_anchor.dart';

class QuizPlacementException implements Exception {
  const QuizPlacementException(this.message);

  final String message;

  @override
  String toString() => message;
}

const String quizConcurrentConflictMessage =
    'クイズが別の画面で変更されました。画面を読み込み直してから再度お試しください。';

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
  if (event.timestampSec >= segment.durationSec) {
    throw QuizPlacementException(
      '表示タイミングは選択したパートの0秒以上、${segment.durationSec}秒未満で入力してください。',
    );
  }
}

List<LessonEvent> mergeLessonQuizEvents({
  required List<LessonEvent> latestEvents,
  List<LessonEvent>? baseEvents,
  required int lessonNumber,
  required List<LessonEvent> replacementQuizEvents,
  required CourseLesson lesson,
}) {
  final baselineEvents = baseEvents ?? latestEvents;
  final baseQuizzes = _quizEventsById(
    baselineEvents,
    lessonNumber: lessonNumber,
  );
  final latestQuizzes = _quizEventsById(
    latestEvents,
    lessonNumber: lessonNumber,
  );
  final localQuizzes = _quizEventsById(
    replacementQuizEvents,
    lessonNumber: lessonNumber,
  );
  final mergedQuizzes = <String, LessonEvent>{};
  final quizIds = <String>{
    ...baseQuizzes.keys,
    ...latestQuizzes.keys,
    ...localQuizzes.keys,
  };

  for (final id in quizIds) {
    final base = baseQuizzes[id];
    final latest = latestQuizzes[id];
    final local = localQuizzes[id];

    if (base == null) {
      if (local == null) {
        // Added concurrently after this editor loaded.
        if (latest != null) {
          mergedQuizzes[id] = latest;
        }
        continue;
      }
      if (latest == null) {
        mergedQuizzes[id] = _withQuizVersion(
          local,
          quizVersion: 1,
          lesson: lesson,
        );
        continue;
      }
      if (_sameQuizContentAndAnchor(latest, local)) {
        mergedQuizzes[id] = latest;
        continue;
      }
      throw const QuizPlacementException(quizConcurrentConflictMessage);
    }

    final localChanged =
        local == null || !_sameQuizContentAndAnchor(base, local);
    final latestChanged =
        latest == null ||
        latest.quizVersion != base.quizVersion ||
        !_sameQuizContentAndAnchor(base, latest);

    if (!localChanged) {
      // Preserve a concurrent edit or deletion when this editor did not touch
      // the quiz.
      if (latest != null) {
        mergedQuizzes[id] = latest;
      }
      continue;
    }

    if (!latestChanged) {
      // The latest event is still the editor's base, so this local edit or
      // deletion can be applied without losing another writer's work.
      if (local != null) {
        mergedQuizzes[id] = _withQuizVersion(
          local,
          quizVersion: quizVersionForEdit(original: latest, edited: local),
          lesson: lesson,
        );
      }
      continue;
    }

    if (local == null && latest == null) {
      // Both writers deleted the same quiz.
      continue;
    }
    if (local != null &&
        latest != null &&
        _sameQuizContentAndAnchor(latest, local)) {
      // Both writers produced the same result. Keep the already-persisted
      // latest version rather than incrementing it a second time.
      mergedQuizzes[id] = latest;
      continue;
    }
    throw const QuizPlacementException(quizConcurrentConflictMessage);
  }

  final otherEvents = latestEvents.where(
    (event) => event.lessonNumber != lessonNumber || !event.isQuiz,
  );
  final sortedReplacements = mergedQuizzes.values.toList()
    ..sort(
      (a, b) => a
          .resolveGlobalTimestampSec(lesson.mediaTimeline)
          .compareTo(b.resolveGlobalTimestampSec(lesson.mediaTimeline)),
    );
  return [...otherEvents, ...sortedReplacements];
}

Map<String, LessonEvent> _quizEventsById(
  Iterable<LessonEvent> events, {
  required int lessonNumber,
}) {
  final result = <String, LessonEvent>{};
  for (final event in events) {
    if (event.lessonNumber != lessonNumber || !event.isQuiz) {
      continue;
    }
    if (event.id.isEmpty || result.containsKey(event.id)) {
      throw const QuizPlacementException(quizConcurrentConflictMessage);
    }
    result[event.id] = event;
  }
  return result;
}

LessonEvent _withQuizVersion(
  LessonEvent event, {
  required int quizVersion,
  required CourseLesson lesson,
}) {
  return LessonEvent(
    id: event.id,
    lessonNumber: event.lessonNumber,
    timestampSec: event.timestampSec,
    type: event.type,
    quiz: event.quiz,
    anchorType: event.anchorType,
    segmentId: event.segmentId,
    quizVersion: quizVersion,
  ).withResolvedGlobalTimestamp(lesson.mediaTimeline);
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
