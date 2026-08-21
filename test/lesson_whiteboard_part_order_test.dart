import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_timed_anchor.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/models/lesson_whiteboard_part_order.dart';

WhiteboardStroke _numberStroke(String id, double atSec) {
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

void main() {
  const orderedIds = ['part-1', 'part-2'];
  final boardSet = BoardSet(
    boards: [
      LessonWhiteboardBoard(
        id: LessonWhiteboardBoard.defaultBoardId,
        order: 0,
        layerBundle: LessonWhiteboardLayerBundle(
          layers: [
            _segmentLayer(
              segmentId: 'part-1',
              order: 0,
              strokes: [
                _numberStroke('n1', 1),
                _numberStroke('n2', 2),
                _numberStroke('n3', 3),
                _numberStroke('n4', 4),
                _numberStroke('n5', 5),
              ],
            ),
            _segmentLayer(
              segmentId: 'part-2',
              order: 1,
              strokes: [
                _numberStroke('n6', 1),
                _numberStroke('n7', 2),
                _numberStroke('n8', 3),
                _numberStroke('n9', 4),
                _numberStroke('n10', 5),
              ],
            ),
          ],
        ),
      ),
    ],
    switchEvents: [
      LessonWhiteboardBoardSwitchEvent(
        boardId: LessonWhiteboardBoard.defaultBoardId,
        globalTimestampSec: 0,
        sequence: 0,
        segmentId: 'part-2',
      ),
    ],
  );

  test('part 1 playback hides later-part writing even if it was recorded first', () {
    final strokes = visibleWhiteboardBundleStrokes(
      bundle: boardSet.defaultBoard!.layerBundle,
      globalPositionSec: 3,
      segmentLocalPositionSec: 3,
      activeSegmentId: 'part-1',
      orderedSegmentIds: orderedIds,
    );
    expect(strokes.map((stroke) => stroke.id), ['n1', 'n2', 'n3']);
  });

  test('part 2 playback inherits completed part 1 writing', () {
    final atStart = visibleWhiteboardBundleStrokes(
      bundle: boardSet.defaultBoard!.layerBundle,
      globalPositionSec: 5,
      segmentLocalPositionSec: 0,
      activeSegmentId: 'part-2',
      orderedSegmentIds: orderedIds,
    );
    expect(atStart.map((stroke) => stroke.id), ['n1', 'n2', 'n3', 'n4', 'n5']);

    final atTwo = visibleWhiteboardBundleStrokes(
      bundle: boardSet.defaultBoard!.layerBundle,
      globalPositionSec: 7,
      segmentLocalPositionSec: 2,
      activeSegmentId: 'part-2',
      orderedSegmentIds: orderedIds,
    );
    expect(atTwo.map((stroke) => stroke.id), [
      'n1',
      'n2',
      'n3',
      'n4',
      'n5',
      'n6',
      'n7',
    ]);
  });

  test('independent part 2 playback still inherits completed part 1 writing', () {
    final strokes = visibleWhiteboardBundleStrokes(
      bundle: boardSet.defaultBoard!.layerBundle,
      globalPositionSec: 1,
      segmentLocalPositionSec: 1,
      activeSegmentId: 'part-2',
      orderedSegmentIds: orderedIds,
    );
    expect(strokes.map((stroke) => stroke.id), [
      'n1',
      'n2',
      'n3',
      'n4',
      'n5',
      'n6',
    ]);
  });

  test('part 2 board switches do not apply during part 1', () {
    const extraBoard = LessonWhiteboardBoard(id: 'later-board', order: 1);
    final withSwitch = boardSet.copyWith(
      boards: [...boardSet.boards, extraBoard],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: extraBoard.id,
          globalTimestampSec: 1,
          sequence: 1,
          segmentId: 'part-2',
        ),
      ],
    );
    final partOrder = WhiteboardPartOrderPlayback(
      orderedSegmentIds: orderedIds,
      activeSegmentId: 'part-1',
      segmentLocalSec: 4,
    );
    expect(
      resolveBoardAtPartOrder(
        boardSet: withSwitch,
        globalTimestampSec: 4,
        partOrder: partOrder,
      )?.id,
      LessonWhiteboardBoard.defaultBoardId,
    );

    final part2Order = WhiteboardPartOrderPlayback(
      orderedSegmentIds: orderedIds,
      activeSegmentId: 'part-2',
      segmentLocalSec: 1,
    );
    expect(
      resolveBoardAtPartOrder(
        boardSet: withSwitch,
        globalTimestampSec: 6,
        partOrder: part2Order,
      )?.id,
      extraBoard.id,
    );
  });

  test('legacy untagged strokes still follow the global clock', () {
    const bundle = LessonWhiteboardLayerBundle(
      layers: [
        LessonWhiteboardLayer(
          id: LessonWhiteboardLayer.primaryLayerId,
          order: 0,
          strokes: [
            WhiteboardStroke(
              id: 'legacy',
              timestampSec: 12,
              points: [
                WhiteboardPoint(x: 0, y: 0, timestampSec: 12),
                WhiteboardPoint(x: 1, y: 1, timestampSec: 12.2),
              ],
            ),
          ],
        ),
      ],
    );
    expect(
      visibleWhiteboardBundleStrokes(
        bundle: bundle,
        globalPositionSec: 11,
        segmentLocalPositionSec: 1,
        activeSegmentId: 'part-2',
        orderedSegmentIds: orderedIds,
      ),
      isEmpty,
    );
    expect(
      visibleWhiteboardBundleStrokes(
        bundle: bundle,
        globalPositionSec: 12.2,
        segmentLocalPositionSec: 2.2,
        activeSegmentId: 'part-2',
        orderedSegmentIds: orderedIds,
      ).single.id,
      'legacy',
    );
  });

  test(
    'part 1 live shows untagged primary ink while hiding later-part layers',
    () {
      const liveStroke = WhiteboardStroke(
        id: 'live-now',
        timestampSec: 1,
        points: [
          WhiteboardPoint(x: 0.3, y: 0.3),
          WhiteboardPoint(x: 0.4, y: 0.4),
        ],
      );
      final bundle = LessonWhiteboardLayerBundle(
        layers: [
          const LessonWhiteboardLayer(
            id: LessonWhiteboardLayer.primaryLayerId,
            order: 0,
            strokes: [liveStroke],
          ),
          _segmentLayer(
            segmentId: 'part-2',
            order: 1,
            strokes: [_numberStroke('n6', 1)],
          ),
        ],
      );

      final visible = visibleWhiteboardBundleStrokes(
        bundle: bundle,
        globalPositionSec: 1,
        segmentLocalPositionSec: 1,
        activeSegmentId: 'part-1',
        orderedSegmentIds: orderedIds,
      );

      expect(visible.map((stroke) => stroke.id), ['live-now']);
    },
  );
}
