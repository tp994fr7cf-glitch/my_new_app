import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lesson_duration_parser.dart';
import '../models/lesson_player_view_state.dart';
import '../models/lesson_whiteboard.dart';
import '../services/lesson_media_playback.dart';
import 'lesson_whiteboard_canvas.dart';

typedef WhiteboardDraftSaveCallback =
    Future<void> Function(LessonWhiteboard whiteboard);

class LessonWhiteboardEditorPanel extends StatefulWidget {
  const LessonWhiteboardEditorPanel({
    super.key,
    required this.courseId,
    required this.lessonNumber,
    required this.mediaUrl,
    required this.mediaDurationSec,
    required this.durationLabel,
    required this.publishedWhiteboard,
    required this.draftWhiteboard,
    required this.onDraftSaved,
    this.onWhiteboardChanged,
    this.playbackFactory = createLessonMediaPlayback,
  });

  final String courseId;
  final int lessonNumber;
  final String mediaUrl;
  final int mediaDurationSec;
  final String durationLabel;
  final LessonWhiteboard? publishedWhiteboard;
  final LessonWhiteboard? draftWhiteboard;
  final WhiteboardDraftSaveCallback onDraftSaved;
  final ValueChanged<LessonWhiteboard>? onWhiteboardChanged;
  final LessonMediaPlaybackFactory playbackFactory;

  @override
  State<LessonWhiteboardEditorPanel> createState() =>
      _LessonWhiteboardEditorPanelState();
}

class _LessonWhiteboardEditorPanelState
    extends State<LessonWhiteboardEditorPanel> {
  LessonMediaPlayback? _playback;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;

  List<WhiteboardStroke> _strokes = [];
  WhiteboardStroke? _inProgressStroke;
  List<WhiteboardPoint> _inProgressPoints = [];

  bool _isRedrawMode = false;
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
    if (lessonHasMediaSource(widget.mediaUrl)) {
      unawaited(_initializeMediaPlayer());
    }
  }

  @override
  void didUpdateWidget(covariant LessonWhiteboardEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      unawaited(_reloadMediaPlayer());
    }
    if (oldWidget.draftWhiteboard != widget.draftWhiteboard ||
        oldWidget.publishedWhiteboard != widget.publishedWhiteboard) {
      if (_inProgressStroke == null && !_isPlaying) {
        _loadInitialStrokes();
      }
    }
  }

  void _loadInitialStrokes() {
    final merged = mergeWhiteboardDraft(
      published: widget.publishedWhiteboard,
      draft: widget.draftWhiteboard,
    );
    _strokes = List<WhiteboardStroke>.from(merged.strokes);
    _isRedrawMode = !_hasPublishedWhiteboard || merged.isEmpty;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    unawaited(_playback?.disposePlayer());
    super.dispose();
  }

  Future<void> _reloadMediaPlayer() async {
    await _playback?.disposePlayer();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _playback = null;
    if (!lessonHasMediaSource(widget.mediaUrl)) {
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
      final playback = widget.playbackFactory(isAudio: true);
      await playback.open(Uri.parse(widget.mediaUrl.trim()));
      if (!mounted) {
        await playback.disposePlayer();
        return;
      }

      _playback = playback;
      _positionSubscription = playback.positionStream.listen((position) {
        if (!mounted) {
          return;
        }
        final nextSec = position.inMilliseconds / 1000;
        setState(() {
          _currentPositionSecExact = nextSec;
          _currentPositionSec = nextSec.floor();
        });
      });
      _durationSubscription = playback.durationStream.listen((duration) {
        _updateResolvedDuration(playerDuration: duration);
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

    final nextTotalDurationSec = resolveLessonMediaDurationSec(
      playerDuration: playerDuration ?? _playback!.duration,
      mediaDurationSec: widget.mediaDurationSec,
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

  void _applyResolvedPlaybackState(LessonMediaPlayback playback) {
    final totalDurationSec = resolveLessonMediaDurationSec(
      playerDuration: playback.duration,
      mediaDurationSec: widget.mediaDurationSec,
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
      lessonHasMediaSource(widget.mediaUrl) &&
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
    await _playback?.seek(Duration(milliseconds: (nextPosition * 1000).round()));
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
          _message = '書き物を一時保存しました。';
        });
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
            '次の編集は0秒地点から始まります。',
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

    setState(() {
      _strokes = [];
      _isRedrawMode = true;
      _message = null;
    });
    _notifyWhiteboardChanged();
    _clearInProgressStroke();
    await _playback?.pause();
    await _seekPlaybackPosition(0);

    setState(() {
      _isSavingDraft = true;
    });
    try {
      await widget.onDraftSaved(const LessonWhiteboard());
      if (mounted) {
        setState(() {
          _message = '書き物をリセットしました。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'リセットの保存に失敗しました: $error';
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

  Future<void> _startRedraw() async {
    final shouldRedraw = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('書き物を描き直す'),
          content: const Text(
            '保存済みの書き物を消して、最初から描き直します。\n'
            '元の書き物は「レッスン情報を保存」するまで受講者には残ります。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('描き直す'),
            ),
          ],
        );
      },
    );
    if (shouldRedraw != true || !mounted) {
      return;
    }

    setState(() {
      _strokes = [];
      _isRedrawMode = true;
      _message = '描き直しモードです。スタートを押して書き始めてください。';
    });
    _notifyWhiteboardChanged();
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
        if (_hasPublishedWhiteboard && !_isRedrawMode) ...[
          SizedBox(
            height: 220,
            child: LessonWhiteboardCanvas(
              strokes: widget.publishedWhiteboard!.strokes,
              drawingEnabled: false,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isSavingDraft ? null : () => unawaited(_startRedraw()),
            icon: const Icon(Icons.refresh),
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
                onPressed: _isSavingDraft || _strokes.isEmpty
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
  if (whiteboard.isEmpty) {
    lessonMap.remove('whiteboardDraft');
  } else {
    lessonMap['whiteboardDraft'] = whiteboard.toMap();
  }
  lessons[lessonIndex] = lessonMap;

  await FirebaseFirestore.instance.collection('courses').doc(courseId).update({
    'lessons': lessons,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
