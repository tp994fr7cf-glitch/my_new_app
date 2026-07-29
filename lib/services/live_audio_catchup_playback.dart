import 'dart:async';

import 'live_audio_catchup_backend_stub.dart'
    if (dart.library.io) 'live_audio_catchup_backend_io.dart'
    if (dart.library.js_interop) 'live_audio_catchup_backend_web.dart'
    as backend;

enum LiveAudioCatchupState { live, loading, catchup, failed }

class LiveAudioCatchupStatus {
  const LiveAudioCatchupStatus({
    required this.state,
    this.positionSec = 0,
    this.message,
  });

  final LiveAudioCatchupState state;
  final double positionSec;
  final String? message;
}

class LiveAudioCatchupPlayback {
  LiveAudioCatchupPlayback() {
    _positionSubscription = _backend.positionStream.listen((positionSec) {
      if (!_statuses.isClosed && _state == LiveAudioCatchupState.catchup) {
        _statuses.add(
          LiveAudioCatchupStatus(state: _state, positionSec: positionSec),
        );
      }
    });
  }

  final backend.LiveAudioCatchupBackend _backend =
      backend.LiveAudioCatchupBackend();
  final _statuses = StreamController<LiveAudioCatchupStatus>.broadcast();
  late final StreamSubscription<double> _positionSubscription;
  LiveAudioCatchupState _state = LiveAudioCatchupState.live;
  String? _openedUrl;

  Stream<LiveAudioCatchupStatus> get statuses => _statuses.stream;
  LiveAudioCatchupState get state => _state;

  Future<void> playFrom({
    required String hlsUrl,
    required double positionSec,
  }) async {
    if (hlsUrl.trim().isEmpty) {
      throw StateError('追っかけ再生用の音声がまだ準備されていません。');
    }
    _emit(LiveAudioCatchupState.loading, positionSec: positionSec);
    try {
      if (_openedUrl != hlsUrl) {
        await _backend.open(hlsUrl);
        _openedUrl = hlsUrl;
      }
      await _backend.seek(positionSec);
      await _backend.play();
      _emit(LiveAudioCatchupState.catchup, positionSec: positionSec);
    } catch (error) {
      _emit(
        LiveAudioCatchupState.failed,
        positionSec: positionSec,
        message: '追っかけ再生を開始できませんでした: $error',
      );
      rethrow;
    }
  }

  Future<void> returnToLive() async {
    await _backend.stop();
    _emit(LiveAudioCatchupState.live);
  }

  Future<void> dispose() async {
    await _positionSubscription.cancel();
    await _backend.dispose();
    await _statuses.close();
  }

  void _emit(
    LiveAudioCatchupState state, {
    double positionSec = 0,
    String? message,
  }) {
    _state = state;
    if (!_statuses.isClosed) {
      _statuses.add(
        LiveAudioCatchupStatus(
          state: state,
          positionSec: positionSec,
          message: message,
        ),
      );
    }
  }
}
