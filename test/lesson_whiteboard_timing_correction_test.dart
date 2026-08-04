import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_media_timeline.dart';
import 'package:my_new_app/models/lesson_whiteboard_timing_correction.dart';

void main() {
  test('segment timing corrections round-trip and default to zero', () {
    final legacy = LessonMediaSegment.fromMap({
      'id': 'legacy',
      'order': 0,
      'durationSec': 30,
    });
    expect(legacy.whiteboardStartCorrectionMs, 0);
    expect(legacy.whiteboardEndCorrectionMs, 0);
    expect(legacy.toMap(), isNot(contains('whiteboardStartCorrectionMs')));

    final corrected = LessonMediaSegment.fromMap({
      'id': 'corrected',
      'order': 0,
      'durationSec': 30,
      'whiteboardStartCorrectionMs': 500,
      'whiteboardEndCorrectionMs': 1500,
    });
    expect(corrected.whiteboardStartCorrectionMs, 500);
    expect(corrected.whiteboardEndCorrectionMs, 1500);
    expect(corrected.toMap()['whiteboardStartCorrectionMs'], 500);
    expect(corrected.toMap()['whiteboardEndCorrectionMs'], 1500);
  });

  test('uses the same value throughout a uniform correction', () {
    expect(
      resolveLessonWhiteboardCorrectionSec(
        startCorrectionMs: 1200,
        endCorrectionMs: 1200,
        segmentLocalSec: 30,
        segmentDurationSec: 60,
      ),
      1.2,
    );
  });

  test('linearly interpolates start and end corrections', () {
    expect(
      resolveLessonWhiteboardCorrectionSec(
        startCorrectionMs: 0,
        endCorrectionMs: 2000,
        segmentLocalSec: 30,
        segmentDurationSec: 60,
      ),
      1,
    );
  });

  test('positive correction looks ahead and negative correction delays', () {
    final earlyTimeline = LessonMediaTimeline(
      segments: const [
        LessonMediaSegment(
          id: 'early',
          order: 0,
          durationSec: 30,
          whiteboardStartCorrectionMs: 1000,
          whiteboardEndCorrectionMs: 1000,
        ),
      ],
    );
    final delayedTimeline = LessonMediaTimeline(
      segments: const [
        LessonMediaSegment(
          id: 'delayed',
          order: 0,
          durationSec: 30,
          whiteboardStartCorrectionMs: -1000,
          whiteboardEndCorrectionMs: -1000,
        ),
      ],
    );

    expect(
      resolveLessonWhiteboardPlaybackLookup(
        playbackGlobalSec: 5,
        timeline: earlyTimeline,
      ).globalSec,
      6,
    );
    expect(
      resolveLessonWhiteboardPlaybackLookup(
        playbackGlobalSec: 5,
        timeline: delayedTimeline,
      ).globalSec,
      4,
    );
  });

  test('does not reveal the next part early', () {
    final timeline = LessonMediaTimeline(
      segments: const [
        LessonMediaSegment(
          id: 'first',
          order: 0,
          durationSec: 10,
          whiteboardStartCorrectionMs: 2000,
          whiteboardEndCorrectionMs: 2000,
        ),
        LessonMediaSegment(id: 'second', order: 1, durationSec: 10),
      ],
    );

    final lookup = resolveLessonWhiteboardPlaybackLookup(
      playbackGlobalSec: 9,
      timeline: timeline,
    );

    expect(lookup.segmentId, 'first');
    expect(lookup.globalSec, lessThan(10));
    expect(lookup.segmentLocalSec, 10);
  });

  test('keeps the previous completed state while delaying a new part', () {
    final timeline = LessonMediaTimeline(
      segments: const [
        LessonMediaSegment(id: 'first', order: 0, durationSec: 10),
        LessonMediaSegment(
          id: 'second',
          order: 1,
          durationSec: 10,
          whiteboardStartCorrectionMs: -1000,
          whiteboardEndCorrectionMs: -1000,
        ),
      ],
    );

    final lookup = resolveLessonWhiteboardPlaybackLookup(
      playbackGlobalSec: 10.5,
      timeline: timeline,
    );

    expect(lookup.segmentId, 'second');
    expect(lookup.globalSec, closeTo(9.999999, 0.0000001));
    expect(lookup.segmentLocalSec, -0.5);
  });
}
