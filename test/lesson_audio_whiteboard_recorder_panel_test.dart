import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/lesson_audio_recording_service.dart';
import 'package:my_new_app/widgets/lesson_audio_whiteboard_recorder_panel.dart';
import 'package:my_new_app/widgets/lesson_whiteboard_canvas.dart';

class _FakeRecordingController implements LessonAudioRecordingController {
  bool started = false;
  bool paused = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async {
    started = true;
    paused = false;
  }

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async => paused = false;

  @override
  Future<PlatformFile?> stop() async {
    started = false;
    return PlatformFile(name: 'recording.m4a', path: 'fake.m4a', size: 1024);
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> deleteRecording(PlatformFile file) async {}

  @override
  Future<void> dispose() async {}
}

class _DelayedStopRecordingController extends _FakeRecordingController {
  final Completer<PlatformFile?> stopCompleter = Completer<PlatformFile?>();
  bool deleted = false;

  @override
  Future<PlatformFile?> stop() => stopCompleter.future;

  @override
  Future<void> deleteRecording(PlatformFile file) async {
    deleted = true;
  }
}

class _FailedStopRecordingController extends _FakeRecordingController {
  @override
  Future<PlatformFile?> stop() async {
    started = false;
    return null;
  }
}

class _DelayedDeleteRecordingController extends _FakeRecordingController {
  final Completer<void> deleteCompleter = Completer<void>();

  @override
  Future<void> deleteRecording(PlatformFile file) => deleteCompleter.future;
}

class _FakePreviewController implements LessonAudioPreviewController {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  bool _isPlaying = false;
  Duration currentPosition = Duration.zero;
  bool throwOnStop = false;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Duration get position => currentPosition;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<Duration?> load(String path) async =>
      const Duration(milliseconds: 7200);

