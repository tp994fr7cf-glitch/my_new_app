import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_media_timeline.dart';
import 'package:my_new_app/models/lesson_timed_anchor.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/lesson_media_playlist_playback.dart';
import 'package:my_new_app/widgets/lesson_playback_synced_whiteboard.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_canvas.dart';

void main() {
  testWidgets(
    'synced whiteboard updates sub-second while audio position ticks once per second',
    (tester) async {
      const stroke = WhiteboardStroke(
        id: 'progressive',
        timestampSec: 0,
        endTimestampSec: 0.6,
        points: [
          WhiteboardPoint(x: 0.0, y: 0.5, timestampSec: 0.0),
          WhiteboardPoint(x: 0.25, y: 0.5, timestampSec: 0.15),
          WhiteboardPoint(x: 0.5, y: 0.5, timestampSec: 0.3),
          WhiteboardPoint(x: 0.75, y: 0.5, timestampSec: 0.45),
        ],
      );
      const bundle = LessonWhiteboardLayerBundle(
        layers: [
          LessonWhiteboardLayer(id: 'layer-1', order: 0, strokes: [stroke]),
        ],
      );
      final timeline = LessonMediaTimeline(
        segments: [
          LessonMediaSegment(
            id: 'audio',
            order: 0,
            mediaType: 'audio',
            url: 'https://example.com/audio.mp3',
            durationSec: 90,
          ),
        ],
      );
      final playback = _ControllableLivePositionFakePlayback(
        totalDurationSec: 90,
        segments: timeline.orderedSegments,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonPlaybackSyncedWhiteboard(
              bundle: bundle,
              timeline: timeline,
              playback: playback,
              isPlaying: true,
              positionSecExact: 0,
              totalDurationSec: 90,
            ),
          ),
        ),
      );

      var canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes, isEmpty);
      expect(canvas.topLeftOverlay, isNull);

      playback.liveOffsetSec = 0.2;
      await tester.pump(const Duration(milliseconds: 50));
      canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes, hasLength(1));
      expect(canvas.strokes.single.points, hasLength(2));

      playback.liveOffsetSec = 0.35;
      await tester.pump(const Duration(milliseconds: 50));
      canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes.single.points, hasLength(3));
      expect(playback.globalPositionSec, 0);
    },
  );

  testWidgets('exact media duration keeps final fractional events visible', (
    tester,
  ) async {
    const finalStroke = WhiteboardStroke(
      id: 'fractional-end',
      timestampSec: 7.05,
      endTimestampSec: 7.1,
      points: [
        WhiteboardPoint(x: 0.2, y: 0.5, timestampSec: 7.05),
        WhiteboardPoint(x: 0.8, y: 0.5, timestampSec: 7.1),
      ],
    );
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          layerBundle: LessonWhiteboardLayerBundle(
            layers: [
              LessonWhiteboardLayer(
                id: LessonWhiteboardLayer.primaryLayerId,
                order: 0,
                strokes: [finalStroke],
              ),
            ],
          ),
        ),
      ],
      viewportEvents: [
        LessonWhiteboardViewportEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 7.1,
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
    final timeline = LessonMediaTimeline(
      segments: const [
        LessonMediaSegment(
          id: 'audio',
          order: 0,
          mediaType: 'audio',
          durationSec: 7,
          durationMs: 7200,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonPlaybackSyncedWhiteboard(
            boardSet: boardSet,
            timeline: timeline,
            playback: null,
            isPlaying: false,
            positionSecExact: 7.15,
            totalDurationSec: 7,
          ),
        ),
      ),
    );

    final canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.single.id, 'fractional-end');
    expect(canvas.viewport?.scale, 2);
  });

  testWidgets('follow, manual selection, and backward seeks select one board', (
    tester,
  ) async {
    const defaultStroke = WhiteboardStroke(
      id: 'default-now',
      timestampSec: 0,
      points: [
        WhiteboardPoint(x: 0.1, y: 0.1, timestampSec: 0),
        WhiteboardPoint(x: 0.9, y: 0.1, timestampSec: 0),
      ],
    );
    const secondStroke = WhiteboardStroke(
      id: 'second-now',
      timestampSec: 0,
      points: [
        WhiteboardPoint(x: 0.1, y: 0.5, timestampSec: 0),
        WhiteboardPoint(x: 0.9, y: 0.5, timestampSec: 0),
      ],
    );
    const futureStroke = WhiteboardStroke(
      id: 'second-future',
      timestampSec: 20,
      points: [
        WhiteboardPoint(x: 0.1, y: 0.8, timestampSec: 20),
        WhiteboardPoint(x: 0.9, y: 0.8, timestampSec: 20),
      ],
    );
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          title: '基本',
          layerBundle: LessonWhiteboardLayerBundle(
            layers: [
              LessonWhiteboardLayer(
                id: LessonWhiteboardLayer.primaryLayerId,
                order: 0,
                strokes: [defaultStroke],
              ),
            ],
          ),
        ),
        LessonWhiteboardBoard(
          id: 'second',
          order: 1,
          title: '補足',
          layerBundle: LessonWhiteboardLayerBundle(
            layers: [
              LessonWhiteboardLayer(
                id: LessonWhiteboardLayer.primaryLayerId,
                order: 0,
                strokes: [secondStroke, futureStroke],
              ),
            ],
          ),
        ),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'second',
          globalTimestampSec: 5,
          sequence: 0,
        ),
      ],
    );
    final timeline = LessonMediaTimeline(segments: const []);

    Future<void> pumpAt(double positionSec) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonPlaybackSyncedWhiteboard(
              boardSet: boardSet,
              timeline: timeline,
              playback: null,
              isPlaying: false,
              positionSecExact: positionSec,
              totalDurationSec: 30,
            ),
          ),
        ),
      );
    }

    await pumpAt(0);
    expect(find.byType(LessonWhiteboardCanvas), findsOneWidget);
    var canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.single.id, 'default-now');

    await pumpAt(6);
    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.strokes.map((stroke) => stroke.id), ['second-now']);
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('learner-whiteboard-follow-switch')),
          )
          .value,
      isTrue,
    );

    tester
        .widget<Switch>(
          find.byKey(const ValueKey('learner-whiteboard-follow-switch')),
        )
        .onChanged!(false);
    await tester.pump();
    await pumpAt(0);
    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.strokes.single.id, 'second-now');

    tester
        .widget<DropdownButton<String>>(
          find.byKey(const ValueKey('learner-whiteboard-board-selector')),
        )
        .onChanged!(LessonWhiteboardBoard.defaultBoardId);
    await tester.pump();
    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.strokes.single.id, 'default-now');

    await pumpAt(6);
    tester
        .widget<Switch>(
          find.byKey(const ValueKey('learner-whiteboard-follow-switch')),
        )
        .onChanged!(true);
    await tester.pump();
    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.strokes.map((stroke) => stroke.id), ['second-now']);

    await pumpAt(0);
    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.strokes.single.id, 'default-now');
    expect(find.byType(LessonWhiteboardCanvas), findsOneWidget);
  });

  testWidgets('manual zoom pauses viewport following and switch restores it', (
    tester,
  ) async {
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
      ],
      viewportEvents: [
        LessonWhiteboardViewportEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 1,
          sequence: 0,
          interactionId: 0,
          viewport: LessonWhiteboardViewport.full,
        ),
        LessonWhiteboardViewportEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 2,
          sequence: 1,
          interactionId: 0,
          viewport: LessonWhiteboardViewport(
            centerX: 0.5,
            centerY: 0.5,
            scale: 2,
          ),
        ),
      ],
    );

    Future<void> pumpAt(double positionSec) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonPlaybackSyncedWhiteboard(
              boardSet: boardSet,
              timeline: LessonMediaTimeline(segments: const []),
              playback: null,
              isPlaying: false,
              positionSecExact: positionSec,
              totalDurationSec: 10,
            ),
          ),
        ),
      );
    }

    await pumpAt(1.5);
    var canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.viewport?.scale, 1.5);

    canvas.onViewportChanged!(
      const LessonWhiteboardViewportChange(
        viewport: LessonWhiteboardViewport(
          centerX: 0.5,
          centerY: 0.5,
          scale: 3,
        ),
        phase: LessonWhiteboardViewportChangePhase.start,
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('learner-whiteboard-follow-switch')),
          )
          .value,
      isFalse,
    );

    await pumpAt(2);
    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.viewport, isNull);

    tester
        .widget<Switch>(
          find.byKey(const ValueKey('learner-whiteboard-follow-switch')),
        )
        .onChanged!(true);
    await tester.pump();
    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.viewport?.scale, 2);
  });

  testWidgets(
    'sub playback stays fixed while main playback advances and can resync',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const boardSet = BoardSet(
        boards: [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            layerBundle: LessonWhiteboardLayerBundle(
              layers: [
                LessonWhiteboardLayer(
                  id: LessonWhiteboardLayer.primaryLayerId,
                  order: 0,
                  strokes: [
                    WhiteboardStroke(
                      id: 'early',
                      timestampSec: 1,
                      points: [
                        WhiteboardPoint(x: 0.1, y: 0.2, timestampSec: 1),
                        WhiteboardPoint(x: 0.2, y: 0.3, timestampSec: 1.5),
                      ],
                    ),
                    WhiteboardStroke(
                      id: 'late',
                      timestampSec: 10,
                      points: [
                        WhiteboardPoint(x: 0.3, y: 0.4, timestampSec: 10),
                        WhiteboardPoint(x: 0.4, y: 0.5, timestampSec: 10.5),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
      final timeline = LessonMediaTimeline(
        segments: const [
          LessonMediaSegment(
            id: 'audio',
            order: 0,
            mediaType: 'audio',
            durationSec: 30,
          ),
        ],
      );
      final playback = _ControllableLivePositionFakePlayback(
        totalDurationSec: 30,
        segments: timeline.orderedSegments,
      )..liveOffsetSec = 12;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonPlaybackSyncedWhiteboard(
              boardSet: boardSet,
              timeline: timeline,
              playback: playback,
              isPlaying: true,
              positionSecExact: 0,
              totalDurationSec: 30,
              enableSubPlayback: true,
            ),
          ),
        ),
      );

      var canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes.map((stroke) => stroke.id), ['early', 'late']);

      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('whiteboard-sub-playback-slider')),
      );
      slider.onChangeStart!(4);
      slider.onChanged!(4);
      slider.onChangeEnd!(4);
      await tester.pump();

      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      expect(canvas.strokes.map((stroke) => stroke.id), ['early']);
      expect(
        find.byKey(const ValueKey('whiteboard-sub-playback-resync')),
        findsOneWidget,
      );

      playback.liveOffsetSec = 20;
      await tester.pump(const Duration(milliseconds: 100));

      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      expect(canvas.strokes.map((stroke) => stroke.id), ['early']);

      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('whiteboard-sub-playback-resync')),
          )
          .onPressed!();
      await tester.pump();

      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      expect(canvas.strokes.map((stroke) => stroke.id), ['early', 'late']);
      expect(
        find.byKey(const ValueKey('whiteboard-sub-playback-resync')),
        findsNothing,
      );
    },
  );

  testWidgets('sub position resolves segment layers independently from main', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          layerBundle: LessonWhiteboardLayerBundle(
            layers: [
              LessonWhiteboardLayer(
                id: 'first-layer',
                order: 0,
                anchorType: LessonTimedAnchorType.segment,
                segmentId: 'first',
                strokes: [
                  WhiteboardStroke(
                    id: 'first-stroke',
                    timestampSec: 1,
                    points: [
                      WhiteboardPoint(x: 0.1, y: 0.1, timestampSec: 1),
                      WhiteboardPoint(x: 0.2, y: 0.2, timestampSec: 1.5),
                    ],
                  ),
                ],
              ),
              LessonWhiteboardLayer(
                id: 'second-layer',
                order: 1,
                anchorType: LessonTimedAnchorType.segment,
                segmentId: 'second',
                strokes: [
                  WhiteboardStroke(
                    id: 'second-stroke',
                    timestampSec: 1,
                    points: [
                      WhiteboardPoint(x: 0.3, y: 0.3, timestampSec: 1),
                      WhiteboardPoint(x: 0.4, y: 0.4, timestampSec: 1.5),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final timeline = LessonMediaTimeline(
      segments: const [
        LessonMediaSegment(
          id: 'first',
          order: 0,
          mediaType: 'audio',
          durationSec: 10,
        ),
        LessonMediaSegment(
          id: 'second',
          order: 1,
          mediaType: 'audio',
          durationSec: 10,
        ),
      ],
    );
    final playback =
        _ControllableLivePositionFakePlayback(
            totalDurationSec: 20,
            segments: timeline.orderedSegments,
          )
          .._globalPositionSec = 12
          .._currentSegmentIndex = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonPlaybackSyncedWhiteboard(
            boardSet: boardSet,
            timeline: timeline,
            playback: playback,
            isPlaying: true,
            positionSecExact: 12,
            totalDurationSec: 20,
            enableSubPlayback: true,
          ),
        ),
      ),
    );

    var canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.map((stroke) => stroke.id), [
      'first-stroke',
      'second-stroke',
    ]);

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('whiteboard-sub-playback-slider')),
    );
    slider.onChangeStart!(2);
    slider.onChanged!(2);
    slider.onChangeEnd!(2);
    await tester.pump();

    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.strokes.single.id, 'first-stroke');
    expect(playback.currentSegment?.id, 'second');
  });

  testWidgets('sub playback warms all material URLs without blocking display', (
    tester,
  ) async {
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          background: LessonWhiteboardBoardBackground(
            assetId: 'image',
            storagePath: 'materials/image.jpg',
            mediaType: lessonWhiteboardBackgroundImage,
            aspectRatio: 4 / 3,
          ),
        ),
        LessonWhiteboardBoard(
          id: 'pdf',
          order: 1,
          background: LessonWhiteboardBoardBackground(
            assetId: 'pdf',
            storagePath: 'materials/document.pdf',
            mediaType: lessonWhiteboardBackgroundPdf,
            aspectRatio: 4 / 3,
          ),
        ),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'pdf',
          globalTimestampSec: 5,
          sequence: 0,
        ),
      ],
    );
    final requestedPaths = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonPlaybackSyncedWhiteboard(
              boardSet: boardSet,
              timeline: LessonMediaTimeline(segments: const []),
              playback: null,
              isPlaying: false,
              positionSecExact: 0,
              totalDurationSec: 10,
              enableSubPlayback: true,
              materialUrlResolver: (storagePath) async {
                requestedPaths.add(storagePath);
                return const LessonWhiteboardMaterialSource.network('');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(requestedPaths, contains('materials/image.jpg'));
    expect(requestedPaths, contains('materials/document.pdf'));
    expect(find.byType(LessonWhiteboardCanvas), findsOneWidget);
  });

  testWidgets('uniform correction advances strokes, board switches, and zoom', (
    tester,
  ) async {
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
        LessonWhiteboardBoard(
          id: 'second',
          order: 1,
          layerBundle: LessonWhiteboardLayerBundle(
            layers: [
              LessonWhiteboardLayer(
                id: LessonWhiteboardLayer.primaryLayerId,
                order: 0,
                strokes: [
                  WhiteboardStroke(
                    id: 'corrected-stroke',
                    timestampSec: 5,
                    points: [
                      WhiteboardPoint(x: 0.1, y: 0.1, timestampSec: 5),
                      WhiteboardPoint(x: 0.2, y: 0.2, timestampSec: 5),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'second',
          globalTimestampSec: 5,
          sequence: 0,
        ),
      ],
      viewportEvents: [
        LessonWhiteboardViewportEvent(
          boardId: 'second',
          globalTimestampSec: 5,
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
    final timeline = LessonMediaTimeline(
      segments: const [
        LessonMediaSegment(
          id: 'audio',
          order: 0,
          durationSec: 10,
          whiteboardStartCorrectionMs: 1000,
          whiteboardEndCorrectionMs: 1000,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonPlaybackSyncedWhiteboard(
            boardSet: boardSet,
            timeline: timeline,
            playback: null,
            isPlaying: false,
            positionSecExact: 4,
            totalDurationSec: 10,
          ),
        ),
      ),
    );

    final canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.single.id, 'corrected-stroke');
    expect(canvas.viewport?.scale, 2);
  });

  testWidgets('two-point correction is interpolated at the sub position', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          layerBundle: LessonWhiteboardLayerBundle(
            layers: [
              LessonWhiteboardLayer(
                id: LessonWhiteboardLayer.primaryLayerId,
                order: 0,
                strokes: [
                  WhiteboardStroke(
                    id: 'ramped-stroke',
                    timestampSec: 6,
                    points: [
                      WhiteboardPoint(x: 0.1, y: 0.1, timestampSec: 6),
                      WhiteboardPoint(x: 0.2, y: 0.2, timestampSec: 6),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final timeline = LessonMediaTimeline(
      segments: const [
        LessonMediaSegment(
          id: 'audio',
          order: 0,
          durationSec: 10,
          whiteboardStartCorrectionMs: 0,
          whiteboardEndCorrectionMs: 2000,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonPlaybackSyncedWhiteboard(
            boardSet: boardSet,
            timeline: timeline,
            playback: null,
            isPlaying: false,
            positionSecExact: 0,
            totalDurationSec: 10,
            enableSubPlayback: true,
          ),
        ),
      ),
    );
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('whiteboard-sub-playback-slider')),
    );
    slider.onChangeStart!(5);
    slider.onChanged!(5);
    slider.onChangeEnd!(5);
    await tester.pump();

    final canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.single.id, 'ramped-stroke');
  });

  testWidgets(
    'delaying a new part keeps prior writing without showing its first event',
    (tester) async {
      const boardSet = BoardSet(
        boards: [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            layerBundle: LessonWhiteboardLayerBundle(
              layers: [
                LessonWhiteboardLayer(
                  id: LessonWhiteboardLayer.primaryLayerId,
                  order: 0,
                  strokes: [
                    WhiteboardStroke(
                      id: 'prior-part',
                      timestampSec: 9.5,
                      points: [
                        WhiteboardPoint(x: 0.1, y: 0.1, timestampSec: 9.5),
                        WhiteboardPoint(x: 0.2, y: 0.2, timestampSec: 9.5),
                      ],
                    ),
                    WhiteboardStroke(
                      id: 'new-part',
                      timestampSec: 10,
                      points: [
                        WhiteboardPoint(x: 0.3, y: 0.3, timestampSec: 10),
                        WhiteboardPoint(x: 0.4, y: 0.4, timestampSec: 10),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
      final timeline = LessonMediaTimeline(
        segments: const [
          LessonMediaSegment(id: 'first', order: 0, durationSec: 10),
          LessonMediaSegment(
            id: 'second',
            order: 1,
            durationSec: 10,
            whiteboardStartCorrectionMs: -1000,
            whiteboardEndCorrectionMs: -1000,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonPlaybackSyncedWhiteboard(
              boardSet: boardSet,
              timeline: timeline,
              playback: null,
              isPlaying: false,
              positionSecExact: 10.5,
              totalDurationSec: 20,
            ),
          ),
        ),
      );

      final canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes.map((stroke) => stroke.id), ['prior-part']);
    },
  );
}

class _ControllableLivePositionFakePlayback
    implements LessonMediaPlaylistController {
  _ControllableLivePositionFakePlayback({
    required this.totalDurationSec,
    required List<LessonMediaSegment> segments,
  }) : _segments = List<LessonMediaSegment>.from(segments);

  @override
  final int totalDurationSec;
  final List<LessonMediaSegment> _segments;

  double _globalPositionSec = 0;
  double liveOffsetSec = 0;
  final bool _isPlaying = true;
  int _currentSegmentIndex = 0;

  @override
  double get globalPositionSec => _globalPositionSec;

  @override
  double get liveGlobalPositionSec => _globalPositionSec + liveOffsetSec;

  @override
  Stream<double> get globalPositionStream => const Stream.empty();

  @override
  Stream<int> get totalDurationStream => const Stream.empty();

  @override
  Stream<bool> get playingStream => const Stream.empty();

  @override
  Stream<int> get segmentIndexStream => const Stream.empty();

  @override
  int get currentSegmentIndex => _currentSegmentIndex;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isReady => true;

  @override
  bool get hasSegments => _segments.isNotEmpty;

  @override
  bool get currentSegmentIsAudio => currentSegment?.isAudio ?? true;

  @override
  LessonMediaSegment? get currentSegment {
    if (_currentSegmentIndex < 0 || _currentSegmentIndex >= _segments.length) {
      return null;
    }
    return _segments[_currentSegmentIndex];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
