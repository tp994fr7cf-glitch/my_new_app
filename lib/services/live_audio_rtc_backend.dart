import 'dart:typed_data';

class LiveAudioRtcEventHandler {
  const LiveAudioRtcEventHandler({
    this.onJoined,
    this.onRejoined,
    this.onConnectionInterrupted,
    this.onConnectionLost,
    this.onLeft,
    this.onError,
    this.onStreamMessage,
    this.onStreamMessageError,
    this.onTokenRefreshRequired,
  });

  final void Function()? onJoined;
  final void Function()? onRejoined;
  final void Function()? onConnectionInterrupted;
  final void Function()? onConnectionLost;
  final void Function()? onLeft;
  final void Function(String code, String message)? onError;
  final void Function(Uint8List data)? onStreamMessage;
  final void Function(String code, int missed)? onStreamMessageError;
  final void Function()? onTokenRefreshRequired;
}

abstract interface class LiveAudioRtcBackend {
  void setEventHandler(LiveAudioRtcEventHandler handler);

  Future<void> initialize(String appId);

  Future<void> enableAudio();

  Future<void> setClientRole({required bool canPublish});

  Future<void> join({
    required String token,
    required String channelName,
    required int uid,
    required bool canPublish,
  });

  Future<bool> isConnected();

  Future<int> getNtpWallTimeInMs();

  Future<int?> getAudioCaptureStartNtpTimeInMs();

  Future<void> renewToken(String token);

  Future<void> updateMediaOptions({required bool canPublish});

  Future<void> muteLocalAudioStream(bool muted);

  Future<void> adjustPlaybackSignalVolume(int volume);

  Future<int> createDataStream();

  Future<void> sendStreamMessage(int streamId, Uint8List data);

  Future<void> leave();

  Future<void> release();
}
