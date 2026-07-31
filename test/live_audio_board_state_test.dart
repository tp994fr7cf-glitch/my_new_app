import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/live_audio_board_state.dart';
import 'package:my_new_app/services/live_audio_probe_message.dart';

void main() {
  test('applies board creation, switch, and viewport in order', () {
    final state = LiveAudioBoardState.initial()
        .applyMessage(
          const LiveAudioProbeMessage(
            kind: LiveAudioProbeMessageKind.boardCreate,
            boardId: 'board-2',
            boardOrder: 1,
            boardTitle: 'Board 2',
            timestampSec: 1,
          ),
        )
        .applyMessage(
          const LiveAudioProbeMessage(
            kind: LiveAudioProbeMessageKind.boardSwitch,
            boardId: 'board-2',
            timestampSec: 2,
          ),
        )
        .applyMessage(
          const LiveAudioProbeMessage(
            kind: LiveAudioProbeMessageKind.viewport,
            boardId: 'board-2',
            timestampSec: 3,
            interactionId: 7,
            viewport: LessonWhiteboardViewport(
              centerX: 0.5,
              centerY: 0.5,
              scale: 2,
            ),
          ),
        );

    expect(state.boardSet.boards, hasLength(2));
    expect(state.selectedBoardId, 'board-2');
    expect(state.selectedViewport.scale, 2);
    expect(state.boardSet.switchEvents.single.globalTimestampSec, 2);
  });

  test('stores a completed stroke on its board and rejects delayed pieces', () {
    var state = LiveAudioBoardState.initial();
    const start = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.strokeStart,
      strokeId: 'stroke-1',
      timestampSec: 1,
    );
    const point = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.strokePoint,
      strokeId: 'stroke-1',
      timestampSec: 1.1,
      point: WhiteboardPoint(x: 0.2, y: 0.3),
    );
    const finish = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.strokeEnd,
      strokeId: 'stroke-1',
      timestampSec: 1.2,
      point: WhiteboardPoint(x: 0.4, y: 0.5),
    );

    state = state.applyMessage(start).applyMessage(point).applyMessage(finish);
    final saved = state.selectedCompletedStrokes.single;
    state = state.markStrokeSaved(
      boardId: LessonWhiteboardBoard.defaultBoardId,
      stroke: saved,
    );
    final afterDelayed = state.applyMessage(point);

    expect(saved.points, hasLength(2));
    expect(afterDelayed.inProgressStrokes, isEmpty);
    expect(afterDelayed.selectedCompletedStrokes, hasLength(1));
  });

  test('restores selected board and saved stroke IDs from a snapshot', () {
    const stroke = WhiteboardStroke(
      id: 'saved',
      timestampSec: 1,
      points: [WhiteboardPoint(x: 0.1, y: 0.2)],
    );
    const snapshot = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: 'board-1',
          order: 0,
          layerBundle: LessonWhiteboardLayerBundle(
            layers: [
              LessonWhiteboardLayer(
                id: LessonWhiteboardLayer.primaryLayerId,
                order: 0,
                strokes: [stroke],
              ),
            ],
          ),
        ),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'board-1',
          globalTimestampSec: 0,
          sequence: 0,
        ),
      ],
    );

    final state = LiveAudioBoardState.fromBoardSet(snapshot);

    expect(state.selectedBoardId, 'board-1');
    expect(state.savedStrokeIds, contains('saved'));
  });

  test('starts a mid-lesson live part on the board visible at that time', () {
    const snapshot = BoardSet(
      boards: [
        LessonWhiteboardBoard(id: 'board-1', order: 0),
        LessonWhiteboardBoard(id: 'board-2', order: 1),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'board-1',
          globalTimestampSec: 0,
          sequence: 0,
        ),
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'board-2',
          globalTimestampSec: 30,
          sequence: 1,
        ),
      ],
    );

    final state = LiveAudioBoardState.fromBoardSet(snapshot, selectedAtSec: 10);

    expect(state.selectedBoardId, 'board-1');
  });
}
