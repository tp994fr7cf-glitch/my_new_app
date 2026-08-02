import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'live_audio_catchup_backend.dart' as contract;

class LiveAudioCatchupBackend implements contract.LiveAudioCatchupBackend {
  LiveAudioCatchupBackend() {
    _positionSubscription = _player.positionStream.listen((position) {
      if (!_positions.isClosed) {
        _positions.add(position.inMilliseconds / 1000);
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final _positions = StreamController<double>.broadcast();
  late final StreamSubscription<Duration> _positionSubscription;

  @override
  Stream<double> get positionStream => _positions.stream;

  @override
  Future<void> open(String url) =>
      _player.setAudioSource(createLiveAudioCatchupAudioSource(url));

  @override
  Future<void> seek(double positionSec) =>
      _player.seek(Duration(milliseconds: (positionSec * 1000).round()));

  @override
  Future<void> play() async {
    unawaited(_player.play());
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    await _positionSubscription.cancel();
    await _player.dispose();
    await _positions.close();
  }
}

AudioSource createLiveAudioCatchupAudioSource(String url) {
  return HlsAudioSource(Uri.parse(url));
}
