import 'dart:async';

class LiveAudioRtcInitializationException implements Exception {
  const LiveAudioRtcInitializationException();

  @override
  String toString() {
    return 'Agoraの初期化が完了しませんでした。'
        'アプリを完全に終了してから、もう一度開いてください。';
  }
}

class LiveAudioRtcInitializationGuard {
  bool _requiresProcessRestart = false;

  bool get requiresProcessRestart => _requiresProcessRestart;

  Future<void> initialize(
    Future<void> Function() operation, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_requiresProcessRestart) {
      throw const LiveAudioRtcInitializationException();
    }
    try {
      await operation().timeout(timeout);
    } on TimeoutException {
      _requiresProcessRestart = true;
      throw const LiveAudioRtcInitializationException();
    }
  }
}

final liveAudioRtcInitializationGuard = LiveAudioRtcInitializationGuard();
