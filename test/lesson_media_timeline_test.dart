import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_media_timeline.dart';

void main() {
  group('LessonMediaTimeline', () {
    final segments = [
      const LessonMediaSegment(
        id: 'seg-1',
        order: 0,
        mediaType: 'audio',
        url: 'https://example.com/a.mp3',
        durationSec: 30,
      ),
      const LessonMediaSegment(
        id: 'seg-2',
        order: 1,
        mediaType: 'video',
        url: 'https://example.com/b.mp4',
        durationSec: 60,
      ),
      const LessonMediaSegment(
        id: 'seg-3',
        order: 2,
        mediaType: 'audio',
        url: 'https://example.com/c.mp3',
        durationSec: 60,
      ),
    ];

    test('totalDurationSec sums all segments', () {
      final timeline = LessonMediaTimeline(segments: segments);
      expect(timeline.totalDurationSec, 150);
    });

    test('resolveGlobalSec maps to segment-local position', () {
      final timeline = LessonMediaTimeline(segments: segments);
      final position = timeline.resolveGlobalSec(45);
      expect(position.segmentIndex, 1);
      expect(position.segmentId, 'seg-2');
      expect(position.localSec, 15);
      expect(position.globalSec, 45);
    });

    test('globalSecForSegmentLocal converts back to global seconds', () {
      final timeline = LessonMediaTimeline(segments: segments);
      expect(
        timeline.globalSecForSegmentLocal(segmentId: 'seg-3', localSec: 10),
        100,
      );
    });

    test('startGlobalSecForSegmentIndex returns segment offsets', () {
      final timeline = LessonMediaTimeline(segments: segments);
      expect(timeline.startGlobalSecForSegmentIndex(0), 0);
      expect(timeline.startGlobalSecForSegmentIndex(1), 30);
      expect(timeline.startGlobalSecForSegmentIndex(2), 90);
    });

    test('uses millisecond duration for exact recorded-audio boundaries', () {
      final recordedSegment = const LessonMediaSegment(
        id: 'recorded',
        order: 0,
        mediaType: 'audio',
        url: 'https://example.com/recorded.m4a',
        durationSec: 7,
        durationMs: 7200,
      );
      final timeline = LessonMediaTimeline(
        segments: [
          recordedSegment,
          const LessonMediaSegment(
            id: 'next',
            order: 1,
            url: 'https://example.com/next.mp4',
            durationSec: 5,
          ),
        ],
      );

      expect(recordedSegment.toMap()['durationMs'], 7200);
      expect(
        LessonMediaSegment.fromMap(recordedSegment.toMap()).durationSecExact,
        7.2,
      );
      expect(timeline.startGlobalSecForSegmentIndex(1), 7.2);
      expect(timeline.totalDurationSecExact, 12.2);
      expect(timeline.resolveGlobalSec(7.1).segmentId, 'recorded');
      expect(timeline.resolveGlobalSec(7.3).segmentId, 'next');
      expect(timeline.resolveGlobalSec(7.3).localSec, closeTo(0.1, 0.0001));
    });
  });
}
