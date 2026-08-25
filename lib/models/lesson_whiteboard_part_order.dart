import 'lesson_media_timeline.dart';
import 'lesson_timed_anchor.dart';
import 'lesson_whiteboard.dart';
import 'lesson_whiteboard_board_set.dart';

class WhiteboardPartOrderPlayback {
  const WhiteboardPartOrderPlayback({
    required this.orderedSegmentIds,
    required this.segmentLocalSec,
    this.activeSegmentId,
  });

  final List<String> orderedSegmentIds;
  final String? activeSegmentId;
  final double segmentLocalSec;

  factory WhiteboardPartOrderPlayback.fromTimeline(
    LessonMediaTimeline timeline, {
    required String? activeSegmentId,
    required double segmentLocalSec,
  }) {
    return WhiteboardPartOrderPlayback(
      orderedSegmentIds: [
        for (final segment in timeline.orderedSegments) segment.id,
      ],
      activeSegmentId: activeSegmentId,
      segmentLocalSec: segmentLocalSec,
    );
  }

  bool get isEmpty => orderedSegmentIds.isEmpty;
}

bool whiteboardPartOrderTimestampIsActive({
  required WhiteboardPartOrderRole role,
  required double timestampSec,
  required WhiteboardPartOrderPlayback playback,
  required double globalSec,
  bool inheritEarlierPartEvents = false,
}) {
  switch (role) {
    case WhiteboardPartOrderRole.earlier:
      // Strokes still inherit earlier parts. Board switches and viewport
      // events do not: each independently recorded part starts from the
      // default board unless that part itself switched.
      return inheritEarlierPartEvents;
    case WhiteboardPartOrderRole.later:
      return false;
    case WhiteboardPartOrderRole.current:
      return timestampSec <= playback.segmentLocalSec;
    case WhiteboardPartOrderRole.untagged:
      return timestampSec <= globalSec;
  }
}

int _partOrderRank(WhiteboardPartOrderRole role) {
  return switch (role) {
    WhiteboardPartOrderRole.earlier => 0,
    WhiteboardPartOrderRole.untagged => 1,
    WhiteboardPartOrderRole.current => 2,
    WhiteboardPartOrderRole.later => 3,
  };
}

List<LessonWhiteboardBoardSwitchEvent> _activeSwitchEvents({
  required BoardSet boardSet,
  required WhiteboardPartOrderPlayback playback,
  required double globalSec,
}) {
  final events = <LessonWhiteboardBoardSwitchEvent>[
    for (final event in boardSet.switchEvents)
      if (whiteboardPartOrderTimestampIsActive(
        role: resolveWhiteboardPartOrderRole(
          segmentId: event.segmentId,
          orderedSegmentIds: playback.orderedSegmentIds,
          activeSegmentId: playback.activeSegmentId,
        ),
        timestampSec: event.globalTimestampSec,
        playback: playback,
        globalSec: globalSec,
      ))
        event,
  ]..sort((left, right) {
    final rankComparison = _partOrderRank(
      resolveWhiteboardPartOrderRole(
        segmentId: left.segmentId,
        orderedSegmentIds: playback.orderedSegmentIds,
        activeSegmentId: playback.activeSegmentId,
      ),
    ).compareTo(
      _partOrderRank(
        resolveWhiteboardPartOrderRole(
          segmentId: right.segmentId,
          orderedSegmentIds: playback.orderedSegmentIds,
          activeSegmentId: playback.activeSegmentId,
        ),
      ),
    );
    if (rankComparison != 0) {
      return rankComparison;
    }
    final timeComparison = left.globalTimestampSec.compareTo(
      right.globalTimestampSec,
    );
    if (timeComparison != 0) {
      return timeComparison;
    }
    return left.sequence.compareTo(right.sequence);
  });
  return events;
}

List<LessonWhiteboardViewportEvent> _activeViewportEvents({
  required BoardSet boardSet,
  required String boardId,
  required WhiteboardPartOrderPlayback playback,
  required double globalSec,
}) {
  final events = <LessonWhiteboardViewportEvent>[
    for (final event in boardSet.viewportEvents)
      if (event.boardId == boardId &&
          whiteboardPartOrderTimestampIsActive(
            role: resolveWhiteboardPartOrderRole(
              segmentId: event.segmentId,
              orderedSegmentIds: playback.orderedSegmentIds,
              activeSegmentId: playback.activeSegmentId,
            ),
            timestampSec: event.globalTimestampSec,
            playback: playback,
            globalSec: globalSec,
          ))
        event,
  ]..sort((left, right) {
    final rankComparison = _partOrderRank(
      resolveWhiteboardPartOrderRole(
        segmentId: left.segmentId,
        orderedSegmentIds: playback.orderedSegmentIds,
        activeSegmentId: playback.activeSegmentId,
      ),
    ).compareTo(
      _partOrderRank(
        resolveWhiteboardPartOrderRole(
          segmentId: right.segmentId,
          orderedSegmentIds: playback.orderedSegmentIds,
          activeSegmentId: playback.activeSegmentId,
        ),
      ),
    );
    if (rankComparison != 0) {
      return rankComparison;
    }
    final timeComparison = left.globalTimestampSec.compareTo(
      right.globalTimestampSec,
    );
    if (timeComparison != 0) {
      return timeComparison;
    }
    return left.sequence.compareTo(right.sequence);
  });
  return events;
}

