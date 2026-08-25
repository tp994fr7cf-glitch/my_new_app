import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';

void main() {
  test('live start counts unpublished duration without a URL', () {
    const segments = [
      LessonMediaSegment(
        id: 'record',
        order: 0,
        mediaType: 'audio',
        durationSec: 12,
      ),
      LessonMediaSegment(
        id: 'live',
        order: 1,
        mediaType: 'audio',
        sourceKind: lessonMediaSourceLiveArchive,
      ),
    ];

    expect(liveStartSecBeforeIndex(segments, index: 1), 12);
    expect(liveStartSecBeforeIndex(segments, index: 0), 0);
  });

  test('live start skips retired parts and empty placeholders', () {
    const segments = [
      LessonMediaSegment(id: 'hole', order: 0, mediaType: 'video'),
      LessonMediaSegment(
        id: 'retired',
        order: 1,
        mediaType: 'audio',
        durationSec: 9,
        isRetired: true,
      ),
      LessonMediaSegment(
        id: 'ready',
        order: 2,
        mediaType: 'audio',
        durationMs: 4500,
      ),
      LessonMediaSegment(
        id: 'live',
        order: 3,
        mediaType: 'audio',
        sourceKind: lessonMediaSourceLiveArchive,
      ),
    ];

    expect(liveStartSecBeforeIndex(segments, index: 3), 4.5);
  });
}
