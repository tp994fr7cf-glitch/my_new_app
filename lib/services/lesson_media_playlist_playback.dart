import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/lesson_media_segment.dart';
import '../models/lesson_media_timeline.dart';
import 'lesson_media_playback.dart';

typedef LessonMediaPlaylistPlaybackFactory =
    LessonMediaPlaylistController Function();

/// Temporary diagnostic logging to help track down a reported audio/video
/// segment-switch failure that could not be reproduced with fakes in tests.
/// Safe to remove once the root cause is confirmed; prints only, no
/// behavior change.
void _logSwitch(String message) {
  debugPrint('[LessonMediaSwitchDebug] $message');
}

abstract class LessonMediaPlaylistController {
  Stream<double> get globalPositionStream;
  Stream<int> get totalDurationStream;
  Stream<bool> get playingStream;
  Stream<int> get segmentIndexStream;

  double get globalPositionSec;
  double get liveGlobalPositionSec;
  int get totalDurationSec;
  int get currentSegmentIndex;
  bool get isPlaying;
  bool get isReady;
  bool get hasSegments;
  bool get currentSegmentIsAudio;

  LessonMediaSegment? get currentSegment;
  VideoPlayerController? get videoController;

  Future<void> openSegments(List<LessonMediaSegment> segments);
  Future<void> play();
  Future<void> pause();
  Future<void> seekGlobal(double globalSec);
  Future<void> seekToSegmentIndex(int segmentIndex);
  Future<void> disposePlayer();
  Future<void> close();
}

class _MediaPlayerSlot {
  _MediaPlayerSlot({
    required this.isAudio,
    required this.createPlayer,
  });

  final bool isAudio;
  final LessonMediaPlayback Function() createPlayer;
  LessonMediaPlayback? _player;
  int? loadedSegmentIndex;
  String? loadedUrl;
  Future<void>? _prepareFuture;

  LessonMediaPlayback get player => _player ??= createPlayer();

  bool isPreparedFor(int segmentIndex, String url) {
    return loadedSegmentIndex == segmentIndex &&
        loadedUrl == url &&
        player.isReady;
  }
}

class LessonMediaPlaylistPlayback implements LessonMediaPlaylistController {
  LessonMediaPlaylistPlayback({
    LessonMediaPlaybackFactory? playbackFactory,
  }) : _playbackFactory = playbackFactory ?? createLessonMediaPlayback;

  final LessonMediaPlaybackFactory _playbackFactory;
  final StreamController<double> _globalPositionController =
      StreamController<double>.broadcast();
  final StreamController<int> _totalDurationController =
      StreamController<int>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<int> _segmentIndexController =
      StreamController<int>.broadcast();

  LessonMediaTimeline _timeline = const LessonMediaTimeline(segments: []);
  LessonMediaPlayback? _activePlayer;
  _MediaPlayerSlot? _audioSlot;
  _MediaPlayerSlot? _videoSlot;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;

  int _currentSegmentIndex = 0;
  double _globalPositionSec = 0;
  int _totalDurationSec = 0;
  bool _isReady = false;
  bool _isPlaying = false;
  bool _autoAdvanceEnabled = true;
  bool _isSwitchingSegment = false;
  bool _isAdvancing = false;
  double? _pendingSeekGlobalSec;
  bool _seekInProgress = false;

  Stream<double> get globalPositionStream => _globalPositionController.stream;
  Stream<int> get totalDurationStream => _totalDurationController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<int> get segmentIndexStream => _segmentIndexController.stream;

  double get globalPositionSec => _globalPositionSec;

  double get liveGlobalPositionSec {
    if (_timeline.isEmpty || _activePlayer == null || _isSwitchingSegment) {
      return _globalPositionSec;
    }
    final localSec = _activePlayer!.position.inMilliseconds / 1000;
    return _timeline.globalSecForSegmentIndex(
      segmentIndex: _currentSegmentIndex,
      localSec: localSec,
    );
  }

