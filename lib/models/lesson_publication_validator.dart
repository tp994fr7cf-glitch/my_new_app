import 'course.dart';
import 'lesson_media_config.dart';
import 'lesson_media_segment.dart';
import 'lesson_whiteboard_board_set.dart';

const String lessonPlaybackModeLockedError = '公開済みのパートがあるため、再生モードは変更できません。';
const String lessonPublishedSegmentsLockedError =
    '公開済みのパートと予約済みの配信パートは、タイトル以外の内容や順序を変更・削除できません。';
const String lessonInvalidSegmentIdError = 'パートIDが空欄または重複しているため保存できません。';
const String lessonInvalidPublishedSegmentIdsError =
    '公開対象のパートIDが空欄、重複、または存在しないため保存できません。';
const String lessonDuplicateSegmentOrderError = 'パートの順序が重複しているため保存できません。';
const String lessonMalformedPublicationMetadataError =
    '公開パート情報が破損しているため保存できません。管理者による安全な修復が必要です。';
const String lessonMediaSegmentLimitError = 'メディアパートは100件まで公開できます。';
const String lessonContentRevisionLimitError =
    'コンテンツリビジョンの上限に達したため、新しいパートを公開できません。';
const String lessonPublishedMaterialBoardsLockedError =
    '公開済みのPDF・画像ボードは、背景の変更や削除ができません。新しいボードとして追加してください。';
const String lessonWhiteboardTimingCorrectionInvalidError =
    '板書タイミング補正は±5秒以内で、時間が逆戻りしない値にしてください。';
