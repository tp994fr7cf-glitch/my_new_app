import 'dart:async';

import 'live_audio_catchup_backend.dart' as contract;

class LiveAudioCatchupBackend implements contract.LiveAudioCatchupBackend {
  @override
  Stream<double> get positionStream => const Stream<double>.empty();

  @override
  Future<void> open(String url) async {
    throw UnsupportedError('この端末では追っかけ再生を利用できません。');
  }

  @override
  Future<void> seek(double positionSec) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
