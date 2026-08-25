import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_payload_size_validator.dart';
import 'package:my_new_app/models/lesson_scoped_board_set.dart';
import 'package:my_new_app/models/lesson_timed_anchor.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/models/lesson_whiteboard_part_order.dart';

WhiteboardStroke _stroke(String id, double atSec) {
  return WhiteboardStroke(
    id: id,
    timestampSec: atSec,
    points: const [
      WhiteboardPoint(x: 0.1, y: 0.1),
      WhiteboardPoint(x: 0.2, y: 0.2),
    ],
  );
}

LessonWhiteboardLayer _segmentLayer({
  required String segmentId,
  required List<WhiteboardStroke> strokes,
  required int order,
}) {
  return LessonWhiteboardLayer(
    id: whiteboardSegmentLayerId(segmentId),
    order: order,
    anchorType: LessonTimedAnchorType.segment,
    segmentId: segmentId,
    strokes: strokes,
  );
}

BoardSet _twoPartBoardSet({
  List<WhiteboardStroke>? part1Strokes,
  List<WhiteboardStroke>? part2Strokes,
  List<LessonWhiteboardBoardSwitchEvent> switchEvents = const [],
}) {
  return BoardSet(
    boards: [
      LessonWhiteboardBoard(
        id: LessonWhiteboardBoard.defaultBoardId,
        order: 0,
        layerBundle: LessonWhiteboardLayerBundle(
          layers: [
            _segmentLayer(
              segmentId: 'part-1',
              order: 0,
              strokes: part1Strokes ?? [_stroke('p1', 1)],
            ),
            _segmentLayer(
              segmentId: 'part-2',
              order: 1,
              strokes: part2Strokes ?? [_stroke('p2', 1)],
            ),
          ],
        ),
      ),
    ],
    switchEvents: switchEvents,
  );
}