  int get totalDurationSec => _totalDurationSec;
  int get currentSegmentIndex => _currentSegmentIndex;
  bool get isPlaying => _isPlaying;
  bool get isReady => _isReady;
  bool get hasSegments => _timeline.segmentCount > 0;

  LessonMediaSegment? get currentSegment {
    final ordered = _timeline.orderedSegments;
    if (_currentSegmentIndex < 0 || _currentSegmentIndex >= ordered.length) {
      return null;
    }
    return ordered[_currentSegmentIndex];
  }

  bool get currentSegmentIsAudio => currentSegment?.isAudio ?? true;

  VideoPlayerController? get videoController => _activePlayer?.videoController;

  Future<void> openSegments(List<LessonMediaSegment> segments) async {
    await disposePlayer();
    _timeline = LessonMediaTimeline(
      segments: LessonMediaSegment.normalizeOrders(segments),
    );
    _totalDurationSec = _timeline.totalDurationSec;
    _totalDurationController.add(_totalDurationSec);
    _globalPositionSec = 0;
    _globalPositionController.add(_globalPositionSec);
    _currentSegmentIndex = 0;
    _segmentIndexController.add(_currentSegmentIndex);

    if (_timeline.isEmpty) {
      _isReady = true;
      return;
    }

    await _activateSegment(0, localStartSec: 0);
  }

  _MediaPlayerSlot _slotForSegment(LessonMediaSegment segment) {
    if (segment.isAudio) {
      return _audioSlot ??= _MediaPlayerSlot(
        isAudio: true,
        createPlayer: () => _playbackFactory(isAudio: true),
      );
    }
    return _videoSlot ??= _MediaPlayerSlot(
      isAudio: false,
      createPlayer: () => _playbackFactory(isAudio: false),
    );
  }

  Future<void> _prepareSegmentInSlot(
    int segmentIndex, {
    double localStartSec = 0,
    bool repositionIfAlreadyPrepared = true,
  }) async {
    final ordered = _timeline.orderedSegments;
    if (segmentIndex < 0 || segmentIndex >= ordered.length) {
      return;
    }

    final segment = ordered[segmentIndex];
    if (!segment.hasUrl) {
      return;
    }

    final slot = _slotForSegment(segment);
    final url = segment.url.trim();
    final targetLocalSec = localStartSec.clamp(
      0.0,
      segment.durationSec.toDouble(),
    );

    _logSwitch(
      '_prepareSegmentInSlot start: segmentIndex=$segmentIndex '
      'isAudio=${slot.isAudio} targetLocalSec=$targetLocalSec '
      'repositionIfAlreadyPrepared=$repositionIfAlreadyPrepared '
      'loadedSegmentIndex=${slot.loadedSegmentIndex} '
      'playerIsReady=${slot._player?.isReady} '
      'hasPendingPrepare=${slot._prepareFuture != null}',
    );

    // Always funnel work on this slot through the same completer, even when
    // it looks already-prepared. Without this, a preload "touch" of an
    // already-open slot and a real activation seek for that same slot could
    // both issue native seek() calls to the underlying player concurrently,
    // with no guarantee about which one the player ends up honoring.
    final previousPrepare = slot._prepareFuture;
    final prepareCompleter = Completer<void>();
    slot._prepareFuture = prepareCompleter.future;
    await previousPrepare;
    try {
      if (slot.isPreparedFor(segmentIndex, url)) {
        if (repositionIfAlreadyPrepared) {
          _logSwitch(
            '_prepareSegmentInSlot: already prepared, seeking to '
            '$targetLocalSec (isAudio=${slot.isAudio})',
          );
          await slot.player.seek(
            Duration(milliseconds: (targetLocalSec * 1000).round()),
          );
        } else {
          _logSwitch(
            '_prepareSegmentInSlot: already prepared, skipping reposition '
            '(isAudio=${slot.isAudio})',
          );
        }
        return;
      }

      _logSwitch(
        '_prepareSegmentInSlot: not prepared, opening url (isAudio=${slot.isAudio})',
      );
      if (slot.player.isPlaying) {
        await slot.player.pause();
      }
      await slot.player.open(Uri.parse(url));
      slot.loadedSegmentIndex = segmentIndex;
      slot.loadedUrl = url;
      if (targetLocalSec > 0) {
        await slot.player.seek(
          Duration(milliseconds: (targetLocalSec * 1000).round()),
        );
      }
      _logSwitch(
        '_prepareSegmentInSlot: opened+seeked (isAudio=${slot.isAudio}) '
        'segmentIndex=$segmentIndex',
      );
    } catch (error, stackTrace) {
      _logSwitch(
        '_prepareSegmentInSlot: ERROR segmentIndex=$segmentIndex '
        'isAudio=${slot.isAudio} error=$error\n$stackTrace',
      );
      rethrow;
    } finally {
      if (!prepareCompleter.isCompleted) {
        prepareCompleter.complete();
      }
      if (identical(slot._prepareFuture, prepareCompleter.future)) {
        slot._prepareFuture = null;
      }
    }
  }

