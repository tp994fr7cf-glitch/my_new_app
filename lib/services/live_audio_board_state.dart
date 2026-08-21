import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';
import '../models/lesson_whiteboard_part_order.dart';
import 'live_audio_probe_message.dart';

class LiveAudioBoardState {
  LiveAudioBoardState({
    required this.boardSet,
    required this.selectedBoardId,
    Map<String, WhiteboardStroke> inProgressStrokes = const {},
    Set<String> savedStrokeIds = const {},
  }) : inProgressStrokes = Map.unmodifiable(inProgressStrokes),
       savedStrokeIds = Set.unmodifiable(savedStrokeIds);

  factory LiveAudioBoardState.initial() {
    const board = LessonWhiteboardBoard(
      id: LessonWhiteboardBoard.defaultBoardId,
      order: 0,
      title: 'ボード1',
    );
    return LiveAudioBoardState(
      boardSet: const BoardSet(boards: [board]),
      selectedBoardId: board.id,
    );
  }

  factory LiveAudioBoardState.fromBoardSet(
    BoardSet boardSet, {
    double? selectedAtSec,
    WhiteboardPartOrderPlayback? partOrder,
  }) {
    final normalized = boardSet.isEmpty
        ? LiveAudioBoardState.initial().boardSet
        : boardSet;
    final selectedId = partOrder == null
        ? (selectedAtSec == null
              ? normalized.orderedSwitchEvents.lastOrNull?.boardId
              : normalized.resolveBoardAt(selectedAtSec)?.id)
        : resolveBoardAtPartOrder(
            boardSet: normalized,
            globalTimestampSec: selectedAtSec ?? 0,
            partOrder: partOrder,
          )?.id;
    return LiveAudioBoardState(
      boardSet: normalized,
      selectedBoardId:
          selectedId ??
          normalized.defaultBoard?.id ??
          LessonWhiteboardBoard.defaultBoardId,
      savedStrokeIds: {
        for (final board in normalized.boards)
          for (final layer in board.layerBundle.layers)
            for (final stroke in layer.strokes) stroke.id,
      },
    );
  }

  final BoardSet boardSet;
  final String selectedBoardId;
  final Map<String, WhiteboardStroke> inProgressStrokes;
  final Set<String> savedStrokeIds;

  LessonWhiteboardBoard get selectedBoard =>
      boardSet.boardById(selectedBoardId) ??
      boardSet.defaultBoard ??
      LiveAudioBoardState.initial().selectedBoard;

  LessonWhiteboardViewport get selectedViewport => boardSet.resolveViewportAt(
    boardId: selectedBoard.id,
    globalTimestampSec: double.infinity,
  );

  List<WhiteboardStroke> get selectedCompletedStrokes =>
      selectedBoard.layerBundle.namedPrimaryLayer?.strokes ?? const [];

  List<WhiteboardStroke> get selectedRemoteInProgressStrokes =>
      remoteInProgressStrokesForBoard(selectedBoardId);

  List<WhiteboardStroke> remoteInProgressStrokesForBoard(String boardId) =>
      inProgressStrokes.entries
          .where((entry) => entry.key.startsWith('$boardId\u0000'))
          .map((entry) => entry.value)
          .toList(growable: false);

  LiveAudioBoardState replaceSnapshot(
    BoardSet snapshot, {
    required bool preserveSelectedBoard,
  }) {
    final restored = LiveAudioBoardState.fromBoardSet(snapshot);
    return LiveAudioBoardState(
      boardSet: restored.boardSet,
      selectedBoardId:
          preserveSelectedBoard &&
              restored.boardSet.boardById(selectedBoardId) != null
          ? selectedBoardId
          : restored.selectedBoardId,
      inProgressStrokes: inProgressStrokes,
      savedStrokeIds: {...savedStrokeIds, ...restored.savedStrokeIds},
    );
  }

  LiveAudioBoardState applyMessage(
    LiveAudioProbeMessage message, {
    String? localStrokeId,
  }) {
    switch (message.kind) {
      case LiveAudioProbeMessageKind.boardCreate:
        return _createBoard(
          boardId: message.boardId,
          order: message.boardOrder ?? boardSet.boards.length,
          title: message.boardTitle ?? '',
        );
      case LiveAudioProbeMessageKind.boardSwitch:
        return _switchBoard(
          message.boardId,
          timestampSec: message.timestampSec,
        );
      case LiveAudioProbeMessageKind.viewport:
        final viewport = message.viewport;
        if (viewport == null || boardSet.boardById(message.boardId) == null) {
          return this;
        }
        return LiveAudioBoardState(
          boardSet: boardSet.copyWith(
            viewportEvents: _boundedViewportEvents([
              ...boardSet.viewportEvents,
              LessonWhiteboardViewportEvent(
                boardId: message.boardId,
                globalTimestampSec: message.timestampSec,
                sequence: boardSet.nextViewportSequence,
                interactionId:
                    message.interactionId ?? boardSet.nextViewportInteractionId,
                viewport: viewport,
              ),
            ]),
          ),
          selectedBoardId: selectedBoardId,
          inProgressStrokes: inProgressStrokes,
          savedStrokeIds: savedStrokeIds,
        );
      case LiveAudioProbeMessageKind.strokeStart:
      case LiveAudioProbeMessageKind.strokePoint:
      case LiveAudioProbeMessageKind.strokeEnd:
        if (message.strokeId == localStrokeId ||
            savedStrokeIds.contains(message.strokeId) ||
            boardSet.boardById(message.boardId) == null) {
          return this;
        }
        return _applyStrokeMessage(message);
    }
  }