  @override
  Future<void> play() async {
    _isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> stop() async {
    if (throwOnStop) {
      throw StateError('preview stop failed');
    }
    _isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> dispose() => _playing.close();
}

void main() {
  testWidgets('recording can pause, resume, preview, and confirm upload', (
    tester,
  ) async {
    final recorder = _FakeRecordingController();
    final preview = _FakePreviewController();
    PlatformFile? usedFile;
    int? usedDuration;
    int? usedDurationMs;

    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonAudioWhiteboardRecorderPanel(
              segmentStartSec: 30,
              initialBoardSet: const BoardSet(),
              recordingControllerFactory: () => recorder,
              previewControllerFactory: () => preview,
              onDiscard: () {},
              onBusyChanged: (_) {},
              onUseRecording: (file, durationSec, durationMs, boardSet) async {
                usedFile = file;
                usedDuration = durationSec;
                usedDurationMs = durationMs;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('start-audio-whiteboard-recording')),
    );
    await tester.pump();
    expect(recorder.started, isTrue);
    expect(find.byKey(const ValueKey('pause-audio-recording')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pause-audio-recording')));
    await tester.pump();
    expect(recorder.paused, isTrue);
    expect(
      find.byKey(const ValueKey('resume-audio-recording')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('resume-audio-recording')));
    await tester.pump();
    expect(recorder.paused, isFalse);

    await tester.tap(find.byKey(const ValueKey('stop-audio-recording')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('preview-audio-recording')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('use-audio-recording')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('use-audio-recording')));
    await tester.pumpAndSettle();
    expect(usedFile?.name, 'recording.m4a');
    expect(usedDuration, 7);
    expect(usedDurationMs, 7200);
  });

  testWidgets(
    'deleting the current recording returns to idle without auto-starting',
    (tester) async {
      final recorder = _FakeRecordingController();
      final preview = _FakePreviewController();

      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonAudioWhiteboardRecorderPanel(
                segmentStartSec: 30,
                initialBoardSet: const BoardSet(),
                recordingControllerFactory: () => recorder,
                previewControllerFactory: () => preview,
                onDiscard: () {},
                onBusyChanged: (_) {},
                onUseRecording: (_, _, _, _) async {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('audio-whiteboard-add-board')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('start-audio-whiteboard-recording')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('audio-whiteboard-add-board')),
      );
      await tester.pump();
      expect(find.text('3. ボード3'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('stop-audio-recording')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('delete-current-audio-recording')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '削除'));
      await tester.pumpAndSettle();

      expect(recorder.started, isFalse);
      expect(
        find.byKey(const ValueKey('start-audio-whiteboard-recording')),
        findsOneWidget,
      );
      expect(find.text('2. ボード2'), findsOneWidget);
      expect(find.text('3. ボード3'), findsNothing);
    },
  );

  testWidgets('restored setup is not reused after later start failure', (
    tester,
  ) async {
    final recorder = _FakeRecordingController();
    final preview = _FakePreviewController();

    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonAudioWhiteboardRecorderPanel(
              segmentStartSec: 30,
              initialBoardSet: const BoardSet(),
              recordingControllerFactory: () => recorder,
              previewControllerFactory: () => preview,
              onDiscard: () {},
              onBusyChanged: (_) {},
              onUseRecording: (_, _, _, _) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('audio-whiteboard-add-board')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('start-audio-whiteboard-recording')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stop-audio-recording')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('delete-current-audio-recording')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '削除'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('audio-whiteboard-add-board')));
    await tester.pump();
    expect(find.text('3. ボード3'), findsOneWidget);
    preview.throwOnStop = true;

    await tester.tap(
      find.byKey(const ValueKey('start-audio-whiteboard-recording')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('start-audio-whiteboard-recording')),
      findsOneWidget,
    );
    expect(find.text('3. ボード3'), findsOneWidget);
    expect(find.textContaining('録音を開始できませんでした'), findsOneWidget);
  });

  testWidgets(
    'recording actions are disabled while current audio is deleting',
    (tester) async {
      final recorder = _DelayedDeleteRecordingController();
      final preview = _FakePreviewController();

      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonAudioWhiteboardRecorderPanel(
                segmentStartSec: 30,
                initialBoardSet: const BoardSet(),
                recordingControllerFactory: () => recorder,
                previewControllerFactory: () => preview,
                onDiscard: () {},
                onBusyChanged: (_) {},
                onUseRecording: (_, _, _, _) async {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('start-audio-whiteboard-recording')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('stop-audio-recording')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('delete-current-audio-recording')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '削除'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('preview-audio-recording')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('use-audio-recording')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('delete-current-audio-recording')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('discard-audio-recording-part')),
            )
            .onPressed,
        isNull,
      );

      recorder.deleteCompleter.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('start-audio-whiteboard-recording')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'boards can be prepared before recording and added while paused',
    (tester) async {
      final recorder = _FakeRecordingController();
      final preview = _FakePreviewController();
      BoardSet? usedBoardSet;

      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonAudioWhiteboardRecorderPanel(
                segmentStartSec: 30,
                initialBoardSet: const BoardSet(),
                recordingControllerFactory: () => recorder,
                previewControllerFactory: () => preview,
                onDiscard: () {},
                onBusyChanged: (_) {},
                onUseRecording:
                    (file, durationSec, durationMs, boardSet) async {
                      usedBoardSet = boardSet;
                    },
              ),
            ),
          ),
        ),
      );

      expect(find.byType(LessonWhiteboardCanvas), findsOneWidget);
      expect(
        find.byKey(const ValueKey('audio-whiteboard-share-current-board')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('whiteboard-zoom-in')), findsNothing);
      var addButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('audio-whiteboard-add-board')),
      );
      expect(addButton.onPressed, isNotNull);
      await tester.tap(
        find.byKey(const ValueKey('audio-whiteboard-add-board')),
      );
      await tester.pump();
      expect(find.text('2. ボード2'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('start-audio-whiteboard-recording')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      var canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
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
      await tester.tap(
        find.byKey(const ValueKey('audio-whiteboard-share-current-board')),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pause-audio-recording')));
      await tester.pumpAndSettle();
      addButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('audio-whiteboard-add-board')),
      );
      expect(addButton.onPressed, isNotNull);
      await tester.tap(
        find.byKey(const ValueKey('audio-whiteboard-add-board')),
      );
      await tester.pump();
      expect(find.text('3. ボード3'), findsOneWidget);
      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      canvas.onViewportChanged!(
        const LessonWhiteboardViewportChange(
          viewport: LessonWhiteboardViewport(
            centerX: 0.5,
            centerY: 0.5,
            scale: 3,
          ),
          phase: LessonWhiteboardViewportChangePhase.end,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('resume-audio-recording')));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('stop-audio-recording')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('use-audio-recording')));
      await tester.pumpAndSettle();

