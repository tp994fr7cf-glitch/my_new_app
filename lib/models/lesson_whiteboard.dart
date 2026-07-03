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
}

class WhiteboardPoint {
  const WhiteboardPoint({required this.x, required this.y});

  final double x;
  final double y;

  factory WhiteboardPoint.fromMap(Map data) {
    return WhiteboardPoint(
      x: (data['x'] as num?)?.toDouble() ?? 0,
      y: (data['y'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {'x': x, 'y': y};
  }

  Offset toOffset() => Offset(x, y);
}

List<WhiteboardStroke> visibleWhiteboardStrokes({
  required List<WhiteboardStroke> strokes,
  required double positionSec,
}) {
  return strokes
      .where((stroke) => stroke.timestampSec <= positionSec)
      .toList(growable: false);
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
