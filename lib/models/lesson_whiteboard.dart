import 'dart:math' as math;
import 'dart:ui';

class LessonWhiteboard {
  const LessonWhiteboard({
    this.version = currentVersion,
    this.strokes = const [],
    this.updatedAtMs = 0,
  });

  static const int currentVersion = 1;

  final int version;
  final List<WhiteboardStroke> strokes;
  final int updatedAtMs;

  bool get isEmpty => strokes.isEmpty;

  LessonWhiteboard copyWith({
    int? version,
    List<WhiteboardStroke>? strokes,
    int? updatedAtMs,
  }) {
    return LessonWhiteboard(
      version: version ?? this.version,
      strokes: strokes ?? this.strokes,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  factory LessonWhiteboard.fromMap(Map? data) {
    if (data == null) {
      return const LessonWhiteboard();
    }

    final strokesData = data['strokes'];
    return LessonWhiteboard(
      version: (data['version'] as num?)?.toInt() ?? currentVersion,
      strokes: strokesData is List
          ? strokesData
                .whereType<Map>()
                .map(WhiteboardStroke.fromMap)
                .toList()
          : const [],
      updatedAtMs: (data['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    if (isEmpty) {
      return const {};
    }

    return {
      'version': version,
      'strokes': strokes.map((stroke) => stroke.toMap()).toList(),
      if (updatedAtMs > 0) 'updatedAtMs': updatedAtMs,
    };
  }
}

class WhiteboardStroke {
  const WhiteboardStroke({
    required this.id,
    required this.timestampSec,
    required this.points,
    this.endTimestampSec,
    this.colorArgb = 0xFF000000,
    this.strokeWidth = 3,
  });

  final String id;
  final double timestampSec;
  final double? endTimestampSec;
  final List<WhiteboardPoint> points;
  final int colorArgb;
  final double strokeWidth;

  bool get hasPointTimestamps =>
      points.isNotEmpty && points.every((point) => point.hasTimestamp);

  factory WhiteboardStroke.fromMap(Map data) {
    final pointsData = data['points'];

    return WhiteboardStroke(
      id: data['id'] as String? ?? '',
      timestampSec: (data['timestampSec'] as num?)?.toDouble() ?? 0,
      endTimestampSec: (data['endTimestampSec'] as num?)?.toDouble(),
      points: pointsData is List
          ? pointsData
                .whereType<Map>()
                .map(WhiteboardPoint.fromMap)
                .toList()
          : const [],
      colorArgb: (data['colorArgb'] as num?)?.toInt() ?? 0xFF000000,
      strokeWidth: (data['strokeWidth'] as num?)?.toDouble() ?? 3,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestampSec': timestampSec,
      if (endTimestampSec != null) 'endTimestampSec': endTimestampSec,
      'points': points.map((point) => point.toMap()).toList(),
      'colorArgb': colorArgb,
      'strokeWidth': strokeWidth,
    };
  }

  WhiteboardStroke copyWith({
    List<WhiteboardPoint>? points,
  }) {
    return WhiteboardStroke(
      id: id,
      timestampSec: timestampSec,
      endTimestampSec: endTimestampSec,
      points: points ?? this.points,
      colorArgb: colorArgb,
      strokeWidth: strokeWidth,
    );
  }
}

class WhiteboardPoint {
  const WhiteboardPoint({
    required this.x,
    required this.y,
    this.timestampSec,
  });

  final double x;
  final double y;
  final double? timestampSec;

  bool get hasTimestamp => timestampSec != null;

  factory WhiteboardPoint.fromMap(Map data) {
    return WhiteboardPoint(
      x: (data['x'] as num?)?.toDouble() ?? 0,
      y: (data['y'] as num?)?.toDouble() ?? 0,
      timestampSec: (data['timestampSec'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      if (timestampSec != null) 'timestampSec': timestampSec,
    };
  }

  Offset toOffset() => Offset(x, y);
}

const double whiteboardMinPointIntervalSec = 0.05;
const double whiteboardMinPointDistance = 0.005;

bool shouldSampleWhiteboardPoint({
  required List<WhiteboardPoint> existingPoints,
  required WhiteboardPoint nextPoint,
  required double nextTimestampSec,
  required bool force,
}) {
  if (force || existingPoints.isEmpty) {
    return true;
  }

  final lastPoint = existingPoints.last;
  final lastTimestampSec = lastPoint.timestampSec;
  if (lastTimestampSec == null) {
    return true;
  }

  final elapsedSec = nextTimestampSec - lastTimestampSec;
  if (elapsedSec >= whiteboardMinPointIntervalSec) {
    return true;
  }

  final dx = nextPoint.x - lastPoint.x;
  final dy = nextPoint.y - lastPoint.y;
  final distance = math.sqrt(dx * dx + dy * dy);
  return distance >= whiteboardMinPointDistance;
}

List<WhiteboardStroke> visibleWhiteboardStrokes({
  required List<WhiteboardStroke> strokes,
  required double positionSec,
}) {
  final visibleStrokes = <WhiteboardStroke>[];

  for (final stroke in strokes) {
    final visibleStroke = visiblePortionOfWhiteboardStroke(
      stroke: stroke,
      positionSec: positionSec,
    );
    if (visibleStroke != null) {
      visibleStrokes.add(visibleStroke);
    }
  }

  return visibleStrokes;
}

WhiteboardStroke? visiblePortionOfWhiteboardStroke({
  required WhiteboardStroke stroke,
  required double positionSec,
}) {
  if (stroke.timestampSec > positionSec) {
    return null;
  }

  if (!stroke.hasPointTimestamps) {
    return stroke;
  }

  final visiblePoints = stroke.points
      .where(
        (point) => point.timestampSec != null && point.timestampSec! <= positionSec,
      )
      .toList(growable: false);
  if (visiblePoints.length < 2) {
    return null;
  }

  return stroke.copyWith(points: visiblePoints);
}

LessonWhiteboard mergeWhiteboardDraft({
  required LessonWhiteboard? published,
  required LessonWhiteboard? draft,
}) {
  if (draft != null && !draft.isEmpty) {
    return draft;
  }
  return published ?? const LessonWhiteboard();
}

enum WhiteboardEditSessionKind {
  none,
  fresh,
  published,
  draft,
  pendingReset,
}

/// Chooses which whiteboard should be published when saving lesson info.
/// Unsaved in-memory edits are ignored when a published whiteboard already exists.
LessonWhiteboard? resolveWhiteboardForLessonPublish({
  required LessonWhiteboard? publishedWhiteboard,
  required LessonWhiteboard? draftWhiteboard,
  required LessonWhiteboard workingWhiteboard,
}) {
  if (draftWhiteboard != null && !draftWhiteboard.isEmpty) {
    return draftWhiteboard;
  }
  if (publishedWhiteboard != null && !publishedWhiteboard.isEmpty) {
    return publishedWhiteboard;
  }
  return workingWhiteboard.isEmpty ? null : workingWhiteboard;
}
