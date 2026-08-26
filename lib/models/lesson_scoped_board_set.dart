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

/// True when discarding unsaved edits for [segmentId] would change [current].
///
/// Other parts' ink and recorded events are ignored. Board add / rename /
/// delete / PDF are lesson-wide, so those count even when they were made
/// from another part editor.
bool hasUnsavedScopedLessonEdits({
  required BoardSet current,
  required BoardSet lastPersisted,
  required String segmentId,
}) {
  final trimmedId = segmentId.trim();
  if (trimmedId.isEmpty) {
    return false;
  }
  final persisted = lastPersisted.ensureEditable();
  final working = current.ensureEditable();
  return !_sameBoardStructure(working, persisted) ||
      !_sameSegmentStrokes(working, persisted, trimmedId) ||
      !_sameSegmentSwitchEvents(working, persisted, trimmedId) ||
      !_sameSegmentViewportEvents(working, persisted, trimmedId);
}

/// Restores this part's unsaved traces and unsaved board/PDF changes.
///
/// Other parts' unsaved ink on boards that still exist after the restore is
/// kept. Ink on a board that was never saved is dropped with that board.
BoardSet restoreLastPersistedScopedLessonEdits({
  required BoardSet working,
  required BoardSet lastPersisted,
  required String segmentId,
}) {
  return mergeScopedLessonBoardSet(
    baseline: working,
    scoped: lastPersisted.ensureEditable(),
    segmentId: segmentId,
  );
}

bool _sameBoardStructure(BoardSet left, BoardSet right) {
  final leftBoards = left.orderedBoards;
  final rightBoards = right.orderedBoards;
  if (leftBoards.length != rightBoards.length) {
    return false;
  }
  for (var index = 0; index < leftBoards.length; index++) {
    final a = leftBoards[index];
    final b = rightBoards[index];
    if (a.id != b.id || a.title != b.title || a.order != b.order) {
      return false;
    }
    final aBackground = a.background == null
        ? null
        : Map<String, dynamic>.from(a.background!.toMap());
    final bBackground = b.background == null
        ? null
        : Map<String, dynamic>.from(b.background!.toMap());
    if (!_sameMap(aBackground, bBackground)) {
      return false;
    }
  }
  return true;
}

bool _sameSegmentStrokes(BoardSet left, BoardSet right, String segmentId) {
  final boardIds = <String>{
    for (final board in left.orderedBoards) board.id,
    for (final board in right.orderedBoards) board.id,
  };
  for (final boardId in boardIds) {
    final leftStrokes = strokesForSegmentLayer(
      bundle: left.boardById(boardId)?.layerBundle ??
          const LessonWhiteboardLayerBundle(),
      segmentId: segmentId,
    );
    final rightStrokes = strokesForSegmentLayer(
      bundle: right.boardById(boardId)?.layerBundle ??
          const LessonWhiteboardLayerBundle(),
      segmentId: segmentId,
    );
    if (leftStrokes.length != rightStrokes.length) {
      return false;
    }
    for (var index = 0; index < leftStrokes.length; index++) {
      if (!_sameStroke(leftStrokes[index], rightStrokes[index])) {
        return false;
      }
    }
  }
  return true;
}

bool _sameSegmentSwitchEvents(BoardSet left, BoardSet right, String segmentId) {
  return _sameEventMaps(
    _segmentSwitchMaps(left, segmentId),
    _segmentSwitchMaps(right, segmentId),
  );
}

bool _sameSegmentViewportEvents(
  BoardSet left,
  BoardSet right,
  String segmentId,
) {
  return _sameEventMaps(
    _segmentViewportMaps(left, segmentId),
    _segmentViewportMaps(right, segmentId),
  );
}

List<Map<String, dynamic>> _segmentSwitchMaps(
  BoardSet boardSet,
  String segmentId,
) {
  final events = [
    for (final event in boardSet.switchEvents)
      if ((event.segmentId ?? '').trim() == segmentId)
        <String, dynamic>{
          'boardId': event.boardId,
          'globalTimestampSec': event.globalTimestampSec,
        },
  ];
  events.sort(_compareEventMaps);
  return events;
}

List<Map<String, dynamic>> _segmentViewportMaps(
  BoardSet boardSet,
  String segmentId,
) {
  final events = [
    for (final event in boardSet.viewportEvents)
      if ((event.segmentId ?? '').trim() == segmentId)
        <String, dynamic>{
          'boardId': event.boardId,
          'globalTimestampSec': event.globalTimestampSec,
          'interactionId': event.interactionId,
          'centerX': event.viewport.centerX,
          'centerY': event.viewport.centerY,
          'scale': event.viewport.scale,
        },
  ];
  events.sort(_compareEventMaps);
  return events;
}

