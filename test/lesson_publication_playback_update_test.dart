import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_publication_playback_update.dart';

void main() {
  const unpublishedLive = LessonMediaSegment(
    id: 'live',
    order: 0,
    mediaType: 'audio',
    sourceKind: lessonMediaSourceLiveArchive,
  );
  const recorded = LessonMediaSegment(
    id: 'record',
    order: 1,
    mediaType: 'audio',
    url: 'https://example.com/record.mp3',
    durationSec: 12,
  );
  const publishedLive = LessonMediaSegment(
    id: 'live',
    order: 0,
    mediaType: 'audio',
    url: 'https://example.com/live.mp3',
    durationSec: 20,
    sourceKind: lessonMediaSourceLiveArchive,
  );

  test('jumps to an earlier part that just became playable', () {
    final target = earliestNewlyPlayableEarlierPart(
      previousVisibleParts: const [unpublishedLive, recorded],
      nextVisibleParts: const [publishedLive, recorded],
      currentPlayableSegmentId: recorded.id,
    );

    expect(target?.id, publishedLive.id);
  });

  test('does not jump when only a later part is added', () {
    const later = LessonMediaSegment(
      id: 'later',
      order: 2,
      mediaType: 'audio',
      url: 'https://example.com/later.mp3',
      durationSec: 8,
    );
    final target = earliestNewlyPlayableEarlierPart(
      previousVisibleParts: const [publishedLive, recorded],
      nextVisibleParts: const [publishedLive, recorded, later],
      currentPlayableSegmentId: recorded.id,
    );

    expect(target, isNull);
  });
}
