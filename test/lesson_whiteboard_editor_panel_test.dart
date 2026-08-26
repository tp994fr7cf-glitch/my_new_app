import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:my_new_app/models/lesson_material_library.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_timed_anchor.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/models/lesson_whiteboard_part_order.dart';
import 'package:my_new_app/services/lesson_material_library_service.dart';
import 'package:my_new_app/services/lesson_media_playlist_playback.dart';
import 'package:my_new_app/services/lesson_material_storage_service.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_canvas.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_editor_panel.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_payload_meter.dart';

List<LessonMediaSegment> testMediaSegments({int durationSec = 90}) {
  return [
    LessonMediaSegment(
      id: 'test-segment',
      order: 0,
      mediaType: 'audio',
      url: 'https://example.com/lesson.mp3',
      durationSec: durationSec,
    ),
  ];
}

List<LessonMediaSegment> threePartMediaSegments({int partDurationSec = 10}) {
  return [
    for (var index = 0; index < 3; index++)
      LessonMediaSegment(
        id: 'part-${index + 1}',
        order: index,
        mediaType: 'audio',
        url: 'https://example.com/part-${index + 1}.mp3',
        durationSec: partDurationSec,
      ),
  ];
}

LessonMediaPlaylistPlaybackFactory fakePlaylistPlaybackFactory({
  int durationSec = 90,
}) {
  return () => FakeLessonMediaPlaylistPlayback(totalDurationSec: durationSec);
}

void _completeSliderSeek(Slider slider, double value) {
  slider.onChangeStart?.call(value);
  slider.onChanged?.call(value);
  slider.onChangeEnd?.call(value);
}

void _drawEditorStroke(
  LessonWhiteboardCanvas canvas, {
  double x0 = 0.1,
  double x1 = 0.4,
}) {
  canvas.onStrokeStart?.call();
  canvas.onStrokeUpdate?.call(WhiteboardPoint(x: x0, y: 0.5));
  canvas.onStrokeEnd?.call(WhiteboardPoint(x: x1, y: 0.5));
}

