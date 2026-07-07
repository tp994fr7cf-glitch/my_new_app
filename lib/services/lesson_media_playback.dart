import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

typedef LessonMediaPlaybackFactory =
    LessonMediaPlayback Function({required bool isAudio});

class LessonMediaLoadException implements Exception {
  LessonMediaLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class LessonMediaPlayback {
  VideoPlayerController? get videoController;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;
  Duration get position;
  Duration? get duration;
  bool get isPlaying;
  bool get isReady;

  Future<void> open(Uri url);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> disposePlayer();
}

LessonMediaPlayback createLessonMediaPlayback({required bool isAudio}) {
  return isAudio ? AudioLessonMediaPlayback() : VideoLessonMediaPlayback();
}

class AudioLessonMediaPlayback implements LessonMediaPlayback {
  AudioLessonMediaPlayback() : _player = AudioPlayer() {
    _player.playingStream.listen(_handlePlayingChanged);
    _player.positionStream.listen(_onPlayerPositionUpdate);
    _player.durationStream.listen((duration) {
      if (!_durationController.isClosed) {
        _durationController.add(duration);
      }
    });
  }

  static const Duration _positionRefreshInterval = Duration(seconds: 1);
  static const int _anchorRecalibrateDriftMs = 1000;

  final AudioPlayer _player;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  Timer? _positionRefreshTimer;
  Duration _anchorPosition = Duration.zero;
  DateTime? _anchorWallTime;
  bool _isReady = false;

  @override
  VideoPlayerController? get videoController => null;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Duration get position => _reportedPosition;

  Duration get _reportedPosition {
    if (!_player.playing) {
      return _player.position;
    }
    _ensurePlaybackAnchor();
    return _anchorPosition + DateTime.now().difference(_anchorWallTime!);
  }

  void _ensurePlaybackAnchor() {
    if (_anchorWallTime != null) {
      return;
    }
    _anchorPosition = _player.position;
    _anchorWallTime = DateTime.now();
  }

  @override
  Duration? get duration => _player.duration;

  @override
  bool get isPlaying => _player.playing;

  @override
  bool get isReady => _isReady;

  void _emitPosition(Duration position) {
    if (!_positionController.isClosed) {
      _positionController.add(position);
    }
  }

  void _onPlayerPositionUpdate(Duration position) {
    if (_player.playing) {
      _ensurePlaybackAnchor();
      final driftMs =
          (position.inMilliseconds - _reportedPosition.inMilliseconds).abs();
      if (driftMs >= _anchorRecalibrateDriftMs) {
        _anchorPosition = position;
        _anchorWallTime = DateTime.now();
      }
      return;
    }
    _emitPosition(position);
  }

  void _publishCurrentPosition() {
    _emitPosition(_reportedPosition);
  }

  void _resetPlaybackAnchor({Duration? position, bool? playing}) {
    _anchorPosition = position ?? _player.position;
    final isPlaying = playing ?? _player.playing;
    _anchorWallTime = isPlaying ? DateTime.now() : null;
  }

  void _handlePlayingChanged(bool playing) {
    if (!_playingController.isClosed) {
      _playingController.add(playing);
    }
    if (playing) {
      _resetPlaybackAnchor(playing: true);
      _startPositionRefresh();
    } else {
      _anchorWallTime = null;
      _stopPositionRefresh();
      _publishCurrentPosition();
    }
  }

  void _startPositionRefresh() {
    _stopPositionRefresh();
    _publishCurrentPosition();
    _positionRefreshTimer = Timer.periodic(
      _positionRefreshInterval,
      (_) => _publishCurrentPosition(),
    );
  }

  void _stopPositionRefresh() {
    _positionRefreshTimer?.cancel();
    _positionRefreshTimer = null;
  }

  @override
  Future<void> open(Uri url) async {
    _isReady = false;
    if (kIsWeb) {
      await _player.setWebCrossOrigin(WebCrossOrigin.anonymous);
    }
    await _player.setUrl(url.toString());
    await _waitUntilReady();
    _isReady = true;
    await _waitForUsableDuration();
    if (!_durationController.isClosed) {
      _durationController.add(_player.duration);
    }
    _publishCurrentPosition();
  }

