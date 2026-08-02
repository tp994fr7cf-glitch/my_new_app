import 'dart:async';

abstract interface class LiveAudioCatchupBackend {
  Stream<double> get positionStream;

  Future<void> open(String url);

  Future<void> seek(double positionSec);

  Future<void> play();

  Future<void> stop();

  Future<void> dispose();
}
