import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_duration_parser.dart';
import '../models/lesson_media_segment.dart';
import '../models/lesson_media_timeline.dart';
import '../models/lesson_payload_size_validator.dart';
import '../models/lesson_player_view_state.dart';
import '../models/lesson_publication_validator.dart';
import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';
import '../services/lesson_media_playback.dart';
import '../services/lesson_media_playlist_playback.dart';
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
    this.playlistPlaybackFactory = createLessonMediaPlaylistPlayback,
  }) : assert(
         onDraftSaved != null || onBoardSetDraftSaved != null,
         'A whiteboard draft callback is required.',
       );

  final String courseId;
  final int lessonNumber;
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
  final LessonMediaPlaylistPlaybackFactory playlistPlaybackFactory;

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

  List<WhiteboardStroke> _strokes = [];
  BoardSet _boardSet = const BoardSet();
  String _selectedBoardId = LessonWhiteboardBoard.defaultBoardId;
  WhiteboardStroke? _inProgressStroke;
  List<WhiteboardPoint> _inProgressPoints = [];

  WhiteboardEditSessionKind _editSessionKind = WhiteboardEditSessionKind.none;
  bool _isLoadingMedia = false;
  bool _isPlaying = false;
  bool _isSavingDraft = false;
  String? _mediaLoadError;
  String? _message;
  int _currentPositionSec = 0;
  int _totalDurationSec = 0;
  double _currentPositionSecExact = 0;
  double? _sliderDragPositionSec;
  double? _strokeStartSec;

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
      return playback.liveGlobalPositionSec.clamp(
        0.0,
        _totalDurationSec.toDouble(),
      );
    }
    return _currentPositionSecExact;
  }

  bool get _drawingEnabled => _isPlaying;
  bool get _hasPublishedWhiteboard => _publishedBoardSet.isNotEmpty;

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
        if (_isDraggingSlider) {
          _currentPositionSecExact = position;
          return;
        }
        setState(() {
          _currentPositionSecExact = position;
          _currentPositionSec = position.floor();
        });
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

  Future<void> _startRecording() async {
    if (!_canControlPlayback) {
      return;
    }

    setState(() {
      _message = null;
    });

    try {
      await _playback?.play();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = '再生に失敗しました: $error';
        });
      }
    }
  }

  Future<void> _pauseRecording() async {
    await _playback?.pause();
    _finishInProgressStroke();
  }

  Future<void> _seekPlaybackPosition(int positionSec) async {
    if (_totalDurationSec <= 0) {
      return;
    }
    final nextPosition = positionSec.clamp(0, _totalDurationSec);
    await _playback?.seekGlobal(nextPosition.toDouble());
    setState(() {
      _currentPositionSec = nextPosition;
      _currentPositionSecExact = nextPosition.toDouble();
      _message = null;
    });
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

  void _notifyWhiteboardChanged() {
    if (_editSessionKind == WhiteboardEditSessionKind.fresh) {
      widget.onWhiteboardChanged?.call(_buildCurrentWhiteboard());
      widget.onBoardSetChanged?.call(_buildCurrentBoardSet());
    }
  }

  void _syncWorkingWhiteboardAfterDraftSave() {
    widget.onWhiteboardChanged?.call(_buildCurrentWhiteboard());
    widget.onBoardSetChanged?.call(_buildCurrentBoardSet());
  }

  Future<void> _saveDraft() async {
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

  void _switchBoard(String boardId) {
    if (boardId == _selectedBoardId || _boardSet.boardById(boardId) == null) {
      return;
    }
    _finishInProgressStroke();
    _commitSelectedBoard();
    final nextSequence = _boardSet.nextSwitchSequence;
    setState(() {
      _boardSet = _boardSet.copyWith(
        switchEvents: [
          ..._boardSet.switchEvents,
          LessonWhiteboardBoardSwitchEvent(
            boardId: boardId,
            globalTimestampSec: _recordingPositionSec,
            sequence: nextSequence,
          ),
        ],
      );
      _selectedBoardId = boardId;
      _strokes = List<WhiteboardStroke>.from(
        _selectedBoard.layerBundle.primaryLayer?.strokes ?? const [],
      );
      _message = null;
    });
    widget.onBoardSetChanged?.call(_boardSet);
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
      );
      _selectedBoardId = nextId;
      _strokes = List<WhiteboardStroke>.from(
        _selectedBoard.layerBundle.primaryLayer?.strokes ?? const [],
      );
    });
    // Deleting the active board necessarily selects another board.
    final sequence = _boardSet.nextSwitchSequence;
    setState(() {
      _boardSet = _boardSet.copyWith(
        switchEvents: [
          ..._boardSet.switchEvents,
          LessonWhiteboardBoardSwitchEvent(
            boardId: nextId,
            globalTimestampSec: _recordingPositionSec,
            sequence: sequence,
          ),
        ],
      );
    });
    widget.onBoardSetChanged?.call(_buildCurrentBoardSet());
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

  @override
  Widget build(BuildContext context) {
    final sliderMax = _totalDurationSec > 0
        ? _totalDurationSec.toDouble()
        : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            value: (_sliderDragPositionSec ?? _currentPositionSec.toDouble())
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
                      _sliderDragPositionSec = _currentPositionSec.toDouble();
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
        Wrap(
          key: const ValueKey('whiteboard-board-selector'),
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final entry in _boardSet.orderedBoards.indexed)
              ChoiceChip(
                key: ValueKey('whiteboard-board-${entry.$2.id}'),
                selected: entry.$2.id == _selectedBoardId,
                label: Text(
                  entry.$2.title.isEmpty
                      ? '${entry.$1 + 1}'
                      : '${entry.$1 + 1}. ${entry.$2.title}',
                ),
                onSelected: (_) => _switchBoard(entry.$2.id),
              ),
            if (_shouldShowEditingCanvas)
              OutlinedButton.icon(
                key: const ValueKey('whiteboard-add-board'),
                onPressed: _boardSet.canAddBoard ? _addBoard : null,
                icon: const Icon(Icons.add),
                label: const Text('ボードを追加'),
              ),
          ],
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
                onPressed: _boardSet.boards.length > 1
                    ? () => unawaited(_deleteSelectedBoard())
                    : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('ボードを削除'),
              ),
              Text('${_boardSet.boards.length}/$maxLessonWhiteboardBoards'),
            ],
          ),
        ],
        const SizedBox(height: 8),
        if (_hasPublishedWhiteboard && !_shouldShowEditingCanvas) ...[
          SizedBox(
            height: 220,
            child: LessonWhiteboardCanvas(
              strokes: [
                for (final layer in _selectedBoard.layerBundle.orderedLayers)
                  ...layer.strokes,
              ],
              drawingEnabled: false,
            ),
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
          SizedBox(
            height: 220,
            child: LessonWhiteboardCanvas(
              strokes: _visibleStrokes,
              inProgressStroke: _inProgressStroke,
              drawingEnabled: _drawingEnabled,
              onStrokeStart: _handleStrokeStart,
              onStrokeUpdate: _handleStrokeUpdate,
              onStrokeEnd: _handleStrokeEnd,
            ),
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
        if (_message != null) ...[const SizedBox(height: 8), Text(_message!)],
      ],
    );
  }
}