  Future<void> _preloadNextSegment(int segmentIndex) async {
    if (segmentIndex < 0 || segmentIndex >= _timeline.segmentCount) {
      return;
    }
    _logSwitch('_preloadNextSegment: segmentIndex=$segmentIndex');
    try {
      // Only ensure the segment is open/buffered; don't reposition it. It
      // may already be prepared at a meaningful position (e.g. we just
      // switched away from it moments ago), and resetting it to 0 here
      // serves no preloading purpose while risking a race with a genuine
      // seek back into this same segment shortly after.
      await _prepareSegmentInSlot(
        segmentIndex,
        repositionIfAlreadyPrepared: false,
      );
    } catch (error) {
      // Preload failures should not interrupt active playback.
      _logSwitch('_preloadNextSegment: FAILED segmentIndex=$segmentIndex error=$error');
    }
  }

  Future<void> _activateSegment(
    int segmentIndex, {
    required double localStartSec,
    bool? resumePlaying,
  }) async {
    final ordered = _timeline.orderedSegments;
    if (segmentIndex < 0 || segmentIndex >= ordered.length) {
      return;
    }

    _logSwitch(
      '_activateSegment start: segmentIndex=$segmentIndex '
      'localStartSec=$localStartSec resumePlaying=$resumePlaying '
      'currentSegmentIndex=$_currentSegmentIndex',
    );

    _isSwitchingSegment = true;
    var shouldResumePlaying = false;
    try {
      final segment = ordered[segmentIndex];
      if (!segment.hasUrl) {
        _isReady = false;
        _logSwitch(
          '_activateSegment ABORT: segmentIndex=$segmentIndex has no url',
        );
        return;
      }

      shouldResumePlaying = resumePlaying == true;

      if (_activePlayer != null && _activePlayer!.isPlaying) {
        await _activePlayer!.pause();
      }

      await _prepareSegmentInSlot(
        segmentIndex,
        localStartSec: localStartSec,
      );

      final slot = _slotForSegment(segment);
      await _detachActiveSubscriptions();

      _activePlayer = slot.player;
      _currentSegmentIndex = segmentIndex;

      final targetLocalSec = localStartSec.clamp(
        0.0,
        segment.durationSec.toDouble(),
      );
      _globalPositionSec = _timeline.globalSecForSegmentIndex(
        segmentIndex: segmentIndex,
        localSec: targetLocalSec,
      );
      _globalPositionController.add(_globalPositionSec);
      _segmentIndexController.add(_currentSegmentIndex);
      _attachActiveSubscriptions();

      _isReady = slot.player.isReady;
      _emitTotalDuration();

      unawaited(_preloadNextSegment(segmentIndex + 1));
      _logSwitch(
        '_activateSegment done: segmentIndex=$segmentIndex '
        'globalPositionSec=$_globalPositionSec isReady=$_isReady',
      );
    } catch (error, stackTrace) {
      _logSwitch(
        '_activateSegment ERROR: segmentIndex=$segmentIndex error=$error\n$stackTrace',
      );
      rethrow;
    } finally {
      _isSwitchingSegment = false;
      _syncActivePlaybackPosition(forceEmit: true);
      if (shouldResumePlaying) {
        await play();
      }
    }
  }

