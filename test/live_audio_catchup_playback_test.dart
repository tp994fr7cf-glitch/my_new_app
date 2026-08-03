import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/live_audio_catchup_backend.dart';
import 'package:my_new_app/services/live_audio_catchup_playback.dart';

void main() {
  test('waits for an active seek before returning to live', () async {
    final backend = _FakeLiveAudioCatchupBackend();
    final playback = LiveAudioCatchupPlayback(playbackBackend: backend);
    addTearDown(playback.dispose);

    final play = playback.playFrom(
      hlsUrl: 'https://example.com/liveAudioProbeHls',
      positionSec: 12,
    );
    await backend.seekStarted.future;

    final returnToLive = playback.returnToLive();
    await Future<void>.delayed(Duration.zero);

    expect(backend.events, ['open', 'seek:start']);

    backend.releaseSeek.complete();
    await Future.wait([play, returnToLive]);

    expect(backend.events, ['open', 'seek:start', 'seek:end', 'play', 'stop']);
    expect(playback.state, LiveAudioCatchupState.live);
  });

  test('waits for live return before starting a new seek', () async {
    final backend = _FakeLiveAudioCatchupBackend(blockStop: true);
    final playback = LiveAudioCatchupPlayback(playbackBackend: backend);
    addTearDown(playback.dispose);

    final returnToLive = playback.returnToLive();
    await backend.stopStarted.future;

    final play = playback.playFrom(
      hlsUrl: 'https://example.com/liveAudioProbeHls',
      positionSec: 24,
    );
    await Future<void>.delayed(Duration.zero);

    expect(backend.events, ['stop:start']);

    backend.releaseStop.complete();
    await returnToLive;
    await backend.seekStarted.future;
    backend.releaseSeek.complete();
    await play;

    expect(backend.events, [
      'stop:start',
      'stop:end',
      'open',
      'seek:start',
      'seek:end',
      'play',
    ]);
    expect(playback.state, LiveAudioCatchupState.catchup);
  });
}

class _FakeLiveAudioCatchupBackend implements LiveAudioCatchupBackend {
  _FakeLiveAudioCatchupBackend({this.blockStop = false});

  final bool blockStop;
  final events = <String>[];
  final seekStarted = Completer<void>();
  final releaseSeek = Completer<void>();
  final stopStarted = Completer<void>();
  final releaseStop = Completer<void>();

  @override
  Stream<double> get positionStream => const Stream<double>.empty();

  @override
  Future<void> open(String url) async {
    events.add('open');
  }

  @override
  Future<void> seek(double positionSec) async {
    events.add('seek:start');
    seekStarted.complete();
    await releaseSeek.future;
    events.add('seek:end');
  }

  @override
  Future<void> play() async {
    events.add('play');
  }

  @override
  Future<void> stop() async {
    if (!blockStop) {
      events.add('stop');
      return;
    }
    events.add('stop:start');
    stopStarted.complete();
    await releaseStop.future;
    events.add('stop:end');
  }

  @override
  Future<void> dispose() async {}
}
