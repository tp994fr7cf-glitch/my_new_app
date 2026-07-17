import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_media_timeline.dart';
import 'package:my_new_app/models/lesson_timed_anchor.dart';

void main() {
  const first = LessonMediaSegment(
    id: 'first',
    order: 0,
    durationSec: 30,
  );
  const second = LessonMediaSegment(
    id: 'second',
    order: 1,
    durationSec: 20,
  );

  test('existing segment anchor wins over stored global fallback', () {
    const anchor = LessonTimedAnchor(
      anchorType: LessonTimedAnchorType.segment,
      segmentId: 'second',
      timestampSec: 5,
      globalTimestampSec: 999,
    );

    expect(
      anchor.resolveGlobalTimestampSec(
        const LessonMediaTimeline(segments: [first, second]),
      ),
      35,
    );
  });

  test('stored global timestamp is used after anchored segment is removed', () {
    const anchor = LessonTimedAnchor(
      anchorType: LessonTimedAnchorType.segment,
      segmentId: 'second',
      timestampSec: 5,
      globalTimestampSec: 18,
    );

    expect(
      anchor.resolveGlobalTimestampSec(
        const LessonMediaTimeline(segments: [first]),
      ),
      18,
    );
  });

  test('segment local timestamp is final fallback without a global snapshot', () {
    const anchor = LessonTimedAnchor(
      anchorType: LessonTimedAnchorType.segment,
      segmentId: 'removed',
      timestampSec: 7,
    );

    expect(
      anchor.resolveGlobalTimestampSec(
        const LessonMediaTimeline(segments: [first]),
      ),
      7,
    );
  });
}
