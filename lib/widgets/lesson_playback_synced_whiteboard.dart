import 'dart:async';

import 'package:flutter/material.dart';

import '../models/lesson_media_timeline.dart';
import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';
import '../services/lesson_media_playlist_playback.dart';
import 'lesson_whiteboard_canvas.dart';

/// Keeps the lesson whiteboard in sync with playback using sub-second
/// position reads, without rebuilding the surrounding lesson page every tick.
class LessonPlaybackSyncedWhiteboard extends StatefulWidget {
  const LessonPlaybackSyncedWhiteboard({
    super.key,
    this.bundle,
    this.boardSet,
    required this.timeline,
    required this.playback,
    required this.isPlaying,
    required this.positionSecExact,
    required this.totalDurationSec,
  }) : assert(bundle != null || boardSet != null);

  final LessonWhiteboardLayerBundle? bundle;
  final BoardSet? boardSet;
  final LessonMediaTimeline timeline;
  final LessonMediaPlaylistController? playback;
  final bool isPlaying;
  final double positionSecExact;
  final int totalDurationSec;

  @override
  State<LessonPlaybackSyncedWhiteboard> createState() =>
      _LessonPlaybackSyncedWhiteboardState();
}

class _LessonPlaybackSyncedWhiteboardState
    extends State<LessonPlaybackSyncedWhiteboard> {
  static const Duration _refreshInterval = Duration(milliseconds: 50);

  Timer? _refreshTimer;
  double _livePositionSec = 0;
  bool _followsTeacher = true;
  String? _selectedBoardId;

  BoardSet get _boardSet =>
      widget.boardSet ??
      BoardSet(
        boards: [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            layerBundle: widget.bundle ?? const LessonWhiteboardLayerBundle(),
          ),
        ],
      );

  @override
  void initState() {
    super.initState();
    _livePositionSec = _resolvedPositionSec();
    _selectedBoardId = _boardSet.resolveBoardAt(_livePositionSec)?.id;
    _syncRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant LessonPlaybackSyncedWhiteboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_tracksLivePlayback ||
        widget.positionSecExact != oldWidget.positionSecExact) {
      _livePositionSec = _resolvedPositionSec();
    }
    final selectedStillExists =
        _selectedBoardId != null &&
        _boardSet.boardById(_selectedBoardId!) != null;
    if (_followsTeacher || !selectedStillExists) {
      _selectedBoardId = _boardSet.resolveBoardAt(_livePositionSec)?.id;
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

  double get _maxPositionSec {
    final exactTimelineDuration = widget.timeline.totalDurationSecExact;
    return exactTimelineDuration > 0
        ? exactTimelineDuration
        : widget.totalDurationSec.toDouble();
  }

  void _syncRefreshTimer() {
    final shouldRefresh = _tracksLivePlayback && _maxPositionSec > 0;
    if (shouldRefresh) {
      _refreshTimer ??= Timer.periodic(_refreshInterval, (_) {
        if (!mounted) {
          return;
        }
        final nextPositionSec = _resolvedPositionSec();
        if (nextPositionSec == _livePositionSec) {
          return;
        }
        setState(() {
          _livePositionSec = nextPositionSec;
          if (_followsTeacher) {
            _selectedBoardId = _boardSet.resolveBoardAt(nextPositionSec)?.id;
          }
        });
      });
      return;
    }

    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  double _resolvedPositionSec() {
    final maxSec = _maxPositionSec;
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
    return widget.timeline.resolveGlobalSec(globalSec).localSec;
  }

  void _setFollowsTeacher(bool value) {
    final positionSec = _tracksLivePlayback
        ? _livePositionSec
        : _resolvedPositionSec();
    setState(() {
      if (value || _followsTeacher) {
        _selectedBoardId = _boardSet.resolveBoardAt(positionSec)?.id;
      }
      _followsTeacher = value;
    });
  }

  void _selectBoardManually(String? boardId) {
    if (boardId == null || _boardSet.boardById(boardId) == null) {
      return;
    }
    setState(() {
      _selectedBoardId = boardId;
      _followsTeacher = false;
    });
  }

  void _handleManualViewportChange(LessonWhiteboardViewportChange change) {
    if (_followsTeacher &&
        change.phase == LessonWhiteboardViewportChangePhase.start) {
      setState(() => _followsTeacher = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final positionSec = _tracksLivePlayback
        ? _livePositionSec
        : _resolvedPositionSec();
    final orderedBoards = _boardSet.orderedBoards;
    final teacherBoard = _boardSet.resolveBoardAt(positionSec);
    final selectedBoard = _followsTeacher
        ? teacherBoard
        : _boardSet.boardById(_selectedBoardId ?? '');
    final activeBoard = selectedBoard ?? teacherBoard ?? _boardSet.defaultBoard;
    final strokes = visibleWhiteboardBundleStrokes(
      bundle: activeBoard?.layerBundle ?? const LessonWhiteboardLayerBundle(),
      globalPositionSec: positionSec,
      segmentLocalPositionSec: _segmentLocalPositionSec(positionSec),
      activeSegmentId: widget.playback?.currentSegment?.id,
    );
    final teacherViewport = activeBoard == null
        ? LessonWhiteboardViewport.full
        : _boardSet.resolveViewportAt(
            boardId: activeBoard.id,
            globalTimestampSec: positionSec,
          );

    return Column(
      key: const ValueKey('synced-whiteboard'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                key: const ValueKey('learner-whiteboard-board-selector'),
                value: activeBoard?.id,
                isExpanded: true,
                items: [
                  for (final entry in orderedBoards.indexed)
                    DropdownMenuItem(
                      value: entry.$2.id,
                      child: Text(
                        entry.$2.title.isEmpty
                            ? 'ボード ${entry.$1 + 1}'
                            : '${entry.$1 + 1}. ${entry.$2.title}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: orderedBoards.length > 1
                    ? _selectBoardManually
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              key: const ValueKey('learner-whiteboard-follow-switch'),
              value: _followsTeacher,
              onChanged: activeBoard == null ? null : _setFollowsTeacher,
            ),
          ],
        ),
        Text(
          '先生のボードと表示範囲に合わせる（自分で操作すると一時解除）',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        LessonWhiteboardCanvas(
          key: ValueKey('learner-whiteboard-canvas-${activeBoard?.id}'),
          strokes: strokes,
          drawingEnabled: false,
          viewport: _followsTeacher ? teacherViewport : null,
          onViewportChanged: _handleManualViewportChange,
        ),
      ],
    );
  }
}
