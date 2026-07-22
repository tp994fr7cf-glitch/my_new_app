import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/lesson_audio_recording_service.dart';
import 'package:my_new_app/widgets/lesson_audio_whiteboard_recorder_panel.dart';

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

class _FakePreviewController implements LessonAudioPreviewController {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  bool _isPlaying = false;

  @override
  bool get isPlaying => _isPlaying;

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
}
