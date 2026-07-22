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
  Stream<void> get completedStream;
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

/// Temporary diagnostic logging to help track down a reported audio/video
/// segment-switch failure that could not be reproduced with fakes in tests.
/// Safe to remove once the root cause is confirmed; prints only, no
/// behavior change.
void _logPlayback(String message) {
  debugPrint('[LessonMediaSwitchDebug] $message');
}

/// Whether a video player's `isPlaying=false` update should be ignored
/// rather than treated as a real pause.
///
/// video_player/ExoPlayer report `isPlaying=false` whenever playback is
/// momentarily buffering (e.g. re-buffering right after a seek, or a brief
/// network stall), even though `play()` was never paused and playback
/// intends to resume as soon as buffering finishes. Propagating that as a
/// real pause incorrectly stops playback state upstream (observed as an
/// unwanted auto-pause near the end of a video segment, and whenever
/// rewinding, since rewinding always triggers a short buffering period).
bool shouldSuppressVideoPlayingUpdate({
  required bool isPlaying,
  required bool isBuffering,
}) {
  return !isPlaying && isBuffering;
}

/// Tracks completion from the user's play/pause intent rather than a native
/// player's momentary `isPlaying` value.
///
/// Video players commonly report `isPlaying=false` while a seek buffers even
/// though playback will resume automatically. Using that transient value to
/// re-arm completion loses the eventual natural-end event and prevents the
/// playlist from advancing.
@visibleForTesting
class LessonMediaCompletionState {
  bool _playRequested = false;
  bool _completionArmed = false;
  bool _completionReported = false;
  bool _seekInProgress = false;

  bool get playRequested => _playRequested;
  bool get completionArmed => _completionArmed;

  void reset() {
    _playRequested = false;
    _completionArmed = false;
    _completionReported = false;
    _seekInProgress = false;
  }

  void markPlayRequested() {
    _playRequested = true;
    _completionArmed = true;
    _completionReported = false;
  }

  void markPauseRequested() {
    _playRequested = false;
    _completionArmed = false;
  }

  void beginSeek() {
    _seekInProgress = true;
    _completionArmed = false;
  }

  void finishSeek({required Duration position, required Duration? duration}) {
    _seekInProgress = false;
    _completionReported = false;
    _completionArmed =
        _playRequested &&
        duration != null &&
        duration > Duration.zero &&
        position < duration;
  }

  void updateKnownDuration({
    required Duration position,
    required Duration? duration,
  }) {
    if (_seekInProgress ||
        _completionArmed ||
        _completionReported ||
        !_playRequested) {
      return;
    }
    _completionArmed =
        duration != null && duration > Duration.zero && position < duration;
  }

  bool consumeNaturalCompletion() {
    if (!_completionArmed || _completionReported) {
      return false;
    }
    _playRequested = false;
    _completionReported = true;
    _completionArmed = false;
    return true;
  }
}

class AudioLessonMediaPlayback implements LessonMediaPlayback {
  AudioLessonMediaPlayback() : _player = AudioPlayer() {
    _player.playingStream.listen(_handlePlayingChanged);
    _player.positionStream.listen(_onPlayerPositionUpdate);
    _player.processingStateStream.listen(_handleProcessingStateChanged);
    _player.durationStream.listen((duration) {
      _completionState.updateKnownDuration(
        position: _player.position,
        duration: duration,
      );
      if (!_durationController.isClosed) {
        _durationController.add(duration);
      }
    });
  }

  /// Treats `play` as a start command, without waiting for the whole playback
  /// session to end.
  ///
  /// `just_audio` deliberately keeps the Future returned by `AudioPlayer.play`
  /// pending until playback is paused, stopped, or completed. The playlist
  /// controller, however, needs this wrapper's Future to complete once the
  /// start command has been issued; otherwise a resumed audio segment keeps
  /// the playlist's seek lock held for the entire time it is playing.
  @visibleForTesting
  static Future<void> completePlayCommandOnStart({
    required Future<void> playbackUntilStopped,
    required VoidCallback onStarted,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) {
    unawaited(
      playbackUntilStopped.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          onError(error, stackTrace);
        },
      ),
    );
    onStarted();
    return Future<void>.value();
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
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  Timer? _positionRefreshTimer;
  Duration _anchorPosition = Duration.zero;
  DateTime? _anchorWallTime;
  bool _isReady = false;
  final LessonMediaCompletionState _completionState =
      LessonMediaCompletionState();
  bool? _lastReportedPlaying;

