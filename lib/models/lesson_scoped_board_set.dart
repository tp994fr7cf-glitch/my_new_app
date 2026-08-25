import 'lesson_timed_anchor.dart';
import 'lesson_whiteboard.dart';
import 'lesson_whiteboard_board_set.dart';
import 'lesson_whiteboard_part_order.dart';

/// Merges one part-scoped editor onto the lesson board set.
///
/// Boards (add/rename/delete) follow [scoped]. Ink, board switches, and
/// viewport events for other parts are kept from [baseline].
BoardSet mergeScopedLessonBoardSet({
  required BoardSet baseline,
  required BoardSet scoped,
  required String segmentId,
}) {
  final trimmedId = segmentId.trim();
  if (trimmedId.isEmpty) {
    return scoped;
  }

  return _withUniqueTimelineSequences(
    BoardSet(
      boards: [
        for (final board in scoped.orderedBoards)
          board.copyWith(
            layerBundle: _mergeScopedBoardLayers(
              baseline: baseline.boardById(board.id)?.layerBundle,
              scoped: board.layerBundle,
              segmentId: trimmedId,
            ),
          ),
      ],
      switchEvents: [
        for (final event in baseline.switchEvents)
          if ((event.segmentId ?? '').trim() != trimmedId) event,
        for (final event in scoped.switchEvents)
          if ((event.segmentId ?? '').trim() == trimmedId) event,
      ],
      viewportEvents: [
        for (final event in baseline.viewportEvents)
          if ((event.segmentId ?? '').trim() != trimmedId) event,
        for (final event in scoped.viewportEvents)
          if ((event.segmentId ?? '').trim() == trimmedId) event,
      ],
    ),
  );
}

/// Clears only one part's ink and that part's recorded screen-share events.
BoardSet clearLessonSegmentWriting({
  required BoardSet boardSet,
  required String segmentId,
}) {
  final trimmedId = segmentId.trim();
  if (trimmedId.isEmpty) {
    return boardSet;
  }

  var next = boardSet;
  for (final board in next.boards) {
    next = next.replaceBoard(
      board.copyWith(
        layerBundle: copyWithSegmentLayerStrokes(
          bundle: board.layerBundle,
          segmentId: trimmedId,
          strokes: const [],
        ),
      ),
    );
  }
  return next.copyWith(
    switchEvents: [
      for (final event in next.switchEvents)
        if ((event.segmentId ?? '').trim() != trimmedId) event,
    ],
    viewportEvents: [
      for (final event in next.viewportEvents)
        if ((event.segmentId ?? '').trim() != trimmedId) event,
    ],
  );
}

