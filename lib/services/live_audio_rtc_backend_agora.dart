import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import 'live_audio_rtc_backend.dart';

class LiveAudioAgoraRtcBackend implements LiveAudioRtcBackend {
  RtcEngine? _engine;
  LiveAudioRtcEventHandler _handler = const LiveAudioRtcEventHandler();

  RtcEngine get _activeEngine {
    final engine = _engine;
    if (engine == null) {
      throw StateError('Agoraエンジンが初期化されていません。');
    }
    return engine;
  }

  @override
  void setEventHandler(LiveAudioRtcEventHandler handler) {
    _handler = handler;
  }

  @override
  Future<void> initialize(String appId) async {
    final engine = createAgoraRtcEngine();
    _engine = engine;
    await engine.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        autoRegisterAgoraExtensions: false,
      ),
    );
    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (_, _) => _handler.onJoined?.call(),
        onConnectionStateChanged: (_, state, _) {
          if (state == ConnectionStateType.connectionStateConnected) {
            _handler.onJoined?.call();
          }
        },
        onRejoinChannelSuccess: (_, _) => _handler.onRejoined?.call(),
        onConnectionInterrupted: (_) =>
            _handler.onConnectionInterrupted?.call(),
        onConnectionLost: (_) => _handler.onConnectionLost?.call(),
        onLeaveChannel: (_, _) => _handler.onLeft?.call(),
        onError: (code, message) => _handler.onError?.call(code.name, message),
        onStreamMessage: (_, _, _, data, length, _) {
          final safeLength = length.clamp(0, data.length);
          _handler.onStreamMessage?.call(
            Uint8List.fromList(data.sublist(0, safeLength)),
          );
        },
        onStreamMessageError: (_, _, _, code, missed, _) =>
            _handler.onStreamMessageError?.call(code.name, missed),
        onTokenPrivilegeWillExpire: (_, _) =>
            _handler.onTokenRefreshRequired?.call(),
        onRequestToken: (_) => _handler.onTokenRefreshRequired?.call(),
      ),
    );
  }

  @override
  Future<void> enableAudio() => _activeEngine.enableAudio();

  @override
  Future<void> setClientRole({required bool canPublish}) {
    return _activeEngine.setClientRole(
      role: canPublish
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
      options: const ClientRoleOptions(
        audienceLatencyLevel:
            AudienceLatencyLevelType.audienceLatencyLevelUltraLowLatency,
      ),
    );
  }

  @override
  Future<void> join({
    required String token,
    required String channelName,
    required int uid,
    required bool canPublish,
  }) {
    return _activeEngine.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: _mediaOptions(canPublish),
    );
  }

  @override
  Future<bool> isConnected() async {
    return await _activeEngine.getConnectionState() ==
        ConnectionStateType.connectionStateConnected;
  }

  @override
  Future<void> renewToken(String token) => _activeEngine.renewToken(token);

  @override
  Future<void> updateMediaOptions({required bool canPublish}) {
    return _activeEngine.updateChannelMediaOptions(_mediaOptions(canPublish));
  }

  @override
  Future<void> muteLocalAudioStream(bool muted) {
    return _activeEngine.muteLocalAudioStream(muted);
  }

  @override
  Future<void> muteAllRemoteAudioStreams(bool muted) {
    return _activeEngine.muteAllRemoteAudioStreams(muted);
  }

  @override
  Future<int> createDataStream() {
    return _activeEngine.createDataStream(
      const DataStreamConfig(syncWithAudio: true, ordered: true),
    );
  }

  @override
  Future<void> sendStreamMessage(int streamId, Uint8List data) {
    return _activeEngine.sendStreamMessage(
      streamId: streamId,
      data: data,
      length: data.length,
    );
  }

  @override
  Future<void> leave() async {
    final engine = _engine;
    if (engine != null) {
      await engine.leaveChannel();
    }
  }

  @override
  Future<void> release() async {
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      await engine.release(sync: true);
    }
  }

  ChannelMediaOptions _mediaOptions(bool canPublish) {
    return ChannelMediaOptions(
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      clientRoleType: canPublish
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
      audienceLatencyLevel:
          AudienceLatencyLevelType.audienceLatencyLevelUltraLowLatency,
      publishMicrophoneTrack: canPublish,
      publishCameraTrack: false,
      autoSubscribeAudio: true,
      autoSubscribeVideo: false,
      enableAudioRecordingOrPlayout: true,
    );
  }
}