  void _attachActiveSubscriptions() {
    final player = _activePlayer;
    if (player == null) {
      return;
    }
    _positionSubscription = player.positionStream.listen(_handleLocalPosition);
    _durationSubscription = player.durationStream.listen((_) {
      _emitTotalDuration();
    });
    _playingSubscription = player.playingStream.listen(_handlePlayingUpdate);
  }

  Future<void> _detachActiveSubscriptions() async {
    await _positionSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _playingSubscription?.cancel();
    _positionSubscription = null;
    _durationSubscription = null;
    _playingSubscription = null;
  }

  void _syncActivePlaybackPosition({bool forceEmit = false}) {
    if (_isSwitchingSegment || _timeline.isEmpty || _activePlayer == null) {
      return;
    }
    final segment = currentSegment;
    if (segment == null) {
      return;
    }

    final localSec = _activePlayer!.position.inMilliseconds / 1000;
    final globalSec = _timeline.globalSecForSegmentIndex(
      segmentIndex: _currentSegmentIndex,
      localSec: localSec,
    );
    final changed = (globalSec - _globalPositionSec).abs() >= 0.01;
    if (!changed && !forceEmit) {
      return;
    }

    _globalPositionSec = globalSec;
    _globalPositionController.add(_globalPositionSec);
  }

  void _handleLocalPosition(Duration localPosition) {
    if (_isSwitchingSegment) {
      return;
    }
    final segment = currentSegment;
    if (segment == null) {
      return;
    }

    final localSec = localPosition.inMilliseconds / 1000;
    _globalPositionSec = _timeline.globalSecForSegmentIndex(
      segmentIndex: _currentSegmentIndex,
      localSec: localSec,
    );
    _globalPositionController.add(_globalPositionSec);

    final segmentDuration = segment.durationSec.toDouble();
    if (_isPlaying &&
        _autoAdvanceEnabled &&
        segmentDuration > 0 &&
        localSec >= segmentDuration - 0.05) {
      unawaited(_advanceToNextSegmentOrStop());
    }
  }

  Future<void> _advanceToNextSegmentOrStop() async {
    if (_isSwitchingSegment || _isAdvancing) {
      return;
    }
    _isAdvancing = true;
    try {
      final nextIndex = _currentSegmentIndex + 1;
      final ordered = _timeline.orderedSegments;
      if (nextIndex >= ordered.length) {
        _globalPositionSec = _totalDurationSec.toDouble();
        _globalPositionController.add(_globalPositionSec);
        await pause();
        return;
      }

      final wasPlaying = _isPlaying;
      await _activateSegment(
        nextIndex,
        localStartSec: 0,
        resumePlaying: wasPlaying,
      );
    } finally {
      _isAdvancing = false;
    }
  }

  void _handlePlayingUpdate(bool isPlaying) {
    if (_isSwitchingSegment) {
      return;
    }
    _isPlaying = isPlaying;
    _playingController.add(isPlaying);
  }

  void _emitTotalDuration() {
    final timelineTotal = _timeline.totalDurationSec;
    if (timelineTotal > 0) {
      _totalDurationSec = timelineTotal;
    } else {
      _totalDurationSec = _activePlayer?.duration?.inSeconds ?? 0;
    }
    _totalDurationController.add(_totalDurationSec);
  }

  Future<void> play() async {
    if (_activePlayer == null) {
      return;
    }
    if (_globalPositionSec >= _totalDurationSec && _totalDurationSec > 0) {
      await seekGlobal(0);
    }
    _logSwitch('play: currentSegmentIndex=$_currentSegmentIndex');
    await _activePlayer!.play();
    _isPlaying = true;
    _playingController.add(true);
    _syncActivePlaybackPosition(forceEmit: true);
  }

  Future<void> pause() async {
    _logSwitch('pause: currentSegmentIndex=$_currentSegmentIndex');
    await _activePlayer?.pause();
    _isPlaying = false;
    _playingController.add(false);
  }

