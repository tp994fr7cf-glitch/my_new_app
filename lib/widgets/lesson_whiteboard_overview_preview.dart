import 'dart:async';

import 'package:flutter/material.dart';

import '../models/lesson_duration_parser.dart';
import '../models/lesson_media_segment.dart';
import '../models/lesson_media_timeline.dart';
import '../models/lesson_player_view_state.dart';
import '../models/lesson_whiteboard_board_set.dart';
import '../services/lesson_material_source_resolver.dart';
import '../services/lesson_media_playback.dart';
import '../services/lesson_media_playlist_playback.dart';
import 'lesson_media_playback_gate.dart';
import 'lesson_playback_synced_whiteboard.dart';
import 'lesson_whiteboard_canvas.dart';

/// View-only full-lesson media + whiteboard preview for lesson management.
class LessonWhiteboardOverviewPreview extends StatefulWidget {
  const LessonWhiteboardOverviewPreview({
    super.key,
    required this.courseId,
    this.lessonId,
    required this.mediaSegments,
    required this.durationLabel,
    required this.boardSet,
    this.playbackGate,
    this.playbackOwnerId = 'overview',
    this.enabled = true,
    this.playlistPlaybackFactory = createLessonMediaPlaylistPlayback,
  });

  final String courseId;
  final String? lessonId;
  final List<LessonMediaSegment> mediaSegments;
  final String durationLabel;
  final BoardSet boardSet;
  final LessonMediaPlaybackGate? playbackGate;
  final String playbackOwnerId;
  final bool enabled;
  final LessonMediaPlaylistPlaybackFactory playlistPlaybackFactory;

  @override
  State<LessonWhiteboardOverviewPreview> createState() =>
      _LessonWhiteboardOverviewPreviewState();
}

class _LessonWhiteboardOverviewPreviewState
    extends State<LessonWhiteboardOverviewPreview> {
  LessonMediaPlaylistController? _playback;
  StreamSubscription<double>? _positionSubscription;
  StreamSubscription<int>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  bool _isLoadingMedia = false;
  bool _isPlaying = false;
  String? _mediaLoadError;
  int _currentPositionSec = 0;
  int _totalDurationSec = 0;
  double _currentPositionSecExact = 0;
  double? _sliderDragPositionSec;
  late final String _gateOwnerId;

  LessonMediaTimeline get _timeline =>
      LessonMediaTimeline(segments: widget.mediaSegments);

  int get _displayedPositionSec =>
      (_sliderDragPositionSec ?? _currentPositionSec.toDouble()).round();

  bool get _canControlPlayback =>
      lessonHasPlayableMedia(mediaSegments: widget.mediaSegments) &&
      _mediaLoadError == null &&
      _totalDurationSec > 0 &&
      (_playback?.isReady ?? false);

  @override
  void initState() {
    super.initState();
    _gateOwnerId = widget.playbackOwnerId.trim().isEmpty
        ? 'overview-${identityHashCode(this)}'
        : widget.playbackOwnerId.trim();
    widget.playbackGate?.register(ownerId: _gateOwnerId, pause: _pausePlayback);
    if (lessonHasPlayableMedia(mediaSegments: widget.mediaSegments)) {
      unawaited(_initializeMediaPlayer());
    }
  }

  @override
  void didUpdateWidget(covariant LessonWhiteboardOverviewPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackGate != widget.playbackGate ||
        oldWidget.playbackOwnerId != widget.playbackOwnerId) {
      oldWidget.playbackGate?.unregister(_gateOwnerId);
      widget.playbackGate?.register(
        ownerId: _gateOwnerId,
        pause: _pausePlayback,
      );
    }
    if (!_segmentsEqual(oldWidget.mediaSegments, widget.mediaSegments)) {
      unawaited(_reloadMediaPlayer());
    }
  }

  @override
  void dispose() {
    widget.playbackGate?.unregister(_gateOwnerId);
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    unawaited(_playback?.close());
    super.dispose();
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

  Future<void> _reloadMediaPlayer() async {
    await _playback?.close();
    await _positionSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _playingSubscription?.cancel();
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
        if (!mounted || _sliderDragPositionSec != null) {
          return;
        }
        setState(() {
          _currentPositionSecExact = position;
          _currentPositionSec = position.floor();
        });
      });
      _durationSubscription = playback.totalDurationStream.listen((duration) {
        if (!mounted) {
          return;
        }
        final nextTotalDurationSec = resolveTimelineDurationSec(
          timeline: _timeline,
          playerDuration: Duration(seconds: duration),
          durationLabel: widget.durationLabel,
        );
        if (nextTotalDurationSec <= _totalDurationSec) {
          return;
        }
        setState(() => _totalDurationSec = nextTotalDurationSec);
      });
      _playingSubscription = playback.playingStream.listen((isPlaying) {
        if (!mounted) {
          return;
        }
        setState(() => _isPlaying = isPlaying);
      });
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

  Future<void> _startPlayback() async {
    if (!_canControlPlayback) {
      return;
    }
    try {
      await widget.playbackGate?.claim(_gateOwnerId);
      await _playback?.play();
    } catch (error) {
      if (mounted) {
        setState(() => _mediaLoadError = '再生に失敗しました: $error');
      }
    }
  }

  Future<void> _pausePlayback() async {
    await _playback?.pause();
  }

  Future<void> _seekPlaybackPosition(int positionSec) async {
    if (_totalDurationSec <= 0) {
      return;
    }
    final nextPosition = positionSec.clamp(0, _totalDurationSec);
    await _playback?.seekGlobal(nextPosition.toDouble());
    if (!mounted) {
      return;
    }
    setState(() {
      _currentPositionSec = nextPosition;
      _currentPositionSecExact = nextPosition.toDouble();
    });
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
            Text(
              'レッスン全体のプレビュー',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '書き物の編集は各パートで行います。ここでは通しの再生だけ確認できます。',
              style: Theme.of(context).textTheme.bodySmall,
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
                        setState(() => _sliderDragPositionSec = value);
                      },
                onChangeEnd: _isPlaying
                    ? null
                    : (value) {
                        final targetSec = value.round();
                        setState(() => _sliderDragPositionSec = null);
                        unawaited(_seekPlaybackPosition(targetSec));
                      },
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _isPlaying
                        ? null
                        : () => unawaited(_startPlayback()),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('スタート'),
                  ),
                  OutlinedButton.icon(
                    onPressed: !_isPlaying
                        ? null
                        : () => unawaited(_pausePlayback()),
                    icon: const Icon(Icons.pause),
                    label: const Text('一時停止'),
                  ),
                ],
              ),
            ],
            if (widget.boardSet.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'ホワイトボード',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              LessonPlaybackSyncedWhiteboard(
                boardSet: widget.boardSet,
                timeline: _timeline,
                playback: _playback,
                isPlaying: _isPlaying,
                positionSecExact: _currentPositionSecExact,
                totalDurationSec: _totalDurationSec,
                materialUrlResolver: _resolveMaterialSource,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
