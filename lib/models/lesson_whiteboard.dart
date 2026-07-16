import 'dart:math' as math;
import 'dart:ui';

import 'lesson_timed_anchor.dart';

class LessonWhiteboardLayer {
  const LessonWhiteboardLayer({
    required this.id,
    required this.order,
    this.title = '',
    this.anchorType = LessonTimedAnchorType.global,
    this.segmentId,
    this.visibleFromSec,
    this.visibleUntilSec,
    this.strokes = const [],
    this.updatedAtMs = 0,
  });

  static const String primaryLayerId = 'primary';

  final String id;
  final int order;
  final String title;
  final LessonTimedAnchorType anchorType;
  final String? segmentId;
  final double? visibleFromSec;
  final double? visibleUntilSec;
  final List<WhiteboardStroke> strokes;
  final int updatedAtMs;

  bool get isEmpty => strokes.isEmpty;

  factory LessonWhiteboardLayer.fromMap(Map data) {
    final strokesData = data['strokes'];
    return LessonWhiteboardLayer(
      id: data['id'] as String? ?? primaryLayerId,
      order: (data['order'] as num?)?.toInt() ?? 0,
      title: data['title'] as String? ?? '',
      anchorType: LessonTimedAnchorType.fromStorage(data['anchorType'] as String?),
      segmentId: data['segmentId'] as String?,
      visibleFromSec: (data['visibleFromSec'] as num?)?.toDouble(),
      visibleUntilSec: (data['visibleUntilSec'] as num?)?.toDouble(),
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
    if (isEmpty &&
        title.isEmpty &&
        visibleFromSec == null &&
        visibleUntilSec == null) {
      return const {};
    }

    return {
      'id': id,
      'order': order,
      if (title.isNotEmpty) 'title': title,
      'anchorType': anchorType.toStorage(),
      if (segmentId != null && segmentId!.isNotEmpty) 'segmentId': segmentId,
      if (visibleFromSec != null) 'visibleFromSec': visibleFromSec,
      if (visibleUntilSec != null) 'visibleUntilSec': visibleUntilSec,
      if (strokes.isNotEmpty)
        'strokes': strokes.map((stroke) => stroke.toMap()).toList(),
      if (updatedAtMs > 0) 'updatedAtMs': updatedAtMs,
    };
  }

  LessonWhiteboardLayer copyWith({
    String? id,
    int? order,
    String? title,
    LessonTimedAnchorType? anchorType,
    String? segmentId,
    double? visibleFromSec,
    double? visibleUntilSec,
    List<WhiteboardStroke>? strokes,
    int? updatedAtMs,
  }) {
    return LessonWhiteboardLayer(
      id: id ?? this.id,
      order: order ?? this.order,
      title: title ?? this.title,
      anchorType: anchorType ?? this.anchorType,
      segmentId: segmentId ?? this.segmentId,
      visibleFromSec: visibleFromSec ?? this.visibleFromSec,
      visibleUntilSec: visibleUntilSec ?? this.visibleUntilSec,
      strokes: strokes ?? this.strokes,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}

class LessonWhiteboardLayerBundle {
  const LessonWhiteboardLayerBundle({this.layers = const []});

  final List<LessonWhiteboardLayer> layers;

  bool get isEmpty => layers.isEmpty || layers.every((layer) => layer.isEmpty);

  List<LessonWhiteboardLayer> get orderedLayers {
    final sorted = List<LessonWhiteboardLayer>.from(layers)
      ..sort((a, b) => a.order.compareTo(b.order));
    return sorted;
  }

  LessonWhiteboardLayer? get primaryLayer {
    final ordered = orderedLayers.where((layer) => !layer.isEmpty).toList();
    if (ordered.isEmpty) {
      return null;
    }
    return ordered.firstWhere(
      (layer) => layer.id == LessonWhiteboardLayer.primaryLayerId,
      orElse: () => ordered.first,
    );
  }

  factory LessonWhiteboardLayerBundle.fromMap(Object? data) {
    if (data is! List) {
      return const LessonWhiteboardLayerBundle();
    }
    return LessonWhiteboardLayerBundle(
      layers: data
          .whereType<Map>()
          .map(LessonWhiteboardLayer.fromMap)
          .where((layer) => layer.toMap().isNotEmpty)
          .toList(),
    );
  }

  List<Map<String, dynamic>> toMapList() {
    return orderedLayers
        .map((layer) => layer.toMap())
        .where((map) => map.isNotEmpty)
        .toList();
  }

  LessonWhiteboard? toLegacyWhiteboard() {
    final layer = primaryLayer;
    if (layer == null || layer.isEmpty) {
      return null;
    }
    return LessonWhiteboard(
      version: LessonWhiteboard.currentVersion,
      strokes: layer.strokes,
      updatedAtMs: layer.updatedAtMs,
    );
  }

  factory LessonWhiteboardLayerBundle.fromLegacyWhiteboard(
    LessonWhiteboard? whiteboard,
  ) {
    if (whiteboard == null || whiteboard.isEmpty) {
      return const LessonWhiteboardLayerBundle();
    }
    return LessonWhiteboardLayerBundle(
      layers: [
        LessonWhiteboardLayer(
          id: LessonWhiteboardLayer.primaryLayerId,
          order: 0,
          anchorType: LessonTimedAnchorType.global,
          strokes: whiteboard.strokes,
          updatedAtMs: whiteboard.updatedAtMs,
        ),
      ],
    );
  }

  LessonWhiteboardLayerBundle copyWithPrimaryStrokes({
    required List<WhiteboardStroke> strokes,
    int? updatedAtMs,
  }) {
    final primary = primaryLayer;
    if (primary == null) {
      if (strokes.isEmpty) {
        return this;
      }
      return LessonWhiteboardLayerBundle(
        layers: [
          LessonWhiteboardLayer(
            id: LessonWhiteboardLayer.primaryLayerId,
            order: 0,
            anchorType: LessonTimedAnchorType.global,
            strokes: strokes,
            updatedAtMs: updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
          ),
        ],
      );
    }

    final nextLayers = orderedLayers.map((layer) {
      if (layer.id != primary.id) {
        return layer;
      }
      return layer.copyWith(
        strokes: strokes,
        updatedAtMs: updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();

    return LessonWhiteboardLayerBundle(layers: nextLayers);
  }
}

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

LessonWhiteboardLayerBundle mergeWhiteboardDraftLayers({
  required LessonWhiteboardLayerBundle? published,
  required LessonWhiteboardLayerBundle? draft,
}) {
  if (draft != null && !draft.isEmpty) {
    return draft;
  }
  return published ?? const LessonWhiteboardLayerBundle();
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

List<LessonWhiteboardLayer> resolveWhiteboardLayersForLessonPublish({
  required List<LessonWhiteboardLayer> publishedLayers,
  required List<LessonWhiteboardLayer> draftLayers,
  required LessonWhiteboardLayerBundle workingLayers,
}) {
  if (draftLayers.isNotEmpty) {
    return draftLayers;
  }
  if (publishedLayers.isNotEmpty) {
    return publishedLayers;
  }
  return workingLayers.isEmpty ? const [] : workingLayers.orderedLayers;
}

double resolveWhiteboardLayerPositionSec({
  required LessonWhiteboardLayer layer,
  required double globalPositionSec,
  required double segmentLocalPositionSec,
}) {
  if (layer.anchorType == LessonTimedAnchorType.segment) {
    return segmentLocalPositionSec;
  }
  return globalPositionSec;
}

bool isWhiteboardLayerVisible({
  required LessonWhiteboardLayer layer,
  required double positionSec,
}) {
  final from = layer.visibleFromSec;
  final until = layer.visibleUntilSec;
  if (from != null && positionSec < from) {
    return false;
  }
  if (until != null && positionSec > until) {
    return false;
  }
  return true;
}

List<WhiteboardStroke> visibleWhiteboardLayerStrokes({
  required LessonWhiteboardLayer layer,
  required double positionSec,
}) {
  if (!isWhiteboardLayerVisible(layer: layer, positionSec: positionSec)) {
    return const [];
  }
  return visibleWhiteboardStrokes(strokes: layer.strokes, positionSec: positionSec);
}

List<WhiteboardStroke> visibleWhiteboardBundleStrokes({
  required LessonWhiteboardLayerBundle bundle,
  required double globalPositionSec,
  required double segmentLocalPositionSec,
  String? activeSegmentId,
}) {
  final visibleStrokes = <WhiteboardStroke>[];
  for (final layer in bundle.orderedLayers) {
    if (layer.anchorType == LessonTimedAnchorType.segment) {
      final layerSegmentId = layer.segmentId;
      if (layerSegmentId != null &&
          layerSegmentId.isNotEmpty &&
          activeSegmentId != null &&
          layerSegmentId != activeSegmentId) {
        continue;
      }
    }
    final positionSec = resolveWhiteboardLayerPositionSec(
      layer: layer,
      globalPositionSec: globalPositionSec,
      segmentLocalPositionSec: segmentLocalPositionSec,
    );
    visibleStrokes.addAll(
      visibleWhiteboardLayerStrokes(layer: layer, positionSec: positionSec),
    );
  }
  return visibleStrokes;
}
