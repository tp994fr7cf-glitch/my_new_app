import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lesson_duration_parser.dart';
import '../models/lesson_media_segment.dart';
import '../models/lesson_media_timeline.dart';
import '../models/lesson_player_view_state.dart';
import '../models/lesson_whiteboard.dart';
import '../services/lesson_media_playback.dart';
import '../services/lesson_media_playlist_playback.dart';
import 'lesson_whiteboard_canvas.dart';

typedef WhiteboardDraftSaveCallback =
    Future<void> Function(LessonWhiteboard whiteboard);

class LessonWhiteboardEditorPanel extends StatefulWidget {
  const LessonWhiteboardEditorPanel({
    super.key,
    required this.courseId,
    required this.lessonNumber,
    required this.mediaSegments,
    required this.durationLabel,
    required this.publishedWhiteboard,
    required this.draftWhiteboard,
    required this.onDraftSaved,
    this.onWhiteboardChanged,
    this.playlistPlaybackFactory = createLessonMediaPlaylistPlayback,
  });

  final String courseId;
  final int lessonNumber;
  final List<LessonMediaSegment> mediaSegments;
  final String durationLabel;
  final LessonWhiteboard? publishedWhiteboard;
  final LessonWhiteboard? draftWhiteboard;
  final WhiteboardDraftSaveCallback onDraftSaved;
  final ValueChanged<LessonWhiteboard>? onWhiteboardChanged;
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
  double? _strokeStartSec;

  bool get _drawingEnabled => _isPlaying;
  bool get _hasPublishedWhiteboard =>
      widget.publishedWhiteboard != null && !widget.publishedWhiteboard!.isEmpty;

  bool get _hasUnpublishedDraft {
    final draft = widget.draftWhiteboard;
    return draft != null && !draft.isEmpty;
  }

  bool get _shouldShowEditingCanvas =>
      _editSessionKind != WhiteboardEditSessionKind.none;

  List<WhiteboardStroke> get _visibleStrokes {
    return visibleWhiteboardStrokes(
      strokes: _strokes,
      positionSec: _currentPositionSecExact,
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
        oldWidget.publishedWhiteboard != widget.publishedWhiteboard) {
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
      final draft = widget.draftWhiteboard;
      _strokes = draft != null && !draft.isEmpty
          ? List<WhiteboardStroke>.from(draft.strokes)
          : [];
      _editSessionKind = WhiteboardEditSessionKind.fresh;
      return;
    }

    if (_hasUnpublishedDraft) {
      _strokes = List<WhiteboardStroke>.from(widget.draftWhiteboard!.strokes);
      if (!preserveActiveSession ||
          _editSessionKind == WhiteboardEditSessionKind.none) {
        _editSessionKind = WhiteboardEditSessionKind.draft;
      }
      return;
    }

    if (!preserveActiveSession) {
      _strokes = [];
      _editSessionKind = WhiteboardEditSessionKind.none;
    }
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
      playerDuration: playerDuration ?? Duration(seconds: _playback!.totalDurationSec),
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
    _strokeStartSec = _currentPositionSecExact;
    _inProgressPoints = [];
  }

  void _handleStrokeUpdate(WhiteboardPoint point) {
    _recordPoint(point, force: false);
  }

