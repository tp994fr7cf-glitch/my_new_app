import 'dart:async';

class LiveAudioCatchupBackend {
  Stream<double> get positionStream => const Stream<double>.empty();

  Future<void> open(String url) async {
    throw UnsupportedError('この端末では追っかけ再生を利用できません。');
  }

  Future<void> seek(double positionSec) async {}

  Future<void> play() async {}

  Future<void> stop() async {}

  Future<void> dispose() async {}
}
