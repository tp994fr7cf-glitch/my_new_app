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
  AudioLessonMediaPlayback() : _player = AudioPlayer();

  final AudioPlayer _player;
  bool _isReady = false;

  @override
  VideoPlayerController? get videoController => null;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  bool get isPlaying => _player.playing;

  @override
  bool get isReady => _isReady;

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
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> disposePlayer() async {
    _isReady = false;
    await _player.dispose();
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

class FakeLessonMediaPlayback implements LessonMediaPlayback {
  FakeLessonMediaPlayback({Duration? totalDuration})
    : _totalDuration = totalDuration ?? const Duration(seconds: 90);

  final Duration _totalDuration;
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
    _position = Duration.zero;
    _isReady = true;
    _positionController.add(_position);
    _durationController.add(_totalDuration);
  }

  @override
  Future<void> play() async {
    _timer?.cancel();
    _isPlaying = true;
    _playingController.add(true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_position >= _totalDuration) {
        unawaited(pause());
        return;
      }
      _position += const Duration(seconds: 1);
      _positionController.add(_position);
    });
  }

  @override
  Future<void> pause() async {
    _timer?.cancel();
    _timer = null;
    _isPlaying = false;
    _playingController.add(false);
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