  void _recordPoint(WhiteboardPoint point, {required bool force}) {
    if (_strokeStartSec == null) {
      return;
    }

    final timestampSec = _currentPositionSecExact;
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
    final timestampSec = _currentPositionSecExact;
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
        endTimestampSec: _currentPositionSecExact,
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
        endTimestampSec: _currentPositionSecExact,
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

  void _notifyWhiteboardChanged() {
    if (_editSessionKind == WhiteboardEditSessionKind.fresh) {
      widget.onWhiteboardChanged?.call(_buildCurrentWhiteboard());
    }
  }

  void _syncWorkingWhiteboardAfterDraftSave() {
    widget.onWhiteboardChanged?.call(_buildCurrentWhiteboard());
  }

  Future<void> _saveDraft() async {
    setState(() {
      _isSavingDraft = true;
      _message = null;
    });

    try {
      await widget.onDraftSaved(_buildCurrentWhiteboard());
      if (mounted) {
        setState(() {
          final saved = _buildCurrentWhiteboard();
          if (saved.isEmpty && _hasPublishedWhiteboard) {
            _editSessionKind = WhiteboardEditSessionKind.none;
            _strokes = [];
            _message = '書き物を一時保存しました。';
          } else {
            _editSessionKind = WhiteboardEditSessionKind.draft;
            _message = '書き物を一時保存しました。';
          }
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
    final published = widget.publishedWhiteboard;
    if (published == null || published.isEmpty) {
      return;
    }

    setState(() {
      _strokes = List<WhiteboardStroke>.from(published.strokes);
      _editSessionKind = WhiteboardEditSessionKind.published;
      _message = '公開中の書き物を編集しています。一時保存で仮保存されます。';
    });
    _clearInProgressStroke();
    await _playback?.pause();
  }

  Future<void> _beginEditingDraft() async {
    final draft = widget.draftWhiteboard;
    if (draft == null || draft.isEmpty) {
      return;
    }

    setState(() {
      _strokes = List<WhiteboardStroke>.from(draft.strokes);
      _editSessionKind = WhiteboardEditSessionKind.draft;
      _message = '仮保存中の書き物を編集しています。';
    });
    _clearInProgressStroke();
    await _playback?.pause();
  }

  Future<void> _beginPendingReset() async {
    setState(() {
      _strokes = [];
      _editSessionKind = WhiteboardEditSessionKind.pendingReset;
      _message = '最初から描き直します。一時保存で確定してください。';
    });
    _clearInProgressStroke();
    await _playback?.pause();
    await _seekPlaybackPosition(0);
  }

  @override
  Widget build(BuildContext context) {
    final sliderMax = _totalDurationSec > 0 ? _totalDurationSec.toDouble() : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '音声プレビュー',
          style: Theme.of(context).textTheme.titleSmall,
        ),
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
            '${formatLessonTime(_currentPositionSec)} / ${formatLessonTime(_totalDurationSec)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Slider(
            value: _currentPositionSec.clamp(0, _totalDurationSec).toDouble(),
            min: 0,
            max: sliderMax,
            divisions: _totalDurationSec > 0 ? _totalDurationSec : null,
            label: formatLessonTime(_currentPositionSec),
            onChanged: _isPlaying
                ? null
                : (value) {
                    unawaited(_seekPlaybackPosition(value.round()));
                  },
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'ホワイトボード',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          _isPlaying
              ? '再生中はペンで書けます。'
              : 'スタートを押すと音声が流れ、同時に書けるようになります。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_hasPublishedWhiteboard && !_shouldShowEditingCanvas) ...[
          SizedBox(
            height: 220,
            child: LessonWhiteboardCanvas(
              strokes: widget.publishedWhiteboard!.strokes,
              drawingEnabled: false,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isSavingDraft ? null : () => unawaited(_showEditOptions()),
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
                onPressed: !_isPlaying ? null : () => unawaited(_pauseRecording()),
                icon: const Icon(Icons.pause),
                label: const Text('一時停止'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _isSavingDraft ||
                        (_strokes.isEmpty &&
                            _editSessionKind !=
                                WhiteboardEditSessionKind.pendingReset)
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
                onPressed: _isSavingDraft ? null : () => unawaited(_showEditOptions()),
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
    );
  }
}

enum _WhiteboardEditChoice {
  published,
  draft,
  reset,
}

Future<void> saveLessonWhiteboardDraft({
  required String courseId,
  required int lessonIndex,
  required LessonWhiteboard whiteboard,
}) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('courses')
      .doc(courseId)
      .get();
  if (!snapshot.exists) {
    throw StateError('講座が見つかりません。');
  }

  final course = snapshot.data() ?? {};
  final lessonsData = course['lessons'];
  if (lessonsData is! List || lessonIndex < 0 || lessonIndex >= lessonsData.length) {
    throw StateError('レッスンが見つかりません。');
  }

  final lessons = lessonsData
      .whereType<Map>()
      .map((lesson) => Map<String, dynamic>.from(lesson))
      .toList();
  final lessonMap = Map<String, dynamic>.from(lessons[lessonIndex]);
  final draftLayers =
      LessonWhiteboardLayerBundle.fromLegacyWhiteboard(
        whiteboard.isEmpty ? null : whiteboard,
      ).toMapList();
  if (draftLayers.isEmpty) {
    lessonMap.remove('whiteboardDraftLayers');
    lessonMap.remove('whiteboardDraft');
  } else {
    lessonMap['whiteboardDraftLayers'] = draftLayers;
    lessonMap.remove('whiteboardDraft');
  }
  lessons[lessonIndex] = lessonMap;

  await FirebaseFirestore.instance.collection('courses').doc(courseId).update({
    'lessons': lessons,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