  Future<void> seekGlobal(double globalSec) async {
    if (_timeline.isEmpty) {
      return;
    }

    _logSwitch(
      'seekGlobal called: globalSec=$globalSec '
      'seekInProgress=$_seekInProgress '
      'currentSegmentIndex=$_currentSegmentIndex',
    );

    _pendingSeekGlobalSec = globalSec.clamp(
      0.0,
      _totalDurationSec.toDouble(),
    );
    if (_seekInProgress) {
      _logSwitch(
        'seekGlobal: another seek already in progress, queued '
        'target=$_pendingSeekGlobalSec',
      );
      return;
    }

    _seekInProgress = true;
    try {
      while (_pendingSeekGlobalSec != null) {
        final target = _pendingSeekGlobalSec!;
        _pendingSeekGlobalSec = null;
        await _seekGlobalImmediate(target);
      }
    } catch (error, stackTrace) {
      _logSwitch('seekGlobal: ERROR globalSec=$globalSec error=$error\n$stackTrace');
      rethrow;
    } finally {
      // Always clear this even if a segment activation above throws (e.g.
      // the new segment's media fails to load), so a single failed seek
      // does not permanently block all future seeks.
      _pendingSeekGlobalSec = null;
      _seekInProgress = false;
      _logSwitch('seekGlobal: finished globalSec=$globalSec');
    }
  }

  Future<void> _seekGlobalImmediate(double globalSec) async {
    final position = _timeline.resolveGlobalSec(globalSec);
    _logSwitch(
      '_seekGlobalImmediate: globalSec=$globalSec -> '
      'segmentIndex=${position.segmentIndex} localSec=${position.localSec} '
      'currentSegmentIndex=$_currentSegmentIndex '
      'crossSegment=${position.segmentIndex != _currentSegmentIndex}',
    );
    if (position.segmentIndex != _currentSegmentIndex) {
      final wasPlaying = _isPlaying;
      // Mark the switch as starting immediately, before pausing the
      // about-to-be-abandoned player. Pausing a real audio player can
      // republish its last known (pre-seek) position as a side effect; if
      // that happens before this flag is set, the stale position briefly
      // (or persistently, if activation is slow) overwrites the freshly
      // requested segment's position on screen.
      _isSwitchingSegment = true;
      try {
        if (wasPlaying) {
          await pause();
        }
        await _activateSegment(
          position.segmentIndex,
          localStartSec: position.localSec,
          resumePlaying: false,
        );
        if (wasPlaying) {
          await play();
        }
      } catch (error, stackTrace) {
        debugPrint(
          'LessonMediaPlaylistPlayback: cross-segment seek to '
          '${position.segmentIndex} failed: $error\n$stackTrace',
        );
        rethrow;
      } finally {
        _isSwitchingSegment = false;
      }
      return;
    }

    _logSwitch(
      '_seekGlobalImmediate: same-segment seek to localSec=${position.localSec} '
      'segmentIndex=${position.segmentIndex}',
    );
    await _activePlayer?.seek(
      Duration(milliseconds: (position.localSec * 1000).round()),
    );
    _globalPositionSec = position.globalSec;
    _globalPositionController.add(_globalPositionSec);
  }

  Future<void> seekToSegmentIndex(int segmentIndex) async {
    if (segmentIndex < 0 || segmentIndex >= _timeline.segmentCount) {
      return;
    }
    final globalSec = _timeline.startGlobalSecForSegmentIndex(segmentIndex);
    await seekGlobal(globalSec);
  }

  Future<void> disposePlayer() async {
    _isReady = false;
    _isPlaying = false;
    _pendingSeekGlobalSec = null;
    await _disposeAllSlots();
    _timeline = const LessonMediaTimeline(segments: []);
    _currentSegmentIndex = 0;
    _globalPositionSec = 0;
    _totalDurationSec = 0;
  }

  Future<void> close() async {
    await disposePlayer();
    await _globalPositionController.close();
    await _totalDurationController.close();
    await _playingController.close();
    await _segmentIndexController.close();
  }