  bool _hasUsableDuration(Duration? duration) {
    return duration != null && duration > Duration.zero;
  }

  Future<void> _waitUntilReady() async {
    final currentState = _player.processingState;
    if (currentState == ProcessingState.ready ||
        currentState == ProcessingState.completed) {
      return;
    }

    try {
      await _player.processingStateStream
          .firstWhere(
            (state) =>
                state == ProcessingState.ready ||
                state == ProcessingState.completed,
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw LessonMediaLoadException('音声の読み込みがタイムアウトしました。');
    }
  }

  Future<void> _waitForUsableDuration() async {
    if (_hasUsableDuration(_player.duration)) {
      return;
    }

    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (_hasUsableDuration(_player.duration)) {
        return;
      }
    }

    try {
      await _player.durationStream
          .firstWhere(_hasUsableDuration)
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
      return;
    }
  }

  @override
  Future<void> play() async {
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(_player.position);
    }
    await _player.play();
    _resetPlaybackAnchor(playing: true);
    _publishCurrentPosition();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _anchorWallTime = null;
    _stopPositionRefresh();
    _publishCurrentPosition();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _resetPlaybackAnchor(position: position, playing: _player.playing);
    _publishCurrentPosition();
  }

  @override
  Future<void> disposePlayer() async {
    _isReady = false;
    _stopPositionRefresh();
    await _player.dispose();
    await _playingController.close();
    await _positionController.close();
    await _durationController.close();
  }
}

class VideoLessonMediaPlayback implements LessonMediaPlayback {
  VideoLessonMediaPlayback();

  VideoPlayerController? _controller;
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  bool _isReady = false;

  @override
  VideoPlayerController? get videoController => _controller;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Duration get position => _controller?.value.position ?? Duration.zero;

  @override
  Duration? get duration => _controller?.value.duration;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  bool get isReady => _isReady;

  @override
  Future<void> open(Uri url) async {
    _isReady = false;
    final controller = VideoPlayerController.networkUrl(url);
    _controller = controller;
    controller.addListener(_onControllerUpdate);
    await controller.initialize();
    _isReady = controller.value.isInitialized;
    _onControllerUpdate();
  }

  void _onControllerUpdate() {
    if (_controller == null) {
      return;
    }
    if (!_positionController.isClosed) {
      _positionController.add(_controller!.value.position);
    }
    if (!_durationController.isClosed) {
      _durationController.add(_controller!.value.duration);
    }
    _notifyPlaying();
  }

  void _notifyPlaying() {
    if (_controller == null || _playingController.isClosed) {
      return;
    }
    _playingController.add(_controller!.value.isPlaying);
  }

  @override
  Future<void> play() async {
    final controller = _controller;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero) {
      await controller.seekTo(controller.value.position);
    }
    await _controller?.play();
    _notifyPlaying();
  }

  @override
  Future<void> pause() async {
    await _controller?.pause();
    _notifyPlaying();
  }

  @override
  Future<void> seek(Duration position) async {
    await _controller?.seekTo(position);
    _onControllerUpdate();
  }

  @override
  Future<void> disposePlayer() async {
    _isReady = false;
    _controller?.removeListener(_onControllerUpdate);
    await _controller?.dispose();
    _controller = null;
    await _playingController.close();
    await _positionController.close();
    await _durationController.close();
  }
}

/// Test fake that mirrors audio playback: [position] reads are sub-second via a
/// wall clock, while [positionStream] still ticks once per second for display.
class WallClockFakeLessonMediaPlayback implements LessonMediaPlayback {
  WallClockFakeLessonMediaPlayback({
    Duration? totalDuration,
  }) : _totalDuration = totalDuration ?? const Duration(seconds: 90);

  final Duration _totalDuration;
  final List<Uri> openedUrls = [];
  Duration _storedPosition = Duration.zero;
  Duration _anchorPosition = Duration.zero;
  DateTime? _anchorWallTime;
  bool _isPlaying = false;
  bool _isReady = false;
  Timer? _streamTimer;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();