  LiveAudioBoardState saveCompletedStroke({
    required String boardId,
    required WhiteboardStroke stroke,
    bool markSaved = false,
  }) {
    final board = boardSet.boardById(boardId);
    if (board == null) {
      return this;
    }
    final existing = board.layerBundle.namedPrimaryLayer?.strokes ?? const [];
    final nextStrokes =
        [
          for (final item in existing)
            if (item.id != stroke.id) item,
          stroke,
        ]..sort((a, b) {
          final byTime = a.timestampSec.compareTo(b.timestampSec);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
    final nextBoard = board.copyWith(
      layerBundle: board.layerBundle.copyWithNamedPrimaryStrokes(
        strokes: nextStrokes,
      ),
    );
    return LiveAudioBoardState(
      boardSet: boardSet.copyWith(
        boards: [
          for (final item in boardSet.boards)
            if (item.id == boardId) nextBoard else item,
        ],
      ),
      selectedBoardId: selectedBoardId,
      inProgressStrokes: {
        for (final entry in inProgressStrokes.entries)
          if (entry.key != _strokeKey(boardId, stroke.id))
            entry.key: entry.value,
      },
      savedStrokeIds: {...savedStrokeIds, if (markSaved) stroke.id},
    );
  }

  LiveAudioBoardState markStrokeSaved({
    required String boardId,
    required WhiteboardStroke stroke,
  }) {
    return saveCompletedStroke(
      boardId: boardId,
      stroke: stroke,
      markSaved: true,
    );
  }

  LiveAudioBoardState _createBoard({
    required String boardId,
    required int order,
    required String title,
  }) {
    if (boardSet.boardById(boardId) != null || !boardSet.canAddBoard) {
      return this;
    }
    return LiveAudioBoardState(
      boardSet: boardSet.copyWith(
        boards: [
          ...boardSet.boards,
          LessonWhiteboardBoard(
            id: boardId,
            order: order.clamp(0, maxLessonWhiteboardBoards - 1),
            title: title,
          ),
        ],
      ),
      selectedBoardId: selectedBoardId,
      inProgressStrokes: inProgressStrokes,
      savedStrokeIds: savedStrokeIds,
    );
  }

  LiveAudioBoardState _switchBoard(
    String boardId, {
    required double timestampSec,
  }) {
    if (boardSet.boardById(boardId) == null) {
      return this;
    }
    return LiveAudioBoardState(
      boardSet: boardSet.copyWith(
        switchEvents: [
          ...boardSet.switchEvents,
          LessonWhiteboardBoardSwitchEvent(
            boardId: boardId,
            globalTimestampSec: timestampSec,
            sequence: boardSet.nextSwitchSequence,
          ),
        ],
      ),
      selectedBoardId: boardId,
      inProgressStrokes: inProgressStrokes,
      savedStrokeIds: savedStrokeIds,
    );
  }

  LiveAudioBoardState _applyStrokeMessage(LiveAudioProbeMessage message) {
    final key = _strokeKey(message.boardId, message.strokeId);
    final inProgress = Map<String, WhiteboardStroke>.from(inProgressStrokes);
    switch (message.kind) {
      case LiveAudioProbeMessageKind.strokeStart:
        inProgress[key] = WhiteboardStroke(
          id: message.strokeId,
          timestampSec: message.timestampSec,
          points: const [],
        );
        return LiveAudioBoardState(
          boardSet: boardSet,
          selectedBoardId: selectedBoardId,
          inProgressStrokes: inProgress,
          savedStrokeIds: savedStrokeIds,
        );
      case LiveAudioProbeMessageKind.strokePoint:
        final current =
            inProgress[key] ??
            WhiteboardStroke(
              id: message.strokeId,
              timestampSec: message.timestampSec,
              points: const [],
            );
        inProgress[key] = current.copyWith(
          points: [...current.points, message.point!],
        );
        return LiveAudioBoardState(
          boardSet: boardSet,
          selectedBoardId: selectedBoardId,
          inProgressStrokes: inProgress,
          savedStrokeIds: savedStrokeIds,
        );
      case LiveAudioProbeMessageKind.strokeEnd:
        final current =
            inProgress.remove(key) ??
            WhiteboardStroke(
              id: message.strokeId,
              timestampSec: message.timestampSec,
              points: const [],
            );
        return LiveAudioBoardState(
          boardSet: boardSet,
          selectedBoardId: selectedBoardId,
          inProgressStrokes: inProgress,
          savedStrokeIds: savedStrokeIds,
        ).saveCompletedStroke(
          boardId: message.boardId,
          stroke: WhiteboardStroke(
            id: current.id,
            timestampSec: current.timestampSec,
            endTimestampSec: message.timestampSec,
            points: [...current.points, message.point!],
          ),
        );
      case LiveAudioProbeMessageKind.boardCreate:
      case LiveAudioProbeMessageKind.boardSwitch:
      case LiveAudioProbeMessageKind.viewport:
        return this;
    }
  }
}

String _strokeKey(String boardId, String strokeId) => '$boardId\u0000$strokeId';

List<LessonWhiteboardViewportEvent> _boundedViewportEvents(
  List<LessonWhiteboardViewportEvent> events,
) {
  if (events.length <= maxLessonViewportEvents) {
    return events;
  }
  final compacted = <LessonWhiteboardViewportEvent>[
    events.first,
    for (var index = 1; index < events.length - 1; index += 2) events[index],
    events.last,
  ];
  return [
    for (final entry in compacted.indexed)
      LessonWhiteboardViewportEvent(
        boardId: entry.$2.boardId,
        globalTimestampSec: entry.$2.globalTimestampSec,
        sequence: entry.$1,
        interactionId: entry.$2.interactionId,
        viewport: entry.$2.viewport,
        segmentId: entry.$2.segmentId,
      ),
  ];
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
