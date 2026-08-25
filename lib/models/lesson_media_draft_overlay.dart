import 'lesson_media_segment.dart';

/// Merges published lesson parts with private media drafts without dropping
/// unpublished numbering slots or reversing the teacher's part order.
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

  final draftById = {
    for (final segment in draftSegments) segment.id: segment,
  };
  final mergedById = <String, LessonMediaSegment>{
    for (final published in publishedSegments)
      published.id: _preferDraftMedia(published, draftById[published.id]),
  };
  final publishedIds = {
    for (final published in publishedSegments) published.id,
  };
  final orderedPublished = [
    for (final published in LessonMediaSegment.normalizeOrders(
      publishedSegments,
    ))
      mergedById[published.id]!.copyWith(order: published.order),
  ];
  final extras = [
    for (final draftSegment in draftSegments)
      if (!publishedIds.contains(draftSegment.id) && draftSegment.hasUrl)
        draftSegment,
  ]..sort((left, right) => left.order.compareTo(right.order));

  final merged = [...orderedPublished];
  for (final extra in extras) {
    final index = extra.order.clamp(0, merged.length);
    merged.insert(index, extra);
  }
  return [
    for (var index = 0; index < merged.length; index++)
      merged[index].copyWith(order: index),
  ];
}

LessonMediaSegment _preferDraftMedia(
  LessonMediaSegment published,
  LessonMediaSegment? draft,
) {
  if (draft == null || published.isRetired) {
    return published;
  }
  if (published.hasUrl && !draft.hasUrl) {
    return published;
  }
  return draft.copyWith(
    sourceKind: draft.sourceKind.isNotEmpty
        ? draft.sourceKind
        : published.sourceKind,
    liveSessionId: draft.liveSessionId.isNotEmpty
        ? draft.liveSessionId
        : published.liveSessionId,
  );
}

bool isPersistableMediaDraftSegment(LessonMediaSegment segment) {
  if (segment.id.trim().isEmpty || segment.isRetired) {
    return false;
  }
  return segment.hasUrl && segment.durationSec > 0;
}
