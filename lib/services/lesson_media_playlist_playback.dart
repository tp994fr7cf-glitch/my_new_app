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
  Stream<int> get segmentCompletedStream;

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
  Future<void> seekToSegmentIndex(int segmentIndex, {double localStartSec = 0});
  Future<void> disposePlayer();
  Future<void> close();
}

class _MediaPlayerSlot {
  _MediaPlayerSlot({required this.isAudio, required this.createPlayer});

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

class _PlaylistSeekTarget {
  const _PlaylistSeekTarget({
    required this.globalSec,
    this.segmentIndex,
    this.localSec,
  });

  final double globalSec;
  final int? segmentIndex;
  final double? localSec;
}

class LessonMediaPlaylistPlayback implements LessonMediaPlaylistController {
  LessonMediaPlaylistPlayback({LessonMediaPlaybackFactory? playbackFactory})
    : _playbackFactory = playbackFactory ?? createLessonMediaPlayback;

  final LessonMediaPlaybackFactory _playbackFactory;
  final StreamController<double> _globalPositionController =
      StreamController<double>.broadcast();
  final StreamController<int> _totalDurationController =
      StreamController<int>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<int> _segmentIndexController =
      StreamController<int>.broadcast();
  final StreamController<int> _segmentCompletedController =
      StreamController<int>.broadcast();

  LessonMediaTimeline _timeline = const LessonMediaTimeline(segments: []);
  LessonMediaPlayback? _activePlayer;
  _MediaPlayerSlot? _activeSlot;
  _MediaPlayerSlot? _audioSlot;
  _MediaPlayerSlot? _videoSlot;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<void>? _completedSubscription;

  int _currentSegmentIndex = 0;
  double _globalPositionSec = 0;
  int _totalDurationSec = 0;
  bool _isReady = false;
  bool _isPlaying = false;
  final bool _autoAdvanceEnabled = true;
  bool _isSwitchingSegment = false;
  bool _isAdvancing = false;
  bool _isResetting = false;
  _PlaylistSeekTarget? _pendingSeekTarget;
  Future<void>? _seekDrainFuture;

  /// Bumped every time a user/UI-initiated [play] or [pause] call actually
  /// runs. Used to detect "did the user tap play/pause again while a
  /// segment switch I started earlier was still in flight" without ever
  /// delaying or dropping that tap (see [play] / [pause]).
  int _playbackIntentGeneration = 0;

  @override
  Stream<double> get globalPositionStream => _globalPositionController.stream;
  @override
  Stream<int> get totalDurationStream => _totalDurationController.stream;
  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<int> get segmentIndexStream => _segmentIndexController.stream;
  @override
  Stream<int> get segmentCompletedStream => _segmentCompletedController.stream;

  @override
  double get globalPositionSec => _globalPositionSec;

  @override
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

  @override
  int get totalDurationSec => _totalDurationSec;
  @override
  int get currentSegmentIndex => _currentSegmentIndex;
  @override
  bool get isPlaying => _isPlaying;
  @override
  bool get isReady => _isReady;
  @override
  bool get hasSegments => _timeline.segmentCount > 0;

  @override
  LessonMediaSegment? get currentSegment {
    final ordered = _timeline.orderedSegments;
    if (_currentSegmentIndex < 0 || _currentSegmentIndex >= ordered.length) {
      return null;
    }
    return ordered[_currentSegmentIndex];
  }

  @override
  bool get currentSegmentIsAudio => currentSegment?.isAudio ?? true;

  @override
  VideoPlayerController? get videoController => _activePlayer?.videoController;

  @override
  Future<void> openSegments(List<LessonMediaSegment> segments) async {
    _isResetting = true;
    try {
      await _disposePlayerInternal();
      // Published metadata can outlive a failed/removed upload. Keep those
      // entries visible to the UI, but never let an URL-less entry prevent a
      // later valid part from opening.
      _timeline = LessonMediaTimeline(
        segments: LessonMediaSegment.normalizeOrders(
          segments.where((segment) => segment.hasUrl).toList(),
        ),
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
    } finally {
      _isResetting = false;
    }
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
      final segment = _timeline.orderedSegments[segmentIndex];
      final targetSlot = _slotForSegment(segment);
      if (identical(targetSlot, _activeSlot)) {
        // There is one player slot per media type. Opening an adjacent
        // same-type segment in that slot would replace the media that is
        // currently playing, so it cannot be safely preloaded.
        return;
      }
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
      _logSwitch(
        '_preloadNextSegment: FAILED segmentIndex=$segmentIndex error=$error',
      );
    }
  }