      expect(usedBoardSet, isNotNull);
      expect(usedBoardSet!.boards, hasLength(3));
      expect(usedBoardSet!.switchEvents, hasLength(1));
      expect(usedBoardSet!.orderedSwitchEvents.map((event) => event.sequence), [
        0,
      ]);
      expect(usedBoardSet!.orderedSwitchEvents.map((event) => event.boardId), [
        usedBoardSet!.orderedBoards[1].id,
      ]);
      expect(
        usedBoardSet!.orderedSwitchEvents.every(
          (event) =>
              event.globalTimestampSec >= 30 &&
              event.globalTimestampSec <= 37.2,
        ),
        isTrue,
      );
      expect(usedBoardSet!.viewportEvents, hasLength(1));
      expect(
        usedBoardSet!.viewportEvents.map((event) => event.boardId).toSet(),
        {usedBoardSet!.orderedBoards[1].id},
      );
      expect(
        usedBoardSet!.viewportEvents
            .where(
              (event) => event.boardId == usedBoardSet!.orderedBoards[1].id,
            )
            .single
            .viewport
            .scale,
        2,
      );
    },
  );

  testWidgets('failed stop restores the board setup from before recording', (
    tester,
  ) async {
    final recorder = _FailedStopRecordingController();
    final preview = _FakePreviewController();

    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonAudioWhiteboardRecorderPanel(
              segmentStartSec: 30,
              initialBoardSet: const BoardSet(),
              recordingControllerFactory: () => recorder,
              previewControllerFactory: () => preview,
              onDiscard: () {},
              onBusyChanged: (_) {},
              onUseRecording: (_, _, _, _) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('audio-whiteboard-add-board')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('start-audio-whiteboard-recording')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('audio-whiteboard-add-board')));
    await tester.pump();
    expect(find.text('3. ボード3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stop-audio-recording')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('start-audio-whiteboard-recording')),
      findsOneWidget,
    );
    expect(find.text('2. ボード2'), findsOneWidget);
    expect(find.text('3. ボード3'), findsNothing);
    expect(find.textContaining('録音の保存に失敗しました'), findsOneWidget);
  });

  testWidgets('paused local preview keeps future strokes hidden', (
    tester,
  ) async {
    final recorder = _FakeRecordingController();
    final preview = _FakePreviewController();
    const initialBoardSet = BoardSet(
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
                    timestampSec: 31,
                    points: [
                      WhiteboardPoint(x: 0.1, y: 0.2, timestampSec: 31),
                      WhiteboardPoint(x: 0.2, y: 0.2, timestampSec: 31.2),
                    ],
                  ),
                  WhiteboardStroke(
                    id: 'future',
                    timestampSec: 35,
                    points: [
                      WhiteboardPoint(x: 0.1, y: 0.8, timestampSec: 35),
                      WhiteboardPoint(x: 0.2, y: 0.8, timestampSec: 35.2),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      viewportEvents: [
        LessonWhiteboardViewportEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 31,
          sequence: 0,
          interactionId: 0,
          viewport: LessonWhiteboardViewport(
            centerX: 0.5,
            centerY: 0.5,
            scale: 2,
          ),
        ),
        LessonWhiteboardViewportEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 35,
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
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LessonAudioWhiteboardRecorderPanel(
              segmentStartSec: 30,
              initialBoardSet: initialBoardSet,
              recordingControllerFactory: () => recorder,
              previewControllerFactory: () => preview,
              onDiscard: () {},
              onBusyChanged: (_) {},
              onUseRecording: (_, _, _, _) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('start-audio-whiteboard-recording')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stop-audio-recording')));
    await tester.pumpAndSettle();

    preview.currentPosition = const Duration(seconds: 2);
    await tester.tap(find.byKey(const ValueKey('preview-audio-recording')));
    await tester.pump(const Duration(milliseconds: 60));
    var canvas = tester.widget<LessonWhiteboardCanvas>(
      find.byType(LessonWhiteboardCanvas),
    );
    expect(canvas.strokes.map((stroke) => stroke.id), ['early']);
    expect(canvas.viewport?.scale, 2);

    await tester.tap(find.byKey(const ValueKey('preview-audio-recording')));
    await tester.pump();
    canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
    expect(canvas.strokes.map((stroke) => stroke.id), ['early']);
    expect(canvas.viewport?.scale, 2);
  });

  testWidgets('a stopped file is deleted when disposal wins the stop race', (
    tester,
  ) async {
    final recorder = _DelayedStopRecordingController();
    final preview = _FakePreviewController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonAudioWhiteboardRecorderPanel(
            segmentStartSec: 0,
            initialBoardSet: const BoardSet(),
            recordingControllerFactory: () => recorder,
            previewControllerFactory: () => preview,
            onDiscard: () {},
            onBusyChanged: (_) {},
            onUseRecording: (_, _, _, _) async {},
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('start-audio-whiteboard-recording')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stop-audio-recording')));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    recorder.stopCompleter.complete(
      PlatformFile(name: 'late.m4a', path: 'late.m4a', size: 1024),
    );
    await tester.pumpAndSettle();

    expect(recorder.deleted, isTrue);
  });

  testWidgets(
    'paused recording accepts distance-sampled strokes and can undo them',
    (tester) async {
      final recorder = _FakeRecordingController();
      final preview = _FakePreviewController();
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LessonAudioWhiteboardRecorderPanel(
                segmentStartSec: 0,
                initialBoardSet: const BoardSet(),
                recordingControllerFactory: () => recorder,
                previewControllerFactory: () => preview,
                onDiscard: () {},
                onBusyChanged: (_) {},
                onUseRecording: (_, _, _, _) async {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('start-audio-whiteboard-recording')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pause-audio-recording')));
      await tester.pumpAndSettle();

      var canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.drawingEnabled, isTrue);

      canvas.onStrokeStart?.call();
      canvas.onStrokeUpdate?.call(const WhiteboardPoint(x: 0.10, y: 0.50));
      canvas.onStrokeUpdate?.call(const WhiteboardPoint(x: 0.20, y: 0.50));
      canvas.onStrokeUpdate?.call(const WhiteboardPoint(x: 0.30, y: 0.50));
      canvas.onStrokeEnd?.call(const WhiteboardPoint(x: 0.40, y: 0.50));
      await tester.pump();

      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      expect(canvas.strokes, hasLength(1));
      expect(canvas.strokes.single.points, hasLength(4));
      expect(
        canvas.strokes.single.points.map((point) => point.timestampSec).toSet(),
        hasLength(1),
      );

      await tester.tap(
        find.byKey(const ValueKey('audio-whiteboard-undo-stroke')),
      );
      await tester.pump();
      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      expect(canvas.strokes, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('audio-whiteboard-redo-stroke')),
      );
      await tester.pump();
      canvas = tester.widget(find.byType(LessonWhiteboardCanvas));
      expect(canvas.strokes, hasLength(1));
    },
  );
}