/// Replaces one part's recorded screen-share interval without touching others.
BoardSet replaceScopedScreenShareTimelineInterval({
  required BoardSet current,
  required BoardSet baseline,
  required String segmentId,
  required List<String> orderedSegmentIds,
  required double startLocalSec,
  required double endLocalSec,
  required List<LessonWhiteboardBoardSwitchEvent> replacementSwitchEvents,
  required List<LessonWhiteboardViewportEvent> replacementViewportEvents,
}) {
  final trimmedId = segmentId.trim();
  if (trimmedId.isEmpty ||
      !startLocalSec.isFinite ||
      !endLocalSec.isFinite ||
      endLocalSec <= startLocalSec) {
    return current;
  }

  final validBoardIds = current.boards.map((board) => board.id).toSet();
  final replacementSwitches = [
    for (final event in replacementSwitchEvents)
      if (validBoardIds.contains(event.boardId) &&
          event.globalTimestampSec >= startLocalSec &&
          event.globalTimestampSec <= endLocalSec)
        LessonWhiteboardBoardSwitchEvent(
          boardId: event.boardId,
          globalTimestampSec: event.globalTimestampSec,
          sequence: event.sequence,
          segmentId: trimmedId,
        ),
  ];
  final replacementViewports = [
    for (final event in replacementViewportEvents)
      if (validBoardIds.contains(event.boardId) &&
          event.globalTimestampSec >= startLocalSec &&
          event.globalTimestampSec <= endLocalSec)
        LessonWhiteboardViewportEvent(
          boardId: event.boardId,
          globalTimestampSec: event.globalTimestampSec,
          sequence: event.sequence,
          interactionId: event.interactionId,
          viewport: event.viewport,
          segmentId: trimmedId,
        ),
  ];

  bool isThisSegment(String? eventSegmentId) =>
      (eventSegmentId ?? '').trim() == trimmedId;

  var nextSwitchSequence = 0;
  for (final event in current.switchEvents.followedBy(replacementSwitches)) {
    if (event.sequence >= nextSwitchSequence) {
      nextSwitchSequence = event.sequence + 1;
    }
  }
  final endPartOrder = WhiteboardPartOrderPlayback(
    orderedSegmentIds: orderedSegmentIds,
    activeSegmentId: trimmedId,
    segmentLocalSec: endLocalSec,
  );
  final restoredBoard = resolveBoardAtPartOrder(
    boardSet: baseline,
    globalTimestampSec: endLocalSec,
    partOrder: endPartOrder,
  );
  final mergedSwitches = <LessonWhiteboardBoardSwitchEvent>[
    for (final event in current.switchEvents)
      if (!isThisSegment(event.segmentId) ||
          event.globalTimestampSec < startLocalSec ||
          event.globalTimestampSec > endLocalSec)
        event,
    ...replacementSwitches,
    if (restoredBoard != null && validBoardIds.contains(restoredBoard.id))
      LessonWhiteboardBoardSwitchEvent(
        boardId: restoredBoard.id,
        globalTimestampSec: endLocalSec,
        sequence: nextSwitchSequence,
        segmentId: trimmedId,
      ),
  ]..sort(_compareSwitchEvents);

  final touchedBoardIds = <String>{
    for (final event in replacementSwitches) event.boardId,
    for (final event in replacementViewports) event.boardId,
  };
  var nextViewportSequence = 0;
  var nextInteractionId = 0;
  for (final event in current.viewportEvents.followedBy(replacementViewports)) {
    if (event.sequence >= nextViewportSequence) {
      nextViewportSequence = event.sequence + 1;
    }
    if (event.interactionId >= nextInteractionId) {
      nextInteractionId = event.interactionId + 1;
    }
  }
  final startPartOrder = WhiteboardPartOrderPlayback(
    orderedSegmentIds: orderedSegmentIds,
    activeSegmentId: trimmedId,
    segmentLocalSec: startLocalSec,
  );
  final mergedViewports = <LessonWhiteboardViewportEvent>[
    for (final event in current.viewportEvents)
      if (!isThisSegment(event.segmentId) ||
          !touchedBoardIds.contains(event.boardId) ||
          event.globalTimestampSec < startLocalSec ||
          event.globalTimestampSec > endLocalSec)
        event,
    for (final boardId in touchedBoardIds)
      if (validBoardIds.contains(boardId))
        LessonWhiteboardViewportEvent(
          boardId: boardId,
          globalTimestampSec: startLocalSec,
          sequence: -1,
          interactionId: nextInteractionId++,
          viewport: resolveViewportAtPartOrder(
            boardSet: baseline,
            boardId: boardId,
            globalTimestampSec: startLocalSec,
            partOrder: startPartOrder,
          ),
          segmentId: trimmedId,
        ),
    ...replacementViewports,
    for (final boardId in touchedBoardIds)
      if (validBoardIds.contains(boardId))
        LessonWhiteboardViewportEvent(
          boardId: boardId,
          globalTimestampSec: endLocalSec,
          sequence: nextViewportSequence++,
          interactionId: nextInteractionId++,
          viewport: resolveViewportAtPartOrder(
            boardSet: baseline,
            boardId: boardId,
            globalTimestampSec: endLocalSec,
            partOrder: endPartOrder,
          ),
          segmentId: trimmedId,
        ),
  ]..sort(_compareViewportEvents);

  return current.copyWith(
    switchEvents: [
      for (final entry in mergedSwitches.indexed)
        LessonWhiteboardBoardSwitchEvent(
          boardId: entry.$2.boardId,
          globalTimestampSec: entry.$2.globalTimestampSec,
          sequence: entry.$1,
          segmentId: entry.$2.segmentId,
        ),
    ],
    viewportEvents: [
      for (final entry in mergedViewports.indexed)
        LessonWhiteboardViewportEvent(
          boardId: entry.$2.boardId,
          globalTimestampSec: entry.$2.globalTimestampSec,
          sequence: entry.$1,
          interactionId: entry.$2.interactionId,
          viewport: entry.$2.viewport,
          segmentId: entry.$2.segmentId,
        ),
    ],
  );
}

