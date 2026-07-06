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

  testWidgets('Teacher whiteboard editor shows published preview without draft', (
    WidgetTester tester,
  ) async {
    const published = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'published',
          timestampSec: 0,
          points: [
            WhiteboardPoint(x: 0.1, y: 0.5, timestampSec: 0),
            WhiteboardPoint(x: 0.9, y: 0.5, timestampSec: 10),
          ],
        ),
      ],
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
            publishedWhiteboard: published,
            draftWhiteboard: null,
            onDraftSaved: (_) async {},
            playbackFactory: ({required isAudio}) => FakeLessonMediaPlayback(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '書き物を描き直す'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '書き物を一時保存'), findsNothing);

    final canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.single.id, 'published');
    expect(canvas.drawingEnabled, isFalse);
  });

  testWidgets('Teacher whiteboard editor keeps draft canvas after temporary save', (
    WidgetTester tester,
  ) async {
    const published = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'published-old',
          timestampSec: 0,
          points: [
            WhiteboardPoint(x: 0.1, y: 0.5, timestampSec: 0),
            WhiteboardPoint(x: 0.9, y: 0.5, timestampSec: 10),
          ],
        ),
      ],
    );
    const redrawnDraft = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'draft-new',
          timestampSec: 0,
          points: [
            WhiteboardPoint(x: 0.2, y: 0.2, timestampSec: 0),
            WhiteboardPoint(x: 0.8, y: 0.8, timestampSec: 10),
          ],
        ),
      ],
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
            publishedWhiteboard: published,
            draftWhiteboard: redrawnDraft,
            onDraftSaved: (_) async {},
            playbackFactory: ({required isAudio}) => FakeLessonMediaPlayback(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '書き物を一時保存'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '書き物を描き直す'), findsNothing);

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(10);
    await tester.pumpAndSettle();

    final canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.single.id, 'draft-new');
    expect(canvas.drawingEnabled, isFalse);
  });

  testWidgets('Teacher whiteboard editor updates to draft canvas after redraw save', (
    WidgetTester tester,
  ) async {
    const published = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'published-old',
          timestampSec: 0,
          points: [
            WhiteboardPoint(x: 0.1, y: 0.5, timestampSec: 0),
            WhiteboardPoint(x: 0.9, y: 0.5, timestampSec: 10),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: _DraftSaveHost(publishedWhiteboard: published),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '書き物を描き直す'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '書き物を描き直す'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'リセットして描き直す'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '書き物を一時保存'), findsOneWidget);

    final hostState = tester.state<_DraftSaveHostState>(find.byType(_DraftSaveHost));
    hostState.simulateRedrawnDraftSave();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '書き物を一時保存'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '書き物を描き直す'), findsNothing);

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(10);
    await tester.pumpAndSettle();

    final canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.single.id, 'draft-new');
  });

  testWidgets('Teacher whiteboard editor can edit published content from options', (
    WidgetTester tester,
  ) async {
    const published = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'published',
          timestampSec: 0,
          points: [
            WhiteboardPoint(x: 0.1, y: 0.5, timestampSec: 0),
            WhiteboardPoint(x: 0.9, y: 0.5, timestampSec: 10),
          ],
        ),
      ],
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
            publishedWhiteboard: published,
            draftWhiteboard: null,
            onDraftSaved: (_) async {},
            playbackFactory: ({required isAudio}) => FakeLessonMediaPlayback(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '書き物を描き直す'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(OutlinedButton, '公開しているものを編集する'),
    );
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(10);
    await tester.pumpAndSettle();

    final canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.single.id, 'published');
    expect(find.widgetWithText(OutlinedButton, '書き物を一時保存'), findsOneWidget);
  });

  testWidgets('Teacher whiteboard editor shows three edit options when draft exists', (
    WidgetTester tester,
  ) async {
    const published = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'published',
          timestampSec: 0,
          points: [
            WhiteboardPoint(x: 0.1, y: 0.5, timestampSec: 0),
            WhiteboardPoint(x: 0.9, y: 0.5, timestampSec: 10),
          ],
        ),
      ],
    );
    const draft = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'draft',
          timestampSec: 0,
          points: [
            WhiteboardPoint(x: 0.2, y: 0.2, timestampSec: 0),
            WhiteboardPoint(x: 0.8, y: 0.8, timestampSec: 10),
          ],
        ),
      ],
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
            publishedWhiteboard: published,
            draftWhiteboard: draft,
            onDraftSaved: (_) async {},
            playbackFactory: ({required isAudio}) => FakeLessonMediaPlayback(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '編集の選び直し'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '公開しているものを編集する'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '仮保存中のものを編集する'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'リセットして描き直す'), findsOneWidget);
  });

  testWidgets('Teacher whiteboard deferred reset does not save until draft save', (
    WidgetTester tester,
  ) async {
    const published = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'published',
          timestampSec: 0,
          points: [
            WhiteboardPoint(x: 0.1, y: 0.5, timestampSec: 0),
            WhiteboardPoint(x: 0.9, y: 0.5, timestampSec: 10),
          ],
        ),
      ],
    );
    var draftSaveCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonWhiteboardEditorPanel(
            courseId: 'course-1',
            lessonNumber: 1,
            mediaUrl: 'https://example.com/lesson.mp3',
            mediaDurationSec: 90,
            durationLabel: '1分30秒',
            publishedWhiteboard: published,
            draftWhiteboard: null,
            onDraftSaved: (_) async {
              draftSaveCount++;
            },
            playbackFactory: ({required isAudio}) => FakeLessonMediaPlayback(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '書き物を描き直す'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'リセットして描き直す'));
    await tester.pumpAndSettle();

    expect(draftSaveCount, 0);
    expect(find.widgetWithText(OutlinedButton, '書き物を一時保存'), findsOneWidget);
  });
}

class _DraftSaveHost extends StatefulWidget {
  const _DraftSaveHost({required this.publishedWhiteboard});

  final LessonWhiteboard publishedWhiteboard;

  @override
  State<_DraftSaveHost> createState() => _DraftSaveHostState();
}

class _DraftSaveHostState extends State<_DraftSaveHost> {
  LessonWhiteboard? _draftWhiteboard;

  void simulateRedrawnDraftSave() {
    setState(() {
      _draftWhiteboard = const LessonWhiteboard(
        strokes: [
          WhiteboardStroke(
            id: 'draft-new',
            timestampSec: 0,
            points: [
              WhiteboardPoint(x: 0.2, y: 0.2, timestampSec: 0),
              WhiteboardPoint(x: 0.8, y: 0.8, timestampSec: 10),
            ],
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LessonWhiteboardEditorPanel(
        courseId: 'course-1',
        lessonNumber: 1,
        mediaUrl: 'https://example.com/lesson.mp3',
        mediaDurationSec: 90,
        durationLabel: '1分30秒',
        publishedWhiteboard: widget.publishedWhiteboard,
        draftWhiteboard: _draftWhiteboard,
        onDraftSaved: (whiteboard) async {
          setState(() {
            _draftWhiteboard = whiteboard.isEmpty ? null : whiteboard;
          });
        },
        playbackFactory: ({required isAudio}) => FakeLessonMediaPlayback(),
      ),
    );
  }
}
