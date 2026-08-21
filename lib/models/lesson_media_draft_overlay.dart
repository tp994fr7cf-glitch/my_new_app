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
  for (final draftSegment in draftSegments) {
    mergedById.putIfAbsent(draftSegment.id, () => draftSegment);
  }

  final orderById = <String, int>{
    for (final published in publishedSegments) published.id: published.order,
    for (final draftSegment in draftSegments)
      draftSegment.id: draftSegment.order,
  };
  final publishedIndexById = <String, int>{
    for (final entry in publishedSegments.indexed) entry.$2.id: entry.$1,
  };
  final merged = mergedById.values.toList()
    ..sort((left, right) {
      final byOrder = (orderById[left.id] ?? left.order).compareTo(
        orderById[right.id] ?? right.order,
      );
      if (byOrder != 0) {
        return byOrder;
      }
      return (publishedIndexById[left.id] ?? 9999).compareTo(
        publishedIndexById[right.id] ?? 9999,
      );
    });
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
  if (segment.id.trim().isEmpty) {
    return false;
  }
  if (segment.isUnpublishedNumberingPlaceholder) {
    return true;
  }
  return segment.hasUrl && segment.durationSec > 0;
}
