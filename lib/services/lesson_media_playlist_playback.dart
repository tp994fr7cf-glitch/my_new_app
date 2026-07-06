import 'dart:async';

import 'package:video_player/video_player.dart';

import '../models/lesson_media_segment.dart';
import '../models/lesson_media_timeline.dart';
import 'lesson_media_playback.dart';

typedef LessonMediaPlaylistPlaybackFactory =
    LessonMediaPlaylistController Function();

abstract class LessonMediaPlaylistController {
  Stream<double> get globalPositionStream;
  Stream<int> get totalDurationStream;
  Stream<bool> get playingStream;
  Stream<int> get segmentIndexStream;

  double get globalPositionSec;
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

  Stream<double> get globalPositionStream => _globalPositionController.stream;
  Stream<int> get totalDurationStream => _totalDurationController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<int> get segmentIndexStream => _segmentIndexController.stream;

  double get globalPositionSec => _globalPositionSec;
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

    await _loadSegment(_currentSegmentIndex, localStartSec: 0);
  }

  Future<void> _loadSegment(int segmentIndex, {required double localStartSec}) async {
    final ordered = _timeline.orderedSegments;
    if (segmentIndex < 0 || segmentIndex >= ordered.length) {
      return;
    }

    _isSwitchingSegment = true;
    await _disposeActivePlayer();

    final segment = ordered[segmentIndex];
    if (!segment.hasUrl) {
      _isReady = false;
      _isSwitchingSegment = false;
      return;
    }

    final player = _playbackFactory(isAudio: segment.isAudio);
    await player.open(Uri.parse(segment.url.trim()));
    final targetLocalSec = localStartSec.clamp(
      0.0,
      segment.durationSec.toDouble(),
    );
    if (targetLocalSec > 0) {
      await player.seek(Duration(milliseconds: (targetLocalSec * 1000).round()));
    }

    _activePlayer = player;
    _currentSegmentIndex = segmentIndex;
    _segmentIndexController.add(_currentSegmentIndex);
    _positionSubscription = player.positionStream.listen(_handleLocalPosition);
    _durationSubscription = player.durationStream.listen((_) {
      _emitTotalDuration();
    });
    _playingSubscription = player.playingStream.listen(_handlePlayingUpdate);

    _globalPositionSec = _timeline.globalSecForSegmentIndex(
      segmentIndex: segmentIndex,
      localSec: targetLocalSec,
    );
    _globalPositionController.add(_globalPositionSec);
    _isReady = player.isReady;
    _isSwitchingSegment = false;
    _emitTotalDuration();
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
    if (_isSwitchingSegment) {
      return;
    }
    final nextIndex = _currentSegmentIndex + 1;
    final ordered = _timeline.orderedSegments;
    if (nextIndex >= ordered.length) {
      _globalPositionSec = _totalDurationSec.toDouble();
      _globalPositionController.add(_globalPositionSec);
      await pause();
      return;
    }

    final wasPlaying = _isPlaying;
    await _loadSegment(nextIndex, localStartSec: 0);
    if (wasPlaying) {
      await play();
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
    await _activePlayer!.play();
    _isPlaying = true;
    _playingController.add(true);
  }

  Future<void> pause() async {
    await _activePlayer?.pause();
    _isPlaying = false;
    _playingController.add(false);
  }

  Future<void> seekGlobal(double globalSec) async {
    if (_timeline.isEmpty) {
      return;
    }

    final position = _timeline.resolveGlobalSec(globalSec);
    if (position.segmentIndex != _currentSegmentIndex) {
      final wasPlaying = _isPlaying;
      await _loadSegment(
        position.segmentIndex,
        localStartSec: position.localSec,
      );
      if (wasPlaying) {
        await play();
      }
      return;
    }

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
    await _disposeActivePlayer();
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

  Future<void> _disposeActivePlayer() async {
    await _positionSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _playingSubscription?.cancel();
    _positionSubscription = null;
    _durationSubscription = null;
    _playingSubscription = null;
    await _activePlayer?.disposePlayer();
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