  Future<void> _disposeAllSlots() async {
    await _detachActiveSubscriptions();
    if (_audioSlot != null) {
      await _audioSlot!.player.disposePlayer();
      _audioSlot = null;
    }
    if (_videoSlot != null) {
      await _videoSlot!.player.disposePlayer();
      _videoSlot = null;
    }
    _activePlayer = null;
  }
}

LessonMediaPlaylistController createLessonMediaPlaylistPlayback() {
  return LessonMediaPlaylistPlayback();
}

class FakeLessonMediaPlaylistPlayback implements LessonMediaPlaylistController {
  FakeLessonMediaPlaylistPlayback({
    this.totalDurationSec = 90,
    List<LessonMediaSegment>? segments,
  }) : _segments = List<LessonMediaSegment>.from(
         segments ??
             [
               LessonMediaSegment(
                 id: 'fake-segment',
                 order: 0,
                 mediaType: 'audio',
                 url: 'https://example.com/fake.mp3',
                 durationSec: totalDurationSec,
               ),
             ],
       );

  final int totalDurationSec;
  final List<LessonMediaSegment> _segments;
  final StreamController<double> _globalPositionController =
      StreamController<double>.broadcast();
  final StreamController<int> _totalDurationController =
      StreamController<int>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<int> _segmentIndexController =
      StreamController<int>.broadcast();

  double _globalPositionSec = 0;
  bool _isReady = false;
  bool _isPlaying = false;
  int _currentSegmentIndex = 0;
  Timer? _timer;

  Stream<double> get globalPositionStream => _globalPositionController.stream;
  Stream<int> get totalDurationStream => _totalDurationController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<int> get segmentIndexStream => _segmentIndexController.stream;

  double get globalPositionSec => _globalPositionSec;
  double get liveGlobalPositionSec => _globalPositionSec;
  int get currentSegmentIndex => _currentSegmentIndex;
  bool get isPlaying => _isPlaying;
  bool get isReady => _isReady;
  bool get hasSegments => _segments.isNotEmpty;
  bool get currentSegmentIsAudio => currentSegment?.isAudio ?? true;

  LessonMediaSegment? get currentSegment {
    if (_currentSegmentIndex < 0 || _currentSegmentIndex >= _segments.length) {
      return null;
    }
    return _segments[_currentSegmentIndex];
  }

  VideoPlayerController? get videoController => null;

  Future<void> openSegments(List<LessonMediaSegment> segments) async {
    _segments
      ..clear()
      ..addAll(segments);
    _isReady = true;
    _globalPositionSec = 0;
    _globalPositionController.add(_globalPositionSec);
    _totalDurationController.add(totalDurationSec);
    _segmentIndexController.add(_currentSegmentIndex);
  }

  Future<void> play() async {
    if (_globalPositionSec >= totalDurationSec) {
      await seekGlobal(0);
    }
    _timer?.cancel();
    _isPlaying = true;
    _playingController.add(true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _globalPositionSec + 1;
      if (next > totalDurationSec) {
        unawaited(pause());
        return;
      }
      _globalPositionSec = next;
      _globalPositionController.add(_globalPositionSec);
    });
  }

  Future<void> pause() async {
    _timer?.cancel();
    _timer = null;
    _isPlaying = false;
    _playingController.add(false);
  }

  Future<void> seekGlobal(double globalSec) async {
    _globalPositionSec = globalSec.clamp(0, totalDurationSec.toDouble());
    _globalPositionController.add(_globalPositionSec);
  }

  Future<void> seekToSegmentIndex(int segmentIndex) async {
    _currentSegmentIndex = segmentIndex.clamp(0, _segments.length - 1);
    _segmentIndexController.add(_currentSegmentIndex);
  }

  Future<void> disposePlayer() async {
    _timer?.cancel();
    _isReady = false;
    _isPlaying = false;
  }

  Future<void> close() async {
    await disposePlayer();
    await _globalPositionController.close();
    await _totalDurationController.close();
    await _playingController.close();
    await _segmentIndexController.close();
  }
}