LessonWhiteboardLayerBundle _mergeScopedBoardLayers({
  required LessonWhiteboardLayerBundle? baseline,
  required LessonWhiteboardLayerBundle scoped,
  required String segmentId,
}) {
  final kept = <LessonWhiteboardLayer>[
    for (final layer in baseline?.orderedLayers ?? const <LessonWhiteboardLayer>[])
      if (!_layerBelongsToSegment(layer, segmentId)) layer,
  ];
  final scopedLayer = _segmentLayerFrom(scoped, segmentId);
  if (scopedLayer == null || scopedLayer.strokes.isEmpty) {
    return LessonWhiteboardLayerBundle(layers: kept);
  }
  return LessonWhiteboardLayerBundle(layers: [...kept, scopedLayer]);
}

bool _layerBelongsToSegment(LessonWhiteboardLayer layer, String segmentId) {
  return layer.anchorType == LessonTimedAnchorType.segment &&
      (layer.segmentId ?? '').trim() == segmentId;
}

LessonWhiteboardLayer? _segmentLayerFrom(
  LessonWhiteboardLayerBundle bundle,
  String segmentId,
) {
  final layerId = whiteboardSegmentLayerId(segmentId);
  for (final layer in bundle.orderedLayers) {
    if (layer.id == layerId || layer.segmentId == segmentId) {
      return layer.copyWith(
        anchorType: LessonTimedAnchorType.segment,
        segmentId: segmentId,
      );
    }
  }
  return null;
}

/// Makes switch and viewport sequence numbers unique after a part merge.
///
/// A part editor may re-number its whole in-memory list. Combining that with
/// other parts' original numbers would fail persistence validation.
BoardSet _withUniqueTimelineSequences(BoardSet boardSet) {
  final switches = [...boardSet.switchEvents]..sort(_compareSwitchEvents);
  final viewports = [...boardSet.viewportEvents]..sort(_compareViewportEvents);
  return boardSet.copyWith(
    switchEvents: [
      for (final entry in switches.indexed)
        entry.$2.copyWith(sequence: entry.$1),
    ],
    viewportEvents: [
      for (final entry in viewports.indexed)
        entry.$2.copyWith(sequence: entry.$1),
    ],
  );
}

int _compareSwitchEvents(
  LessonWhiteboardBoardSwitchEvent left,
  LessonWhiteboardBoardSwitchEvent right,
) {
  final timeComparison = left.globalTimestampSec.compareTo(
    right.globalTimestampSec,
  );
  if (timeComparison != 0) {
    return timeComparison;
  }
  return left.sequence.compareTo(right.sequence);
}

int _compareViewportEvents(
  LessonWhiteboardViewportEvent left,
  LessonWhiteboardViewportEvent right,
) {
  final timeComparison = left.globalTimestampSec.compareTo(
    right.globalTimestampSec,
  );
  if (timeComparison != 0) {
    return timeComparison;
  }
  return left.sequence.compareTo(right.sequence);
}
