import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_recording_timeline.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';

void main() {
  test('recording clock excludes time spent paused', () {
    var now = Duration.zero;
    final clock = LessonRecordingClock(now: () => now);

    clock.start();
    now = const Duration(seconds: 2);
    expect(clock.elapsed, const Duration(seconds: 2));

    clock.pause();
    now = const Duration(seconds: 8);
    expect(clock.elapsed, const Duration(seconds: 2));

    clock.resume();
    now = const Duration(seconds: 11);
    expect(clock.elapsed, const Duration(seconds: 5));
  });

  test('recorded whiteboard timestamps scale to actual audio duration', () {
    const stroke = WhiteboardStroke(
      id: 'recorded',
      timestampSec: 30,
      endTimestampSec: 34,
      points: [
        WhiteboardPoint(x: 0, y: 0, timestampSec: 30),
        WhiteboardPoint(x: 1, y: 1, timestampSec: 34),
      ],
    );

    final scaled = scaleRecordedWhiteboardStroke(
      stroke: stroke,
      segmentStartSec: 30,
      scale: 1.5,
      segmentDurationSec: 6,
    );

    expect(scaled.timestampSec, 30);
    expect(scaled.endTimestampSec, 36);
    expect(scaled.points.last.timestampSec, 36);
  });

  test('recording sampler caps ordinary points at twenty per second', () {
    const points = [WhiteboardPoint(x: 0, y: 0, timestampSec: 1)];
    expect(
      shouldSampleRecordedWhiteboardPoint(
        existingPoints: points,
        nextTimestampSec: 1.049,
        force: false,
      ),
      isFalse,
    );
    expect(
      shouldSampleRecordedWhiteboardPoint(
        existingPoints: points,
        nextTimestampSec: 1.05,
        force: false,
      ),
      isTrue,
    );
  });
}
