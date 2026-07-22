import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/lesson_payload_size_validator.dart';
import '../models/lesson_player_view_state.dart';
import '../models/lesson_recording_timeline.dart';
import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';
import '../services/lesson_audio_recording_service.dart';
import '../services/lesson_media_storage_service.dart';
import 'lesson_whiteboard_canvas.dart';

typedef LessonRecordedAudioUseCallback =
    Future<void> Function(
      PlatformFile file,
      int durationSec,
      int durationMs,
      BoardSet boardSet,
    );

class LessonAudioWhiteboardRecorderPanel extends StatefulWidget {
  const LessonAudioWhiteboardRecorderPanel({
    super.key,
    required this.segmentStartSec,
    required this.initialBoardSet,
    required this.onUseRecording,
    required this.onDiscard,
    required this.onBusyChanged,
    this.validateForPublication,
    this.recordingControllerFactory = createLessonAudioRecordingController,
    this.previewControllerFactory = createLessonAudioPreviewController,
  });

  final double segmentStartSec;
  final BoardSet initialBoardSet;
  final LessonRecordedAudioUseCallback onUseRecording;
  final VoidCallback onDiscard;
  final ValueChanged<bool> onBusyChanged;
  final String? Function(BoardSet boardSet)? validateForPublication;
  final LessonAudioRecordingController Function() recordingControllerFactory;
  final LessonAudioPreviewController Function() previewControllerFactory;

  @override
  State<LessonAudioWhiteboardRecorderPanel> createState() =>
      _LessonAudioWhiteboardRecorderPanelState();
}