const int maxLessonContentRevision = 2147483647;

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
    if (publishesNewIds &&
        previous.contentRevision >= maxLessonContentRevision) {
      throw const LessonPublicationValidationException(
        lessonContentRevisionLimitError,
      );
    }
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
  if (!previous.hasValidPublishedSegmentIdsMetadata ||
      !next.hasValidPublishedSegmentIdsMetadata) {
    return lessonMalformedPublicationMetadataError;
  }
  if (!_hasValidUniqueSegmentIds(previous.mediaSegments) ||
      !_hasValidUniqueSegmentIds(next.mediaSegments)) {
    return lessonInvalidSegmentIdError;
  }
  if (!_hasValidUniquePublishedIds(previous) ||
      !_hasValidUniquePublishedIds(next)) {
    return lessonInvalidPublishedSegmentIdsError;
  }
  if (!_hasUniqueOrders(previous.mediaSegments) ||
      !_hasUniqueOrders(next.mediaSegments)) {
    return lessonDuplicateSegmentOrderError;
  }
  if (!next.mediaSegments.every(_hasValidWhiteboardTimingCorrection)) {
    return lessonWhiteboardTimingCorrectionInvalidError;
  }

  final previousLockedIds = previous.lockedSegmentIds;
  final nextLockedIds = next.lockedSegmentIds;
  final previousSegmentIds = previous.mediaSegments
      .map((segment) => segment.id)
      .toSet();
  final addsNewSegmentIds = next.mediaSegments.any(
    (segment) => !previousSegmentIds.contains(segment.id),
  );
  final publishesNewSegmentIds = nextLockedIds.any(
    (id) => !previousLockedIds.contains(id),
  );
  if ((next.mediaSegments.length > maxLessonMediaSegments &&
          addsNewSegmentIds) ||
      (nextLockedIds.length > maxLessonMediaSegments &&
          publishesNewSegmentIds)) {
    return lessonMediaSegmentLimitError;
  }
  if (previousLockedIds.isNotEmpty &&
      previous.playbackMode != next.playbackMode) {
    return lessonPlaybackModeLockedError;
  }
  if (!_publishedMaterialBoardsRemainLocked(
    previous.publishedBoardSet,
    next.publishedBoardSet,
  )) {
    return lessonPublishedMaterialBoardsLockedError;
  }

  final previousOrdered = _orderedWithoutNormalizing(previous.mediaSegments);
  final nextOrdered = _orderedWithoutNormalizing(next.mediaSegments);

  if (!_hasValidPublishedLayout(previousOrdered, previousLockedIds)) {
    return lessonPublishedSegmentsLockedError;
  }

  final protectedIndexes = <int>[
    for (var index = 0; index < previousOrdered.length; index++)
      if (previousLockedIds.contains(previousOrdered[index].id) ||
          previousOrdered[index].isLivePlaceholder)
        index,
  ];
  if (protectedIndexes.isNotEmpty &&
      nextOrdered.length <= protectedIndexes.last) {
    return lessonPublishedSegmentsLockedError;
  }

  for (final index in protectedIndexes) {
    final previousSegment = previousOrdered[index];
    final nextSegment = nextOrdered[index];
    final fieldsMatch = previousLockedIds.contains(previousSegment.id)
        ? _lockedFieldsMatch(previousSegment, nextSegment)
        : _reservedLiveFieldsMatch(previousSegment, nextSegment);
    if (!fieldsMatch) {
      return lessonPublishedSegmentsLockedError;
    }
  }

  if (!nextLockedIds.containsAll(previousLockedIds) ||
      nextLockedIds.length > nextOrdered.length ||
      !_hasValidPublishedLayout(nextOrdered, nextLockedIds)) {
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

bool _hasValidPublishedLayout(
  List<LessonMediaSegment> ordered,
  Set<String> lockedIds,
) {
  if (lockedIds.length > ordered.length) {
    return false;
  }
  var reachedEditableTail = false;
  for (final segment in ordered) {
    final isLocked = lockedIds.contains(segment.id);
    if (isLocked && reachedEditableTail) {
      return false;
    }
    if (!isLocked && !segment.isLiveArchive) {
      reachedEditableTail = true;
    }
  }
  return true;
}

bool _lockedFieldsMatch(LessonMediaSegment previous, LessonMediaSegment next) {
  return previous.id == next.id &&
      previous.mediaType == next.mediaType &&
      previous.url == next.url &&
      previous.durationSec == next.durationSec &&
      previous.durationMs == next.durationMs &&
      previous.sourceKind == next.sourceKind &&
      previous.liveSessionId == next.liveSessionId &&
      previous.order == next.order;
}

bool _reservedLiveFieldsMatch(
  LessonMediaSegment previous,
  LessonMediaSegment next,
) {
  return previous.isLivePlaceholder &&
      previous.id == next.id &&
      previous.mediaType == next.mediaType &&
      previous.sourceKind == next.sourceKind &&
      previous.order == next.order &&
      (previous.liveSessionId.isEmpty ||
          previous.liveSessionId == next.liveSessionId);
}

bool _hasValidUniqueSegmentIds(List<LessonMediaSegment> segments) {
  final ids = <String>{};
  return segments.every(
    (segment) => segment.id.trim().isNotEmpty && ids.add(segment.id),
  );
}

bool _hasValidUniquePublishedIds(CourseLesson lesson) {
  final segmentIds = lesson.mediaSegments.map((segment) => segment.id).toSet();
  final publishedIds = <String>{};
  return lesson.publishedSegmentIds.every(
    (id) =>
        id.trim().isNotEmpty && segmentIds.contains(id) && publishedIds.add(id),
  );
}

bool _hasUniqueOrders(List<LessonMediaSegment> segments) {
  final orders = <int>{};
  return segments.every((segment) => orders.add(segment.order));
}

bool _hasValidWhiteboardTimingCorrection(LessonMediaSegment segment) {
  final startMs = segment.whiteboardStartCorrectionMs;
  final endMs = segment.whiteboardEndCorrectionMs;
  if (startMs.abs() > maxLessonWhiteboardTimingCorrectionMs ||
      endMs.abs() > maxLessonWhiteboardTimingCorrectionMs) {
    return false;
  }
  if (startMs == 0 && endMs == 0) {
    return true;
  }
  final durationMs = (segment.durationSecExact * 1000).round();
  return durationMs > 0 && durationMs + endMs - startMs > 0;
}

bool _publishedMaterialBoardsRemainLocked(BoardSet previous, BoardSet next) {
  for (final previousBoard in previous.boards) {
    final previousBackground = previousBoard.background;
    if (previousBackground == null) {
      continue;
    }
    final nextBoard = next.boardById(previousBoard.id);
    final nextBackground = nextBoard?.background;
    if (nextBackground == null ||
        previousBackground.assetId != nextBackground.assetId ||
        previousBackground.storagePath != nextBackground.storagePath ||
        previousBackground.mediaType != nextBackground.mediaType ||
        previousBackground.pageNumber != nextBackground.pageNumber ||
        previousBackground.aspectRatio != nextBackground.aspectRatio) {
      return false;
    }
  }
  return true;
}