  @override
  VideoPlayerController? get videoController => null;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<void> get completedStream => _completedController.stream;

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
    if (!_playingController.isClosed && _lastReportedPlaying != playing) {
      _lastReportedPlaying = playing;
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

  void _handleProcessingStateChanged(ProcessingState state) {
    if (state != ProcessingState.completed ||
        !_completionState.consumeNaturalCompletion() ||
        _completedController.isClosed) {
      return;
    }
    _completedController.add(null);
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
    _logPlayback('AudioLessonMediaPlayback.open: url=$url');
    _isReady = false;
    _completionState.reset();
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
    _logPlayback(
      'AudioLessonMediaPlayback.open: done url=$url duration=${_player.duration}',
    );
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
    _logPlayback('AudioLessonMediaPlayback.play');
    final total = _player.duration;
    if (_player.processingState == ProcessingState.completed &&
        total != null &&
        total > Duration.zero &&
        _player.position >= total) {
      await _player.seek(Duration.zero);
      _resetPlaybackAnchor(position: Duration.zero, playing: false);
      _publishCurrentPosition();
    }
    _completionState.markPlayRequested();
    await completePlayCommandOnStart(
      playbackUntilStopped: _player.play(),
      onStarted: () {
        _resetPlaybackAnchor(playing: _player.playing);
        _publishCurrentPosition();
      },
      onError: (error, stackTrace) {
        _completionState.markPauseRequested();
        _logPlayback(
          'AudioLessonMediaPlayback.play: ERROR error=$error\n$stackTrace',
        );
      },
    );
  }

  @override
  Future<void> pause() async {
    _logPlayback('AudioLessonMediaPlayback.pause');
    // Disarm before awaiting the native player so a pause at (or very near)
    // the end cannot be mistaken for natural completion.
    _completionState.markPauseRequested();
    await _player.pause();
    _anchorWallTime = null;
    _stopPositionRefresh();
    _publishCurrentPosition();
  }

  @override
  Future<void> seek(Duration position) async {
    _logPlayback('AudioLessonMediaPlayback.seek: position=$position');
    _completionState.beginSeek();
    try {
      await _player.seek(position);
      _resetPlaybackAnchor(position: position, playing: _player.playing);
      _publishCurrentPosition();
    } finally {
      _completionState.finishSeek(
        position: _player.position,
        duration: _player.duration,
      );
    }
    _logPlayback('AudioLessonMediaPlayback.seek: done position=$position');
  }

  @override
  Future<void> disposePlayer() async {
    _isReady = false;
    _completionState.reset();
    _stopPositionRefresh();
    await _player.dispose();
    await _playingController.close();
    await _completedController.close();
    await _positionController.close();
    await _durationController.close();
  }
}

class VideoLessonMediaPlayback implements LessonMediaPlayback {
  VideoLessonMediaPlayback();

  VideoPlayerController? _controller;
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  bool _isReady = false;
  final LessonMediaCompletionState _completionState =
      LessonMediaCompletionState();
  bool? _lastReportedPlaying;

  @override
  VideoPlayerController? get videoController => _controller;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<void> get completedStream => _completedController.stream;

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
    _logPlayback('VideoLessonMediaPlayback.open: url=$url');
    _isReady = false;
    _completionState.reset();
    final controller = VideoPlayerController.networkUrl(url);
    _controller = controller;
    controller.addListener(_onControllerUpdate);
    await controller.initialize();
    _isReady = controller.value.isInitialized;
    _onControllerUpdate();
    _logPlayback(
      'VideoLessonMediaPlayback.open: done url=$url '
      'isInitialized=${controller.value.isInitialized} '
      'duration=${controller.value.duration}',
    );
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
    _completionState.updateKnownDuration(
      position: _controller!.value.position,
      duration: _controller!.value.duration,
    );
    _notifyPlaying();
    _notifyCompleted();
  }

  void _notifyPlaying() {
    final controller = _controller;
    if (controller == null || _playingController.isClosed) {
      return;
    }
    final value = controller.value;
    if (shouldSuppressVideoPlayingUpdate(
      isPlaying: value.isPlaying,
      isBuffering: value.isBuffering,
    )) {
      // Keep reporting whatever "playing" state was last known until
      // buffering resolves; see shouldSuppressVideoPlayingUpdate for why.
      _logPlayback(
        'VideoLessonMediaPlayback._notifyPlaying: suppressed '
        'isPlaying=${value.isPlaying} isBuffering=${value.isBuffering} '
        'position=${value.position}',
      );
      return;
    }
    if (_lastReportedPlaying != value.isPlaying) {
      _lastReportedPlaying = value.isPlaying;
      _playingController.add(value.isPlaying);
    }
  }

  void _notifyCompleted() {
    final controller = _controller;
    if (controller == null ||
        _completedController.isClosed ||
        !controller.value.isCompleted ||
        !_completionState.consumeNaturalCompletion()) {
      return;
    }
    _completedController.add(null);
  }

