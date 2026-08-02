import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'live_audio_catchup_backend.dart' as contract;

@JS('Hls')
extension type _Hls._(JSObject _) implements JSObject {
  external factory _Hls();

  external static bool isSupported();

  external void loadSource(String source);

  external void attachMedia(HTMLMediaElement media);

  external void destroy();
}

class LiveAudioCatchupBackend implements contract.LiveAudioCatchupBackend {
  LiveAudioCatchupBackend() {
    _audio = HTMLAudioElement()
      ..preload = 'auto'
      ..crossOrigin = 'anonymous'
      ..style.display = 'none';
    document.body?.append(_audio);
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_positions.isClosed && _audio.currentTime.isFinite) {
        _positions.add(_audio.currentTime);
      }
    });
  }

  late final HTMLAudioElement _audio;
  final _positions = StreamController<double>.broadcast();
  late final Timer _positionTimer;
  _Hls? _hls;

  @override
  Stream<double> get positionStream => _positions.stream;

  @override
  Future<void> open(String url) async {
    await stop();
    _hls?.destroy();
    _hls = null;
    _audio.removeAttribute('src');

    final nativeHls = _audio.canPlayType('application/vnd.apple.mpegurl');
    if (nativeHls.isNotEmpty) {
      _audio.src = url;
      _audio.load();
    } else {
      bool hlsSupported;
      try {
        hlsSupported = _Hls.isSupported();
      } catch (_) {
        hlsSupported = false;
      }
      if (!hlsSupported) {
        throw StateError('このブラウザーではHLS追っかけ再生を利用できません。HLS.jsの読み込みを確認してください。');
      }
      final hls = _Hls()
        ..loadSource(url)
        ..attachMedia(_audio);
      _hls = hls;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<void> seek(double positionSec) async {
    _audio.currentTime = positionSec < 0 ? 0 : positionSec;
  }

  @override
  Future<void> play() async {
    await _audio.play().toDart;
  }

  @override
  Future<void> stop() async {
    _audio.pause();
  }

  @override
  Future<void> dispose() async {
    _positionTimer.cancel();
    _hls?.destroy();
    _audio
      ..pause()
      ..remove();
    await _positions.close();
  }
}
