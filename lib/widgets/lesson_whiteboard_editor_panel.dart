import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/course.dart';
import '../models/lesson_duration_parser.dart';
import '../models/lesson_media_segment.dart';
import '../models/lesson_media_timeline.dart';
import '../models/lesson_payload_size_validator.dart';
import '../models/lesson_player_view_state.dart';
import '../models/lesson_publication_validator.dart';
import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';
import '../services/lesson_material_library_service.dart';
import '../services/lesson_material_source_resolver.dart';
import '../services/lesson_media_playback.dart';
import '../services/lesson_media_playlist_playback.dart';
import '../services/lesson_material_storage_service.dart';
import 'lesson_material_library_picker.dart';
import 'lesson_whiteboard_canvas.dart';

typedef WhiteboardDraftSaveCallback =
    Future<void> Function(LessonWhiteboard whiteboard);
typedef WhiteboardBoardSetDraftSaveCallback =
    Future<void> Function(BoardSet boardSet);

class LessonWhiteboardEditorPanel extends StatefulWidget {
  const LessonWhiteboardEditorPanel({
    super.key,
    required this.courseId,
    required this.lessonNumber,
    this.lessonId,
    required this.mediaSegments,
    required this.durationLabel,
    this.publishedWhiteboard,
    this.draftWhiteboard,
    this.publishedBoardSet,
    this.draftBoardSet,
    this.onDraftSaved,
    this.onBoardSetDraftSaved,
    this.onWhiteboardChanged,
    this.onBoardSetChanged,
    this.publishedTimelineDurationSec = 0,
    this.enabled = true,
    this.playlistPlaybackFactory = createLessonMediaPlaylistPlayback,
    this.materialStorageService = const LessonMaterialStorageService(),
    this.materialLibraryService = const LessonMaterialLibraryService(),
  }) : assert(
         onDraftSaved != null || onBoardSetDraftSaved != null,
         'A whiteboard draft callback is required.',
       );

  final String courseId;
  final int lessonNumber;
  final String? lessonId;
  final List<LessonMediaSegment> mediaSegments;
  final String durationLabel;
  final LessonWhiteboard? publishedWhiteboard;
  final LessonWhiteboard? draftWhiteboard;
  final BoardSet? publishedBoardSet;
  final BoardSet? draftBoardSet;
  final WhiteboardDraftSaveCallback? onDraftSaved;
  final WhiteboardBoardSetDraftSaveCallback? onBoardSetDraftSaved;
  final ValueChanged<LessonWhiteboard>? onWhiteboardChanged;
  final ValueChanged<BoardSet>? onBoardSetChanged;
  final double publishedTimelineDurationSec;
  final bool enabled;
  final LessonMediaPlaylistPlaybackFactory playlistPlaybackFactory;
  final LessonMaterialStorageService materialStorageService;
  final LessonMaterialLibraryService materialLibraryService;

  @override
  State<LessonWhiteboardEditorPanel> createState() =>
      _LessonWhiteboardEditorPanelState();
}