  @override
  Future<void> play() async {
    _logPlayback('VideoLessonMediaPlayback.play');
    final controller = _controller;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero) {
      await controller.seekTo(Duration.zero);
    }
    _completionState.markPlayRequested();
    try {
      await _controller?.play();
      _notifyPlaying();
    } catch (_) {
      _completionState.markPauseRequested();
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    _logPlayback('VideoLessonMediaPlayback.pause');
    _completionState.markPauseRequested();
    await _controller?.pause();
    _notifyPlaying();
  }

  @override
  Future<void> seek(Duration position) async {
    _logPlayback('VideoLessonMediaPlayback.seek: position=$position');
    _completionState.beginSeek();
    try {
      await _controller?.seekTo(position);
      _onControllerUpdate();
    } finally {
      final controller = _controller;
      _completionState.finishSeek(
        position: controller?.value.position ?? position,
        duration: controller?.value.duration,
      );
    }
    _logPlayback(
      'VideoLessonMediaPlayback.seek: done position=$position '
      'actualPosition=${_controller?.value.position}',
    );
  }

  @override
  Future<void> disposePlayer() async {
    _isReady = false;
    _completionState.reset();
    _controller?.removeListener(_onControllerUpdate);
    await _controller?.dispose();
    _controller = null;
    await _playingController.close();
    await _completedController.close();
    await _positionController.close();
    await _durationController.close();
  }
}

/// Test fake that mirrors audio playback: [position] reads are sub-second via a
/// wall clock, while [positionStream] still ticks once per second for display.
class WallClockFakeLessonMediaPlayback implements LessonMediaPlayback {
  WallClockFakeLessonMediaPlayback({Duration? totalDuration})
    : _totalDuration = totalDuration ?? const Duration(seconds: 90);

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
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();

  @override
  VideoPlayerController? get videoController => null;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<void> get completedStream => _completedController.stream;

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
    await _completedController.close();
  }
}

class FakeLessonMediaPlayback implements LessonMediaPlayback {
  FakeLessonMediaPlayback({
    Duration? totalDuration,
    this.naturalEndPosition,
    this.openDelay = Duration.zero,
    this.seekDelay = Duration.zero,
    this.pauseDelay = Duration.zero,
    this.suppressPeriodicPositionTicks = false,
    this.republishPositionOnPause = false,
  }) : _totalDuration = totalDuration ?? const Duration(seconds: 90);

  final Duration _totalDuration;
  final Duration? naturalEndPosition;
  final Duration openDelay;

  /// Artificial delay before a seek() call resolves, used to simulate a
  /// slow/real native seek and reproduce races between overlapping seeks.
  final Duration seekDelay;
  final Duration pauseDelay;
  final bool suppressPeriodicPositionTicks;

  /// When true, mimics [AudioLessonMediaPlayback.pause] re-publishing its
  /// last known position as a side effect of pausing. Real audio playback
  /// does this; most fakes/tests don't need to reproduce it, so it is
  /// opt-in to avoid changing existing test behavior.
  final bool republishPositionOnPause;
  final List<Uri> openedUrls = [];

  /// Every position (in seconds) that [seek] was called with, in order.
  final List<double> seekCallsSec = [];
  int pauseCallCount = 0;
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
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();

  @override
  VideoPlayerController? get videoController => null;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<void> get completedStream => _completedController.stream;

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
      final stopAt = naturalEndPosition ?? _totalDuration;
      if (_position >= stopAt) {
        if (_position > stopAt) {
          _position = stopAt;
          if (!suppressPeriodicPositionTicks) {
            _positionController.add(_position);
          }
        }
        unawaited(simulateNaturalCompletion());
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
        unawaited(simulateNaturalCompletion());
      }
    });
  }

  @override
  Future<void> pause() async {
    pauseCallCount += 1;
    if (pauseDelay > Duration.zero) {
      await Future<void>.delayed(pauseDelay);
    }
    _timer?.cancel();
    _timer = null;
    _isPlaying = false;
    _playingController.add(false);
    if (republishPositionOnPause) {
      _positionController.add(_position);
    }
  }

  /// Test hook that models a native player's distinct natural-end event.
  ///
  /// [emitStoppedFirst] reproduces players that publish `playing=false`
  /// before their completion state.
  Future<void> simulateNaturalCompletion({
    bool emitStoppedFirst = false,
  }) async {
    _timer?.cancel();
    _timer = null;
    if (emitStoppedFirst) {
      _isPlaying = false;
      _playingController.add(false);
    }
    _completedController.add(null);
    if (!emitStoppedFirst) {
      _isPlaying = false;
      _playingController.add(false);
    }
  }

  /// Test hook for reproducing duplicate native playing-state emissions.
  void emitPlayingState(bool playing) {
    _isPlaying = playing;
    _playingController.add(playing);
  }

  @override
  Future<void> seek(Duration position) async {
    seekCallsSec.add(position.inMilliseconds / 1000);
    if (seekDelay > Duration.zero) {
      await Future<void>.delayed(seekDelay);
    }
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
    await _completedController.close();
  }
}
