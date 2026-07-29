import 'dart:async';

import 'package:just_audio/just_audio.dart';

class LiveAudioCatchupBackend {
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

  Stream<double> get positionStream => _positions.stream;

  Future<void> open(String url) => _player.setUrl(url);

  Future<void> seek(double positionSec) =>
      _player.seek(Duration(milliseconds: (positionSec * 1000).round()));

  Future<void> play() async {
    unawaited(_player.play());
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() async {
    await _positionSubscription.cancel();
    await _player.dispose();
    await _positions.close();
  }
}