LessonWhiteboardBoard? resolveBoardAtPartOrder({
  required BoardSet boardSet,
  required double globalTimestampSec,
  WhiteboardPartOrderPlayback? partOrder,
}) {
  if (partOrder == null || partOrder.isEmpty) {
    return boardSet.resolveBoardAt(globalTimestampSec);
  }
  var resolved = boardSet.defaultBoard;
  for (final event in _activeSwitchEvents(
    boardSet: boardSet,
    playback: partOrder,
    globalSec: globalTimestampSec,
  )) {
    resolved = boardSet.boardById(event.boardId) ?? resolved;
  }
  return resolved;
}

LessonWhiteboardViewport resolveViewportAtPartOrder({
  required BoardSet boardSet,
  required String boardId,
  required double globalTimestampSec,
  WhiteboardPartOrderPlayback? partOrder,
}) {
  if (partOrder == null || partOrder.isEmpty) {
    return boardSet.resolveViewportAt(
      boardId: boardId,
      globalTimestampSec: globalTimestampSec,
    );
  }
  final events = _activeViewportEvents(
    boardSet: boardSet,
    boardId: boardId,
    playback: partOrder,
    globalSec: globalTimestampSec,
  );
  if (events.isEmpty) {
    return LessonWhiteboardViewport.full;
  }

  LessonWhiteboardViewportEvent? previous;
  LessonWhiteboardViewportEvent? next;
  final lookupSec = partOrder.segmentLocalSec;
  for (final event in events) {
    final role = resolveWhiteboardPartOrderRole(
      segmentId: event.segmentId,
      orderedSegmentIds: partOrder.orderedSegmentIds,
      activeSegmentId: partOrder.activeSegmentId,
    );
    final eventSec = role == WhiteboardPartOrderRole.untagged
        ? event.globalTimestampSec
        : event.globalTimestampSec;
    final compareSec = role == WhiteboardPartOrderRole.untagged
        ? globalTimestampSec
        : role == WhiteboardPartOrderRole.earlier
        ? double.infinity
        : lookupSec;
    if (eventSec <= compareSec) {
      previous = event;
      continue;
    }
    next = event;
    break;
  }
  if (previous == null) {
    return LessonWhiteboardViewport.full;
  }
  final previousRole = resolveWhiteboardPartOrderRole(
    segmentId: previous.segmentId,
    orderedSegmentIds: partOrder.orderedSegmentIds,
    activeSegmentId: partOrder.activeSegmentId,
  );
  final nextRole = next == null
      ? null
      : resolveWhiteboardPartOrderRole(
          segmentId: next.segmentId,
          orderedSegmentIds: partOrder.orderedSegmentIds,
          activeSegmentId: partOrder.activeSegmentId,
        );
  if (next == null ||
      nextRole != previousRole ||
      next.interactionId != previous.interactionId ||
      next.globalTimestampSec <= previous.globalTimestampSec) {
    return previous.viewport;
  }
  final compareSec = previousRole == WhiteboardPartOrderRole.untagged
      ? globalTimestampSec
      : lookupSec;
  final progress =
      (compareSec - previous.globalTimestampSec) /
      (next.globalTimestampSec - previous.globalTimestampSec);
  return LessonWhiteboardViewport.lerp(
    previous.viewport,
    next.viewport,
    progress,
  );
}

LessonWhiteboardLayerBundle copyWithSegmentLayerStrokes({
  required LessonWhiteboardLayerBundle bundle,
  required String segmentId,
  required List<WhiteboardStroke> strokes,
  int? updatedAtMs,
}) {
  final trimmedId = segmentId.trim();
  if (trimmedId.isEmpty) {
    return bundle.copyWithPrimaryStrokes(
      strokes: strokes,
      updatedAtMs: updatedAtMs,
    );
  }
  final layerId = whiteboardSegmentLayerId(trimmedId);
  final existing = bundle.orderedLayers;
  final index = existing.indexWhere(
    (layer) => layer.id == layerId || layer.segmentId == trimmedId,
  );
  final nowMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
  if (index < 0) {
    if (strokes.isEmpty) {
      return bundle;
    }
    var nextOrder = 0;
    for (final layer in existing) {
      if (layer.order >= nextOrder) {
        nextOrder = layer.order + 1;
      }
    }
    return LessonWhiteboardLayerBundle(
      layers: [
        ...existing,
        LessonWhiteboardLayer(
          id: layerId,
          order: nextOrder,
          anchorType: LessonTimedAnchorType.segment,
          segmentId: trimmedId,
          strokes: strokes,
          updatedAtMs: nowMs,
        ),
      ],
    );
  }
  final current = existing[index];
  return LessonWhiteboardLayerBundle(
    layers: [
      for (var i = 0; i < existing.length; i++)
        if (i == index)
          current.copyWith(
            anchorType: LessonTimedAnchorType.segment,
            segmentId: trimmedId,
            strokes: strokes,
            updatedAtMs: nowMs,
          )
        else
          existing[i],
    ],
  );
}

List<WhiteboardStroke> strokesForSegmentLayer({
  required LessonWhiteboardLayerBundle bundle,
  required String segmentId,
}) {
  final trimmedId = segmentId.trim();
  if (trimmedId.isEmpty) {
    return List<WhiteboardStroke>.from(
      bundle.primaryLayer?.strokes ?? const [],
    );
  }
  final layerId = whiteboardSegmentLayerId(trimmedId);
  for (final layer in bundle.orderedLayers) {
    if (layer.id == layerId || layer.segmentId == trimmedId) {
      return List<WhiteboardStroke>.from(layer.strokes);
    }
  }
  return const [];
}