  @override
  VideoPlayerController? get videoController => null;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Duration get position {
    if (!_isPlaying) {
      return _storedPosition;
    }
    if (_anchorWallTime == null) {
      _anchorPosition = _storedPosition;
      _anchorWallTime = DateTime.now();
    }
    return _anchorPosition + DateTime.now().difference(_anchorWallTime!);
  }

  @override
  Duration? get duration => _totalDuration;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isReady => _isReady;

  @override
  Future<void> open(Uri url) async {
    openedUrls.add(url);
    _storedPosition = Duration.zero;
    _isReady = true;
    _positionController.add(_storedPosition);
    _durationController.add(_totalDuration);
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    _anchorPosition = _storedPosition;
    _anchorWallTime = DateTime.now();
    _playingController.add(true);
    _streamTimer?.cancel();
    _streamTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _storedPosition = Duration(seconds: position.inSeconds);
      _positionController.add(_storedPosition);
    });
    _positionController.add(_storedPosition);
  }

  @override
  Future<void> pause() async {
    _storedPosition = position;
    _streamTimer?.cancel();
    _streamTimer = null;
    _isPlaying = false;
    _anchorWallTime = null;
    _playingController.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    _storedPosition = position;
    _anchorPosition = position;
    _anchorWallTime = _isPlaying ? DateTime.now() : null;
    _positionController.add(_storedPosition);
  }

  @override
  Future<void> disposePlayer() async {
    _isReady = false;
    _streamTimer?.cancel();
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
  }
}

class FakeLessonMediaPlayback implements LessonMediaPlayback {
  FakeLessonMediaPlayback({
    Duration? totalDuration,
    Duration? naturalEndPosition,
    this.openDelay = Duration.zero,
    this.suppressPeriodicPositionTicks = false,
    this.republishPositionOnPause = false,
  }) : _totalDuration = totalDuration ?? const Duration(seconds: 90),
       _naturalEndPosition = naturalEndPosition;

  final Duration _totalDuration;
  final Duration? _naturalEndPosition;
  final Duration openDelay;
  final bool suppressPeriodicPositionTicks;

  /// When true, mimics [AudioLessonMediaPlayback.pause] re-publishing its
  /// last known position as a side effect of pausing. Real audio playback
  /// does this; most fakes/tests don't need to reproduce it, so it is
  /// opt-in to avoid changing existing test behavior.
  final bool republishPositionOnPause;
  final List<Uri> openedUrls = [];
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isReady = false;
  Timer? _timer;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();

  @override
  VideoPlayerController? get videoController => null;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Duration get position => _position;

  @override
  Duration? get duration => _totalDuration;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isReady => _isReady;

  @override
  Future<void> open(Uri url) async {
    openedUrls.add(url);
    if (openDelay > Duration.zero) {
      await Future<void>.delayed(openDelay);
    }
    _position = Duration.zero;
    _isReady = true;
    _positionController.add(_position);
    _durationController.add(_totalDuration);
  }

  @override
  Future<void> play() async {
    if (_position >= _totalDuration) {
      _position = Duration.zero;
      _positionController.add(_position);
    }
    _timer?.cancel();
    _isPlaying = true;
    _playingController.add(true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final stopAt = _naturalEndPosition ?? _totalDuration;
      if (_position >= stopAt) {
        if (_position > stopAt) {
          _position = stopAt;
          if (!suppressPeriodicPositionTicks) {
            _positionController.add(_position);
          }
        }
        unawaited(pause());
        return;
      }
      _position += const Duration(seconds: 1);
      if (_position > stopAt) {
        _position = stopAt;
      }
      if (!suppressPeriodicPositionTicks) {
        _positionController.add(_position);
      }
      if (_position >= stopAt) {
        unawaited(pause());
      }
    });
  }

  @override
  Future<void> pause() async {
    _timer?.cancel();
    _timer = null;
    _isPlaying = false;
    _playingController.add(false);
    if (republishPositionOnPause) {
      _positionController.add(_position);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionController.add(_position);
  }

  @override
  Future<void> disposePlayer() async {
    _isReady = false;
    _timer?.cancel();
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
  }
}