void main() {
  testWidgets(
    'Teacher whiteboard editor shows strokes up to the seek position',
    (WidgetTester tester) async {
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
      const draft = LessonWhiteboard(strokes: [leftStroke, rightStroke]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              publishedWhiteboard: null,
              draftWhiteboard: draft,
              onDraftSaved: (_) async {},
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LessonWhiteboardCanvas), findsOneWidget);
      expect(find.byType(LessonWhiteboardPayloadMeter), findsOneWidget);
      expect(find.textContaining('/850'), findsOneWidget);
      var canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes, isEmpty);

      final slider = tester.widget<Slider>(find.byType(Slider));
      _completeSliderSeek(slider, 60);
      await tester.pumpAndSettle();

      canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes, hasLength(2));

      _completeSliderSeek(slider, 25);
      await tester.pumpAndSettle();

      canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes, hasLength(1));
      expect(canvas.strokes.single.id, 'left');
      expect(canvas.strokes.single.points, hasLength(2));
      expect(canvas.strokes.single.points.last.timestampSec, 15);

      _completeSliderSeek(slider, 60);
      await tester.pumpAndSettle();

      canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes, hasLength(2));
      expect(canvas.strokes.last.id, 'right');
    },
  );

  testWidgets(
    'Teacher whiteboard editor keeps full strokes when saving draft',
    (WidgetTester tester) async {
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
      const draft = LessonWhiteboard(strokes: [leftStroke, rightStroke]);
      LessonWhiteboard? savedWhiteboard;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              publishedWhiteboard: null,
              draftWhiteboard: draft,
              onDraftSaved: (whiteboard) async {
                savedWhiteboard = whiteboard;
              },
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final slider = tester.widget<Slider>(find.byType(Slider));
      _completeSliderSeek(slider, 25);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
      await tester.pumpAndSettle();

      expect(savedWhiteboard, isNotNull);
      expect(savedWhiteboard!.strokes, hasLength(2));
      expect(savedWhiteboard!.strokes.map((stroke) => stroke.id), [
        'left',
        'right',
      ]);
    },
  );

  testWidgets(
    'Teacher whiteboard editor shows published preview without draft',
    (WidgetTester tester) async {
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
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              publishedWhiteboard: published,
              draftWhiteboard: null,
              onDraftSaved: (_) async {},
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
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
    },
  );

  testWidgets(
    'Teacher whiteboard editor keeps draft canvas after temporary save',
    (WidgetTester tester) async {
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
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              publishedWhiteboard: published,
              draftWhiteboard: redrawnDraft,
              onDraftSaved: (_) async {},
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, '書き物を一時保存'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '書き物を描き直す'), findsNothing);

      final slider = tester.widget<Slider>(find.byType(Slider));
      _completeSliderSeek(slider, 10);
      await tester.pumpAndSettle();

      final canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes.single.id, 'draft-new');
      expect(canvas.drawingEnabled, isTrue);
    },
  );

  testWidgets(
    'Teacher whiteboard editor updates to draft canvas after redraw save',
    (WidgetTester tester) async {
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
        MaterialApp(home: _DraftSaveHost(publishedWhiteboard: published)),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, '書き物を描き直す'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を描き直す'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'リセットして描き直す'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, '書き物を一時保存'), findsOneWidget);

      final hostState = tester.state<_DraftSaveHostState>(
        find.byType(_DraftSaveHost),
      );
      hostState.simulateRedrawnDraftSave();
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, '書き物を一時保存'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '書き物を描き直す'), findsNothing);

      final slider = tester.widget<Slider>(find.byType(Slider));
      _completeSliderSeek(slider, 10);
      await tester.pumpAndSettle();

      final canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes.single.id, 'draft-new');
    },
  );

  testWidgets(
    'Teacher whiteboard editor can edit published content from options',
    (WidgetTester tester) async {
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
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              publishedWhiteboard: published,
              draftWhiteboard: null,
              onDraftSaved: (_) async {},
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を描き直す'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '公開しているものを編集する'));
      await tester.pumpAndSettle();

      final slider = tester.widget<Slider>(find.byType(Slider));
      _completeSliderSeek(slider, 10);
      await tester.pumpAndSettle();

      final canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes.single.id, 'published');
      expect(find.widgetWithText(OutlinedButton, '書き物を一時保存'), findsOneWidget);
    },
  );

  testWidgets(
    'Teacher whiteboard editor shows three edit options when draft exists',
    (WidgetTester tester) async {
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
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              publishedWhiteboard: published,
              draftWhiteboard: draft,
              onDraftSaved: (_) async {},
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, '編集の選び直し'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(OutlinedButton, '公開しているものを編集する'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, '仮保存中のものを編集する'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'リセットして描き直す'), findsOneWidget);
    },
  );

  testWidgets(
    'Teacher whiteboard editor timestamps points with sub-second live position while recording',
    (WidgetTester tester) async {
      final playback = _ControllableLivePositionPlaylistPlayback(
        totalDurationSec: 90,
      );
      LessonWhiteboard? savedWhiteboard;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              publishedWhiteboard: null,
              draftWhiteboard: null,
              onDraftSaved: (whiteboard) async {
                savedWhiteboard = whiteboard;
              },
              playlistPlaybackFactory: () => playback,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'スタート'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );

      // The coarse, once-per-second stream stays frozen at 0 for this whole
      // gesture, mirroring how audio position updates in production. Only
      // the player's live (sub-second) position advances.
      canvas.onStrokeStart?.call();
      playback.liveOffsetSec = 0.2;
      canvas.onStrokeUpdate?.call(const WhiteboardPoint(x: 0.1, y: 0.5));
      playback.liveOffsetSec = 0.4;
      canvas.onStrokeUpdate?.call(const WhiteboardPoint(x: 0.2, y: 0.5));
      playback.liveOffsetSec = 0.6;
      canvas.onStrokeEnd?.call(const WhiteboardPoint(x: 0.3, y: 0.5));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
      await tester.pumpAndSettle();

      expect(savedWhiteboard, isNotNull);
      expect(savedWhiteboard!.strokes, hasLength(1));
      final stroke = savedWhiteboard!.strokes.single;
      final timestamps = stroke.points
          .map((point) => point.timestampSec)
          .toList();

      // If the fix regresses to the coarse globalPositionStream, every
      // point would share the same (0) timestamp instead of these distinct
      // sub-second values.
      expect(timestamps, [0.2, 0.4, 0.6]);
      expect(stroke.timestampSec, 0.0);
      expect(stroke.endTimestampSec, 0.6);
    },
  );

  testWidgets(
    'Teacher whiteboard deferred reset does not save until draft save',
    (WidgetTester tester) async {
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
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              publishedWhiteboard: published,
              draftWhiteboard: null,
              onDraftSaved: (_) async {
                draftSaveCount++;
              },
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
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
    },
  );

  testWidgets(
    'board selection is local until each screen-share button is pressed',
    (tester) async {
      final playback = _ControllableLivePositionPlaylistPlayback(
        totalDurationSec: 90,
      );
      BoardSet? saved;
      const draft = BoardSet(
        boards: [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            title: '一枚目',
          ),
          LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              draftBoardSet: draft,
              onBoardSetDraftSaved: (boardSet) async {
                saved = boardSet;
              },
              playlistPlaybackFactory: () => playback,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'スタート'));
      await tester.pumpAndSettle();

      playback.liveOffsetSec = 0.375;
      await _selectBoard(tester, '2. 二枚目');
      expect(_screenShareButtonColor(tester), isNot(Colors.red.shade700));
      await tester.tap(
        find.byKey(const ValueKey('whiteboard-share-current-board')),
      );
      await tester.pump();
      expect(_screenShareButtonColor(tester), Colors.red.shade700);
      await _selectBoard(tester, '1. 一枚目');
      expect(_screenShareButtonColor(tester), isNot(Colors.red.shade700));
      await tester.tap(
        find.byKey(const ValueKey('whiteboard-share-current-board')),
      );
      await tester.pump();
      expect(_screenShareButtonColor(tester), Colors.red.shade700);
      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.switchEvents, hasLength(2));
      expect(saved!.orderedSwitchEvents.map((event) => event.sequence), [0, 1]);
      expect(
        saved!.orderedSwitchEvents.map((event) => event.globalTimestampSec),
        [0.375, 0.375],
      );
    },
  );

  testWidgets(
    'viewport changes record live timestamps and only paused final state',
    (tester) async {
      final playback = _ControllableLivePositionPlaylistPlayback(
        totalDurationSec: 90,
      );
      BoardSet? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              draftBoardSet: const BoardSet(
                boards: [
                  LessonWhiteboardBoard(
                    id: LessonWhiteboardBoard.defaultBoardId,
                    order: 0,
                    title: '一枚目',
                  ),
                  LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
                ],
              ),
              onBoardSetDraftSaved: (boardSet) async {
                saved = boardSet;
              },
              playlistPlaybackFactory: () => playback,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'スタート'));
      await tester.pumpAndSettle();

      var canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      playback.liveOffsetSec = 0.2;
      canvas.onViewportChanged!(
        const LessonWhiteboardViewportChange(
          viewport: LessonWhiteboardViewport.full,
          phase: LessonWhiteboardViewportChangePhase.start,
        ),
      );
      playback.liveOffsetSec = 0.3;
      canvas.onViewportChanged!(
        const LessonWhiteboardViewportChange(
          viewport: LessonWhiteboardViewport(
            centerX: 0.5,
            centerY: 0.5,
            scale: 1.5,
          ),
          phase: LessonWhiteboardViewportChangePhase.update,
        ),
      );
      playback.liveOffsetSec = 0.4;
      canvas.onViewportChanged!(
        const LessonWhiteboardViewportChange(
          viewport: LessonWhiteboardViewport(
            centerX: 0.5,
            centerY: 0.5,
            scale: 2,
          ),
          phase: LessonWhiteboardViewportChangePhase.end,
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, '一時停止'));
      await tester.pumpAndSettle();
      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      canvas.onViewportChanged!(
        const LessonWhiteboardViewportChange(
          viewport: LessonWhiteboardViewport(
            centerX: 0.5,
            centerY: 0.5,
            scale: 3,
          ),
          phase: LessonWhiteboardViewportChangePhase.update,
        ),
      );
      canvas.onViewportChanged!(
        const LessonWhiteboardViewportChange(
          viewport: LessonWhiteboardViewport(
            centerX: 0.5,
            centerY: 0.5,
            scale: 4,
          ),
          phase: LessonWhiteboardViewportChangePhase.end,
        ),
      );
      await _selectBoard(tester, '2. 二枚目');
      await tester.tap(find.widgetWithText(FilledButton, 'スタート'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.viewportEvents, hasLength(4));
      expect(saved!.viewportEvents.map((event) => event.globalTimestampSec), [
        0.2,
        0.3,
        0.4,
        0.4,
      ]);
      expect(saved!.viewportEvents.last.viewport.scale, 4);
      expect(saved!.viewportEvents.map((event) => event.interactionId), [
        0,
        0,
        0,
        1,
      ]);
    },
  );

  testWidgets(
    'recorded screen-share following is available before publication',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final playback = _ControllableLivePositionPlaylistPlayback(
        totalDurationSec: 90,
      );
      const draft = BoardSet(
        boards: [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            title: '一枚目',
          ),
          LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
        ],
        switchEvents: [
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'second',
            globalTimestampSec: 2,
            sequence: 0,
          ),
        ],
        viewportEvents: [
          LessonWhiteboardViewportEvent(
            boardId: 'second',
            globalTimestampSec: 2,
            sequence: 0,
            interactionId: 0,
            viewport: LessonWhiteboardViewport(
              centerX: 0.5,
              centerY: 0.5,
              scale: 2,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonWhiteboardEditorPanel(
                courseId: 'course-1',
                lessonNumber: 1,
                mediaSegments: testMediaSegments(),
                durationLabel: '1分30秒',
                draftBoardSet: draft,
                onBoardSetDraftSaved: (_) async {},
                playlistPlaybackFactory: () => playback,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final followSwitch = tester.widget<Switch>(
        find.byKey(
          const ValueKey('editor-recorded-screen-share-follow-switch'),
        ),
      );
      expect(followSwitch.value, isTrue);
      expect(find.text('記録した画面共有に合わせる'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'スタート'));
      await tester.pump();
      playback.liveOffsetSec = 3;
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        find.byKey(const ValueKey('whiteboard-board-dropdown-second')),
        findsOneWidget,
      );
      final followedCanvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(followedCanvas.viewport?.scale, 2);
    },
  );

  testWidgets(
    'unpublished preview follows only the playing part board switches',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const partDurationSec = 10;
      final playback = _ControllableLivePositionPlaylistPlayback(
        totalDurationSec: partDurationSec * 3,
      );
      const defaultId = LessonWhiteboardBoard.defaultBoardId;
      const draft = BoardSet(
        boards: [
          LessonWhiteboardBoard(id: defaultId, order: 0, title: 'ボード1'),
          LessonWhiteboardBoard(id: 'board-2', order: 1, title: 'ボード2'),
          LessonWhiteboardBoard(id: 'board-3', order: 2, title: 'ボード3'),
        ],
        switchEvents: [
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'board-2',
            globalTimestampSec: 2,
            sequence: 0,
            segmentId: 'part-2',
          ),
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'board-3',
            globalTimestampSec: 3,
            sequence: 1,
            segmentId: 'part-3',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonWhiteboardEditorPanel(
                courseId: 'course-1',
                lessonNumber: 1,
                mediaSegments: threePartMediaSegments(
                  partDurationSec: partDurationSec,
                ),
                durationLabel: '30秒',
                draftBoardSet: draft,
                onBoardSetDraftSaved: (_) async {},
                playlistPlaybackFactory: () => playback,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'スタート'));
      await tester.pump();

      playback.liveOffsetSec = 4;
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.byKey(const ValueKey('whiteboard-board-dropdown-$defaultId')),
        findsOneWidget,
      );

      playback.liveOffsetSec = 12;
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.byKey(const ValueKey('whiteboard-board-dropdown-board-2')),
        findsOneWidget,
      );

      playback.liveOffsetSec = 23;
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.byKey(const ValueKey('whiteboard-board-dropdown-board-3')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'published editing follows recorded board and viewport until manual control',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final playback = _ControllableLivePositionPlaylistPlayback(
        totalDurationSec: 90,
      );
      const published = BoardSet(
        boards: [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            title: '一枚目',
          ),
          LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
        ],
        switchEvents: [
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'second',
            globalTimestampSec: 2,
            sequence: 0,
          ),
        ],
        viewportEvents: [
          LessonWhiteboardViewportEvent(
            boardId: 'second',
            globalTimestampSec: 2,
            sequence: 0,
            interactionId: 0,
            viewport: LessonWhiteboardViewport(
              centerX: 0.5,
              centerY: 0.5,
              scale: 2,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonWhiteboardEditorPanel(
                courseId: 'course-1',
                lessonNumber: 1,
                mediaSegments: testMediaSegments(),
                durationLabel: '1分30秒',
                publishedBoardSet: published,
                publishedTimelineDurationSec: 90,
                onBoardSetDraftSaved: (_) async {},
                playlistPlaybackFactory: () => playback,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を描き直す'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '公開しているものを編集する'));
      await tester.pumpAndSettle();

      var followSwitch = tester.widget<Switch>(
        find.byKey(
          const ValueKey('editor-recorded-screen-share-follow-switch'),
        ),
      );
      expect(followSwitch.value, isTrue);

      await tester.tap(find.widgetWithText(FilledButton, 'スタート'));
      await tester.pump();
      playback.liveOffsetSec = 3;
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        find.byKey(const ValueKey('whiteboard-board-dropdown-second')),
        findsOneWidget,
      );
      final followedCanvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(followedCanvas.viewport?.scale, 2);

      await _selectBoard(tester, '1. 一枚目');
      followSwitch = tester.widget<Switch>(
        find.byKey(
          const ValueKey('editor-recorded-screen-share-follow-switch'),
        ),
      );
      expect(followSwitch.value, isFalse);
    },
  );

  testWidgets(
    'screen-share overwrite temporarily suspends published following',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final playback = _ControllableLivePositionPlaylistPlayback(
        totalDurationSec: 90,
      );
      const published = BoardSet(
        boards: [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            title: '一枚目',
          ),
          LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
        ],
        switchEvents: [
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'second',
            globalTimestampSec: 2,
            sequence: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonWhiteboardEditorPanel(
                courseId: 'course-1',
                lessonNumber: 1,
                mediaSegments: testMediaSegments(),
                durationLabel: '1分30秒',
                publishedBoardSet: published,
                publishedTimelineDurationSec: 90,
                onBoardSetDraftSaved: (_) async {},
                playlistPlaybackFactory: () => playback,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を描き直す'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '公開しているものを編集する'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('screen-share-override-checkbox')),
      );
      await tester.pump();

      final followSwitch = tester.widget<Switch>(
        find.byKey(
          const ValueKey('editor-recorded-screen-share-follow-switch'),
        ),
      );
      expect(followSwitch.value, isTrue);
      expect(followSwitch.onChanged, isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'スタート'));
      await tester.pump();
      playback.liveOffsetSec = 3;
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        find.byKey(const ValueKey('whiteboard-board-dropdown-default')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'published screen-share overwrite restores the original timeline when off',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final playback = _ControllableLivePositionPlaylistPlayback(
        totalDurationSec: 90,
      );
      BoardSet? saved;
      const published = BoardSet(
        boards: [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            title: '一枚目',
          ),
          LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
          LessonWhiteboardBoard(id: 'third', order: 2, title: '三枚目'),
        ],
        switchEvents: [
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'second',
            globalTimestampSec: 2,
            sequence: 0,
          ),
          LessonWhiteboardBoardSwitchEvent(
            boardId: LessonWhiteboardBoard.defaultBoardId,
            globalTimestampSec: 6,
            sequence: 1,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonWhiteboardEditorPanel(
                courseId: 'course-1',
                lessonNumber: 1,
                mediaSegments: testMediaSegments(),
                durationLabel: '1分30秒',
                publishedBoardSet: published,
                publishedTimelineDurationSec: 90,
                onBoardSetDraftSaved: (boardSet) async {
                  saved = boardSet;
                },
                playlistPlaybackFactory: () => playback,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を描き直す'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '公開しているものを編集する'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('screen-share-override-checkbox')),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'スタート'));
      await tester.pumpAndSettle();
      playback.liveOffsetSec = 3;
      await _selectBoard(tester, '3. 三枚目');
      await tester.tap(find.widgetWithText(OutlinedButton, '一時停止'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('screen-share-override-checkbox')),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('whiteboard-board-dropdown-second')),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.resolveBoardAt(1)?.id, 'default');
      expect(saved!.resolveBoardAt(2.5)?.id, 'default');
      expect(saved!.resolveBoardAt(3)?.id, 'second');
      expect(saved!.resolveBoardAt(7)?.id, 'default');
    },
  );

  testWidgets(
    'crossing into an unpublished part closes overwrite before manual sharing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final playback = _ControllableLivePositionPlaylistPlayback(
        totalDurationSec: 90,
      );
      BoardSet? saved;
      const published = BoardSet(
        boards: [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            title: '一枚目',
          ),
          LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
          LessonWhiteboardBoard(id: 'third', order: 2, title: '三枚目'),
        ],
        switchEvents: [
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'second',
            globalTimestampSec: 1,
            sequence: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonWhiteboardEditorPanel(
                courseId: 'course-1',
                lessonNumber: 1,
                mediaSegments: testMediaSegments(),
                durationLabel: '1分30秒',
                publishedBoardSet: published,
                publishedTimelineDurationSec: 2,
                onBoardSetDraftSaved: (boardSet) async {
                  saved = boardSet;
                },
                playlistPlaybackFactory: () => playback,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を描き直す'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '公開しているものを編集する'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('screen-share-override-checkbox')),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'スタート'));
      await tester.pump();

      playback.liveOffsetSec = 3;
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.byKey(const ValueKey('screen-share-override-checkbox')),
        findsNothing,
      );
      await _selectBoard(tester, '3. 三枚目');
      await tester.tap(
        find.byKey(const ValueKey('whiteboard-share-current-board')),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, '一時停止'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.resolveBoardAt(2)?.id, 'second');
      expect(saved!.resolveBoardAt(3)?.id, 'third');
    },
  );

  testWidgets(
    'screen-share overwrite aborts safely when the event limit is reached',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final playback = _ControllableLivePositionPlaylistPlayback(
        totalDurationSec: 90,
      );
      BoardSet? saved;
      final published = BoardSet(
        boards: const [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            title: '一枚目',
          ),
        ],
        switchEvents: List.generate(
          maxLessonBoardSwitchEvents,
          (index) => LessonWhiteboardBoardSwitchEvent(
            boardId: LessonWhiteboardBoard.defaultBoardId,
            globalTimestampSec: index / 1000,
            sequence: index,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonWhiteboardEditorPanel(
                courseId: 'course-1',
                lessonNumber: 1,
                mediaSegments: testMediaSegments(),
                durationLabel: '1分30秒',
                publishedBoardSet: published,
                publishedTimelineDurationSec: 90,
                onBoardSetDraftSaved: (boardSet) async {
                  saved = boardSet;
                },
                playlistPlaybackFactory: () => playback,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を描き直す'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '公開しているものを編集する'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('screen-share-override-checkbox')),
      );
      await tester.pump();

      final checkbox = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('screen-share-override-checkbox')),
      );
      expect(checkbox.value, isFalse);
      expect(find.textContaining('今回の画面共有上書きは反映されませんでした'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.switchEvents, hasLength(maxLessonBoardSwitchEvents));
      expect(saved!.switchEvents, published.switchEvents);
    },
  );

  testWidgets('deleting a board removes every switch event targeting it', (
    tester,
  ) async {
    BoardSet? saved;
    const draft = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          title: '一枚目',
        ),
        LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
        LessonWhiteboardBoard(id: 'third', order: 2, title: '三枚目'),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'second',
          globalTimestampSec: 1,
          sequence: 0,
        ),
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'third',
          globalTimestampSec: 2,
          sequence: 1,
        ),
      ],
      viewportEvents: [
        LessonWhiteboardViewportEvent(
          boardId: 'second',
          globalTimestampSec: 1,
          sequence: 0,
          interactionId: 0,
          viewport: LessonWhiteboardViewport(
            centerX: 0.5,
            centerY: 0.5,
            scale: 2,
          ),
        ),
        LessonWhiteboardViewportEvent(
          boardId: 'third',
          globalTimestampSec: 2,
          sequence: 1,
          interactionId: 1,
          viewport: LessonWhiteboardViewport(
            centerX: 0.5,
            centerY: 0.5,
            scale: 3,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonWhiteboardEditorPanel(
            courseId: 'course-1',
            lessonNumber: 1,
            mediaSegments: testMediaSegments(),
            durationLabel: '1分30秒',
            draftBoardSet: draft,
            onBoardSetDraftSaved: (boardSet) async {
              saved = boardSet;
            },
            playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _selectBoard(tester, '2. 二枚目');
    await tester.tap(find.byKey(const ValueKey('whiteboard-delete-board')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.boardById('second'), isNull);
    expect(
      saved!.switchEvents.where((event) => event.boardId == 'second'),
      isEmpty,
    );
    expect(
      saved!.switchEvents.any((event) => event.boardId == 'third'),
      isTrue,
    );
    expect(
      saved!.viewportEvents.where((event) => event.boardId == 'second'),
      isEmpty,
    );
    expect(
      saved!.viewportEvents.any((event) => event.boardId == 'third'),
      isTrue,
    );
  });

  testWidgets(
    'board action buttons wrap instead of overflowing on a narrow phone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(272, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(272, 800)),
          child: MaterialApp(
            home: Scaffold(
              body: LessonWhiteboardEditorPanel(
                courseId: 'course-1',
                lessonNumber: 1,
                mediaSegments: const [],
                durationLabel: '1分30秒',
                draftBoardSet: const BoardSet(
                  boards: [
                    LessonWhiteboardBoard(
                      id: LessonWhiteboardBoard.defaultBoardId,
                      order: 0,
                      title: 'ボード1',
                    ),
                    LessonWhiteboardBoard(
                      id: 'second',
                      order: 1,
                      title: 'ボード2',
                    ),
                  ],
                ),
                onBoardSetDraftSaved: (boardSet) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('名前を変更'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('whiteboard-delete-board')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'renaming a board keeps the title field alive until the dialog finishes closing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LessonWhiteboardEditorPanel(
                  courseId: 'course-1',
                  lessonNumber: 1,
                  mediaSegments: const [],
                  durationLabel: '1分30秒',
                  draftBoardSet: const BoardSet(
                    boards: [
                      LessonWhiteboardBoard(
                        id: LessonWhiteboardBoard.defaultBoardId,
                        order: 0,
                        title: 'ボード1',
                      ),
                    ],
                  ),
                  onBoardSetDraftSaved: (boardSet) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('名前を変更'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('whiteboard-board-title-field')),
        '表紙',
      );
      await tester.tap(find.widgetWithText(FilledButton, '変更'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('1. 表紙'), findsOneWidget);
    },
  );

  testWidgets('twenty boards are allowed but the twenty-first is disabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boards = [
      for (var index = 0; index < 19; index++)
        LessonWhiteboardBoard(
          id: index == 0
              ? LessonWhiteboardBoard.defaultBoardId
              : 'board-$index',
          order: index,
          title: '板${index + 1}',
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              draftBoardSet: BoardSet(boards: boards),
              onBoardSetDraftSaved: (_) async {},
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LessonWhiteboardCanvas), findsOneWidget);
    var addButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('whiteboard-add-board')),
    );
    expect(addButton.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('whiteboard-add-board')));
    await tester.pump();
    addButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('whiteboard-add-board')),
    );
    expect(addButton.onPressed, isNull);
    expect(find.text('20/20'), findsOneWidget);
  });

  testWidgets('adds a selected image as a material board', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    BoardSet? workingBoardSet;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonId: 'lesson-1',
              lessonNumber: 1,
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              draftBoardSet: const BoardSet(
                boards: [
                  LessonWhiteboardBoard(
                    id: LessonWhiteboardBoard.defaultBoardId,
                    order: 0,
                  ),
                ],
              ),
              onBoardSetDraftSaved: (_) async {},
              onBoardSetChanged: (boardSet) => workingBoardSet = boardSet,
              materialStorageService: const _FakeMaterialStorageService(),
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('whiteboard-add-material-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('画像ファイルを追加'));
    await tester.pumpAndSettle();

    expect(workingBoardSet?.boards, hasLength(2));
    final materialBoard = workingBoardSet!.orderedBoards.last;
    expect(materialBoard.background?.isImage, isTrue);
    expect(materialBoard.background?.aspectRatio, 1.5);
    expect(find.text('2/20'), findsOneWidget);
  });

  testWidgets('adds a saved library image as a material board', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    BoardSet? workingBoardSet;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonId: 'lesson-1',
              lessonNumber: 1,
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              draftBoardSet: const BoardSet(
                boards: [
                  LessonWhiteboardBoard(
                    id: LessonWhiteboardBoard.defaultBoardId,
                    order: 0,
                  ),
                ],
              ),
              onBoardSetDraftSaved: (_) async {},
              onBoardSetChanged: (boardSet) => workingBoardSet = boardSet,
              materialStorageService: const _FakeMaterialStorageService(),
              materialLibraryService: const _FakeMaterialLibraryService(),
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('whiteboard-add-material-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存済みから選ぶ'));
    await tester.pumpAndSettle();

    expect(find.text('latest.png'), findsOneWidget);
    await tester.tap(find.text('latest.png'));
    await tester.pumpAndSettle();

    expect(workingBoardSet?.boards, hasLength(2));
    expect(workingBoardSet!.orderedBoards.last.background?.isImage, isTrue);
    expect(find.text('2/20'), findsOneWidget);
  });

  testWidgets('scoped editor shows earlier-part ink and hides PDF menu', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: const [
                LessonMediaSegment(
                  id: 'part-2',
                  order: 1,
                  mediaType: 'audio',
                  url: 'https://example.com/part-2.mp3',
                  durationSec: 10,
                ),
              ],
              durationLabel: '10秒',
              scopedSegmentId: 'part-2',
              orderedSegmentIds: const ['part-1', 'part-2'],
              draftBoardSet: _twoPartScopedDraft(),
              onBoardSetDraftSaved: (_) async {},
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(
                durationSec: 10,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('このパートのホワイトボード'), findsOneWidget);
    expect(find.text('書き物を描き直す'), findsNothing);
    expect(find.text('編集の選び直し'), findsNothing);
    expect(
      find.byKey(const ValueKey('whiteboard-add-material-menu')),
      findsNothing,
    );

    var canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.map((stroke) => stroke.id), ['p1']);

    final slider = tester.widget<Slider>(find.byType(Slider));
    _completeSliderSeek(slider, 5);
    await tester.pumpAndSettle();

    canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.map((stroke) => stroke.id), ['p1', 'p2']);
  });

  testWidgets('scoped reset clears only this part and keeps papers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    BoardSet? working;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: const [
                LessonMediaSegment(
                  id: 'part-2',
                  order: 1,
                  mediaType: 'audio',
                  url: 'https://example.com/part-2.mp3',
                  durationSec: 10,
                ),
              ],
              durationLabel: '10秒',
              scopedSegmentId: 'part-2',
              orderedSegmentIds: const ['part-1', 'part-2'],
              draftBoardSet: _twoPartScopedDraft(boardTitle: '表'),
              onBoardSetDraftSaved: (_) async {},
              onBoardSetChanged: (boardSet) => working = boardSet,
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(
                durationSec: 10,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('リセット'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'リセット'));
    await tester.pumpAndSettle();
    expect(find.textContaining('このパートの書き物だけを消します'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'リセット'));
    await tester.pumpAndSettle();

    expect(working, isNotNull);
    expect(working!.defaultBoard?.title, '表');
    expect(
      strokesForSegmentLayer(
        bundle: working!.defaultBoard!.layerBundle,
        segmentId: 'part-1',
      ).single.id,
      'p1',
    );
    expect(
      strokesForSegmentLayer(
        bundle: working!.defaultBoard!.layerBundle,
        segmentId: 'part-2',
      ),
      isEmpty,
    );
  });

  testWidgets('scoped save keeps writing on the part layer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    BoardSet? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: const [
                LessonMediaSegment(
                  id: 'part-2',
                  order: 1,
                  mediaType: 'audio',
                  url: 'https://example.com/part-2.mp3',
                  durationSec: 10,
                ),
              ],
              durationLabel: '10秒',
              scopedSegmentId: 'part-2',
              orderedSegmentIds: const ['part-1', 'part-2'],
              draftBoardSet: _twoPartScopedDraft(),
              onBoardSetDraftSaved: (boardSet) async {
                saved = boardSet;
              },
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(
                durationSec: 10,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('書き物を一時保存'));
    await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(
      strokesForSegmentLayer(
        bundle: saved!.defaultBoard!.layerBundle,
        segmentId: 'part-1',
      ).single.id,
      'p1',
    );
    expect(
      strokesForSegmentLayer(
        bundle: saved!.defaultBoard!.layerBundle,
        segmentId: 'part-2',
      ).single.id,
      'p2',
    );
    expect(
      saved!.defaultBoard!.layerBundle.namedPrimaryLayer?.strokes ?? const [],
      isEmpty,
    );
  });

  testWidgets(
    'scoped save with overwrite on asks whether to pin until the part ends',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      BoardSet? saved;
      const published = BoardSet(
        boards: [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            title: '一枚目',
          ),
          LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
        ],
        switchEvents: [
          LessonWhiteboardBoardSwitchEvent(
            boardId: 'second',
            globalTimestampSec: 8,
            sequence: 0,
            segmentId: 'part-2',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonWhiteboardEditorPanel(
                courseId: 'course-1',
                lessonNumber: 1,
                mediaSegments: const [
                  LessonMediaSegment(
                    id: 'part-2',
                    order: 1,
                    mediaType: 'audio',
                    url: 'https://example.com/part-2.mp3',
                    durationSec: 30,
                  ),
                ],
                durationLabel: '30秒',
                scopedSegmentId: 'part-2',
                orderedSegmentIds: const ['part-1', 'part-2'],
                publishedBoardSet: published,
                publishedTimelineDurationSec: 30,
                onBoardSetDraftSaved: (boardSet) async {
                  saved = boardSet;
                },
                playlistPlaybackFactory: fakePlaylistPlaybackFactory(
                  durationSec: 30,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('screen-share-override-checkbox')),
      );
      await tester.tap(
        find.byKey(const ValueKey('screen-share-override-checkbox')),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('書き物を一時保存'));
      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
      await tester.pumpAndSettle();

      expect(find.text('今のボードを最後まで固定する'), findsOneWidget);
      expect(find.text('チェック入れた部分だけ保存'), findsOneWidget);
      expect(saved, isNull);

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(saved, isNull);

      await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('screen-share-override-save-pin-until-end')),
      );
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(
        saved!.switchEvents.any(
          (event) => event.segmentId == 'part-2' && event.boardId == 'second',
        ),
        isFalse,
      );
      expect(
        resolveBoardAtPartOrder(
          boardSet: saved!,
          globalTimestampSec: 9,
          partOrder: const WhiteboardPartOrderPlayback(
            orderedSegmentIds: ['part-1', 'part-2'],
            activeSegmentId: 'part-2',
            segmentLocalSec: 9,
          ),
        )?.id,
        LessonWhiteboardBoard.defaultBoardId,
      );
    },
  );

  testWidgets('scoped save can keep only the checked overwrite interval', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    BoardSet? saved;
    const published = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          title: '一枚目',
        ),
        LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'second',
          globalTimestampSec: 8,
          sequence: 0,
          segmentId: 'part-2',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: const [
                LessonMediaSegment(
                  id: 'part-2',
                  order: 1,
                  mediaType: 'audio',
                  url: 'https://example.com/part-2.mp3',
                  durationSec: 30,
                ),
              ],
              durationLabel: '30秒',
              scopedSegmentId: 'part-2',
              orderedSegmentIds: const ['part-1', 'part-2'],
              publishedBoardSet: published,
              publishedTimelineDurationSec: 30,
              onBoardSetDraftSaved: (boardSet) async {
                saved = boardSet;
              },
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(
                durationSec: 30,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('screen-share-override-checkbox')),
    );
    await tester.tap(
      find.byKey(const ValueKey('screen-share-override-checkbox')),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('書き物を一時保存'));
    await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('screen-share-override-save-interval-only')),
    );
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(
      saved!.switchEvents.any(
        (event) => event.segmentId == 'part-2' && event.boardId == 'second',
      ),
      isTrue,
    );
  });

  testWidgets(
    'Teacher can draw while paused and undo then redo the newest visible stroke',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonWhiteboardEditorPanel(
                courseId: 'course-1',
                lessonNumber: 1,
                mediaSegments: testMediaSegments(),
                durationLabel: '1分30秒',
                draftWhiteboard: null,
                onDraftSaved: (_) async {},
                playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.drawingEnabled, isTrue);

      final slider = tester.widget<Slider>(find.byType(Slider));
      _completeSliderSeek(slider, 25);
      await tester.pumpAndSettle();

      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      _drawEditorStroke(canvas);
      await tester.pump();
      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      _drawEditorStroke(canvas, x0: 0.5, x1: 0.8);
      await tester.pump();

      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      expect(canvas.strokes, hasLength(2));
      expect(
        canvas.strokes.every((stroke) => stroke.timestampSec == 25),
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('whiteboard-undo-stroke')));
      await tester.pump();
      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      expect(canvas.strokes, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('whiteboard-redo-stroke')));
      await tester.pump();
      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      expect(canvas.strokes, hasLength(2));
    },
  );

  testWidgets('Teacher undo skips a future stroke after seeking back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              draftWhiteboard: null,
              onDraftSaved: (_) async {},
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    _drawEditorStroke(canvas);
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider));
    _completeSliderSeek(slider, 25);
    await tester.pumpAndSettle();

    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    _drawEditorStroke(canvas, x0: 0.5, x1: 0.8);
    await tester.pump();
    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.strokes, hasLength(2));

    await tester.tap(find.byKey(const ValueKey('whiteboard-undo-stroke')));
    await tester.pump();
    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.strokes.map((stroke) => stroke.timestampSec), [0]);

    _completeSliderSeek(slider, 0);
    await tester.pumpAndSettle();
    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.strokes, hasLength(1));
    expect(canvas.strokes.single.timestampSec, 0);
  });

  testWidgets('Teacher draft save clears undo and redo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonWhiteboardEditorPanel(
              courseId: 'course-1',
              lessonNumber: 1,
              mediaSegments: testMediaSegments(),
              durationLabel: '1分30秒',
              draftWhiteboard: null,
              onDraftSaved: (_) async {},
              playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    _drawEditorStroke(canvas);
    await tester.pump();

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('whiteboard-undo-stroke')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('whiteboard-undo-stroke')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('whiteboard-redo-stroke')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'Teacher undo on another board shows a short message without switching',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonWhiteboardEditorPanel(
                courseId: 'course-1',
                lessonNumber: 1,
                mediaSegments: testMediaSegments(),
                durationLabel: '1分30秒',
                draftBoardSet: const BoardSet(
                  boards: [
                    LessonWhiteboardBoard(
                      id: LessonWhiteboardBoard.defaultBoardId,
                      order: 0,
                      title: 'ボード1',
                    ),
                    LessonWhiteboardBoard(
                      id: 'second',
                      order: 1,
                      title: 'ボード2',
                    ),
                  ],
                ),
                onBoardSetDraftSaved: (_) async {},
                playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _selectBoard(tester, '2. ボード2');
      var canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      _drawEditorStroke(canvas);
      await tester.pump();

      await _selectBoard(tester, '1. ボード1');
      await tester.tap(find.byKey(const ValueKey('whiteboard-undo-stroke')));
      await tester.pump();

      expect(find.text('「ボード2」の直前の線を戻しました。'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            'whiteboard-board-dropdown-${LessonWhiteboardBoard.defaultBoardId}',
          ),
        ),
        findsOneWidget,
      );
    },
  );
}