class _LessonAudioWhiteboardRecorderPanelState
    extends State<LessonAudioWhiteboardRecorderPanel>
    with WidgetsBindingObserver {
  late final LessonAudioRecordingController _recorder;
  late final LessonAudioPreviewController _preview;
  late final LessonRecordingClock _clock;
  late double _sessionSegmentStartSec;
  StreamSubscription<bool>? _previewPlayingSubscription;
  Timer? _displayTimer;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  _RecordingStatus _status = _RecordingStatus.idle;
  late BoardSet _boardSet;
  late String _selectedBoardId;
  List<WhiteboardStroke> _strokes = [];
  WhiteboardStroke? _inProgressStroke;
  List<WhiteboardPoint> _inProgressPoints = [];
  double? _strokeStartSec;
  final Set<String> _sessionStrokeIds = {};
  final Set<int> _sessionSwitchSequences = {};
  PlatformFile? _recordedFile;
  int _recordedDurationSec = 0;
  int _recordedDurationMs = 0;
  bool _previewPlaying = false;
  bool _previewLoaded = false;
  bool _isStopping = false;
  bool _autoStopRequested = false;
  Future<void>? _activeStopFuture;
  Future<void>? _activeTransitionFuture;
  bool _isUploading = false;
  bool _drawingLimitReached = false;
  bool _payloadWarningShown = false;
  String? _message;

  bool get _isRecording => _status == _RecordingStatus.recording;
  bool get _isPaused => _status == _RecordingStatus.paused;
  bool get _hasActiveRecording =>
      _status == _RecordingStatus.starting ||
      _isRecording ||
      _status == _RecordingStatus.pausing ||
      _isPaused ||
      _status == _RecordingStatus.resuming ||
      _status == _RecordingStatus.stopping ||
      _isStopping;
  bool get _hasUnsavedRecording =>
      _hasActiveRecording || _recordedFile != null || _isUploading;
  bool get _drawingEnabled => _isRecording && !_drawingLimitReached;
  bool get _canAddBoard =>
      (_isRecording || _isPaused) &&
      !_drawingLimitReached &&
      _boardSet.canAddBoard &&
      _boardSet.switchEvents.length < maxLessonBoardSwitchEvents;
  double get _recordingPositionSec =>
      _sessionSegmentStartSec + _clock.elapsedSeconds;

  LessonWhiteboardBoard get _selectedBoard =>
      _boardSet.boardById(_selectedBoardId) ??
      _boardSet.defaultBoard ??
      _boardSet.ensureEditable().defaultBoard!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recorder = widget.recordingControllerFactory();
    _preview = widget.previewControllerFactory();
    _clock = LessonRecordingClock();
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _sessionSegmentStartSec = widget.segmentStartSec;
    _previewPlayingSubscription = _preview.playingStream.listen((playing) {
      if (mounted) {
        setState(() => _previewPlaying = playing);
      }
    });
    _resetWorkingBoardSet();
  }

  @override
  void didUpdateWidget(covariant LessonAudioWhiteboardRecorderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasUnsavedRecording &&
        oldWidget.initialBoardSet != widget.initialBoardSet) {
      _resetWorkingBoardSet();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        !_isStopping) {
      if (_isRecording || _isPaused) {
        unawaited(_stopRecording(automatic: true));
      } else if (_status == _RecordingStatus.starting ||
          _status == _RecordingStatus.pausing ||
          _status == _RecordingStatus.resuming) {
        _autoStopRequested = true;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _displayTimer?.cancel();
    unawaited(_previewPlayingSubscription?.cancel());
    unawaited(_preview.dispose());
    final activeStop = _activeStopFuture;
    if (activeStop != null) {
      unawaited(activeStop.whenComplete(_recorder.dispose));
    } else if (_activeTransitionFuture case final transition?) {
      unawaited(
        transition.catchError((_) {}).then((_) => _stopAndDisposeRecorder()),
      );
    } else if (_isRecording || _isPaused || _isStopping) {
      unawaited(_stopAndDisposeRecorder());
    } else {
      final recordedFile = _recordedFile;
      if (recordedFile != null) {
        unawaited(_recorder.deleteRecording(recordedFile));
      }
      unawaited(_recorder.dispose());
    }
    super.dispose();
  }

  Future<void> _stopAndDisposeRecorder() async {
    try {
      final file = await _recorder.stop();
      if (file != null) {
        await _recorder.deleteRecording(file);
      }
    } finally {
      await _recorder.dispose();
    }
  }

  void _resetWorkingBoardSet() {
    _boardSet = widget.initialBoardSet.ensureEditable();
    _selectedBoardId =
        _boardSet.resolveBoardAt(widget.segmentStartSec)?.id ??
        _boardSet.defaultBoard?.id ??
        LessonWhiteboardBoard.defaultBoardId;
    _loadSelectedStrokes();
    _inProgressStroke = null;
    _inProgressPoints = [];
    _strokeStartSec = null;
    _sessionStrokeIds.clear();
    _sessionSwitchSequences.clear();
    _drawingLimitReached = false;
    _payloadWarningShown = false;
  }

  void _loadSelectedStrokes() {
    _strokes = List<WhiteboardStroke>.from(
      _selectedBoard.layerBundle.primaryLayer?.strokes ?? const [],
    );
  }

  Future<void> _startRecording() {
    final active = _activeTransitionFuture;
    if (active != null) {
      return active;
    }
    final future = _performStartRecording();
    _activeTransitionFuture = future;
    return future.whenComplete(() {
      if (identical(_activeTransitionFuture, future)) {
        _activeTransitionFuture = null;
      }
    });
  }

  Future<void> _performStartRecording() async {
    if (_hasActiveRecording || _isUploading) {
      return;
    }
    setState(() => _message = null);
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          setState(() {
            _status = _RecordingStatus.idle;
            _message = 'マイクの使用が許可されていません。端末の設定から許可してください。';
          });
        }
        return;
      }
      if (!mounted) {
        return;
      }
      if (_lifecycleState != AppLifecycleState.resumed) {
        setState(() {
          _message = 'アプリへ戻ってから、もう一度録音を開始してください。';
        });
        return;
      }
      widget.onBusyChanged(true);
      setState(() => _status = _RecordingStatus.starting);
      await _preview.stop();
      final previousFile = _recordedFile;
      if (previousFile != null) {
        await _recorder.deleteRecording(previousFile);
      }
      await _recorder.start();
      _sessionSegmentStartSec = widget.segmentStartSec;
      _clock.start();
      _startDisplayTimer();
      if (!mounted) {
        return;
      }
      setState(() {
        _resetWorkingBoardSet();
        _recordedFile = null;
        _recordedDurationSec = 0;
        _recordedDurationMs = 0;
        _previewLoaded = false;
        _status = _RecordingStatus.recording;
        _message = '録音中です。話しながらホワイトボードへ書けます。';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = _RecordingStatus.idle;
          _message = '録音を開始できませんでした: $error';
        });
        widget.onBusyChanged(false);
      }
    } finally {
      if (_autoStopRequested && (_isRecording || _isPaused)) {
        _autoStopRequested = false;
        unawaited(_stopRecording(automatic: true));
      }
    }
  }

  void _startDisplayTimer() {
    _displayTimer?.cancel();
    _displayTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _isRecording) {
        setState(() {});
      }
    });
  }

  Future<void> _pauseRecording() {
    final active = _activeTransitionFuture;
    if (active != null) {
      return active;
    }
    final future = _performPauseRecording();
    _activeTransitionFuture = future;
    return future.whenComplete(() {
      if (identical(_activeTransitionFuture, future)) {
        _activeTransitionFuture = null;
      }
    });
  }

  Future<void> _performPauseRecording() async {
    if (!_isRecording || _isStopping) {
      return;
    }
    setState(() => _status = _RecordingStatus.pausing);
    try {
      await _recorder.pause();
      _clock.pause();
      _finishInProgressStroke();
      _displayTimer?.cancel();
      if (mounted) {
        setState(() {
          _status = _RecordingStatus.paused;
          _message = '一時停止中です。再開すると録音と書き物の時計が同時に進みます。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = _RecordingStatus.recording;
          _message = '一時停止できませんでした: $error';
        });
      }
    } finally {
      if (_autoStopRequested && (_isRecording || _isPaused)) {
        _autoStopRequested = false;
        unawaited(_stopRecording(automatic: true));
      }
    }
  }

  Future<void> _resumeRecording() {
    final active = _activeTransitionFuture;
    if (active != null) {
      return active;
    }
    final future = _performResumeRecording();
    _activeTransitionFuture = future;
    return future.whenComplete(() {
      if (identical(_activeTransitionFuture, future)) {
        _activeTransitionFuture = null;
      }
    });
  }

  Future<void> _performResumeRecording() async {
    if (!_isPaused || _isStopping) {
      return;
    }
    setState(() => _status = _RecordingStatus.resuming);
    try {
      await _recorder.resume();
      _clock.resume();
      _startDisplayTimer();
      if (mounted) {
        setState(() {
          _status = _RecordingStatus.recording;
          _message = '録音を再開しました。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = _RecordingStatus.paused;
          _message = '録音を再開できませんでした: $error';
        });
      }
    } finally {
      if (_autoStopRequested && (_isRecording || _isPaused)) {
        _autoStopRequested = false;
        unawaited(_stopRecording(automatic: true));
      }
    }
  }

  Future<void> _stopRecording({bool automatic = false}) {
    final active = _activeStopFuture;
    if (active != null) {
      return active;
    }
    if (_status == _RecordingStatus.pausing ||
        _status == _RecordingStatus.resuming) {
      _autoStopRequested = _autoStopRequested || automatic;
      return Future.value();
    }
    final future = _performStopRecording(automatic: automatic);
    _activeStopFuture = future;
    return future.whenComplete(() {
      if (identical(_activeStopFuture, future)) {
        _activeStopFuture = null;
      }
    });
  }

  Future<void> _performStopRecording({required bool automatic}) async {
    if ((!_isRecording && !_isPaused) || _isStopping) {
      return;
    }
    _isStopping = true;
    _clock.pause();
    _displayTimer?.cancel();
    _finishInProgressStroke();
    if (mounted) {
      setState(() {
        _status = _RecordingStatus.stopping;
        _message = automatic ? '画面を離れたため録音を安全に停止しています…' : '録音を停止しています…';
      });
    }
    try {
      final file = await _recorder.stop();
      if (file == null || file.size <= 0 || file.path == null) {
        throw StateError('録音ファイルを作成できませんでした。');
      }
      Duration? previewDuration;
      try {
        previewDuration = await _preview.load(file.path!);
        _previewLoaded = true;
      } catch (_) {
        // Some devices cannot initialize playback while the app is moving to
        // the background. The completed local file is still kept safely and
        // loading is retried when the teacher taps the preview button.
        _previewLoaded = false;
      }
      final clockDuration = _clock.elapsed;
      final resolvedDuration =
          previewDuration != null && previewDuration > Duration.zero
          ? previewDuration
          : clockDuration;
      final durationMs = resolvedDuration.inMilliseconds
          .clamp(1, 2147483647)
          .toInt();
      final durationSec = (durationMs ~/ 1000).clamp(1, 2147483647).toInt();
      _scaleSessionTimestamps(clockDuration, resolvedDuration);
      if (!mounted) {
        return;
      }
      setState(() {
        _recordedFile = file;
        _recordedDurationSec = durationSec;
        _recordedDurationMs = durationMs;
        _status = _RecordingStatus.ready;
        _message = file.size > LessonMediaStorageService.maxBytes
            ? '録音ファイルが100MBを超えました。録り直してください。'
            : automatic
            ? '画面を離れたため自動停止しました。再生して内容を確認してください。'
            : '端末へ保存しました。再生して内容を確認してください。';
      });
    } catch (error) {
      try {
        await _recorder.cancel();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _status = _RecordingStatus.idle;
          _message = '録音の保存に失敗しました: $error';
        });
        widget.onBusyChanged(false);
      }
    } finally {
      _isStopping = false;
    }
  }

  void _scaleSessionTimestamps(Duration clockDuration, Duration fileDuration) {
    if (clockDuration <= Duration.zero || fileDuration <= Duration.zero) {
      return;
    }
    final clockMicros = clockDuration.inMicroseconds;
    if (clockMicros <= 0) {
      return;
    }
    final scale = fileDuration.inMicroseconds / clockMicros;
    final durationSec = fileDuration.inMicroseconds / 1000000;
    _commitSelectedBoard();
    _boardSet = _boardSet.copyWith(
      boards: [
        for (final board in _boardSet.boards)
          board.copyWith(
            layerBundle: LessonWhiteboardLayerBundle(
              layers: [
                for (final layer in board.layerBundle.layers)
                  layer.copyWith(
                    strokes: [
                      for (final stroke in layer.strokes)
                        if (_sessionStrokeIds.contains(stroke.id))
                          scaleRecordedWhiteboardStroke(
                            stroke: stroke,
                            segmentStartSec: _sessionSegmentStartSec,
                            scale: scale,
                            segmentDurationSec: durationSec,
                          )
                        else
                          stroke,
                    ],
                  ),
              ],
            ),
          ),
      ],
      switchEvents: [
        for (final event in _boardSet.switchEvents)
          if (_sessionSwitchSequences.contains(event.sequence))
            LessonWhiteboardBoardSwitchEvent(
              boardId: event.boardId,
              globalTimestampSec:
                  _sessionSegmentStartSec +
                  ((event.globalTimestampSec - _sessionSegmentStartSec) * scale)
                      .clamp(0.0, durationSec),
              sequence: event.sequence,
            )
          else
            event,
      ],
    );
    _loadSelectedStrokes();
  }

  Future<void> _togglePreview() async {
    if (_recordedFile == null || _isUploading) {
      return;
    }
    try {
      if (!_previewLoaded) {
        final path = _recordedFile?.path;
        if (path == null || path.isEmpty) {
          throw StateError('録音ファイルを読み込めませんでした。');
        }
        await _preview.load(path);
        _previewLoaded = true;
      }
      if (_preview.isPlaying) {
        await _preview.pause();
      } else {
        await _preview.play();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = '録音の再生に失敗しました: $error');
      }
    }
  }

  Future<void> _useRecording() async {
    final file = _recordedFile;
    if (file == null ||
        file.size > LessonMediaStorageService.maxBytes ||
        _recordedDurationSec <= 0 ||
        _recordedDurationMs <= 0 ||
        _isUploading) {
      return;
    }
    setState(() {
      _isUploading = true;
      _message = '書き物を仮保存して、音声をアップロードしています…';
    });
    try {
      await _preview.stop();
      await widget.onUseRecording(
        file,
        _recordedDurationSec,
        _recordedDurationMs,
        _buildCurrentBoardSet(),
      );
      await _recorder.deleteRecording(file);
      widget.onBusyChanged(false);
      if (mounted) {
        setState(() {
          _recordedFile = null;
          _status = _RecordingStatus.used;
          _message = '音声と書き物を追加しました。「レッスン情報を保存」を押してください。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = '保存またはアップロードに失敗しました: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _recordAgain() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('録り直しますか？'),
        content: const Text('端末に保存した音声と、同時に書いた書き物を両方削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('録り直す'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _preview.stop();
    final file = _recordedFile;
    if (file != null) {
      await _recorder.deleteRecording(file);
    }
    _clock.reset();
    setState(() {
      _recordedFile = null;
      _recordedDurationSec = 0;
      _recordedDurationMs = 0;
      _previewLoaded = false;
      _status = _RecordingStatus.idle;
      _resetWorkingBoardSet();
      _message = null;
    });
    await _startRecording();
  }

  Future<void> _discardRecordingPart() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('録音パートを削除しますか？'),
        content: const Text('端末に保存した音声と、同時に書いた書き物を削除します。'),
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
    if (confirmed != true || !mounted) {
      return;
    }
    await _preview.stop();
    final file = _recordedFile;
    if (file != null) {
      await _recorder.deleteRecording(file);
    }
    _recordedFile = null;
    widget.onBusyChanged(false);
    widget.onDiscard();
  }

  void _handleStrokeStart() {
    if (!_drawingEnabled) {
      return;
    }
    _strokeStartSec = _recordingPositionSec;
    _inProgressPoints = [];
  }

  void _handleStrokeUpdate(WhiteboardPoint point) {
    _recordPoint(point, force: false);
  }

  void _recordPoint(WhiteboardPoint point, {required bool force}) {
    if (!_drawingEnabled || _strokeStartSec == null) {
      return;
    }
    final timestampSec = _recordingPositionSec;
    final timedPoint = WhiteboardPoint(
      x: point.x,
      y: point.y,
      timestampSec: timestampSec,
    );
    if (!shouldSampleRecordedWhiteboardPoint(
      existingPoints: _inProgressPoints,
      nextTimestampSec: timestampSec,
      force: force,
    )) {
      return;
    }
    final candidatePoints = [..._inProgressPoints, timedPoint];
    final candidateStroke = WhiteboardStroke(
      id: 'in-progress',
      timestampSec: _strokeStartSec!,
      points: candidatePoints,
    );
    if (candidatePoints.length % 20 == 0 &&
        !_canAcceptBoardSet(
          _buildCurrentBoardSet(strokes: [..._strokes, candidateStroke]),
        )) {
      return;
    }
    setState(() {
      _inProgressPoints = candidatePoints;
      _inProgressStroke = candidateStroke;
    });
  }

  void _handleStrokeEnd(WhiteboardPoint point) {
    if (_strokeStartSec == null) {
      return;
    }
    _recordPoint(point, force: true);
    _finishInProgressStroke();
  }

  void _finishInProgressStroke() {
    if (_inProgressPoints.length >= 2 && _strokeStartSec != null) {
      final id = '${DateTime.now().microsecondsSinceEpoch}';
      final stroke = WhiteboardStroke(
        id: id,
        timestampSec: _strokeStartSec!,
        endTimestampSec: _recordingPositionSec,
        points: List<WhiteboardPoint>.from(_inProgressPoints),
      );
      final candidate = _buildCurrentBoardSet(strokes: [..._strokes, stroke]);
      if (_canAcceptBoardSet(candidate)) {
        _sessionStrokeIds.add(id);
        _strokes = [..._strokes, stroke];
      }
    }
    if (mounted) {
      setState(() {
        _inProgressStroke = null;
        _inProgressPoints = [];
        _strokeStartSec = null;
      });
    } else {
      _inProgressStroke = null;
      _inProgressPoints = [];
      _strokeStartSec = null;
    }
  }

  bool _canAcceptBoardSet(BoardSet boardSet) {
    final bytes = estimateSerializedUtf8JsonBytes(boardSet.toMap());
    final publicationError = widget.validateForPublication?.call(boardSet);
    if (bytes > maxLessonPayloadUtf8Bytes || publicationError != null) {
      if (mounted) {
        setState(() {
          _drawingLimitReached = true;
          _message =
              publicationError ??
              '書き物の保存上限に達したため、新しい描画を停止しました。録音は停止ボタンで保存できます。';
        });
      }
      return false;
    }
    if (bytes >= lessonPayloadWarningUtf8Bytes && !_payloadWarningShown) {
      _payloadWarningShown = true;
      if (mounted) {
        setState(() {
          _message = '書き物のデータ量が保存上限に近づいています。必要な内容を優先してください。';
        });
      }
    }
    return true;
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

  BoardSet _buildCurrentBoardSet({List<WhiteboardStroke>? strokes}) {
    final board = _boardSet.boardById(_selectedBoardId);
    if (board == null) {
      return _boardSet;
    }
    return _boardSet.replaceBoard(
      board.copyWith(
        layerBundle: board.layerBundle.copyWithPrimaryStrokes(
          strokes: strokes ?? _strokes,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  void _addBoard() {
    if (!_canAddBoard) {
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
    final sequence = _boardSet.nextSwitchSequence;
    final candidate = _boardSet.copyWith(
      boards: [..._boardSet.orderedBoards, board],
      switchEvents: [
        ..._boardSet.switchEvents,
        LessonWhiteboardBoardSwitchEvent(
          boardId: id,
          globalTimestampSec: _recordingPositionSec,
          sequence: sequence,
        ),
      ],
    );
    if (!_canAcceptBoardSet(candidate)) {
      return;
    }
    _boardSet = candidate;
    _sessionSwitchSequences.add(sequence);
    setState(() {
      _selectedBoardId = id;
      _loadSelectedStrokes();
    });
  }

  void _switchBoard(String boardId) {
    if (boardId == _selectedBoardId ||
        _boardSet.boardById(boardId) == null ||
        !_hasActiveRecording) {
      return;
    }
    _finishInProgressStroke();
    _commitSelectedBoard();
    if (_boardSet.switchEvents.length >= maxLessonBoardSwitchEvents) {
      setState(() {
        _message = lessonBoardSwitchEventLimitMessage;
      });
      return;
    }
    final sequence = _boardSet.nextSwitchSequence;
    final candidate = _boardSet.copyWith(
      switchEvents: [
        ..._boardSet.switchEvents,
        LessonWhiteboardBoardSwitchEvent(
          boardId: boardId,
          globalTimestampSec: _recordingPositionSec,
          sequence: sequence,
        ),
      ],
    );
    if (!_canAcceptBoardSet(candidate)) {
      return;
    }
    _boardSet = candidate;
    _sessionSwitchSequences.add(sequence);
    setState(() {
      _selectedBoardId = boardId;
      _loadSelectedStrokes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final elapsedSec = _clock.elapsed.inMilliseconds ~/ 1000;
    final canUseRecording =
        _recordedFile != null &&
        _recordedFile!.size <= LessonMediaStorageService.maxBytes &&
        !_isUploading;
    return PopScope(
      canPop: !_hasUnsavedRecording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _hasUnsavedRecording) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('先に録音を停止し、使用または削除を選んでください。')),
          );
        }
      },
      child: Card(
        key: const ValueKey('audio-whiteboard-recorder'),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('録音しながら書く', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                '録音中の音声は端末内へ保存されます。停止後に再生確認し、'
                '「この音声を使用」を押したときだけアップロードします。',
              ),
              const SizedBox(height: 12),
              Text(
                _status == _RecordingStatus.ready
                    ? '録音時間: ${formatLessonTime(_recordedDurationSec)}'
                    : '録音時間: ${formatLessonTime(elapsedSec)}',
                key: const ValueKey('audio-recording-time'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isRecording
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_status == _RecordingStatus.idle)
                    FilledButton.icon(
                      key: const ValueKey('start-audio-whiteboard-recording'),
                      onPressed: _startRecording,
                      icon: const Icon(Icons.mic),
                      label: const Text('録音を開始'),
                    ),
                  if (_isRecording)
                    OutlinedButton.icon(
                      key: const ValueKey('pause-audio-recording'),
                      onPressed: _pauseRecording,
                      icon: const Icon(Icons.pause),
                      label: const Text('一時停止'),
                    ),
                  if (_isPaused)
                    FilledButton.icon(
                      key: const ValueKey('resume-audio-recording'),
                      onPressed: _resumeRecording,
                      icon: const Icon(Icons.mic),
                      label: const Text('録音を再開'),
                    ),
                  if (_isRecording || _isPaused)
                    FilledButton.icon(
                      key: const ValueKey('stop-audio-recording'),
                      onPressed: _isStopping ? null : _stopRecording,
                      icon: const Icon(Icons.stop),
                      label: const Text('録音を停止'),
                    ),
                  if (_status == _RecordingStatus.ready) ...[
                    OutlinedButton.icon(
                      key: const ValueKey('preview-audio-recording'),
                      onPressed: _isUploading ? null : _togglePreview,
                      icon: Icon(
                        _previewPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                      label: Text(_previewPlaying ? '再生を一時停止' : '録音を再生'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('use-audio-recording'),
                      onPressed: canUseRecording ? _useRecording : null,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('この音声を使用'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('record-audio-again'),
                      onPressed: _isUploading ? null : _recordAgain,
                      icon: const Icon(Icons.refresh),
                      label: const Text('録り直す'),
                    ),
                  ],
                  if (_status == _RecordingStatus.idle ||
                      _status == _RecordingStatus.ready)
                    OutlinedButton.icon(
                      key: const ValueKey('discard-audio-recording-part'),
                      onPressed: _isUploading ? null : _discardRecordingPart,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('録音パートを削除'),
                    ),
                ],
              ),
              if (_hasActiveRecording || _status == _RecordingStatus.ready) ...[
                const SizedBox(height: 16),
                Text(
                  _drawingEnabled
                      ? '録音中はペンで書けます（最大20点/秒）。'
                      : _isPaused
                      ? '一時停止中は書けませんが、ボードの追加と切替はできます。'
                      : '録音した書き物を確認できます。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  key: const ValueKey('audio-whiteboard-board-selector'),
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final entry in _boardSet.orderedBoards.indexed)
                      ChoiceChip(
                        selected: entry.$2.id == _selectedBoardId,
                        label: Text(
                          entry.$2.title.isEmpty
                              ? '${entry.$1 + 1}'
                              : '${entry.$1 + 1}. ${entry.$2.title}',
                        ),
                        onSelected: _hasActiveRecording
                            ? (_) => _switchBoard(entry.$2.id)
                            : null,
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('audio-whiteboard-add-board'),
                      onPressed: _canAddBoard ? _addBoard : null,
                      icon: const Icon(Icons.add),
                      label: const Text('ボードを追加'),
                    ),
                    Text(
                      '${_boardSet.boards.length}/$maxLessonWhiteboardBoards',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 220,
                  child: LessonWhiteboardCanvas(
                    strokes: _strokes,
                    inProgressStroke: _inProgressStroke,
                    drawingEnabled: _drawingEnabled,
                    onStrokeStart: _handleStrokeStart,
                    onStrokeUpdate: _handleStrokeUpdate,
                    onStrokeEnd: _handleStrokeEnd,
                  ),
                ),
              ],
              if (_isUploading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _RecordingStatus {
  idle,
  starting,
  recording,
  pausing,
  paused,
  resuming,
  stopping,
  ready,
  used,
}