int _compareEventMaps(Map<String, dynamic> left, Map<String, dynamic> right) {
  final leftTime = left['globalTimestampSec'];
  final rightTime = right['globalTimestampSec'];
  if (leftTime is num && rightTime is num) {
    final timeComparison = leftTime.compareTo(rightTime);
    if (timeComparison != 0) {
      return timeComparison;
    }
  }
  final leftBoard = left['boardId']?.toString() ?? '';
  final rightBoard = right['boardId']?.toString() ?? '';
  return leftBoard.compareTo(rightBoard);
}

bool _sameStroke(WhiteboardStroke left, WhiteboardStroke right) {
  if (left.id != right.id ||
      left.timestampSec != right.timestampSec ||
      left.endTimestampSec != right.endTimestampSec ||
      left.hiddenAtSec != right.hiddenAtSec ||
      left.colorArgb != right.colorArgb ||
      left.strokeWidth != right.strokeWidth ||
      left.points.length != right.points.length) {
    return false;
  }
  for (var index = 0; index < left.points.length; index++) {
    final a = left.points[index];
    final b = right.points[index];
    if (a.x != b.x || a.y != b.y || a.timestampSec != b.timestampSec) {
      return false;
    }
  }
  return true;
}

bool _sameEventMaps(
  List<Map<String, dynamic>> left,
  List<Map<String, dynamic>> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (!_sameMap(left[index], right[index])) {
      return false;
    }
  }
  return true;
}

bool _sameMap(Map<String, dynamic>? left, Map<String, dynamic>? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
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
///
/// When [pinUntilPartEnd] is true, later automatic switches and zooms in this
/// part are dropped so [pinnedBoardId] and [pinnedViewport] stay until the
/// part ends. Other parts are left unchanged.
BoardSet replaceScopedScreenShareTimelineInterval({
  required BoardSet current,
  required BoardSet baseline,
  required String segmentId,
  required List<String> orderedSegmentIds,
  required double startLocalSec,
  required double endLocalSec,
  required List<LessonWhiteboardBoardSwitchEvent> replacementSwitchEvents,
  required List<LessonWhiteboardViewportEvent> replacementViewportEvents,
  bool pinUntilPartEnd = false,
  String? pinnedBoardId,
  LessonWhiteboardViewport? pinnedViewport,
}) {
  final trimmedId = segmentId.trim();
  if (trimmedId.isEmpty ||
      !startLocalSec.isFinite ||
      !endLocalSec.isFinite ||
      endLocalSec < startLocalSec) {
    return current;
  }
  if (!pinUntilPartEnd && endLocalSec <= startLocalSec) {
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
  final pinBoardId =
      pinnedBoardId != null && validBoardIds.contains(pinnedBoardId)
      ? pinnedBoardId
      : null;
  bool keepThisSegmentSwitch(LessonWhiteboardBoardSwitchEvent event) {
    if (pinUntilPartEnd) {
      return event.globalTimestampSec < startLocalSec;
    }
    return event.globalTimestampSec < startLocalSec ||
        event.globalTimestampSec > endLocalSec;
  }

  final mergedSwitches = <LessonWhiteboardBoardSwitchEvent>[
    for (final event in current.switchEvents)
      if (!isThisSegment(event.segmentId) || keepThisSegmentSwitch(event))
        event,
    ...replacementSwitches,
    if (pinUntilPartEnd && pinBoardId != null)
      LessonWhiteboardBoardSwitchEvent(
        boardId: pinBoardId,
        globalTimestampSec: endLocalSec,
        sequence: nextSwitchSequence,
        segmentId: trimmedId,
      )
    else if (!pinUntilPartEnd &&
        restoredBoard != null &&
        validBoardIds.contains(restoredBoard.id))
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
  bool keepThisSegmentViewport(LessonWhiteboardViewportEvent event) {
    if (pinUntilPartEnd) {
      return event.globalTimestampSec < startLocalSec;
    }
    return !touchedBoardIds.contains(event.boardId) ||
        event.globalTimestampSec < startLocalSec ||
        event.globalTimestampSec > endLocalSec;
  }

  final mergedViewports = <LessonWhiteboardViewportEvent>[
    for (final event in current.viewportEvents)
      if (!isThisSegment(event.segmentId) || keepThisSegmentViewport(event))
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
    if (pinUntilPartEnd && pinBoardId != null)
      LessonWhiteboardViewportEvent(
        boardId: pinBoardId,
        globalTimestampSec: endLocalSec,
        sequence: nextViewportSequence++,
        interactionId: nextInteractionId++,
        viewport: pinnedViewport ?? LessonWhiteboardViewport.full,
        segmentId: trimmedId,
      )
    else if (!pinUntilPartEnd)
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
