import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/services/lesson_media_playback.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_canvas.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_editor_panel.dart';

void main() {
  testWidgets('Teacher whiteboard editor shows strokes up to the seek position', (
    WidgetTester tester,
  ) async {
    const leftStroke = WhiteboardStroke(
      id: 'left',
      timestampSec: 0,
      endTimestampSec: 30,
      points: [
        WhiteboardPoint(x: 0.1, y: 0.5, timestampSec: 0),
        WhiteboardPoint(x: 0.2, y: 0.5, timestampSec: 15),
        WhiteboardPoint(x: 0.3, y: 0.5, timestampSec: 30),
      ],
    );
    const rightStroke = WhiteboardStroke(
      id: 'right',
      timestampSec: 30,
      endTimestampSec: 60,
      points: [
        WhiteboardPoint(x: 0.7, y: 0.5, timestampSec: 30),
        WhiteboardPoint(x: 0.8, y: 0.5, timestampSec: 45),
        WhiteboardPoint(x: 0.9, y: 0.5, timestampSec: 60),
      ],
    );
    const draft = LessonWhiteboard(
      strokes: [leftStroke, rightStroke],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonWhiteboardEditorPanel(
            courseId: 'course-1',
            lessonNumber: 1,
            mediaUrl: 'https://example.com/lesson.mp3',
            mediaDurationSec: 90,
            durationLabel: '1分30秒',
            publishedWhiteboard: null,
            draftWhiteboard: draft,
            onDraftSaved: (_) async {},
            playbackFactory: ({required isAudio}) => FakeLessonMediaPlayback(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LessonWhiteboardCanvas), findsOneWidget);
    var canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes, isEmpty);

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(60);
    await tester.pumpAndSettle();

    canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes, hasLength(2));

    slider.onChanged!(25);
    await tester.pumpAndSettle();

    canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes, hasLength(1));
    expect(canvas.strokes.single.id, 'left');
    expect(canvas.strokes.single.points, hasLength(2));
    expect(canvas.strokes.single.points.last.timestampSec, 15);

    slider.onChanged!(60);
    await tester.pumpAndSettle();

    canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes, hasLength(2));
    expect(canvas.strokes.last.id, 'right');
  });

  testWidgets('Teacher whiteboard editor keeps full strokes when saving draft', (
    WidgetTester tester,
  ) async {
    const leftStroke = WhiteboardStroke(
      id: 'left',
      timestampSec: 0,
      endTimestampSec: 30,
      points: [
        WhiteboardPoint(x: 0.1, y: 0.5, timestampSec: 0),
        WhiteboardPoint(x: 0.3, y: 0.5, timestampSec: 30),
      ],
    );
    const rightStroke = WhiteboardStroke(
      id: 'right',
      timestampSec: 30,
      endTimestampSec: 60,
      points: [
        WhiteboardPoint(x: 0.7, y: 0.5, timestampSec: 30),
        WhiteboardPoint(x: 0.9, y: 0.5, timestampSec: 60),
      ],
    );
    const draft = LessonWhiteboard(
      strokes: [leftStroke, rightStroke],
    );
    LessonWhiteboard? savedWhiteboard;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonWhiteboardEditorPanel(
            courseId: 'course-1',
            lessonNumber: 1,
            mediaUrl: 'https://example.com/lesson.mp3',
            mediaDurationSec: 90,
            durationLabel: '1分30秒',
            publishedWhiteboard: null,
            draftWhiteboard: draft,
            onDraftSaved: (whiteboard) async {
              savedWhiteboard = whiteboard;
            },
            playbackFactory: ({required isAudio}) => FakeLessonMediaPlayback(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(25);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
    await tester.pumpAndSettle();

    expect(savedWhiteboard, isNotNull);
    expect(savedWhiteboard!.strokes, hasLength(2));
    expect(savedWhiteboard!.strokes.map((stroke) => stroke.id), ['left', 'right']);
  });
}
