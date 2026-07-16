import 'dart:async';

import 'package:flutter/material.dart';

import '../models/lesson_media_timeline.dart';
import '../models/lesson_whiteboard.dart';
import '../services/lesson_media_playlist_playback.dart';
import 'lesson_whiteboard_canvas.dart';

/// Keeps the lesson whiteboard in sync with playback using sub-second
/// position reads, without rebuilding the surrounding lesson page every tick.
class LessonPlaybackSyncedWhiteboard extends StatefulWidget {
  const LessonPlaybackSyncedWhiteboard({
    super.key,
    required this.bundle,
    required this.timeline,
    required this.playback,
    required this.isPlaying,
    required this.positionSecExact,
    required this.totalDurationSec,
    this.height = 220,
  });

  final LessonWhiteboardLayerBundle bundle;
  final LessonMediaTimeline timeline;
  final LessonMediaPlaylistController? playback;
  final bool isPlaying;
  final double positionSecExact;
  final int totalDurationSec;
  final double height;

  @override
  State<LessonPlaybackSyncedWhiteboard> createState() =>
      _LessonPlaybackSyncedWhiteboardState();
}

class _LessonPlaybackSyncedWhiteboardState
    extends State<LessonPlaybackSyncedWhiteboard> {
  static const Duration _refreshInterval = Duration(milliseconds: 50);

  Timer? _refreshTimer;
  double _livePositionSec = 0;

  @override
  void initState() {
    super.initState();
    _livePositionSec = _resolvedPositionSec();
    _syncRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant LessonPlaybackSyncedWhiteboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_tracksLivePlayback ||
        widget.positionSecExact != oldWidget.positionSecExact) {
      _livePositionSec = _resolvedPositionSec();
    }
    _syncRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  bool get _tracksLivePlayback =>
      widget.playback != null && widget.playback!.isPlaying;

  void _syncRefreshTimer() {
    final shouldRefresh = _tracksLivePlayback && widget.totalDurationSec > 0;
    if (shouldRefresh) {
      if (_refreshTimer == null) {
        _refreshTimer = Timer.periodic(_refreshInterval, (_) {
          if (!mounted) {
            return;
          }
          final nextPositionSec = _resolvedPositionSec();
          setState(() {
            _livePositionSec = nextPositionSec;
          });
        });
      }
      return;
    }

    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  double _resolvedPositionSec() {
    final maxSec = widget.totalDurationSec.toDouble();
    if (maxSec <= 0) {
      return 0;
    }

    if (_tracksLivePlayback) {
      return widget.playback!.liveGlobalPositionSec.clamp(0.0, maxSec);
    }
    return widget.positionSecExact.clamp(0.0, maxSec);
  }

  double _segmentLocalPositionSec(double globalSec) {
    if (widget.timeline.isEmpty) {
      return globalSec;
    }
    final activeSegment = widget.playback?.currentSegment;
    if (activeSegment != null &&
        widget.timeline.segmentById(activeSegment.id) != null) {
      final segmentStartSec = widget.timeline.startGlobalSecForSegmentId(
        activeSegment.id,
      );
      return (globalSec - segmentStartSec)
          .clamp(0.0, activeSegment.durationSec.toDouble())
          .toDouble();
    }
    return widget.timeline.resolveGlobalSec(globalSec).localSec;
  }

  @override
  Widget build(BuildContext context) {
    final positionSec = _tracksLivePlayback
        ? _livePositionSec
        : _resolvedPositionSec();
    final strokes = visibleWhiteboardBundleStrokes(
      bundle: widget.bundle,
      timeline: widget.timeline,
      globalPositionSec: positionSec,
      segmentLocalPositionSec: _segmentLocalPositionSec(positionSec),
      activeSegmentId: widget.playback?.currentSegment?.id,
    );

    return SizedBox(
      height: widget.height,
      child: LessonWhiteboardCanvas(strokes: strokes, drawingEnabled: false),
    );
  }
}