  Future<void> _activateSegment(
    int segmentIndex, {
    required double localStartSec,
    bool? resumePlaying,
    int? resumeDecisionGeneration,
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

      await _prepareSegmentInSlot(segmentIndex, localStartSec: localStartSec);

      final slot = _slotForSegment(segment);
      await _detachActiveSubscriptions();

      _activePlayer = slot.player;
      _activeSlot = slot;
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

      // `shouldResumePlaying` reflects whatever was playing *before* this
      // switch started, captured by the caller before any of this ran. If
      // the user tapped play/pause again while the switch was still in
      // flight (a real possibility: this method awaits real native
      // open/seek calls), `play`/`pause` already took effect immediately
      // against whatever player was active at that moment - but the
      // player that ends up active is only known now, once the switch has
      // fully settled. Re-apply the user's latest wish against it, instead
      // of blindly trusting the pre-switch snapshot, whenever a play/pause
      // tap is detected to have landed since this switch began.
      final userActedDuringSwitch =
          resumeDecisionGeneration != null &&
          _playbackIntentGeneration != resumeDecisionGeneration;
      final effectiveResume = userActedDuringSwitch
          ? _isPlaying
          : shouldResumePlaying;
      _logSwitch(
        '_activateSegment settling: segmentIndex=$segmentIndex '
        'shouldResumePlaying=$shouldResumePlaying '
        'userActedDuringSwitch=$userActedDuringSwitch '
        'effectiveResume=$effectiveResume',
      );
      if (effectiveResume) {
        await _playInternal();
      } else if (userActedDuringSwitch) {
        await _pauseInternal();
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
    _completedSubscription = player.completedStream.listen((_) {
      unawaited(_handleNaturalCompletion());
    });
  }

  Future<void> _detachActiveSubscriptions() async {
    await _positionSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _playingSubscription?.cancel();
    await _completedSubscription?.cancel();
    _positionSubscription = null;
    _durationSubscription = null;
    _playingSubscription = null;
    _completedSubscription = null;
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
  }

  Future<void> _handleNaturalCompletion() async {
    if (_isResetting ||
        _isSwitchingSegment ||
        _seekDrainFuture != null ||
        _isAdvancing ||
        !_autoAdvanceEnabled) {
      return;
    }
    _segmentCompletedController.add(_currentSegmentIndex);
    await _advanceToNextSegmentOrStop();
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
        await _pauseInternal();
        return;
      }

      final generationAtStart = _playbackIntentGeneration;
      await _activateSegment(
        nextIndex,
        localStartSec: 0,
        // Natural completion means the user's playback intent is still
        // "play", even when the native player emits playing=false first.
        resumePlaying: true,
        resumeDecisionGeneration: generationAtStart,
      );
    } finally {
      _isAdvancing = false;
    }
  }

  void _handlePlayingUpdate(bool isPlaying) {
    if (_isSwitchingSegment) {
      return;
    }
    _emitPlaying(isPlaying);
  }

