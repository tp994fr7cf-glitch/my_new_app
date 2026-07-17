import 'course.dart';
import 'lesson_media_segment.dart';

const String lessonPlaybackModeLockedError = '公開済みのパートがあるため、再生モードは変更できません。';
const String lessonPublishedSegmentsLockedError =
    '公開済みのパートはタイトル以外の内容や順序を変更・削除できません。新しいパートは末尾に追加してください。';

class LessonPublicationValidator {
  const LessonPublicationValidator._();

  static String? validate({
    required CourseLesson previous,
    required CourseLesson next,
  }) {
    return validateAppendOnlyLessonPublication(previous: previous, next: next);
  }

  /// Validates an edited lesson and publishes every URL-bearing segment.
  ///
  /// Publication is append-only: already-published segments keep their
  /// immutable fields, while new tail segments become locked on this save.
  /// The content revision changes only when at least one new segment ID is
  /// published.
  static CourseLesson prepareForPublication({
    required CourseLesson previous,
    required CourseLesson next,
  }) {
    final validationError = validate(previous: previous, next: next);
    if (validationError != null) {
      throw LessonPublicationValidationException(validationError);
    }

    final orderedSegments = LessonMediaSegment.normalizeOrders(
      next.mediaSegments,
    );
    final publishedIds = orderedSegments
        .where(
          (segment) =>
              previous.lockedSegmentIds.contains(segment.id) || segment.hasUrl,
        )
        .map((segment) => segment.id)
        .toList();
    final publishesNewIds = publishedIds.any(
      (id) => !previous.lockedSegmentIds.contains(id),
    );
    final published = next.copyWith(
      mediaSegments: orderedSegments,
      publishedSegmentIds: publishedIds,
      contentRevision: publishesNewIds
          ? previous.contentRevision + 1
          : previous.contentRevision,
    );

    final publishedValidationError = validate(
      previous: previous,
      next: published,
    );
    if (publishedValidationError != null) {
      throw LessonPublicationValidationException(publishedValidationError);
    }
    return published;
  }
}

class LessonPublicationValidationException implements Exception {
  const LessonPublicationValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

String? validateAppendOnlyLessonPublication({
  required CourseLesson previous,
  required CourseLesson next,
}) {
  final previousLockedIds = previous.lockedSegmentIds;
  if (previousLockedIds.isNotEmpty &&
      previous.playbackMode != next.playbackMode) {
    return lessonPlaybackModeLockedError;
  }

  final previousOrdered = _orderedWithoutNormalizing(previous.mediaSegments);
  final nextOrdered = _orderedWithoutNormalizing(next.mediaSegments);
  final previousLocked = previousOrdered
      .where((segment) => previousLockedIds.contains(segment.id))
      .toList();

  if (previousLocked.length != previousLockedIds.length ||
      !_isLockedPrefix(previousOrdered, previousLockedIds)) {
    return lessonPublishedSegmentsLockedError;
  }

  if (nextOrdered.length < previousLocked.length) {
    return lessonPublishedSegmentsLockedError;
  }

  for (var index = 0; index < previousLocked.length; index++) {
    if (!_lockedFieldsMatch(previousLocked[index], nextOrdered[index])) {
      return lessonPublishedSegmentsLockedError;
    }
  }

  final nextLockedIds = next.lockedSegmentIds;
  if (!nextLockedIds.containsAll(previousLockedIds) ||
      nextLockedIds.length > nextOrdered.length ||
      !_isLockedPrefix(nextOrdered, nextLockedIds)) {
    return lessonPublishedSegmentsLockedError;
  }

  return null;
}

String? validateLessonPublication({
  required CourseLesson previous,
  required CourseLesson next,
}) {
  return validateAppendOnlyLessonPublication(previous: previous, next: next);
}

List<LessonMediaSegment> _orderedWithoutNormalizing(
  List<LessonMediaSegment> segments,
) {
  return List<LessonMediaSegment>.from(segments)
    ..sort((a, b) => a.order.compareTo(b.order));
}

bool _isLockedPrefix(List<LessonMediaSegment> ordered, Set<String> lockedIds) {
  if (lockedIds.length > ordered.length) {
    return false;
  }
  for (var index = 0; index < ordered.length; index++) {
    final shouldBeLocked = index < lockedIds.length;
    if (lockedIds.contains(ordered[index].id) != shouldBeLocked) {
      return false;
    }
  }
  return true;
}

bool _lockedFieldsMatch(LessonMediaSegment previous, LessonMediaSegment next) {
  return previous.id == next.id &&
      previous.mediaType == next.mediaType &&
      previous.url == next.url &&
      previous.durationSec == next.durationSec &&
      previous.order == next.order;
}
