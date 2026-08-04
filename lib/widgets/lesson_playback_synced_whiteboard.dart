import 'dart:async';

import 'package:flutter/material.dart';

import '../models/lesson_media_timeline.dart';
import '../models/lesson_player_view_state.dart';
import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';
import '../models/lesson_whiteboard_timing_correction.dart';
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
    this.enableSubPlayback = false,
    this.materialUrlResolver = resolveLessonWhiteboardMaterialUrl,
  }) : assert(bundle != null || boardSet != null);

  final LessonWhiteboardLayerBundle? bundle;
  final BoardSet? boardSet;
  final LessonMediaTimeline timeline;
  final LessonMediaPlaylistController? playback;
  final bool isPlaying;
  final double positionSecExact;
  final int totalDurationSec;
  final bool enableSubPlayback;
  final LessonWhiteboardMaterialUrlResolver materialUrlResolver;

  @override
  State<LessonPlaybackSyncedWhiteboard> createState() =>
      _LessonPlaybackSyncedWhiteboardState();
}

class _LessonPlaybackSyncedWhiteboardState
    extends State<LessonPlaybackSyncedWhiteboard> {
  static const Duration _refreshInterval = Duration(milliseconds: 50);

  Timer? _refreshTimer;
  double _livePositionSec = 0;
  double _subPositionSec = 0;
  double? _subSliderDragPositionSec;
  bool _subPositionDetached = false;
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
    _livePositionSec = _resolvedMainPositionSec();
    _subPositionSec = _livePositionSec;
    _selectedBoardId = _boardSet
        .resolveBoardAt(_lookupAt(_livePositionSec).globalSec)
        ?.id;
    _syncRefreshTimer();
    if (widget.enableSubPlayback) {
      unawaited(_warmMaterialUrls());
    }
  }

  @override
  void didUpdateWidget(covariant LessonPlaybackSyncedWhiteboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_tracksLivePlayback ||
        widget.positionSecExact != oldWidget.positionSecExact) {
      _livePositionSec = _resolvedMainPositionSec();
    }
    if (!widget.enableSubPlayback) {
      _subPositionDetached = false;
      _subSliderDragPositionSec = null;
    } else if (_subPositionDetached) {
      _subPositionSec = _subPositionSec.clamp(0.0, _maxPositionSec);
    } else {
      _subPositionSec = _livePositionSec;
    }
    if (widget.enableSubPlayback &&
        (!oldWidget.enableSubPlayback ||
            widget.boardSet != oldWidget.boardSet ||
            widget.bundle != oldWidget.bundle ||
            widget.materialUrlResolver != oldWidget.materialUrlResolver)) {
      unawaited(_warmMaterialUrls());
    }
    final selectedStillExists =
        _selectedBoardId != null &&
        _boardSet.boardById(_selectedBoardId!) != null;
    if (_followsTeacher || !selectedStillExists) {
      _selectedBoardId = _boardSet
          .resolveBoardAt(_lookupAt(_displayPositionSec).globalSec)
          ?.id;
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
    final shouldRefresh =
        !_subPositionDetached && _tracksLivePlayback && _maxPositionSec > 0;
    if (shouldRefresh) {
      _refreshTimer ??= Timer.periodic(_refreshInterval, (_) {
        if (!mounted) {
          return;
        }
        final nextPositionSec = _resolvedMainPositionSec();
        if (nextPositionSec == _livePositionSec) {
          return;
        }
        setState(() {
          _livePositionSec = nextPositionSec;
          _subPositionSec = nextPositionSec;
          if (_followsTeacher) {
            _selectedBoardId = _boardSet
                .resolveBoardAt(_lookupAt(nextPositionSec).globalSec)
                ?.id;
          }
        });
      });
      return;
    }

    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  double _resolvedMainPositionSec() {
    final maxSec = _maxPositionSec;
    if (maxSec <= 0) {
      return 0;
    }

    if (_tracksLivePlayback) {
      return widget.playback!.liveGlobalPositionSec.clamp(0.0, maxSec);
    }
    return widget.positionSecExact.clamp(0.0, maxSec);
  }

  LessonWhiteboardPlaybackLookup _lookupAt(double playbackPositionSec) {
    return resolveLessonWhiteboardPlaybackLookup(
      playbackGlobalSec: playbackPositionSec,
      timeline: widget.timeline,
    );
  }

  Future<void> _warmMaterialUrls() async {
    final storagePaths = <String>{
      for (final board in _boardSet.boards)
        if (board.background != null) board.background!.storagePath,
    };
    await Future.wait([
      for (final storagePath in storagePaths) _warmMaterialUrl(storagePath),
    ]);
  }

  Future<void> _warmMaterialUrl(String storagePath) async {
    try {
      await widget.materialUrlResolver(storagePath);
    } on Object {
      // The visible background keeps its normal retry/error UI. URL warming
      // must never prevent lesson playback from starting.
    }
  }

  List<LessonWhiteboardBoardBackground> _nearbyBackgroundsToPreload({
    required double positionSec,
    required LessonWhiteboardBoard? activeBoard,
  }) {
    final activeStoragePath = activeBoard?.background?.storagePath;
    for (final event in _boardSet.orderedSwitchEvents) {
      if (event.globalTimestampSec <= positionSec) {
        continue;
      }
      final background = _boardSet.boardById(event.boardId)?.background;
      if (background != null && background.storagePath != activeStoragePath) {
        return [background];
      }
    }

    final orderedBoards = _boardSet.orderedBoards;
    final activeIndex = activeBoard == null
        ? -1
        : orderedBoards.indexWhere((board) => board.id == activeBoard.id);
    for (var index = activeIndex + 1; index < orderedBoards.length; index++) {
      final background = orderedBoards[index].background;
      if (background != null && background.storagePath != activeStoragePath) {
        return [background];
      }
    }
    return const [];
  }

  double get _displayPositionSec {
    if (widget.enableSubPlayback && _subPositionDetached) {
      return (_subSliderDragPositionSec ?? _subPositionSec).clamp(
        0.0,
        _maxPositionSec,
      );
    }
    return _tracksLivePlayback ? _livePositionSec : _resolvedMainPositionSec();
  }

  void _setFollowsTeacher(bool value) {
    final positionSec = _displayPositionSec;
    setState(() {
      if (value || _followsTeacher) {
        _selectedBoardId = _boardSet
            .resolveBoardAt(_lookupAt(positionSec).globalSec)
            ?.id;
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

  void _startSubPositionDrag(double value) {
    final nextPositionSec = value.clamp(0.0, _maxPositionSec);
    setState(() {
      _subPositionDetached = true;
      _subPositionSec = nextPositionSec;
      _subSliderDragPositionSec = nextPositionSec;
      if (_followsTeacher) {
        _selectedBoardId = _boardSet
            .resolveBoardAt(_lookupAt(nextPositionSec).globalSec)
            ?.id;
      }
    });
    _syncRefreshTimer();
  }

  void _updateSubPosition(double value) {
    final nextPositionSec = value.clamp(0.0, _maxPositionSec);
    setState(() {
      _subPositionSec = nextPositionSec;
      _subSliderDragPositionSec = nextPositionSec;
      if (_followsTeacher) {
        _selectedBoardId = _boardSet
            .resolveBoardAt(_lookupAt(nextPositionSec).globalSec)
            ?.id;
      }
    });
  }

  void _finishSubPositionDrag(double value) {
    final nextPositionSec = value.clamp(0.0, _maxPositionSec);
    setState(() {
      _subPositionSec = nextPositionSec;
      _subSliderDragPositionSec = null;
      if (_followsTeacher) {
        _selectedBoardId = _boardSet
            .resolveBoardAt(_lookupAt(nextPositionSec).globalSec)
            ?.id;
      }
    });
  }

  void _resyncSubPositionToMain() {
    final mainPositionSec = _resolvedMainPositionSec();
    setState(() {
      _livePositionSec = mainPositionSec;
      _subPositionSec = mainPositionSec;
      _subSliderDragPositionSec = null;
      _subPositionDetached = false;
      if (_followsTeacher) {
        _selectedBoardId = _boardSet
            .resolveBoardAt(_lookupAt(mainPositionSec).globalSec)
            ?.id;
      }
    });
    _syncRefreshTimer();
  }

  void _handleManualViewportChange(LessonWhiteboardViewportChange change) {
    if (_followsTeacher &&
        change.phase == LessonWhiteboardViewportChangePhase.start) {
      setState(() => _followsTeacher = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final positionSec = _displayPositionSec;
    final lookup = _lookupAt(positionSec);
    final orderedBoards = _boardSet.orderedBoards;
    final teacherBoard = _boardSet.resolveBoardAt(lookup.globalSec);
    final selectedBoard = _followsTeacher
        ? teacherBoard
        : _boardSet.boardById(_selectedBoardId ?? '');
    final activeBoard = selectedBoard ?? teacherBoard ?? _boardSet.defaultBoard;
    final strokes = visibleWhiteboardBundleStrokes(
      bundle: activeBoard?.layerBundle ?? const LessonWhiteboardLayerBundle(),
      globalPositionSec: lookup.globalSec,
      segmentLocalPositionSec: lookup.segmentLocalSec,
      activeSegmentId: lookup.segmentId,
    );
    final teacherViewport = activeBoard == null
        ? LessonWhiteboardViewport.full
        : _boardSet.resolveViewportAt(
            boardId: activeBoard.id,
            globalTimestampSec: lookup.globalSec,
          );
    final nearbyBackgrounds = widget.enableSubPlayback
        ? _nearbyBackgroundsToPreload(
            positionSec: lookup.globalSec,
            activeBoard: activeBoard,
          )
        : const <LessonWhiteboardBoardBackground>[];

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
        if (widget.enableSubPlayback && _maxPositionSec > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '書き物の再生位置',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (_subPositionDetached)
                OutlinedButton.icon(
                  key: const ValueKey('whiteboard-sub-playback-resync'),
                  onPressed: _resyncSubPositionToMain,
                  icon: const Icon(Icons.sync),
                  label: const Text('メインに合わせる'),
                ),
            ],
          ),
          Text(
            '${formatLessonTime(positionSec.floor())} / '
            '${formatLessonTime(_maxPositionSec.floor())}',
            key: const ValueKey('whiteboard-sub-playback-position'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Slider(
            key: const ValueKey('whiteboard-sub-playback-slider'),
            value: positionSec,
            min: 0,
            max: _maxPositionSec,
            label: formatLessonTime(positionSec.floor()),
            onChangeStart: _startSubPositionDrag,
            onChanged: _updateSubPosition,
            onChangeEnd: _finishSubPositionDrag,
          ),
          Text(
            _subPositionDetached
                ? '書き物は選んだ位置で停止しています。音声・動画はそのまま再生されます。'
                : '書き物はメイン再生の位置に合っています。',
            key: const ValueKey('whiteboard-sub-playback-status'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 6),
        LessonWhiteboardCanvas(
          key: ValueKey('learner-whiteboard-canvas-${activeBoard?.id}'),
          strokes: strokes,
          drawingEnabled: false,
          viewport: _followsTeacher ? teacherViewport : null,
          onViewportChanged: _handleManualViewportChange,
          background: activeBoard?.background,
          aspectRatio: activeBoard?.aspectRatio ?? lessonWhiteboardAspectRatio,
          materialUrlResolver: widget.materialUrlResolver,
        ),
        LessonWhiteboardBackgroundPreloader(
          backgrounds: nearbyBackgrounds,
          materialUrlResolver: widget.materialUrlResolver,
        ),
      ],
    );
  }
}