  void _emitPlaying(bool isPlaying) {
    if (_isPlaying == isPlaying) {
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

  /// Public entry point for user/UI-initiated play requests.
  ///
  /// This always takes effect immediately against whatever player is
  /// currently active - it must never be delayed or silently dropped, or
  /// the play/pause button would stop responding to taps (a real
  /// regression that was observed when an earlier version of this method
  /// deferred the call instead: same-segment seeks never consume a
  /// deferred request, so it could be lost forever).
  ///
  /// If a segment switch is concurrently in flight, `_playbackIntentGeneration`
  /// lets that switch notice this tap landed and re-apply it against
  /// whichever player the switch ends up on, instead of trusting a
  /// "was it playing before the switch" snapshot that this call just made
  /// stale. See `_activateSegment`'s use of `resumeDecisionGeneration`.
  @override
  Future<void> play() async {
    if (_isResetting) {
      return;
    }
    _playbackIntentGeneration++;
    await _playInternal();
  }

  /// Public entry point for user/UI-initiated pause requests. See [play].
  @override
  Future<void> pause() async {
    if (_isResetting) {
      return;
    }
    _playbackIntentGeneration++;
    await _pauseInternal();
  }

  Future<void> _playInternal() async {
    if (_activePlayer == null) {
      return;
    }
    if (_globalPositionSec >= _totalDurationSec && _totalDurationSec > 0) {
      await seekGlobal(0);
    }
    _logSwitch('_playInternal: currentSegmentIndex=$_currentSegmentIndex');
    await _activePlayer!.play();
    _emitPlaying(true);
    _syncActivePlaybackPosition(forceEmit: true);
  }

  Future<void> _pauseInternal() async {
    _logSwitch('_pauseInternal: currentSegmentIndex=$_currentSegmentIndex');
    await _activePlayer?.pause();
    _emitPlaying(false);
  }

  @override
  Future<void> seekGlobal(double globalSec) async {
    if (_isResetting || _timeline.isEmpty) {
      return;
    }
    final clampedGlobalSec = globalSec.clamp(0.0, _totalDurationSec.toDouble());
    await _enqueueSeek(_PlaylistSeekTarget(globalSec: clampedGlobalSec));
  }

  Future<void> _enqueueSeek(_PlaylistSeekTarget target) async {
    _logSwitch(
      'seek called: globalSec=${target.globalSec} '
      'seekInProgress=${_seekDrainFuture != null} '
      'currentSegmentIndex=$_currentSegmentIndex',
    );

    _pendingSeekTarget = target;
    final activeDrain = _seekDrainFuture;
    if (activeDrain != null) {
      _logSwitch(
        'seek: another seek already in progress, queued '
        'target=${target.globalSec}',
      );
      return activeDrain;
    }

    final completion = Completer<void>();
    _seekDrainFuture = completion.future;
    unawaited(_runSeekDrain(target.globalSec, completion));
    return completion.future;
  }

  Future<void> _runSeekDrain(
    double requestedGlobalSec,
    Completer<void> completion,
  ) async {
    try {
      await _drainPendingSeeks(requestedGlobalSec);
      // Clear the active drain before completing callers. A request made by
      // one of their continuations must start a new drain rather than attach
      // itself to an already-completed Future and remain unapplied.
      _seekDrainFuture = null;
      completion.complete();
    } catch (error, stackTrace) {
      _seekDrainFuture = null;
      completion.completeError(error, stackTrace);
    } finally {
      _logSwitch('seek: finished globalSec=$requestedGlobalSec');
    }
  }

  Future<void> _drainPendingSeeks(double requestedGlobalSec) async {
    try {
      while (_pendingSeekTarget != null) {
        final target = _pendingSeekTarget!;
        _pendingSeekTarget = null;
        await _seekImmediate(target);
      }
    } catch (error, stackTrace) {
      _logSwitch(
        'seekGlobal: ERROR globalSec=$requestedGlobalSec '
        'error=$error\n$stackTrace',
      );
      rethrow;
    } finally {
      // A failed activation must not permanently block later seek requests.
      _pendingSeekTarget = null;
    }
  }

  Future<void> _seekImmediate(_PlaylistSeekTarget target) async {
    final forcedSegmentIndex = target.segmentIndex;
    final position = forcedSegmentIndex == null
        ? _timeline.resolveGlobalSec(target.globalSec)
        : LessonMediaPosition(
            segmentIndex: forcedSegmentIndex,
            segmentId: _timeline.orderedSegments[forcedSegmentIndex].id,
            localSec: target.localSec!,
            globalSec: target.globalSec,
            segment: _timeline.orderedSegments[forcedSegmentIndex],
          );
    _logSwitch(
      '_seekImmediate: globalSec=${target.globalSec} -> '
      'segmentIndex=${position.segmentIndex} localSec=${position.localSec} '
      'currentSegmentIndex=$_currentSegmentIndex '
      'crossSegment=${position.segmentIndex != _currentSegmentIndex}',
    );
    if (position.segmentIndex != _currentSegmentIndex) {
      final wasPlaying = _isPlaying;
      final generationAtStart = _playbackIntentGeneration;
      // Mark the switch as starting immediately, before pausing the
      // about-to-be-abandoned player. Pausing a real audio player can
      // republish its last known (pre-seek) position as a side effect; if
      // that happens before this flag is set, the stale position briefly
      // (or persistently, if activation is slow) overwrites the freshly
      // requested segment's position on screen.
      _isSwitchingSegment = true;
      try {
        if (wasPlaying) {
          await _pauseInternal();
        }
        // Let `_activateSegment` itself decide, in its own finally block,
        // whether to resume playback once the switch has fully settled,
        // using `generationAtStart` to detect (without ever delaying or
        // dropping it - see `play`/`pause`) a real play()/pause() tap that
        // landed while this switch was still running, which should win
        // over the `wasPlaying` snapshot taken above.
        await _activateSegment(
          position.segmentIndex,
          localStartSec: position.localSec,
          resumePlaying: wasPlaying,
          resumeDecisionGeneration: generationAtStart,
        );
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

  @override
  Future<void> seekToSegmentIndex(
    int segmentIndex, {
    double localStartSec = 0,
  }) async {
    if (_isResetting ||
        segmentIndex < 0 ||
        segmentIndex >= _timeline.segmentCount) {
      return;
    }
    final globalSec = _timeline.globalSecForSegmentIndex(
      segmentIndex: segmentIndex,
      localSec: localStartSec,
    );
    final segment = _timeline.orderedSegments[segmentIndex];
    final clampedLocalSec = localStartSec.clamp(
      0.0,
      segment.durationSec.toDouble(),
    );
    await _enqueueSeek(
      _PlaylistSeekTarget(
        globalSec: globalSec,
        segmentIndex: segmentIndex,
        localSec: clampedLocalSec,
      ),
    );
  }

  @override
  Future<void> disposePlayer() async {
    _isResetting = true;
    try {
      await _disposePlayerInternal();
    } finally {
      _isResetting = false;
    }
  }

  Future<void> _disposePlayerInternal() async {
    final activeSeekDrain = _seekDrainFuture;
    if (activeSeekDrain != null) {
      try {
        await activeSeekDrain;
      } catch (_) {
        // The original seek caller still receives the failure. Disposal must
        // nevertheless continue so partially prepared players are released.
      }
    }
    _isReady = false;
    _isPlaying = false;
    _pendingSeekTarget = null;
    await _disposeAllSlots();
    _timeline = const LessonMediaTimeline(segments: []);
    _currentSegmentIndex = 0;
    _globalPositionSec = 0;
    _totalDurationSec = 0;
  }

  @override
  Future<void> close() async {
    await disposePlayer();
    await _globalPositionController.close();
    await _totalDurationController.close();
    await _playingController.close();
    await _segmentIndexController.close();
    await _segmentCompletedController.close();
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
    _activeSlot = null;
  }
}

LessonMediaPlaylistController createLessonMediaPlaylistPlayback() {
  return LessonMediaPlaylistPlayback();
}

class FakeLessonMediaPlaylistPlayback implements LessonMediaPlaylistController {
  FakeLessonMediaPlaylistPlayback({
    this.totalDurationSec = 90,
    this.seekDelay = Duration.zero,
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

  @override
  final int totalDurationSec;
  Duration seekDelay;
  final List<LessonMediaSegment> _segments;
  final StreamController<double> _globalPositionController =
      StreamController<double>.broadcast();
  final StreamController<int> _totalDurationController =
      StreamController<int>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<int> _segmentIndexController =
      StreamController<int>.broadcast();
  final StreamController<int> _segmentCompletedController =
      StreamController<int>.broadcast();

  double _globalPositionSec = 0;
  bool _isReady = false;
  bool _isPlaying = false;
  int _currentSegmentIndex = 0;
  Timer? _timer;

  @override
  Stream<double> get globalPositionStream => _globalPositionController.stream;
  @override
  Stream<int> get totalDurationStream => _totalDurationController.stream;
  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<int> get segmentIndexStream => _segmentIndexController.stream;
  @override
  Stream<int> get segmentCompletedStream => _segmentCompletedController.stream;

  @override
  double get globalPositionSec => _globalPositionSec;
  @override
  double get liveGlobalPositionSec => _globalPositionSec;
  @override
  int get currentSegmentIndex => _currentSegmentIndex;
  @override
  bool get isPlaying => _isPlaying;
  @override
  bool get isReady => _isReady;
  @override
  bool get hasSegments => _segments.isNotEmpty;
  @override
  bool get currentSegmentIsAudio => currentSegment?.isAudio ?? true;

  @override
  LessonMediaSegment? get currentSegment {
    if (_currentSegmentIndex < 0 || _currentSegmentIndex >= _segments.length) {
      return null;
    }
    return _segments[_currentSegmentIndex];
  }

  @override
  VideoPlayerController? get videoController => null;

  @override
  Future<void> openSegments(List<LessonMediaSegment> segments) async {
    _segments
      ..clear()
      ..addAll(segments.where((segment) => segment.hasUrl));
    _isReady = true;
    _globalPositionSec = 0;
    _currentSegmentIndex = 0;
    _globalPositionController.add(_globalPositionSec);
    _totalDurationController.add(totalDurationSec);
    _segmentIndexController.add(_currentSegmentIndex);
  }

  @override
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
      if (_segments.isNotEmpty) {
        final timeline = LessonMediaTimeline(segments: _segments);
        final nextIndex = timeline
            .resolveGlobalSec(_globalPositionSec)
            .segmentIndex;
        if (nextIndex != _currentSegmentIndex) {
          _segmentCompletedController.add(_currentSegmentIndex);
          _currentSegmentIndex = nextIndex;
          _segmentIndexController.add(_currentSegmentIndex);
        }
      }
      if (next >= totalDurationSec) {
        _segmentCompletedController.add(_currentSegmentIndex);
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
  }

  @override
  Future<void> seekGlobal(double globalSec) async {
    if (seekDelay > Duration.zero) {
      await Future<void>.delayed(seekDelay);
    }
    _globalPositionSec = globalSec.clamp(0, totalDurationSec.toDouble());
    _globalPositionController.add(_globalPositionSec);
    if (_segments.isNotEmpty) {
      final timeline = LessonMediaTimeline(segments: _segments);
      final nextIndex = timeline
          .resolveGlobalSec(_globalPositionSec)
          .segmentIndex;
      if (nextIndex != _currentSegmentIndex) {
        _currentSegmentIndex = nextIndex;
        _segmentIndexController.add(_currentSegmentIndex);
      }
    }
  }

  @override
  Future<void> seekToSegmentIndex(
    int segmentIndex, {
    double localStartSec = 0,
  }) async {
    if (_segments.isEmpty) {
      return;
    }
    if (seekDelay > Duration.zero) {
      await Future<void>.delayed(seekDelay);
    }
    final timeline = LessonMediaTimeline(segments: _segments);
    final targetIndex = segmentIndex.clamp(0, _segments.length - 1);
    _currentSegmentIndex = targetIndex;
    _globalPositionSec = timeline.globalSecForSegmentIndex(
      segmentIndex: targetIndex,
      localSec: localStartSec,
    );
    _globalPositionController.add(_globalPositionSec);
    _segmentIndexController.add(_currentSegmentIndex);
  }

  @override
  Future<void> disposePlayer() async {
    _timer?.cancel();
    _isReady = false;
    _isPlaying = false;
  }

  @override
  Future<void> close() async {
    await disposePlayer();
    await _globalPositionController.close();
    await _totalDurationController.close();
    await _playingController.close();
    await _segmentIndexController.close();
    await _segmentCompletedController.close();
  }
}
