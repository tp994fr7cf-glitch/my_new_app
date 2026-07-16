import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_media_timeline.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
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

  testWidgets(
    'synced whiteboard keeps writing with its segment after reorder',
    (tester) async {
      const stroke = WhiteboardStroke(
        id: 'audio-writing',
        timestampSec: 10,
        segmentId: 'audio',
        segmentTimestampSec: 10,
        points: [
          WhiteboardPoint(
            x: 0.1,
            y: 0.5,
            timestampSec: 10,
            segmentId: 'audio',
            segmentTimestampSec: 10,
          ),
          WhiteboardPoint(
            x: 0.9,
            y: 0.5,
            timestampSec: 20,
            segmentId: 'audio',
            segmentTimestampSec: 20,
          ),
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
            id: 'video',
            order: 0,
            mediaType: 'video',
            url: 'https://example.com/video.mp4',
            durationSec: 90,
          ),
          LessonMediaSegment(
            id: 'audio',
            order: 1,
            mediaType: 'audio',
            url: 'https://example.com/audio.mp3',
            durationSec: 90,
          ),
        ],
      );
      final playback = _ControllableLivePositionFakePlayback(
        totalDurationSec: 180,
        segments: timeline.orderedSegments,
        initialGlobalPositionSec: 110,
        initialSegmentIndex: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonPlaybackSyncedWhiteboard(
              bundle: bundle,
              timeline: timeline,
              playback: playback,
              isPlaying: false,
              positionSecExact: 110,
              totalDurationSec: 180,
            ),
          ),
        ),
      );

      final canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes, hasLength(1));
      expect(canvas.strokes.single.id, 'audio-writing');
    },
  );

  testWidgets(
    'synced whiteboard uses the active player at a segment boundary',
    (tester) async {
      const stroke = WhiteboardStroke(
        id: 'audio-ending',
        timestampSec: 89,
        segmentId: 'audio',
        segmentTimestampSec: 89,
        points: [
          WhiteboardPoint(
            x: 0.1,
            y: 0.5,
            timestampSec: 89,
            segmentId: 'audio',
            segmentTimestampSec: 89,
          ),
          WhiteboardPoint(
            x: 0.9,
            y: 0.5,
            timestampSec: 90,
            segmentId: 'audio',
            segmentTimestampSec: 90,
          ),
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
          LessonMediaSegment(
            id: 'video',
            order: 1,
            mediaType: 'video',
            url: 'https://example.com/video.mp4',
            durationSec: 90,
          ),
        ],
      );
      final playback = _ControllableLivePositionFakePlayback(
        totalDurationSec: 180,
        segments: timeline.orderedSegments,
        initialGlobalPositionSec: 90,
        initialSegmentIndex: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonPlaybackSyncedWhiteboard(
              bundle: bundle,
              timeline: timeline,
              playback: playback,
              isPlaying: false,
              positionSecExact: 90,
              totalDurationSec: 180,
            ),
          ),
        ),
      );

      final canvas = tester.widget<LessonWhiteboardCanvas>(
        find.byType(LessonWhiteboardCanvas),
      );
      expect(canvas.strokes, hasLength(1));
      expect(canvas.strokes.single.points, hasLength(2));
    },
  );
}

class _ControllableLivePositionFakePlayback
    implements LessonMediaPlaylistController {
  _ControllableLivePositionFakePlayback({
    required this.totalDurationSec,
    required List<LessonMediaSegment> segments,
    double initialGlobalPositionSec = 0,
    int initialSegmentIndex = 0,
  }) : _segments = List<LessonMediaSegment>.from(segments),
       _globalPositionSec = initialGlobalPositionSec,
       _currentSegmentIndex = initialSegmentIndex;

  @override
  final int totalDurationSec;
  final List<LessonMediaSegment> _segments;

  final double _globalPositionSec;
  double liveOffsetSec = 0;
  final bool _isPlaying = true;
  final int _currentSegmentIndex;

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
