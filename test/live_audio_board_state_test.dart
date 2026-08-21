import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_timed_anchor.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/live_audio_board_state.dart';
import 'package:my_new_app/services/live_audio_probe_message.dart';
import 'package:my_new_app/services/live_audio_snapshot_tracker.dart';

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

  test('follower adopts the latest switch from a server snapshot', () {
    final current = LiveAudioBoardState.initial().applyMessage(
      const LiveAudioProbeMessage(
        kind: LiveAudioProbeMessageKind.boardCreate,
        boardId: 'board-2',
        boardOrder: 1,
        timestampSec: 10,
      ),
    );
    const snapshot = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
        LessonWhiteboardBoard(id: 'board-2', order: 1),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 0,
          sequence: 0,
        ),
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'board-2',
          globalTimestampSec: 10,
          sequence: 1,
        ),
      ],
    );

    final restored = current.replaceSnapshot(
      snapshot,
      preserveSelectedBoard: false,
    );

    expect(current.selectedBoardId, LessonWhiteboardBoard.defaultBoardId);
    expect(restored.selectedBoardId, 'board-2');
  });

  test('publisher keeps its selected board when applying a snapshot', () {
    final current = LiveAudioBoardState.initial().applyMessage(
      const LiveAudioProbeMessage(
        kind: LiveAudioProbeMessageKind.boardCreate,
        boardId: 'board-2',
        boardOrder: 1,
        timestampSec: 10,
      ),
    );
    const snapshot = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
        LessonWhiteboardBoard(id: 'board-2', order: 1),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'board-2',
          globalTimestampSec: 10,
          sequence: 0,
        ),
      ],
    );

    final restored = current.replaceSnapshot(
      snapshot,
      preserveSelectedBoard: true,
    );

    expect(restored.selectedBoardId, LessonWhiteboardBoard.defaultBoardId);
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

  test(
    'keeps RTC stroke and board switch when the server revision is unchanged',
    () {
      const staleSnapshot = BoardSet(
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
        ],
      );
      final tracker = LiveAudioSnapshotTracker();
      var state = LiveAudioBoardState.initial();

      expect(
        tracker.shouldApplyServerSnapshot(
          revision: 0,
          preserveUnsavedLocalChanges: false,
        ),
        isTrue,
      );
      state = state.replaceSnapshot(
        staleSnapshot,
        preserveSelectedBoard: false,
      );
      tracker.markServerSnapshotApplied(0);

      state = state
          .applyMessage(
            const LiveAudioProbeMessage(
              kind: LiveAudioProbeMessageKind.boardSwitch,
              boardId: 'board-2',
              timestampSec: 1,
            ),
          )
          .applyMessage(
            const LiveAudioProbeMessage(
              kind: LiveAudioProbeMessageKind.strokeStart,
              strokeId: 'rtc-stroke',
              boardId: 'board-2',
              timestampSec: 1,
            ),
          )
          .applyMessage(
            const LiveAudioProbeMessage(
              kind: LiveAudioProbeMessageKind.strokePoint,
              strokeId: 'rtc-stroke',
              boardId: 'board-2',
              timestampSec: 1.1,
              point: WhiteboardPoint(x: 0.2, y: 0.3),
            ),
          )
          .applyMessage(
            const LiveAudioProbeMessage(
              kind: LiveAudioProbeMessageKind.strokeEnd,
              strokeId: 'rtc-stroke',
              boardId: 'board-2',
              timestampSec: 1.2,
              point: WhiteboardPoint(x: 0.4, y: 0.5),
            ),
          );

      if (tracker.shouldApplyServerSnapshot(
        revision: 0,
        preserveUnsavedLocalChanges: false,
      )) {
        state = state.replaceSnapshot(
          staleSnapshot,
          preserveSelectedBoard: false,
        );
        tracker.markServerSnapshotApplied(0);
      }

      expect(state.selectedBoardId, 'board-2');
      expect(state.selectedCompletedStrokes, hasLength(1));
      expect(state.selectedCompletedStrokes.single.id, 'rtc-stroke');
    },
  );

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

  test(
    'live completed strokes go onto named primary, not a later-part layer',
    () {
      const laterStroke = WhiteboardStroke(
        id: 'part-2-ink',
        timestampSec: 1,
        points: [WhiteboardPoint(x: 0.1, y: 0.1), WhiteboardPoint(x: 0.2, y: 0.2)],
      );
      const liveStroke = WhiteboardStroke(
        id: 'live-ink',
        timestampSec: 2,
        points: [WhiteboardPoint(x: 0.3, y: 0.3), WhiteboardPoint(x: 0.4, y: 0.4)],
      );
      const laterLayer = LessonWhiteboardLayer(
        id: 'segment-part-2',
        order: 0,
        anchorType: LessonTimedAnchorType.segment,
        segmentId: 'part-2',
        strokes: [laterStroke],
      );
      final state = LiveAudioBoardState.fromBoardSet(
        const BoardSet(
          boards: [
            LessonWhiteboardBoard(
              id: LessonWhiteboardBoard.defaultBoardId,
              order: 0,
              layerBundle: LessonWhiteboardLayerBundle(layers: [laterLayer]),
            ),
          ],
        ),
      ).saveCompletedStroke(
        boardId: LessonWhiteboardBoard.defaultBoardId,
        stroke: liveStroke,
      );

      final bundle = state.selectedBoard.layerBundle;
      expect(bundle.namedPrimaryLayer?.strokes.single.id, 'live-ink');
      expect(bundle.namedPrimaryLayer?.order, 1);
      expect(
        bundle.layers.map((layer) => layer.order).toSet().length,
        bundle.layers.length,
      );
      expect(
        bundle.layers
            .where((layer) => layer.id == 'segment-part-2')
            .single
            .strokes
            .single
            .id,
        'part-2-ink',
      );
      expect(
        visibleWhiteboardBundleStrokes(
          bundle: bundle,
          globalPositionSec: 2,
          segmentLocalPositionSec: 2,
          activeSegmentId: 'part-1',
          orderedSegmentIds: const ['part-1', 'part-2'],
        ).map((stroke) => stroke.id),
        ['live-ink'],
      );
    },
  );
}
