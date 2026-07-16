import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/services/lesson_media_playlist_playback.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_canvas.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_editor_panel.dart';

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
      expect(canvas.drawingEnabled, isFalse);
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
      expect(stroke.segmentId, 'test-segment');
      expect(stroke.segmentTimestampSec, 0.0);
      expect(stroke.segmentEndTimestampSec, 0.6);
      expect(stroke.points.map((point) => point.segmentId), [
        'test-segment',
        'test-segment',
        'test-segment',
      ]);
      expect(stroke.points.map((point) => point.segmentTimestampSec), [
        0.2,
        0.4,
        0.6,
      ]);
    },
  );

  testWidgets(
    'Teacher whiteboard editor warns about strokes linked to a deleted part',
    (WidgetTester tester) async {
      const published = LessonWhiteboard(
        strokes: [
          WhiteboardStroke(
            id: 'orphan',
            timestampSec: 5,
            segmentId: 'deleted-segment',
            segmentTimestampSec: 5,
            points: [
              WhiteboardPoint(
                x: 0.1,
                y: 0.5,
                timestampSec: 5,
                segmentId: 'deleted-segment',
                segmentTimestampSec: 5,
              ),
              WhiteboardPoint(
                x: 0.9,
                y: 0.5,
                timestampSec: 6,
                segmentId: 'deleted-segment',
                segmentTimestampSec: 6,
              ),
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

      expect(
        find.text(
          '削除済みパートにリンクされた書き物が1件あります。'
          '受講者には表示されません。',
        ),
        findsOneWidget,
      );
      expect(find.text('リンク切れの書き物を整理'), findsOneWidget);
    },
  );

  testWidgets('Teacher can convert an orphaned stroke back to global timing', (
    WidgetTester tester,
  ) async {
    const published = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'orphan',
          timestampSec: 5,
          segmentId: 'deleted-segment',
          segmentTimestampSec: 5,
          points: [
            WhiteboardPoint(
              x: 0.1,
              y: 0.5,
              timestampSec: 5,
              segmentId: 'deleted-segment',
              segmentTimestampSec: 5,
            ),
            WhiteboardPoint(
              x: 0.9,
              y: 0.5,
              timestampSec: 6,
              segmentId: 'deleted-segment',
              segmentTimestampSec: 6,
            ),
          ],
        ),
      ],
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
            publishedWhiteboard: published,
            draftWhiteboard: null,
            onDraftSaved: (whiteboard) async {
              savedWhiteboard = whiteboard;
            },
            playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('リンク切れの書き物を整理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全体の時刻として残す'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
    await tester.pumpAndSettle();

    expect(savedWhiteboard, isNotNull);
    expect(savedWhiteboard!.strokes.single.timestampSec, 5);
    expect(savedWhiteboard!.strokes.single.segmentId, isNull);
    expect(
      savedWhiteboard!.strokes.single.points.every(
        (point) => point.segmentId == null,
      ),
      isTrue,
    );
  });

  testWidgets('Teacher can save after deleting every orphaned stroke', (
    WidgetTester tester,
  ) async {
    const published = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'orphan',
          timestampSec: 5,
          segmentId: 'deleted-segment',
          segmentTimestampSec: 5,
          points: [
            WhiteboardPoint(
              x: 0.1,
              y: 0.5,
              timestampSec: 5,
              segmentId: 'deleted-segment',
              segmentTimestampSec: 5,
            ),
            WhiteboardPoint(
              x: 0.9,
              y: 0.5,
              timestampSec: 6,
              segmentId: 'deleted-segment',
              segmentTimestampSec: 6,
            ),
          ],
        ),
      ],
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
            publishedWhiteboard: published,
            draftWhiteboard: null,
            onDraftSaved: (whiteboard) async {
              savedWhiteboard = whiteboard;
            },
            playlistPlaybackFactory: fakePlaylistPlaybackFactory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('リンク切れの書き物を整理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除する'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '書き物を一時保存'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '書き物を一時保存'));
    await tester.pumpAndSettle();

    expect(savedWhiteboard, isNotNull);
    expect(savedWhiteboard!.isEmpty, isTrue);
  });

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
  Future<void> seekToSegmentIndex(int segmentIndex) async {
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
