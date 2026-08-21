import 'lesson_media_segment.dart';

const String unpublishedLessonPartMessage = 'まだ公開前です';
const String newlyPublishedPartMovedMessage =
    '新しいパートが公開されたので、その始まりに移りました。';

/// Finds the earliest part that just became playable and sits before the
/// part the learner is currently watching.
LessonMediaSegment? earliestNewlyPlayableEarlierPart({
  required List<LessonMediaSegment> previousVisibleParts,
  required List<LessonMediaSegment> nextVisibleParts,
  required String? currentPlayableSegmentId,
}) {
  final previousPlayableIds = {
    for (final segment in previousVisibleParts)
      if (segment.hasUrl) segment.id,
  };
  final currentIndex = currentPlayableSegmentId == null
      ? -1
      : nextVisibleParts.indexWhere(
          (segment) => segment.id == currentPlayableSegmentId,
        );
  for (final segment in nextVisibleParts) {
    if (!segment.hasUrl || previousPlayableIds.contains(segment.id)) {
      continue;
    }
    final nextIndex = nextVisibleParts.indexWhere(
      (item) => item.id == segment.id,
    );
    if (currentIndex < 0 || nextIndex < currentIndex) {
      return segment;
    }
  }
  return null;
}