BoardSet _twoPartScopedDraft({String boardTitle = ''}) {
  return BoardSet(
    boards: [
      LessonWhiteboardBoard(
        id: LessonWhiteboardBoard.defaultBoardId,
        order: 0,
        title: boardTitle,
        layerBundle: LessonWhiteboardLayerBundle(
          layers: [
            LessonWhiteboardLayer(
              id: whiteboardSegmentLayerId('part-1'),
              order: 0,
              anchorType: LessonTimedAnchorType.segment,
              segmentId: 'part-1',
              strokes: const [
                WhiteboardStroke(
                  id: 'p1',
                  timestampSec: 1,
                  points: [
                    WhiteboardPoint(x: 0.1, y: 0.1, timestampSec: 1),
                    WhiteboardPoint(x: 0.2, y: 0.2, timestampSec: 1),
                  ],
                ),
              ],
            ),
            LessonWhiteboardLayer(
              id: whiteboardSegmentLayerId('part-2'),
              order: 1,
              anchorType: LessonTimedAnchorType.segment,
              segmentId: 'part-2',
              strokes: const [
                WhiteboardStroke(
                  id: 'p2',
                  timestampSec: 1,
                  points: [
                    WhiteboardPoint(x: 0.7, y: 0.5, timestampSec: 1),
                    WhiteboardPoint(x: 0.8, y: 0.5, timestampSec: 1),
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

Future<void> _selectBoard(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Color? _screenShareButtonColor(WidgetTester tester) {
  final button = tester.widget<FilledButton>(
    find.byKey(const ValueKey('whiteboard-share-current-board')),
  );
  return button.style?.backgroundColor?.resolve({});
}

class _FakeMaterialStorageService extends LessonMaterialStorageService {
  const _FakeMaterialStorageService();

  @override
  Future<List<PickedLessonImage>> pickImageFiles({
    required int maximumCount,
  }) async {
    return [
      PickedLessonImage(
        fileName: 'diagram.png',
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/png',
        aspectRatio: 1.5,
      ),
    ];
  }

  @override
  Future<LessonMaterialUploadResult> uploadImages({
    required String courseId,
    required String lessonId,
    required List<PickedLessonImage> images,
  }) async {
    return LessonMaterialUploadResult(
      backgrounds: [
        for (final image in images)
          LessonWhiteboardBoardBackground(
            assetId: 'material-${image.fileName}',
            storagePath:
                'courseMedia/course-1/lessons/lesson-1/materials/'
                'material-${image.fileName}/shared/image.png',
            mediaType: lessonWhiteboardBackgroundImage,
            aspectRatio: image.aspectRatio,
          ),
      ],
      titles: [for (final image in images) image.fileName],
    );
  }

  @override
  Future<PickedLessonImage> openImageFromStorage({
    required String storagePath,
    required String fileName,
  }) async {
    return PickedLessonImage(
      fileName: fileName,
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'image/png',
      aspectRatio: 1.5,
    );
  }
}

class _FakeMaterialLibraryService extends LessonMaterialLibraryService {
  const _FakeMaterialLibraryService();

  @override
  Future<List<LessonMaterialLibraryItem>> listItems() async {
    return [
      LessonMaterialLibraryItem(
        courseId: 'c1',
        lessonId: 'l2',
        assetId: 'new',
        courseTitle: '数学',
        lessonTitle: '復習',
        mediaType: lessonWhiteboardBackgroundImage,
        sharedStoragePath:
            'courseMedia/c1/lessons/l2/materials/new/shared/image.png',
        sourceStoragePath:
            'courseMedia/c1/lessons/l2/materials/new/source/original.png',
        fileName: 'latest.png',
        uploadedAt: DateTime.utc(2026, 8, 20, 12),
      ),
    ];
  }
}

/// A fake playlist controller whose [globalPositionStream] only ticks in
/// whole seconds (mirroring production audio playback), while
/// [liveGlobalPositionSec] can be driven independently to simulate the
/// player's real sub-second position.
class _ControllableLivePositionPlaylistPlayback
    implements LessonMediaPlaylistController {
  _ControllableLivePositionPlaylistPlayback({required this.totalDurationSec});

  @override
  final int totalDurationSec;
  final StreamController<double> _globalPositionController =
      StreamController<double>.broadcast();
  final StreamController<int> _totalDurationController =
      StreamController<int>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<int> _segmentIndexController =
      StreamController<int>.broadcast();
  final StreamController<int> _segmentCompletedController =
      StreamController<int>.broadcast();

  double _globalPositionSec = 0;
  double liveOffsetSec = 0;
  bool _isPlaying = false;

  @override
  Stream<double> get globalPositionStream => _globalPositionController.stream;

  @override
  Stream<int> get totalDurationStream => _totalDurationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<int> get segmentIndexStream => _segmentIndexController.stream;

  @override
  Stream<int> get segmentCompletedStream => _segmentCompletedController.stream;

  @override
  double get globalPositionSec => _globalPositionSec;

  @override
  double get liveGlobalPositionSec => (_globalPositionSec + liveOffsetSec)
      .clamp(0.0, totalDurationSec.toDouble());

  @override
  int get currentSegmentIndex => 0;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isReady => true;

  @override
  bool get hasSegments => true;

  @override
  bool get currentSegmentIsAudio => true;

  @override
  LessonMediaSegment? get currentSegment =>
      testMediaSegments(durationSec: totalDurationSec).first;

  @override
  VideoPlayerController? get videoController => null;

  @override
  Future<void> openSegments(List<LessonMediaSegment> segments) async {
    _globalPositionSec = 0;
    _globalPositionController.add(_globalPositionSec);
    _totalDurationController.add(totalDurationSec);
    _segmentIndexController.add(0);
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    liveOffsetSec = 0;
    _playingController.add(false);
  }

  @override
  Future<void> seekGlobal(double globalSec) async {
    _globalPositionSec = globalSec.clamp(0, totalDurationSec.toDouble());
    liveOffsetSec = 0;
    _globalPositionController.add(_globalPositionSec);
  }

  @override
  Future<void> seekToSegmentIndex(
    int segmentIndex, {
    double localStartSec = 0,
  }) async {
    _segmentIndexController.add(0);
  }

  @override
  Future<void> disposePlayer() async {}

  @override
  Future<void> close() async {
    await _globalPositionController.close();
    await _totalDurationController.close();
    await _playingController.close();
    await _segmentIndexController.close();
    await _segmentCompletedController.close();
  }
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
        mediaSegments: testMediaSegments(),
        durationLabel: '1分30秒',
        publishedWhiteboard: widget.publishedWhiteboard,
        draftWhiteboard: _draftWhiteboard,
        onDraftSaved: (whiteboard) async {
          setState(() {
            _draftWhiteboard = whiteboard.isEmpty ? null : whiteboard;
          });
        },
        playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
      ),
    );
  }
}