void main() {
  test('merge keeps other parts and takes this part from the scoped editor', () {
    final baseline = _twoPartBoardSet();
    final scoped = _twoPartBoardSet(
      part1Strokes: [_stroke('stale-p1', 1)],
      part2Strokes: [_stroke('p2-new', 2), _stroke('p2-newer', 3)],
    );

    final merged = mergeScopedLessonBoardSet(
      baseline: baseline,
      scoped: scoped,
      segmentId: 'part-2',
    );

    final bundle = merged.defaultBoard!.layerBundle;
    expect(
      strokesForSegmentLayer(bundle: bundle, segmentId: 'part-1').single.id,
      'p1',
    );
    expect(
      strokesForSegmentLayer(
        bundle: bundle,
        segmentId: 'part-2',
      ).map((stroke) => stroke.id),
      ['p2-new', 'p2-newer'],
    );
  });

  test('merge uses scoped boards when this part adds a paper', () {
    final baseline = _twoPartBoardSet();
    final scoped = BoardSet(
      boards: [
        ...baseline.boards,
        const LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
      ],
    );

    final merged = mergeScopedLessonBoardSet(
      baseline: baseline,
      scoped: scoped,
      segmentId: 'part-1',
    );

    expect(merged.orderedBoards.map((board) => board.id), [
      LessonWhiteboardBoard.defaultBoardId,
      'second',
    ]);
    expect(merged.boardById('second')?.title, '二枚目');
    expect(
      strokesForSegmentLayer(
        bundle: merged.defaultBoard!.layerBundle,
        segmentId: 'part-1',
      ).single.id,
      'p1',
    );
  });

  test('clearing one part leaves other parts and the papers', () {
    final boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          title: '表',
          layerBundle: LessonWhiteboardLayerBundle(
            layers: [
              _segmentLayer(
                segmentId: 'part-1',
                order: 0,
                strokes: [_stroke('p1', 1)],
              ),
              _segmentLayer(
                segmentId: 'part-2',
                order: 1,
                strokes: [_stroke('p2', 1)],
              ),
            ],
          ),
        ),
      ],
      switchEvents: const [
        LessonWhiteboardBoardSwitchEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 1,
          sequence: 0,
          segmentId: 'part-1',
        ),
        LessonWhiteboardBoardSwitchEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 2,
          sequence: 1,
          segmentId: 'part-2',
        ),
      ],
    );

    final cleared = clearLessonSegmentWriting(
      boardSet: boardSet,
      segmentId: 'part-2',
    );

    expect(cleared.defaultBoard?.title, '表');
    expect(
      strokesForSegmentLayer(
        bundle: cleared.defaultBoard!.layerBundle,
        segmentId: 'part-1',
      ).single.id,
      'p1',
    );
    expect(
      strokesForSegmentLayer(
        bundle: cleared.defaultBoard!.layerBundle,
        segmentId: 'part-2',
      ),
      isEmpty,
    );
    expect(cleared.switchEvents.single.segmentId, 'part-1');
  });

  test('scoped screen-share replace leaves other parts events', () {
    const baseline = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
        LessonWhiteboardBoard(id: 'second', order: 1),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'second',
          globalTimestampSec: 1,
          sequence: 0,
          segmentId: 'part-1',
        ),
        LessonWhiteboardBoardSwitchEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 2,
          sequence: 1,
          segmentId: 'part-2',
        ),
      ],
    );

    final overwritten = replaceScopedScreenShareTimelineInterval(
      current: baseline,
      baseline: baseline,
      segmentId: 'part-2',
      orderedSegmentIds: const ['part-1', 'part-2'],
      startLocalSec: 1,
      endLocalSec: 5,
      replacementSwitchEvents: const [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'second',
          globalTimestampSec: 2,
          sequence: 0,
          segmentId: 'part-2',
        ),
      ],
      replacementViewportEvents: const [],
    );

    expect(
      overwritten.switchEvents
          .where((event) => event.segmentId == 'part-1')
          .single
          .boardId,
      'second',
    );
    expect(
      overwritten.switchEvents.any(
        (event) => event.segmentId == 'part-2' && event.boardId == 'second',
      ),
      isTrue,
    );
  });

  test(
    'merge re-numbers switch history after a part editor reindexes the full list',
    () {
      const boards = [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
        LessonWhiteboardBoard(id: 'second', order: 1),
      ];
      const baseline = BoardSet(
        boards: boards,
        switchEvents: [
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'second',
            globalTimestampSec: 3,
            sequence: 0,
            segmentId: 'part-1',
          ),
          LessonWhiteboardBoardSwitchEvent(
            boardId: LessonWhiteboardBoard.defaultBoardId,
            globalTimestampSec: 4,
            sequence: 1,
            segmentId: 'part-1',
          ),
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'second',
            globalTimestampSec: 1,
            sequence: 2,
            segmentId: 'part-2',
          ),
        ],
        viewportEvents: [
          LessonWhiteboardViewportEvent(
            boardId: 'second',
            globalTimestampSec: 3,
            sequence: 0,
            interactionId: 0,
            viewport: LessonWhiteboardViewport.full,
            segmentId: 'part-1',
          ),
          LessonWhiteboardViewportEvent(
            boardId: 'second',
            globalTimestampSec: 1,
            sequence: 1,
            interactionId: 1,
            viewport: LessonWhiteboardViewport(
              centerX: 0.5,
              centerY: 0.5,
              scale: 2,
            ),
            segmentId: 'part-2',
          ),
        ],
      );
      const scopedAfterOverride = BoardSet(
        boards: boards,
        switchEvents: [
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'second',
            globalTimestampSec: 1,
            sequence: 0,
            segmentId: 'part-2',
          ),
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'second',
            globalTimestampSec: 3,
            sequence: 1,
            segmentId: 'part-1',
          ),
          LessonWhiteboardBoardSwitchEvent(
            boardId: LessonWhiteboardBoard.defaultBoardId,
            globalTimestampSec: 4,
            sequence: 2,
            segmentId: 'part-1',
          ),
        ],
        viewportEvents: [
          LessonWhiteboardViewportEvent(
            boardId: 'second',
            globalTimestampSec: 1,
            sequence: 0,
            interactionId: 1,
            viewport: LessonWhiteboardViewport(
              centerX: 0.5,
              centerY: 0.5,
              scale: 2,
            ),
            segmentId: 'part-2',
          ),
          LessonWhiteboardViewportEvent(
            boardId: 'second',
            globalTimestampSec: 3,
            sequence: 1,
            interactionId: 0,
            viewport: LessonWhiteboardViewport.full,
            segmentId: 'part-1',
          ),
        ],
      );

      final merged = mergeScopedLessonBoardSet(
        baseline: baseline,
        scoped: scopedAfterOverride,
        segmentId: 'part-2',
      );

      expect(() => validateBoardSetForPersistence(merged), returnsNormally);
      expect(
        merged.switchEvents.map((event) => event.sequence).toList(),
        [0, 1, 2],
      );
      expect(
        merged.switchEvents.map((event) => event.segmentId).toList(),
        ['part-2', 'part-1', 'part-1'],
      );
      expect(
        merged.viewportEvents.map((event) => event.sequence).toList(),
        [0, 1],
      );
      expect(
        merged.viewportEvents.map((event) => event.segmentId).toList(),
        ['part-2', 'part-1'],
      );
    },
  );
}