class _LessonWhiteboardEditorPanelState
    extends State<LessonWhiteboardEditorPanel> {
  LessonMediaPlaylistController? _playback;
  LessonMediaTimeline get _timeline =>
      LessonMediaTimeline(segments: widget.mediaSegments);
  StreamSubscription<double>? _positionSubscription;
  StreamSubscription<int>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  Timer? _viewportRefreshTimer;

  List<WhiteboardStroke> _strokes = [];
  BoardSet _boardSet = const BoardSet();
  String _selectedBoardId = LessonWhiteboardBoard.defaultBoardId;
  WhiteboardStroke? _inProgressStroke;
  List<WhiteboardPoint> _inProgressPoints = [];

  WhiteboardEditSessionKind _editSessionKind = WhiteboardEditSessionKind.none;
  bool _isLoadingMedia = false;
  bool _isPlaying = false;
  bool _isSavingDraft = false;
  bool _isUploadingMaterial = false;
  String? _mediaLoadError;
  String? _message;
  int _currentPositionSec = 0;
  int _totalDurationSec = 0;
  double _currentPositionSecExact = 0;
  double? _sliderDragPositionSec;
  double? _strokeStartSec;
  int? _activeViewportInteractionId;
  double? _lastViewportEventSec;
  LessonWhiteboardViewport? _pendingPausedViewport;
  final Map<String, LessonWhiteboardViewport> _editorViewports = {};
  bool _followsRecordedScreenShare = true;
  bool _screenShareOverrideEnabled = false;
  BoardSet? _screenShareOverrideBaseline;
  double? _screenShareOverrideStartSec;
  final List<LessonWhiteboardBoardSwitchEvent> _overrideSwitchEvents = [];
  final List<LessonWhiteboardViewportEvent> _overrideViewportEvents = [];
  int _nextOverrideSwitchSequence = 0;
  int _nextOverrideViewportSequence = 0;
  int _nextOverrideInteractionId = 0;

  bool get _isDraggingSlider => _sliderDragPositionSec != null;

  int get _displayedPositionSec =>
      (_sliderDragPositionSec ?? _currentPositionSec.toDouble()).round();

  /// Position used when timestamping whiteboard points as they are drawn.
  ///
  /// [_currentPositionSecExact] only updates once per second for audio
  /// (mirroring the stabilized display stream), which would make every
  /// point drawn within the same second share an identical timestamp and
  /// look "stepped" during playback. While actively recording, read the
  /// player's live sub-second position directly instead.
  double get _recordingPositionSec {
    final playback = _playback;
    if (_isPlaying && playback != null && _totalDurationSec > 0) {
      final exactTimelineDuration = _timeline.totalDurationSecExact;
      final maxPositionSec = exactTimelineDuration > 0
          ? exactTimelineDuration
          : _totalDurationSec.toDouble();
      return playback.liveGlobalPositionSec.clamp(0.0, maxPositionSec);
    }
    return _currentPositionSecExact;
  }

  bool get _drawingEnabled => _isPlaying && widget.enabled;
  bool get _hasPublishedWhiteboard => _publishedBoardSet.isNotEmpty;
  bool get _isInPublishedTimeline {
    final publishedEnd = widget.publishedTimelineDurationSec;
    return _hasPublishedWhiteboard &&
        publishedEnd > 0 &&
        _recordingPositionSec < publishedEnd;
  }

  bool get _hasRecordedScreenShareTimeline =>
      _boardSet.switchEvents.isNotEmpty || _boardSet.viewportEvents.isNotEmpty;

  bool get _isFollowingRecordedScreenShare =>
      _followsRecordedScreenShare &&
      !_screenShareOverrideEnabled &&
      _hasRecordedScreenShareTimeline;

  LessonWhiteboardViewport get _selectedEditorViewport {
    if (_isFollowingRecordedScreenShare) {
      return _boardSet.resolveViewportAt(
        boardId: _selectedBoardId,
        globalTimestampSec: _recordingPositionSec,
      );
    }
    return _editorViewports[_selectedBoardId] ??
        _boardSet.resolveViewportAt(
          boardId: _selectedBoardId,
          globalTimestampSec: _recordingPositionSec,
        );
  }

  bool get _hasUnpublishedDraft {
    return _draftBoardSet.isNotEmpty;
  }

  BoardSet get _publishedBoardSet {
    final boardSet = widget.publishedBoardSet;
    if (boardSet != null) {
      return boardSet;
    }
    final legacy = widget.publishedWhiteboard;
    return legacy == null || legacy.isEmpty
        ? const BoardSet()
        : BoardSet.fromLegacyLayers(
            LessonWhiteboardLayerBundle.fromLegacyWhiteboard(legacy).layers,
          );
  }

  BoardSet get _draftBoardSet {
    final boardSet = widget.draftBoardSet;
    if (boardSet != null) {
      return boardSet;
    }
    final legacy = widget.draftWhiteboard;
    return legacy == null || legacy.isEmpty
        ? const BoardSet()
        : BoardSet.fromLegacyLayers(
            LessonWhiteboardLayerBundle.fromLegacyWhiteboard(legacy).layers,
          );
  }

  LessonWhiteboardBoard get _selectedBoard =>
      _boardSet.boardById(_selectedBoardId) ??
      _boardSet.defaultBoard ??
      _boardSet.ensureEditable().defaultBoard!;

  bool get _selectedMaterialBoardIsPublished =>
      _publishedBoardSet.boardById(_selectedBoardId)?.background != null;

  bool get _shouldShowEditingCanvas =>
      _editSessionKind != WhiteboardEditSessionKind.none;

  LessonWhiteboardLayerBundle get _selectedWorkingBundle {
    final bundle = _selectedBoard.layerBundle;
    return bundle.copyWithPrimaryStrokes(
      strokes: _strokes,
      updatedAtMs: bundle.primaryLayer?.updatedAtMs ?? 0,
    );
  }

  List<WhiteboardStroke> get _visibleStrokes {
    final resolvedPosition = _timeline.isEmpty
        ? null
        : _timeline.resolveGlobalSec(_currentPositionSecExact);
    return visibleWhiteboardBundleStrokes(
      bundle: _selectedWorkingBundle,
      globalPositionSec: _currentPositionSecExact,
      segmentLocalPositionSec:
          resolvedPosition?.localSec ?? _currentPositionSecExact,
      activeSegmentId: _playback?.currentSegment?.id,
      orderedSegmentIds: [
        for (final segment in _timeline.orderedSegments) segment.id,
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _loadInitialStrokes();
    if (lessonHasPlayableMedia(mediaSegments: widget.mediaSegments)) {
      unawaited(_initializeMediaPlayer());
    }
  }

  @override
  void didUpdateWidget(covariant LessonWhiteboardEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_segmentsEqual(oldWidget.mediaSegments, widget.mediaSegments)) {
      unawaited(_reloadMediaPlayer());
    }
    if (oldWidget.enabled && !widget.enabled) {
      unawaited(_pauseRecording());
    }
    if (oldWidget.draftWhiteboard != widget.draftWhiteboard ||
        oldWidget.publishedWhiteboard != widget.publishedWhiteboard ||
        oldWidget.draftBoardSet != widget.draftBoardSet ||
        oldWidget.publishedBoardSet != widget.publishedBoardSet) {
      if (_inProgressStroke == null && !_isPlaying) {
        _loadInitialStrokes(
          preserveActiveSession:
              _editSessionKind == WhiteboardEditSessionKind.published ||
              _editSessionKind == WhiteboardEditSessionKind.pendingReset,
        );
      }
    }
  }

  void _loadInitialStrokes({bool preserveActiveSession = false}) {
    if (!_hasPublishedWhiteboard) {
      _loadBoardSet(_hasUnpublishedDraft ? _draftBoardSet : const BoardSet());
      _editSessionKind = WhiteboardEditSessionKind.fresh;
      return;
    }

    if (_hasUnpublishedDraft) {
      _loadBoardSet(_draftBoardSet);
      if (!preserveActiveSession ||
          _editSessionKind == WhiteboardEditSessionKind.none) {
        _editSessionKind = WhiteboardEditSessionKind.draft;
      }
      return;
    }

    if (!preserveActiveSession) {
      _loadBoardSet(_publishedBoardSet);
      _editSessionKind = WhiteboardEditSessionKind.none;
    }
  }

  void _loadBoardSet(BoardSet boardSet) {
    _boardSet = boardSet.ensureEditable();
    final selected = _boardSet.boardById(_selectedBoardId);
    _selectedBoardId = selected?.id ?? _boardSet.defaultBoard!.id;
    _strokes = List<WhiteboardStroke>.from(
      _selectedBoard.layerBundle.primaryLayer?.strokes ?? const [],
    );
    _pendingPausedViewport = null;
    _activeViewportInteractionId = null;
    _lastViewportEventSec = null;
    _followsRecordedScreenShare = true;
    _editorViewports
      ..clear()
      ..[_selectedBoardId] = _boardSet.resolveViewportAt(
        boardId: _selectedBoardId,
        globalTimestampSec: _recordingPositionSec,
      );
    _clearScreenShareOverride();
  }

  bool _segmentsEqual(
    List<LessonMediaSegment> left,
    List<LessonMediaSegment> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index].id != right[index].id ||
          left[index].url != right[index].url ||
          left[index].durationSec != right[index].durationSec) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _viewportRefreshTimer?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    unawaited(_playback?.close());
    super.dispose();
  }

  Future<void> _reloadMediaPlayer() async {
    await _playback?.close();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _playback = null;
    if (!lessonHasPlayableMedia(mediaSegments: widget.mediaSegments)) {
      setState(() {
        _isLoadingMedia = false;
        _mediaLoadError = null;
        _totalDurationSec = 0;
      });
      return;
    }
    await _initializeMediaPlayer();
  }

  Future<void> _initializeMediaPlayer() async {
    setState(() {
      _isLoadingMedia = true;
      _mediaLoadError = null;
    });

    try {
      final playback = widget.playlistPlaybackFactory();
      await playback.openSegments(widget.mediaSegments);
      if (!mounted) {
        await playback.close();
        return;
      }

      _playback = playback;
      _positionSubscription = playback.globalPositionStream.listen((position) {
        if (!mounted) {
          return;
        }
        if (_screenShareOverrideEnabled &&
            position >= widget.publishedTimelineDurationSec) {
          _finishScreenShareOverride(
            endGlobalSec: widget.publishedTimelineDurationSec,
          );
        }
        if (_isDraggingSlider) {
          _currentPositionSecExact = position;
          return;
        }
        setState(() {
          _currentPositionSecExact = position;
          _currentPositionSec = position.floor();
        });
        _syncRecordedScreenShare(position);
      });
      _durationSubscription = playback.totalDurationStream.listen((duration) {
        _updateResolvedDuration(playerDuration: Duration(seconds: duration));
      });
      _playingSubscription = playback.playingStream.listen((isPlaying) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isPlaying = isPlaying;
        });
        _syncViewportRefreshTimer();
      });

      _applyResolvedPlaybackState(playback);
    } on LessonMediaLoadException catch (error) {
      if (mounted) {
        setState(() {
          _mediaLoadError = error.message;
          _isLoadingMedia = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _mediaLoadError = '音声の読み込みに失敗しました: $error';
          _isLoadingMedia = false;
        });
      }
    }
  }

  void _updateResolvedDuration({Duration? playerDuration}) {
    if (!mounted || _playback == null) {
      return;
    }

    final nextTotalDurationSec = resolveTimelineDurationSec(
      timeline: _timeline,
      playerDuration:
          playerDuration ?? Duration(seconds: _playback!.totalDurationSec),
      durationLabel: widget.durationLabel,
    );
    if (nextTotalDurationSec <= _totalDurationSec) {
      return;
    }

    setState(() {
      _totalDurationSec = nextTotalDurationSec;
      _mediaLoadError = null;
    });
  }

  void _applyResolvedPlaybackState(LessonMediaPlaylistController playback) {
    final totalDurationSec = resolveTimelineDurationSec(
      timeline: _timeline,
      playerDuration: Duration(seconds: playback.totalDurationSec),
      durationLabel: widget.durationLabel,
    );

    setState(() {
      _totalDurationSec = totalDurationSec;
      _isLoadingMedia = false;
      if (!playback.isReady) {
        _mediaLoadError = '音声の読み込みに失敗しました。';
      } else if (totalDurationSec <= 0) {
        _mediaLoadError = '再生時間を取得できませんでした。';
      } else {
        _mediaLoadError = null;
      }
    });
  }

  bool get _canControlPlayback =>
      lessonHasPlayableMedia(mediaSegments: widget.mediaSegments) &&
      _mediaLoadError == null &&
      _totalDurationSec > 0 &&
      (_playback?.isReady ?? false);

  void _syncViewportRefreshTimer() {
    if (_isPlaying) {
      _viewportRefreshTimer ??= Timer.periodic(
        const Duration(milliseconds: 50),
        (_) {
          if (mounted && _isPlaying) {
            _finishOverrideAtPublishedBoundaryIfNeeded();
            _syncRecordedScreenShare(_recordingPositionSec);
            setState(() {});
          }
        },
      );
      return;
    }
    _viewportRefreshTimer?.cancel();
    _viewportRefreshTimer = null;
  }

  Future<void> _startRecording() async {
    if (!_canControlPlayback) {
      return;
    }

    setState(() {
      _message = null;
    });

    try {
      final resumePositionSec = _currentPositionSecExact;
      await _playback?.play();
      _flushPendingViewport(timestampSec: resumePositionSec);
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = '再生に失敗しました: $error';
        });
      }
    }
  }

  Future<void> _pauseRecording() async {
    final pausedPositionSec = _recordingPositionSec;
    await _playback?.pause();
    if (mounted) {
      setState(() {
        _currentPositionSecExact = pausedPositionSec;
        _currentPositionSec = pausedPositionSec.floor();
      });
    }
    _finishInProgressStroke();
  }

  void _setFollowsRecordedScreenShare(bool value) {
    if (_screenShareOverrideEnabled) {
      return;
    }
    if (!value && _isFollowingRecordedScreenShare) {
      _editorViewports[_selectedBoardId] = _boardSet.resolveViewportAt(
        boardId: _selectedBoardId,
        globalTimestampSec: _recordingPositionSec,
      );
    }
    setState(() => _followsRecordedScreenShare = value);
    if (value) {
      _syncRecordedScreenShare(_recordingPositionSec);
    }
  }

  void _syncRecordedScreenShare(double positionSec) {
    if (!_shouldShowEditingCanvas || !_isFollowingRecordedScreenShare) {
      return;
    }
    final followedBoard = _boardSet.resolveBoardAt(positionSec);
    if (followedBoard == null || followedBoard.id == _selectedBoardId) {
      return;
    }
    _finishInProgressStroke();
    _pendingPausedViewport = null;
    _activeViewportInteractionId = null;
    _lastViewportEventSec = null;
    _commitSelectedBoard();
    setState(() {
      _selectedBoardId = followedBoard.id;
      _strokes = List<WhiteboardStroke>.from(
        followedBoard.layerBundle.primaryLayer?.strokes ?? const [],
      );
    });
  }

  void _handleViewportChanged(LessonWhiteboardViewportChange change) {
    _finishOverrideAtPublishedBoundaryIfNeeded();
    if (_isFollowingRecordedScreenShare &&
        change.phase == LessonWhiteboardViewportChangePhase.start) {
      setState(() => _followsRecordedScreenShare = false);
    }
    _editorViewports[_selectedBoardId] = change.viewport;
    if (!_shouldRecordSelectedViewport()) {
      _pendingPausedViewport = null;
      return;
    }
    if (!_isPlaying) {
      _pendingPausedViewport = change.viewport;
      return;
    }
    switch (change.phase) {
      case LessonWhiteboardViewportChangePhase.start:
        _activeViewportInteractionId = _allocateViewportInteractionId();
        _lastViewportEventSec = null;
        _appendViewportEvent(change.viewport, force: true);
        return;
      case LessonWhiteboardViewportChangePhase.update:
        _activeViewportInteractionId ??= _allocateViewportInteractionId();
        _appendViewportEvent(change.viewport, force: false);
        return;
      case LessonWhiteboardViewportChangePhase.end:
        _activeViewportInteractionId ??= _allocateViewportInteractionId();
        _appendViewportEvent(change.viewport, force: true);
        _activeViewportInteractionId = null;
        _lastViewportEventSec = null;
        return;
    }
  }

  void _flushPendingViewport({double? timestampSec}) {
    final viewport = _pendingPausedViewport;
    if (viewport == null) {
      return;
    }
    if (_shouldRecordSelectedViewport()) {
      _activeViewportInteractionId = _allocateViewportInteractionId();
      _appendViewportEvent(viewport, force: true, timestampSec: timestampSec);
    }
    _activeViewportInteractionId = null;
    _lastViewportEventSec = null;
    _pendingPausedViewport = null;
  }

  bool _appendViewportEvent(
    LessonWhiteboardViewport viewport, {
    required bool force,
    double? timestampSec,
  }) {
    if (_boardSet.viewportEvents.length + _overrideViewportEvents.length >=
        maxLessonViewportEvents) {
      if (mounted) {
        if (_screenShareOverrideEnabled) {
          _cancelScreenShareOverrideDueToLimit();
        } else {
          setState(() => _message = lessonViewportEventLimitMessage);
        }
      }
      return false;
    }
    final resolvedTimestampSec = timestampSec ?? _recordingPositionSec;
    final previousSec = _lastViewportEventSec;
    if (!force &&
        previousSec != null &&
        resolvedTimestampSec - previousSec < 0.095) {
      return false;
    }
    final interactionId =
        _activeViewportInteractionId ?? _allocateViewportInteractionId();
    final event = LessonWhiteboardViewportEvent(
      boardId: _selectedBoardId,
      globalTimestampSec: resolvedTimestampSec,
      sequence: _screenShareOverrideEnabled
          ? _nextOverrideViewportSequence++
          : _boardSet.nextViewportSequence,
      interactionId: interactionId,
      viewport: viewport,
    );
    if (_screenShareOverrideEnabled) {
      _overrideViewportEvents.add(event);
    } else {
      setState(() {
        _boardSet = _boardSet.copyWith(
          viewportEvents: [..._boardSet.viewportEvents, event],
        );
      });
      widget.onBoardSetChanged?.call(_boardSet);
    }
    _lastViewportEventSec = resolvedTimestampSec;
    return true;
  }

  bool _shouldRecordSelectedViewport() {
    if (_screenShareOverrideEnabled && _isInPublishedTimeline) {
      return true;
    }
    if (_isInPublishedTimeline) {
      return false;
    }
    return _boardSet.resolveBoardAt(_recordingPositionSec)?.id ==
        _selectedBoardId;
  }

  int _allocateViewportInteractionId() {
    if (_screenShareOverrideEnabled) {
      return _nextOverrideInteractionId++;
    }
    return _boardSet.nextViewportInteractionId;
  }

  Future<void> _seekPlaybackPosition(int positionSec) async {
    if (_totalDurationSec <= 0) {
      return;
    }
    if (_screenShareOverrideEnabled) {
      _finishScreenShareOverride(endGlobalSec: _recordingPositionSec);
    }
    final nextPosition = positionSec.clamp(0, _totalDurationSec);
    await _playback?.seekGlobal(nextPosition.toDouble());
    setState(() {
      _currentPositionSec = nextPosition;
      _currentPositionSecExact = nextPosition.toDouble();
      _message = null;
    });
    _syncRecordedScreenShare(nextPosition.toDouble());
  }

  void _handleStrokeStart() {
    _strokeStartSec = _recordingPositionSec;
    _inProgressPoints = [];
  }

  void _handleStrokeUpdate(WhiteboardPoint point) {
    _recordPoint(point, force: false);
  }

  void _recordPoint(WhiteboardPoint point, {required bool force}) {
    if (_strokeStartSec == null) {
      return;
    }

    final timestampSec = _recordingPositionSec;
    final timedPoint = WhiteboardPoint(
      x: point.x,
      y: point.y,
      timestampSec: timestampSec,
    );
    if (!shouldSampleWhiteboardPoint(
      existingPoints: _inProgressPoints,
      nextPoint: timedPoint,
      nextTimestampSec: timestampSec,
      force: force,
    )) {
      return;
    }

    setState(() {
      _inProgressPoints = [..._inProgressPoints, timedPoint];
      _inProgressStroke = WhiteboardStroke(
        id: 'in-progress',
        timestampSec: _strokeStartSec!,
        points: _inProgressPoints,
      );
    });
  }

  List<WhiteboardPoint> _finalizeStrokePoints(WhiteboardPoint endPoint) {
    final timestampSec = _recordingPositionSec;
    final timedEndPoint = WhiteboardPoint(
      x: endPoint.x,
      y: endPoint.y,
      timestampSec: timestampSec,
    );
    final points = List<WhiteboardPoint>.from(_inProgressPoints);
    if (points.isEmpty) {
      return [timedEndPoint];
    }

    final lastPoint = points.last;
    if (lastPoint.x == timedEndPoint.x && lastPoint.y == timedEndPoint.y) {
      points[points.length - 1] = timedEndPoint;
      return points;
    }

    if (shouldSampleWhiteboardPoint(
      existingPoints: points,
      nextPoint: timedEndPoint,
      nextTimestampSec: timestampSec,
      force: true,
    )) {
      points.add(timedEndPoint);
    }
    return points;
  }

  void _handleStrokeEnd(WhiteboardPoint point) {
    if (_strokeStartSec == null) {
      return;
    }

    final points = _finalizeStrokePoints(point);
    if (points.length >= 2) {
      final stroke = WhiteboardStroke(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        timestampSec: _strokeStartSec!,
        endTimestampSec: _recordingPositionSec,
        points: points,
      );
      setState(() {
        _strokes = [..._strokes, stroke];
      });
      _notifyWhiteboardChanged();
    }

    _clearInProgressStroke();
  }

  void _finishInProgressStroke() {
    if (_inProgressPoints.length >= 2 && _strokeStartSec != null) {
      final stroke = WhiteboardStroke(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        timestampSec: _strokeStartSec!,
        endTimestampSec: _recordingPositionSec,
        points: List<WhiteboardPoint>.from(_inProgressPoints),
      );
      setState(() {
        _strokes = [..._strokes, stroke];
      });
      _notifyWhiteboardChanged();
    }
    _clearInProgressStroke();
  }

  void _clearInProgressStroke() {
    setState(() {
      _inProgressStroke = null;
      _inProgressPoints = [];
      _strokeStartSec = null;
    });
  }

  LessonWhiteboard _buildCurrentWhiteboard() {
    return LessonWhiteboard(
      strokes: _strokes,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _commitSelectedBoard() {
    final board = _boardSet.boardById(_selectedBoardId);
    if (board == null) {
      return;
    }
    _boardSet = _boardSet.replaceBoard(
      board.copyWith(
        layerBundle: board.layerBundle.copyWithPrimaryStrokes(
          strokes: List<WhiteboardStroke>.from(_strokes),
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  BoardSet _buildCurrentBoardSet() {
    _commitSelectedBoard();
    return _boardSet;
  }

  Future<LessonWhiteboardMaterialSource> _resolveMaterialSource(
    String storagePath,
  ) {
    return resolveCachedLessonMaterialSource(
      courseId: widget.courseId,
      lessonId: widget.lessonId ?? '',
      storagePath: storagePath,
    );
  }

  void _notifyWhiteboardChanged() {
    // Keep the parent working copy current even before Firestore draft save.
    // This lets a newly-added recording session start from every visible
    // stroke without publishing those edits prematurely.
    widget.onWhiteboardChanged?.call(_buildCurrentWhiteboard());
    widget.onBoardSetChanged?.call(_buildCurrentBoardSet());
  }

  void _syncWorkingWhiteboardAfterDraftSave() {
    widget.onWhiteboardChanged?.call(_buildCurrentWhiteboard());
    widget.onBoardSetChanged?.call(_buildCurrentBoardSet());
  }

  Future<void> _saveDraft() async {
    if (_screenShareOverrideEnabled) {
      _finishScreenShareOverride(endGlobalSec: _recordingPositionSec);
    }
    setState(() {
      _isSavingDraft = true;
      _message = null;
    });

    try {
      final boardSet = _buildCurrentBoardSet();
      validateBoardSetForPersistence(boardSet);
      final boardSetCallback = widget.onBoardSetDraftSaved;
      if (boardSetCallback != null) {
        await boardSetCallback(boardSet);
      } else {
        await widget.onDraftSaved!(_buildCurrentWhiteboard());
      }
      if (mounted) {
        setState(() {
          _editSessionKind = WhiteboardEditSessionKind.draft;
          _message = '書き物を一時保存しました。';
        });
        _syncWorkingWhiteboardAfterDraftSave();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = '一時保存に失敗しました: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingDraft = false;
        });
      }
    }
  }

  void _setScreenShareOverride(bool enabled) {
    if (enabled) {
      if (!_isInPublishedTimeline || _screenShareOverrideEnabled) {
        return;
      }
      _editorViewports[_selectedBoardId] = _selectedEditorViewport;
      _commitSelectedBoard();
      _screenShareOverrideBaseline = _boardSet;
      _screenShareOverrideStartSec = _recordingPositionSec;
      _overrideSwitchEvents.clear();
      _overrideViewportEvents.clear();
      _nextOverrideSwitchSequence = _boardSet.nextSwitchSequence;
      _nextOverrideViewportSequence = _boardSet.nextViewportSequence;
      _nextOverrideInteractionId = _boardSet.nextViewportInteractionId;
      setState(() {
        _screenShareOverrideEnabled = true;
        _message = 'この時点から、受講者に見せる画面を上書きしています。';
      });
      _recordSharedBoardSelection();
      return;
    }
    _finishScreenShareOverride(endGlobalSec: _recordingPositionSec);
  }

  void _finishScreenShareOverride({required double endGlobalSec}) {
    if (!_screenShareOverrideEnabled) {
      return;
    }
    final baseline = _screenShareOverrideBaseline;
    final startGlobalSec = _screenShareOverrideStartSec;
    if (baseline == null || startGlobalSec == null) {
      _clearScreenShareOverride();
      return;
    }
    final boundedEnd = endGlobalSec
        .clamp(startGlobalSec, widget.publishedTimelineDurationSec)
        .toDouble();
    if (_pendingPausedViewport != null) {
      _flushPendingViewport(timestampSec: boundedEnd);
    }
    if (!_screenShareOverrideEnabled) {
      return;
    }
    _commitSelectedBoard();
    final merged = _boardSet.replaceScreenShareTimelineInterval(
      baseline: baseline,
      startGlobalSec: startGlobalSec,
      endGlobalSec: boundedEnd,
      replacementSwitchEvents: List.of(_overrideSwitchEvents),
      replacementViewportEvents: List.of(_overrideViewportEvents),
    );
    if (merged.switchEvents.length > maxLessonBoardSwitchEvents ||
        merged.viewportEvents.length > maxLessonViewportEvents) {
      setState(() {
        _clearScreenShareOverride();
        _message = '操作履歴が保存上限に達したため、今回の画面共有上書きは反映されませんでした。';
      });
      _syncRecordedScreenShare(_recordingPositionSec);
      return;
    }
    setState(() {
      _boardSet = merged;
      _clearScreenShareOverride();
      _message = '画面共有の上書きを終了しました。この先は元の共有内容を引き継ぎます。';
    });
    widget.onBoardSetChanged?.call(_buildCurrentBoardSet());
    _syncRecordedScreenShare(_recordingPositionSec);
  }

  void _finishOverrideAtPublishedBoundaryIfNeeded() {
    if (_screenShareOverrideEnabled &&
        _recordingPositionSec >= widget.publishedTimelineDurationSec) {
      _finishScreenShareOverride(
        endGlobalSec: widget.publishedTimelineDurationSec,
      );
    }
  }

  void _clearScreenShareOverride() {
    _screenShareOverrideEnabled = false;
    _screenShareOverrideBaseline = null;
    _screenShareOverrideStartSec = null;
    _overrideSwitchEvents.clear();
    _overrideViewportEvents.clear();
    _activeViewportInteractionId = null;
    _lastViewportEventSec = null;
  }

  void _cancelScreenShareOverrideDueToLimit() {
    setState(() {
      _clearScreenShareOverride();
      _message = '操作履歴が保存上限に達したため、今回の画面共有上書きは反映されませんでした。';
    });
    _syncRecordedScreenShare(_recordingPositionSec);
  }

  void _switchBoard(String boardId) {
    if (boardId == _selectedBoardId || _boardSet.boardById(boardId) == null) {
      return;
    }
    final stopsFollowing = _isFollowingRecordedScreenShare;
    _finishOverrideAtPublishedBoundaryIfNeeded();
    _finishInProgressStroke();
    if (_pendingPausedViewport != null) {
      _flushPendingViewport(timestampSec: _recordingPositionSec);
    }
    _commitSelectedBoard();
    setState(() {
      if (stopsFollowing) {
        _followsRecordedScreenShare = false;
      }
      _selectedBoardId = boardId;
      _strokes = List<WhiteboardStroke>.from(
        _selectedBoard.layerBundle.primaryLayer?.strokes ?? const [],
      );
      if (stopsFollowing) {
        _editorViewports[boardId] = _boardSet.resolveViewportAt(
          boardId: boardId,
          globalTimestampSec: _recordingPositionSec,
        );
      } else {
        _editorViewports.putIfAbsent(
          boardId,
          () => _boardSet.resolveViewportAt(
            boardId: boardId,
            globalTimestampSec: _recordingPositionSec,
          ),
        );
      }
      _message = null;
    });
    if (_screenShareOverrideEnabled && _isInPublishedTimeline) {
      _recordSharedBoardSelection();
    }
  }

  void _shareBoard(String boardId) {
    _finishOverrideAtPublishedBoundaryIfNeeded();
    if (_boardSet.boardById(boardId) == null || _isInPublishedTimeline) {
      return;
    }
    if (boardId != _selectedBoardId) {
      _switchBoard(boardId);
    }
    if (_recordSharedBoardSelection()) {
      setState(() {
        _message = 'この時点から「${_selectedBoard.title}」を受講者に共有します。';
      });
    }
  }

  bool _recordSharedBoardSelection() {
    if (_boardSet.switchEvents.length + _overrideSwitchEvents.length >=
        maxLessonBoardSwitchEvents) {
      if (_screenShareOverrideEnabled) {
        _cancelScreenShareOverrideDueToLimit();
      } else {
        setState(() => _message = lessonBoardSwitchEventLimitMessage);
      }
      return false;
    }
    if (_boardSet.viewportEvents.length + _overrideViewportEvents.length >=
        maxLessonViewportEvents) {
      if (_screenShareOverrideEnabled) {
        _cancelScreenShareOverrideDueToLimit();
      } else {
        setState(() => _message = lessonViewportEventLimitMessage);
      }
      return false;
    }
    final timestampSec = _recordingPositionSec;
    final switchEvent = LessonWhiteboardBoardSwitchEvent(
      boardId: _selectedBoardId,
      globalTimestampSec: timestampSec,
      sequence: _screenShareOverrideEnabled
          ? _nextOverrideSwitchSequence++
          : _boardSet.nextSwitchSequence,
    );
    if (_screenShareOverrideEnabled) {
      _overrideSwitchEvents.add(switchEvent);
    } else {
      _boardSet = _boardSet.copyWith(
        switchEvents: [..._boardSet.switchEvents, switchEvent],
      );
    }

    _activeViewportInteractionId = _allocateViewportInteractionId();
    _lastViewportEventSec = null;
    final viewportRecorded = _appendViewportEvent(
      _selectedEditorViewport,
      force: true,
      timestampSec: timestampSec,
    );
    _activeViewportInteractionId = null;
    _lastViewportEventSec = null;
    if (!viewportRecorded) {
      return false;
    }
    if (!_screenShareOverrideEnabled) {
      widget.onBoardSetChanged?.call(_boardSet);
    }
    return true;
  }

  Future<void> _addFromLibrary() async {
    final lessonId = widget.lessonId?.trim() ?? '';
    final remaining = maxLessonWhiteboardBoards - _boardSet.boards.length;
    if (lessonId.isEmpty || remaining <= 0 || _isUploadingMaterial) {
      setState(() {
        _message = lessonId.isEmpty
            ? 'PDF・画像を追加するには、先にレッスンを保存してください。'
            : lessonBoardLimitMessage;
      });
      return;
    }
    setState(() {
      _isUploadingMaterial = true;
      _message = '保存済み資料を読み込んでいます…';
    });
    PickedLessonPdf? pickedPdf;
    try {
      final items = await widget.materialLibraryService.listItems();
      if (!mounted) {
        return;
      }
      setState(() {
        _isUploadingMaterial = false;
        _message = null;
      });
      final selected = await showLessonMaterialLibraryPicker(
        context: context,
        items: items,
      );
      if (selected == null || !mounted) {
        return;
      }
      setState(() {
        _isUploadingMaterial = true;
        _message = selected.isPdf ? 'PDFを読み込んでいます…' : '画像を読み込んでいます…';
      });
      if (selected.isPdf) {
        pickedPdf = await widget.materialStorageService.openPdfFromStorage(
          storagePath: selected.sourceStoragePath,
          fileName: selected.fileName,
        );
        if (!mounted) {
          return;
        }
        final selectedPages = await _selectPdfPages(
          pickedPdf,
          maximumCount: remaining,
        );
        if (selectedPages == null || selectedPages.isEmpty || !mounted) {
          return;
        }
        setState(() => _message = '選択したPDFページを安全な共有用ファイルにしています…');
        final result = await widget.materialStorageService
            .uploadSelectedPdfPages(
              courseId: widget.courseId,
              lessonId: lessonId,
              pickedPdf: pickedPdf,
              selectedPageNumbers: selectedPages,
            );
        if (!mounted) {
          return;
        }
        _appendMaterialBoards(result);
      } else {
        final image = await widget.materialStorageService.openImageFromStorage(
          storagePath: selected.sourceStoragePath,
          fileName: selected.fileName,
        );
        if (!mounted) {
          return;
        }
        setState(() => _message = '画像をアップロードしています…');
        final result = await widget.materialStorageService.uploadImages(
          courseId: widget.courseId,
          lessonId: lessonId,
          images: [image],
        );
        if (mounted) {
          _appendMaterialBoards(result);
        }
      }
    } on LessonMaterialStorageException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '保存済み資料の追加に失敗しました。時間をおいて再度お試しください。');
      }
    } finally {
      await pickedPdf?.dispose();
      if (mounted) {
        setState(() => _isUploadingMaterial = false);
      }
    }
  }

  Future<void> _addPdfMaterial() async {
    final lessonId = widget.lessonId?.trim() ?? '';
    final remaining = maxLessonWhiteboardBoards - _boardSet.boards.length;
    if (lessonId.isEmpty || remaining <= 0 || _isUploadingMaterial) {
      setState(() {
        _message = lessonId.isEmpty
            ? 'PDF・画像を追加するには、先にレッスンを保存してください。'
            : lessonBoardLimitMessage;
      });
      return;
    }
    setState(() {
      _isUploadingMaterial = true;
      _message = 'PDFを読み込んでいます…';
    });
    PickedLessonPdf? pickedPdf;
    try {
      pickedPdf = await widget.materialStorageService.pickPdf();
      if (pickedPdf == null || !mounted) {
        return;
      }
      final selectedPages = await _selectPdfPages(
        pickedPdf,
        maximumCount: remaining,
      );
      if (selectedPages == null || selectedPages.isEmpty || !mounted) {
        return;
      }
      setState(() => _message = '選択したPDFページを安全な共有用ファイルにしています…');
      final result = await widget.materialStorageService.uploadSelectedPdfPages(
        courseId: widget.courseId,
        lessonId: lessonId,
        pickedPdf: pickedPdf,
        selectedPageNumbers: selectedPages,
      );
      if (!mounted) {
        return;
      }
      _appendMaterialBoards(result);
    } on LessonMaterialStorageException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'PDFの追加に失敗しました。時間をおいて再度お試しください。');
      }
    } finally {
      await pickedPdf?.dispose();
      if (mounted) {
        setState(() => _isUploadingMaterial = false);
      }
    }
  }

  Future<List<int>?> _selectPdfPages(
    PickedLessonPdf pickedPdf, {
    required int maximumCount,
  }) {
    final selected = <int>{};
    return showDialog<List<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('共有するPDFページを選択'),
          content: SizedBox(
            width: 620,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '選択したページだけを共有します。'
                  ' 残り$maximumCount枚まで追加できます。',
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 150,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.75,
                        ),
                    itemCount: pickedPdf.document.pages.length,
                    itemBuilder: (context, index) {
                      final pageNumber = index + 1;
                      final isSelected = selected.contains(pageNumber);
                      final enabled =
                          isSelected || selected.length < maximumCount;
                      return InkWell(
                        key: ValueKey('material-pdf-page-$pageNumber'),
                        onTap: enabled
                            ? () {
                                setDialogState(() {
                                  if (!selected.add(pageNumber)) {
                                    selected.remove(pageNumber);
                                  }
                                });
                              }
                            : null,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              width: isSelected ? 3 : 1,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: PdfPageView(
                                  document: pickedPdf.document,
                                  pageNumber: pageNumber,
                                  maximumDpi: 96,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.topRight,
                                child: Checkbox(
                                  value: isSelected,
                                  onChanged: enabled
                                      ? (_) {
                                          setDialogState(() {
                                            if (!selected.add(pageNumber)) {
                                              selected.remove(pageNumber);
                                            }
                                          });
                                        }
                                      : null,
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: ColoredBox(
                                  color: Colors.black54,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      '$pageNumber',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              key: const ValueKey('material-pdf-pages-confirm'),
              onPressed: selected.isEmpty
                  ? null
                  : () {
                      final pages = selected.toList()..sort();
                      Navigator.of(dialogContext).pop(pages);
                    },
              child: Text('${selected.length}ページを追加'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addImageMaterials({required bool fromGallery}) async {
    final lessonId = widget.lessonId?.trim() ?? '';
    final remaining = maxLessonWhiteboardBoards - _boardSet.boards.length;
    if (lessonId.isEmpty || remaining <= 0 || _isUploadingMaterial) {
      setState(() {
        _message = lessonId.isEmpty
            ? 'PDF・画像を追加するには、先にレッスンを保存してください。'
            : lessonBoardLimitMessage;
      });
      return;
    }
    setState(() {
      _isUploadingMaterial = true;
      _message = '画像を読み込んでいます…';
    });
    try {
      final images = fromGallery
          ? await widget.materialStorageService.pickGalleryImages(
              maximumCount: remaining,
            )
          : await widget.materialStorageService.pickImageFiles(
              maximumCount: remaining,
            );
      if (images.isEmpty || !mounted) {
        return;
      }
      setState(() => _message = '画像をアップロードしています…');
      final result = await widget.materialStorageService.uploadImages(
        courseId: widget.courseId,
        lessonId: lessonId,
        images: images,
      );
      if (mounted) {
        _appendMaterialBoards(result);
      }
    } on LessonMaterialStorageException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '画像の追加に失敗しました。時間をおいて再度お試しください。');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingMaterial = false);
      }
    }
  }

  void _appendMaterialBoards(LessonMaterialUploadResult result) {
    if (result.backgrounds.isEmpty) {
      return;
    }
    _finishInProgressStroke();
    _commitSelectedBoard();
    final firstOrder = _boardSet.boards.length;
    final newBoards = <LessonWhiteboardBoard>[];
    for (final entry in result.backgrounds.indexed) {
      var id = LessonWhiteboardBoard.generateId();
      while (_boardSet.boardById(id) != null ||
          newBoards.any((board) => board.id == id)) {
        id = LessonWhiteboardBoard.generateId();
      }
      newBoards.add(
        LessonWhiteboardBoard(
          id: id,
          order: firstOrder + entry.$1,
          title: result.titles[entry.$1],
          background: entry.$2,
        ),
      );
    }
    final selectedId = newBoards.first.id;
    setState(() {
      _boardSet = _boardSet.copyWith(
        boards: [..._boardSet.orderedBoards, ...newBoards],
      );
      _selectedBoardId = selectedId;
      _strokes = [];
      _editorViewports[selectedId] = LessonWhiteboardViewport.full;
      _message =
          '${newBoards.length}枚の資料ボードを追加しました。'
          '「下書きを保存」で確定してください。';
    });
    widget.onBoardSetChanged?.call(_buildCurrentBoardSet());
  }

  void _addBoard() {
    if (!_boardSet.canAddBoard) {
      return;
    }
    _finishInProgressStroke();
    _commitSelectedBoard();
    var id = LessonWhiteboardBoard.generateId();
    while (_boardSet.boardById(id) != null) {
      id = LessonWhiteboardBoard.generateId();
    }
    final board = LessonWhiteboardBoard(
      id: id,
      order: _boardSet.boards.length,
      title: 'ボード${_boardSet.boards.length + 1}',
    );
    setState(() {
      _boardSet = _boardSet.copyWith(
        boards: [..._boardSet.orderedBoards, board],
      );
    });
    _switchBoard(id);
  }

  Future<void> _renameSelectedBoard() async {
    final board = _selectedBoard;
    final controller = TextEditingController(text: board.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ボード名を変更'),
        content: TextField(
          key: const ValueKey('whiteboard-board-title-field'),
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'ボード名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('変更'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || !mounted) {
      return;
    }
    setState(() {
      _boardSet = _boardSet.replaceBoard(board.copyWith(title: title));
    });
    widget.onBoardSetChanged?.call(_buildCurrentBoardSet());
  }

  Future<void> _deleteSelectedBoard() async {
    if (_boardSet.boards.length <= 1) {
      return;
    }
    if (_selectedMaterialBoardIsPublished) {
      setState(() {
        _message = lessonPublishedMaterialBoardsLockedError;
      });
      return;
    }
    final removedBackground = _selectedBoard.background;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ボードを削除'),
        content: const Text('このボードと書き物を削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) {
      return;
    }
    _finishInProgressStroke();
    _pendingPausedViewport = null;
    final removedId = _selectedBoardId;
    final remaining = _boardSet.orderedBoards
        .where((board) => board.id != removedId)
        .toList();
    final nextId = remaining.first.id;
    setState(() {
      _boardSet = _boardSet.copyWith(
        boards: [
          for (final entry in remaining.indexed)
            entry.$2.copyWith(order: entry.$1),
        ],
        switchEvents: [
          for (final event in _boardSet.switchEvents)
            if (event.boardId != removedId) event,
        ],
        viewportEvents: [
          for (final event in _boardSet.viewportEvents)
            if (event.boardId != removedId) event,
        ],
      );
      _selectedBoardId = nextId;
      _editorViewports.remove(removedId);
      _editorViewports.putIfAbsent(
        nextId,
        () => _boardSet.resolveViewportAt(
          boardId: nextId,
          globalTimestampSec: _recordingPositionSec,
        ),
      );
      _strokes = List<WhiteboardStroke>.from(
        _selectedBoard.layerBundle.primaryLayer?.strokes ?? const [],
      );
    });
    if (_screenShareOverrideEnabled && _isInPublishedTimeline) {
      _recordSharedBoardSelection();
    }
    widget.onBoardSetChanged?.call(_buildCurrentBoardSet());
    if (removedBackground != null) {
      unawaited(_deleteMaterialBestEffort(removedBackground));
    }
  }

  Future<void> _deleteMaterialBestEffort(
    LessonWhiteboardBoardBackground background,
  ) async {
    try {
      await widget.materialStorageService.deleteMaterialAsset(background);
    } catch (_) {
      // Orphan cleanup must not revert the already-confirmed board deletion.
    }
  }

  Future<void> _resetWhiteboard() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('書き物をリセット'),
          content: const Text(
            'ホワイトボードの書き物をすべて消します。\n'
            '反映は「書き物を一時保存」を押した時点で確定します。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('リセット'),
            ),
          ],
        );
      },
    );
    if (shouldReset != true || !mounted) {
      return;
    }

    await _beginPendingReset();
    if (mounted) {
      setState(() {
        _message = 'リセットしました。一時保存で確定してください。';
      });
    }
  }

  Future<void> _showEditOptions() async {
    final choices = <_WhiteboardEditChoice>[];
    if (_hasPublishedWhiteboard) {
      choices.add(_WhiteboardEditChoice.published);
    }
    if (_hasUnpublishedDraft) {
      choices.add(_WhiteboardEditChoice.draft);
    }
    choices.add(_WhiteboardEditChoice.reset);

    if (!_hasPublishedWhiteboard && !_hasUnpublishedDraft) {
      await _beginPendingReset();
      return;
    }

    final selected = await showDialog<_WhiteboardEditChoice>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('書き物の編集'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final choice in choices) ...[
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(choice),
                  child: Text(_editChoiceLabel(choice)),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
    if (selected == null || !mounted) {
      return;
    }

    switch (selected) {
      case _WhiteboardEditChoice.published:
        await _beginEditingPublished();
      case _WhiteboardEditChoice.draft:
        await _beginEditingDraft();
      case _WhiteboardEditChoice.reset:
        await _beginPendingReset();
    }
  }

  String _editChoiceLabel(_WhiteboardEditChoice choice) {
    return switch (choice) {
      _WhiteboardEditChoice.published => '公開しているものを編集する',
      _WhiteboardEditChoice.draft => '仮保存中のものを編集する',
      _WhiteboardEditChoice.reset => 'リセットして描き直す',
    };
  }

  Future<void> _beginEditingPublished() async {
    final published = _publishedBoardSet;
    if (published.isEmpty) {
      return;
    }

    setState(() {
      _loadBoardSet(published);
      _editSessionKind = WhiteboardEditSessionKind.published;
      _message = '公開中の書き物を編集しています。一時保存で仮保存されます。';
    });
    _syncRecordedScreenShare(_recordingPositionSec);
    _clearInProgressStroke();
    await _playback?.pause();
  }

  Future<void> _beginEditingDraft() async {
    final draft = _draftBoardSet;
    if (draft.isEmpty) {
      return;
    }

    setState(() {
      _loadBoardSet(draft);
      _editSessionKind = WhiteboardEditSessionKind.draft;
      _message = '仮保存中の書き物を編集しています。';
    });
    _syncRecordedScreenShare(_recordingPositionSec);
    _clearInProgressStroke();
    await _playback?.pause();
  }

  Future<void> _beginPendingReset() async {
    setState(() {
      _loadBoardSet(const BoardSet());
      _editSessionKind = WhiteboardEditSessionKind.pendingReset;
      _message = '最初から描き直します。一時保存で確定してください。';
    });
    _clearInProgressStroke();
    await _playback?.pause();
    await _seekPlaybackPosition(0);
  }

  String _boardLabel(int index, LessonWhiteboardBoard board) {
    return board.title.isEmpty
        ? 'ボード${index + 1}'
        : '${index + 1}. ${board.title}';
  }

  Widget? _buildScreenShareButton(BuildContext context) {
    if (!_shouldShowEditingCanvas || _isInPublishedTimeline) {
      return null;
    }
    final isShared =
        _boardSet.resolveBoardAt(_recordingPositionSec)?.id == _selectedBoardId;
    final colorScheme = Theme.of(context).colorScheme;
    return FilledButton.icon(
      key: const ValueKey('whiteboard-share-current-board'),
      onPressed: () => _shareBoard(_selectedBoardId),
      style: FilledButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        backgroundColor: isShared
            ? Colors.red.shade700
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
        foregroundColor: isShared ? Colors.white : colorScheme.onSurface,
      ),
      icon: const Icon(Icons.screen_share_outlined, size: 17),
      label: const Text('画面共有'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sliderMax = _totalDurationSec > 0
        ? _totalDurationSec.toDouble()
        : 1.0;

    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.enabled) ...[
              const Text('録音パートの作業中は、こちらの既存編集機能を一時停止しています。'),
              const SizedBox(height: 8),
            ],
            Text('メディアプレビュー', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_isLoadingMedia) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('音声を読み込み中…'),
            ] else if (_mediaLoadError != null) ...[
              Text(
                _mediaLoadError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ] else if (_canControlPlayback) ...[
              Text(
                '${formatLessonTime(_displayedPositionSec)} / ${formatLessonTime(_totalDurationSec)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Slider(
                value:
                    (_sliderDragPositionSec ?? _currentPositionSec.toDouble())
                        .clamp(0, _totalDurationSec)
                        .toDouble(),
                min: 0,
                max: sliderMax,
                divisions: _totalDurationSec > 0 ? _totalDurationSec : null,
                label: formatLessonTime(_displayedPositionSec),
                onChangeStart: _isPlaying
                    ? null
                    : (_) {
                        setState(() {
                          _sliderDragPositionSec = _currentPositionSec
                              .toDouble();
                        });
                      },
                onChanged: _isPlaying
                    ? null
                    : (value) {
                        setState(() {
                          _sliderDragPositionSec = value;
                        });
                      },
                onChangeEnd: _isPlaying
                    ? null
                    : (value) {
                        final targetSec = value.round();
                        setState(() {
                          _sliderDragPositionSec = null;
                        });
                        unawaited(_seekPlaybackPosition(targetSec));
                      },
              ),
            ],
            const SizedBox(height: 16),
            Text('ホワイトボード', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              _isPlaying ? '再生中はペンで書けます。' : 'スタートを押すとメディアが流れ、同時に書けるようになります。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              key: const ValueKey('whiteboard-board-selector'),
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      'whiteboard-board-dropdown-$_selectedBoardId',
                    ),
                    initialValue: _selectedBoardId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '表示するボード',
                      isDense: true,
                    ),
                    items: [
                      for (final entry in _boardSet.orderedBoards.indexed)
                        DropdownMenuItem(
                          value: entry.$2.id,
                          child: Text(
                            _boardLabel(entry.$1, entry.$2),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (boardId) {
                      if (boardId != null) {
                        _switchBoard(boardId);
                      }
                    },
                  ),
                ),
                if (_shouldShowEditingCanvas) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('whiteboard-add-board'),
                    onPressed: _boardSet.canAddBoard ? _addBoard : null,
                    icon: const Icon(Icons.add),
                    label: const Text('追加'),
                  ),
                ],
              ],
            ),
            if (_shouldShowEditingCanvas && _hasRecordedScreenShareTimeline)
              SizedBox(
                height: 30,
                child: Tooltip(
                  message: _screenShareOverrideEnabled
                      ? '「画面共有を上書き」の間は一時停止しています。'
                      : '記録時のボード切り替えと拡大・移動を再現します'
                            '（自分で操作すると一時解除）。',
                  child: Row(
                    children: [
                      Switch(
                        key: const ValueKey(
                          'editor-recorded-screen-share-follow-switch',
                        ),
                        value: _followsRecordedScreenShare,
                        onChanged: _screenShareOverrideEnabled
                            ? null
                            : _setFollowsRecordedScreenShare,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _screenShareOverrideEnabled
                              ? '記録した画面共有に合わせる（上書き中は停止）'
                              : '記録した画面共有に合わせる',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_shouldShowEditingCanvas) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () => unawaited(_renameSelectedBoard()),
                    icon: const Icon(Icons.drive_file_rename_outline),
                    label: const Text('名前を変更'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('whiteboard-delete-board'),
                    onPressed:
                        _boardSet.boards.length > 1 &&
                            !_selectedMaterialBoardIsPublished
                        ? () => unawaited(_deleteSelectedBoard())
                        : null,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('ボードを削除'),
                  ),
                  PopupMenuButton<String>(
                    key: const ValueKey('whiteboard-add-material-menu'),
                    enabled: !_isUploadingMaterial && _boardSet.canAddBoard,
                    tooltip: 'PDF・画像を追加',
                    icon: const Icon(Icons.note_add_outlined),
                    onSelected: (value) {
                      if (value == 'pdf') {
                        unawaited(_addPdfMaterial());
                      } else if (value == 'library') {
                        unawaited(_addFromLibrary());
                      } else {
                        unawaited(
                          _addImageMaterials(fromGallery: value == 'gallery'),
                        );
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'pdf', child: Text('PDFを追加')),
                      PopupMenuItem(
                        value: 'image-file',
                        child: Text('画像ファイルを追加'),
                      ),
                      PopupMenuItem(value: 'gallery', child: Text('写真から追加')),
                      PopupMenuItem(value: 'library', child: Text('保存済みから選ぶ')),
                    ],
                  ),
                  Text('${_boardSet.boards.length}/$maxLessonWhiteboardBoards'),
                ],
              ),
              if (_isUploadingMaterial) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(
                  key: ValueKey('whiteboard-material-upload-progress'),
                ),
              ],
            ],
            if (_shouldShowEditingCanvas &&
                _hasPublishedWhiteboard &&
                _isInPublishedTimeline) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: CheckboxListTile(
                    key: const ValueKey('screen-share-override-checkbox'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: const Text('画面共有を上書き'),
                    subtitle: Text(
                      _screenShareOverrideEnabled
                          ? '先生が開くボードとズームを受講者向けに記録しています。'
                          : 'オフの間は、公開済みの画面共有を変更しません。',
                    ),
                    value: _screenShareOverrideEnabled,
                    onChanged: (value) =>
                        _setScreenShareOverride(value ?? false),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_hasPublishedWhiteboard && !_shouldShowEditingCanvas) ...[
              LessonWhiteboardCanvas(
                key: ValueKey('published-canvas-$_selectedBoardId'),
                strokes: [
                  for (final layer in _selectedBoard.layerBundle.orderedLayers)
                    ...layer.strokes,
                ],
                drawingEnabled: false,
                maxWidth: lessonWhiteboardCompactMaxWidth,
                showViewportControls: false,
                background: _selectedBoard.background,
                aspectRatio: _selectedBoard.aspectRatio,
                materialUrlResolver: _resolveMaterialSource,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isSavingDraft
                    ? null
                    : () => unawaited(_showEditOptions()),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('書き物を描き直す'),
              ),
            ] else ...[
              LessonWhiteboardCanvas(
                key: ValueKey('editor-canvas-$_selectedBoardId'),
                strokes: _visibleStrokes,
                inProgressStroke: _inProgressStroke,
                drawingEnabled: _drawingEnabled,
                onStrokeStart: _handleStrokeStart,
                onStrokeUpdate: _handleStrokeUpdate,
                onStrokeEnd: _handleStrokeEnd,
                onStrokeCancel: _clearInProgressStroke,
                maxWidth: lessonWhiteboardCompactMaxWidth,
                viewport: _selectedEditorViewport,
                onViewportChanged: _handleViewportChanged,
                showViewportControls: false,
                bottomLeftOverlay: _buildScreenShareButton(context),
                background: _selectedBoard.background,
                aspectRatio: _selectedBoard.aspectRatio,
                materialUrlResolver: _resolveMaterialSource,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: !_canControlPlayback || _isPlaying
                        ? null
                        : () => unawaited(_startRecording()),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('スタート'),
                  ),
                  OutlinedButton.icon(
                    onPressed: !_isPlaying
                        ? null
                        : () => unawaited(_pauseRecording()),
                    icon: const Icon(Icons.pause),
                    label: const Text('一時停止'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isSavingDraft
                        ? null
                        : () => unawaited(_saveDraft()),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('書き物を一時保存'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isSavingDraft
                        ? null
                        : () => unawaited(_resetWhiteboard()),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('リセット'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isSavingDraft
                        ? null
                        : () => unawaited(_showEditOptions()),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('編集の選び直し'),
                  ),
                ],
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!),
            ],
          ],
        ),
      ),
    );
  }
}

