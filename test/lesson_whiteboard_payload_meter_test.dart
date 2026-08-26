import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_payload_size_validator.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_payload_meter.dart';

BoardSet _boardSetWithStrokeCount(int count) {
  return BoardSet(
    boards: [
      LessonWhiteboardBoard(
        id: LessonWhiteboardBoard.defaultBoardId,
        order: 0,
        layerBundle: LessonWhiteboardLayerBundle(
          layers: [
            LessonWhiteboardLayer(
              id: 'primary',
              order: 0,
              strokes: [
                for (var index = 0; index < count; index++)
                  WhiteboardStroke(
                    id: 'stroke-$index',
                    timestampSec: index.toDouble(),
                    points: [
                      WhiteboardPoint(
                        x: 0.1,
                        y: 0.2,
                        timestampSec: index.toDouble(),
                      ),
                      WhiteboardPoint(
                        x: 0.3,
                        y: 0.4,
                        timestampSec: index + 0.1,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

void main() {
  testWidgets('shows the lesson-wide fraction on open', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonWhiteboardPayloadMeter(
            boardSet: _boardSetWithStrokeCount(0),
          ),
        ),
      ),
    );

    expect(
      find.text(formatLessonPayloadUsageFraction(
        estimateSerializedUtf8JsonBytes(_boardSetWithStrokeCount(0).toMap()),
      )),
      findsOneWidget,
    );
    expect(find.textContaining('/850'), findsOneWidget);
  });

  testWidgets('waits 15 seconds before measuring a new board set', (
    tester,
  ) async {
    final small = _boardSetWithStrokeCount(0);
    final large = _boardSetWithStrokeCount(80);
    final smallLabel = formatLessonPayloadUsageFraction(
      estimateSerializedUtf8JsonBytes(small.toMap()),
    );
    final largeLabel = formatLessonPayloadUsageFraction(
      estimateSerializedUtf8JsonBytes(large.toMap()),
    );
    expect(smallLabel, isNot(largeLabel));

    late void Function(void Function()) setHostState;
    var boardSet = small;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return LessonWhiteboardPayloadMeter(
                boardSet: boardSet,
                scopeKey: 'lesson-1',
              );
            },
          ),
        ),
      ),
    );
    expect(find.text(smallLabel), findsOneWidget);

    setHostState(() {
      boardSet = large;
    });
    await tester.pump();
    expect(find.text(smallLabel), findsOneWidget);
    expect(find.text(largeLabel), findsNothing);

    await tester.pump(const Duration(seconds: 14));
    expect(find.text(smallLabel), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(largeLabel), findsOneWidget);
  });

  testWidgets('remeasures immediately when the lesson scope changes', (
    tester,
  ) async {
    final small = _boardSetWithStrokeCount(0);
    final large = _boardSetWithStrokeCount(80);
    final smallLabel = formatLessonPayloadUsageFraction(
      estimateSerializedUtf8JsonBytes(small.toMap()),
    );
    final largeLabel = formatLessonPayloadUsageFraction(
      estimateSerializedUtf8JsonBytes(large.toMap()),
    );

    late void Function(void Function()) setHostState;
    var boardSet = small;
    var scopeKey = 'lesson-1';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return LessonWhiteboardPayloadMeter(
                boardSet: boardSet,
                scopeKey: scopeKey,
              );
            },
          ),
        ),
      ),
    );
    expect(find.text(smallLabel), findsOneWidget);

    setHostState(() {
      boardSet = large;
      scopeKey = 'lesson-2';
    });
    await tester.pump();
    expect(find.text(largeLabel), findsOneWidget);
  });
}
