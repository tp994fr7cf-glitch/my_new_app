import 'lesson_media_segment.dart';

/// Merges published lesson parts with private media drafts without dropping
/// live reservation slots that have no URL yet.
List<LessonMediaSegment> overlayDraftMediaSegments({
  required List<LessonMediaSegment> publishedSegments,
  required List<LessonMediaSegment> draftSegments,
}) {
  if (draftSegments.isEmpty) {
    return LessonMediaSegment.normalizeOrders(publishedSegments);
  }
  if (publishedSegments.isEmpty) {
    return LessonMediaSegment.normalizeOrders(draftSegments);
  }

  final publishedById = {
    for (final segment in publishedSegments) segment.id: segment,
  };
  final draftById = {
    for (final segment in draftSegments) segment.id: segment,
  };
  final merged = <LessonMediaSegment>[
    for (final published in publishedSegments)
      _preferDraftMedia(published, draftById[published.id]),
  ];
  final extras = [
    for (final draftSegment in draftSegments)
      if (!publishedById.containsKey(draftSegment.id)) draftSegment,
  ];
  var nextOrder = merged.isEmpty
      ? 0
      : merged.map((segment) => segment.order).reduce((a, b) => a > b ? a : b) +
            1;
  for (final extra in extras) {
    merged.add(
      extra.copyWith(order: extra.order >= nextOrder ? extra.order : nextOrder),
    );
    nextOrder += 1;
  }
  return LessonMediaSegment.normalizeOrders(merged);
}

LessonMediaSegment _preferDraftMedia(
  LessonMediaSegment published,
  LessonMediaSegment? draft,
) {
  if (draft == null) {
    return published;
  }
  if (published.hasUrl && !draft.hasUrl) {
    return published;
  }
  return draft.copyWith(order: published.order);
}

bool isPersistableMediaDraftSegment(LessonMediaSegment segment) {
  if (segment.id.trim().isEmpty) {
    return false;
  }
  if (segment.isLivePlaceholder) {
    return true;
  }
  return segment.hasUrl && segment.durationSec > 0;
}
