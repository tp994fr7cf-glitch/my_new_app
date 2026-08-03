import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_canvas.dart';

void main() {
  testWidgets('uses 4:3, zooms to 8x, pans, and hides the minimap', (
    tester,
  ) async {
    final changes = <LessonWhiteboardViewportChange>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonWhiteboardCanvas(
            strokes: const [],
            onViewportChanged: changes.add,
          ),
        ),
      ),
    );

    final aspectFinder = find.byKey(const ValueKey('whiteboard-aspect-ratio'));
    final size = tester.getSize(aspectFinder);
    expect(size.width / size.height, closeTo(4 / 3, 0.001));

    for (var index = 0; index < 3; index++) {
      await tester.tap(find.byKey(const ValueKey('whiteboard-zoom-in')));
      await tester.pump();
    }
    expect(find.text('8x'), findsOneWidget);
    expect(changes.last.viewport.scale, 8);

    await tester.tap(find.byKey(const ValueKey('whiteboard-zoom-reset')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('whiteboard-zoom-in')));
    await tester.pump();
    changes.clear();

    await tester.dragFrom(tester.getCenter(aspectFinder), const Offset(80, 0));
    await tester.pump();
    expect(changes.last.phase, LessonWhiteboardViewportChangePhase.end);
    expect(changes.last.viewport.centerX, lessThan(0.5));

    var minimap = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('whiteboard-minimap')),
    );
    expect(minimap.opacity, 1);
    await tester.pump(const Duration(milliseconds: 2200));
    minimap = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('whiteboard-minimap')),
    );
    expect(minimap.opacity, 0);
  });

  testWidgets('drawing while zoomed stores the point under the visible area', (
    tester,
  ) async {
    final points = <WhiteboardPoint>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonWhiteboardCanvas(
            strokes: const [],
            drawingEnabled: true,
            onStrokeUpdate: points.add,
            onStrokeEnd: points.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('whiteboard-zoom-in')));
    await tester.pump();
    final rect = tester.getRect(
      find.byKey(const ValueKey('whiteboard-aspect-ratio')),
    );
    await tester.dragFrom(
      Offset(rect.left + 20, rect.center.dy),
      const Offset(100, 0),
    );

    expect(points, isNotEmpty);
    expect(points.first.x, greaterThan(0.24));
    expect(points.last.x, lessThan(0.4));
  });

  testWidgets('starting a two-finger gesture cancels the pending stroke', (
    tester,
  ) async {
    var cancelled = 0;
    var ended = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonWhiteboardCanvas(
            strokes: const [],
            drawingEnabled: true,
            onStrokeCancel: () => cancelled++,
            onStrokeEnd: (_) => ended++,
          ),
        ),
      ),
    );

    final center = tester.getCenter(
      find.byKey(const ValueKey('whiteboard-aspect-ratio')),
    );
    final first = await tester.startGesture(center, pointer: 1);
    await tester.pump();
    final second = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 2,
    );
    await tester.pump();

    expect(cancelled, 1);
    expect(ended, 0);
    await second.up();
    await first.up();
  });

  testWidgets('a tap while zoomed does not start a viewport interaction', (
    tester,
  ) async {
    final changes = <LessonWhiteboardViewportChange>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonWhiteboardCanvas(
            strokes: const [],
            viewport: const LessonWhiteboardViewport(
              centerX: 0.5,
              centerY: 0.5,
              scale: 2,
            ),
            onViewportChanged: changes.add,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('whiteboard-aspect-ratio')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(changes, isEmpty);
  });

  testWidgets('one-finger drag at 1x scrolls the parent list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              SizedBox(height: 200),
              LessonWhiteboardCanvas(strokes: []),
              SizedBox(height: 600),
            ],
          ),
        ),
      ),
    );

    final rect = tester.getRect(
      find.byKey(const ValueKey('whiteboard-aspect-ratio')),
    );
    await tester.dragFrom(Offset(rect.center.dx, 500), const Offset(0, -120));
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('pointer cancellation discards an unfinished stroke', (
    tester,
  ) async {
    var cancelled = 0;
    var ended = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonWhiteboardCanvas(
            strokes: const [],
            drawingEnabled: true,
            onStrokeCancel: () => cancelled++,
            onStrokeEnd: (_) => ended++,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('whiteboard-aspect-ratio'))),
    );
    await gesture.moveBy(const Offset(20, 0));
    await gesture.cancel();
    await tester.pump();

    expect(cancelled, 1);
    expect(ended, 0);
  });
}
