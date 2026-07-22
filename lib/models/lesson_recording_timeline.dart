import 'lesson_whiteboard.dart';
import 'lesson_whiteboard_board_set.dart';

typedef LessonMonotonicNow = Duration Function();

class LessonRecordingClock {
  LessonRecordingClock({LessonMonotonicNow? now}) : _now = now ?? _systemNow();

  final LessonMonotonicNow _now;
  Duration _elapsedBeforeRun = Duration.zero;
  Duration? _startedAt;

  bool get isRunning => _startedAt != null;

  Duration get elapsed {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return _elapsedBeforeRun;
    }
    return _elapsedBeforeRun + (_now() - startedAt);
  }

  double get elapsedSeconds => elapsed.inMicroseconds / 1000000;

  void start() {
    _elapsedBeforeRun = Duration.zero;
    _startedAt = _now();
  }

  void pause() {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return;
    }
    _elapsedBeforeRun += _now() - startedAt;
    _startedAt = null;
  }

  void resume() {
    if (_startedAt != null) {
      return;
    }
    _startedAt = _now();
  }

  void reset() {
    _elapsedBeforeRun = Duration.zero;
    _startedAt = null;
  }

  static LessonMonotonicNow _systemNow() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}

bool shouldSampleRecordedWhiteboardPoint({
  required List<WhiteboardPoint> existingPoints,
  required double nextTimestampSec,
  required bool force,
}) {
  if (force || existingPoints.isEmpty) {
    return true;
  }
  final previousTimestampSec = existingPoints.last.timestampSec;
  if (previousTimestampSec == null) {
    return true;
  }
  return nextTimestampSec - previousTimestampSec >=
      whiteboardMinPointIntervalSec;
}

WhiteboardStroke scaleRecordedWhiteboardStroke({
  required WhiteboardStroke stroke,
  required double segmentStartSec,
  required double scale,
  required double segmentDurationSec,
}) {
  double scaleTimestamp(double timestampSec) {
    final localSec = (timestampSec - segmentStartSec).clamp(
      0.0,
      double.infinity,
    );
    return segmentStartSec + (localSec * scale).clamp(0.0, segmentDurationSec);
  }

  return WhiteboardStroke(
    id: stroke.id,
    timestampSec: scaleTimestamp(stroke.timestampSec),
    endTimestampSec: stroke.endTimestampSec == null
        ? null
        : scaleTimestamp(stroke.endTimestampSec!),
    points: [
      for (final point in stroke.points)
        WhiteboardPoint(
          x: point.x,
          y: point.y,
          timestampSec: point.timestampSec == null
              ? null
              : scaleTimestamp(point.timestampSec!),
        ),
    ],
    colorArgb: stroke.colorArgb,
    strokeWidth: stroke.strokeWidth,
  );
}

LessonWhiteboardViewportEvent scaleRecordedViewportEvent({
  required LessonWhiteboardViewportEvent event,
  required double segmentStartSec,
  required double scale,
  required double segmentDurationSec,
}) {
  final localSec = (event.globalTimestampSec - segmentStartSec).clamp(
    0.0,
    double.infinity,
  );
  return LessonWhiteboardViewportEvent(
    boardId: event.boardId,
    globalTimestampSec:
        segmentStartSec + (localSec * scale).clamp(0.0, segmentDurationSec),
    sequence: event.sequence,
    interactionId: event.interactionId,
    viewport: event.viewport,
  );
}