enum _WhiteboardEditChoice { published, draft, reset }

/// Persists a whiteboard draft for a single lesson.
///
/// [currentLesson] must reflect the lesson's up-to-date state as shown on
/// screen (title, duration, media parts, preview flag, published whiteboard).
/// It is written back together with valid local edits. The latest server
/// lesson is read and append-only publication locks are validated in the same
/// transaction, so a whiteboard draft cannot overwrite locked media fields.
/// Other lessons in the course are left untouched.
Future<void> saveLessonWhiteboardDraft({
  required String courseId,
  required int lessonIndex,
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
  final draftLayers =
      draftBoardSet.defaultBoard?.layerBundle.layers ??
      const <LessonWhiteboardLayer>[];
  final updatedLesson = currentLesson.copyWith(
    draftBoardSet: draftBoardSet,
    whiteboardDraftLayers: draftLayers,
    clearWhiteboardDraftLayers: draftLayers.isEmpty,
  );
  final firestore = FirebaseFirestore.instance;
  final courseReference = firestore.collection('courses').doc(courseId);
  await firestore.runTransaction<void>((transaction) async {
    final snapshot = await transaction.get(courseReference);
    if (!snapshot.exists) {
      throw StateError('講座が見つかりません。');
    }

    final lessonsData = snapshot.data()?['lessons'];
    if (lessonsData is! List ||
        lessonIndex < 0 ||
        lessonIndex >= lessonsData.length ||
        lessonsData[lessonIndex] is! Map) {
      throw StateError('レッスンが見つかりません。');
    }

    final previousLesson = CourseLesson.fromMap(
      lessonsData[lessonIndex] as Map,
    );
    final validationError = LessonPublicationValidator.validate(
      previous: previousLesson,
      next: updatedLesson,
    );
    if (validationError != null) {
      throw LessonPublicationValidationException(validationError);
    }

    final lessons = List<Object?>.from(lessonsData);
    lessons[lessonIndex] = updatedLesson.toMap();
    validateRawLessonsPayloadForPersistence(lessons);
    transaction.update(courseReference, {
      'lessons': lessons,
      'lessonCount': lessons.length,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });
}