enum _WhiteboardEditChoice { published, draft, reset }

/// Persists a whiteboard draft for a single lesson.
///
/// Drafts are stored outside the learner-readable course document. The
/// [currentLesson] parameter remains for source compatibility with existing
/// callers, but lesson/media fields are deliberately never persisted here.
Future<int> saveLessonWhiteboardDraft({
  required String courseId,
  required int lessonIndex,
  int expectedLessonContentVersion = 0,
  int expectedDraftRevision = 0,
  required CourseLesson currentLesson,
  LessonWhiteboard? whiteboard,
  BoardSet? boardSet,
}) async {
  if (whiteboard == null && boardSet == null) {
    throw ArgumentError('whiteboard or boardSet is required.');
  }
  final draftBoardSet =
      boardSet ??
      (whiteboard == null || whiteboard.isEmpty
          ? const BoardSet()
          : BoardSet.fromLegacyLayers(
              LessonWhiteboardLayerBundle.fromLegacyWhiteboard(
                whiteboard,
              ).layers,
            ));
  validateBoardSetForPersistence(draftBoardSet);
  final courseReference = FirebaseFirestore.instance
      .collection('courses')
      .doc(courseId);
  final draftReference = courseReference
      .collection('lessonDrafts')
      .doc('${lessonIndex + 1}');
  return FirebaseFirestore.instance.runTransaction<int>((transaction) async {
    final courseSnapshot = await transaction.get(courseReference);
    if (!courseSnapshot.exists) {
      throw StateError('講座が見つかりません。');
    }
    final storedVersion = courseSnapshot.data()?['lessonContentVersion'];
    if (!lessonContentVersionMatches(
      storedVersion,
      expectedLessonContentVersion,
    )) {
      throw StateError(lessonContentVersionConflictMessage);
    }
    final currentVersion = expectedLessonContentVersion;
    final existingDraft = await transaction.get(draftReference);
    final nextDraftRevision = nextExpectedLessonDraftRevision(
      storedValue: existingDraft.data()?['draftRevision'],
      expectedRevision: expectedDraftRevision,
    );
    transaction.set(draftReference, {
      'lessonNumber': '${lessonIndex + 1}',
      'boardSet': draftBoardSet.toMap(),
      'baseLessonContentVersion': currentVersion,
      'draftRevision': nextDraftRevision,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return nextDraftRevision;
  });
}
