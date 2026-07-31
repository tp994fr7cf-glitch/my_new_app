import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import 'live_audio_probe_message.dart';
import 'live_audio_probe_service.dart';

enum LiveAudioProbeRtcState {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  failed,
}

class LiveAudioProbeRtcStatus {
  const LiveAudioProbeRtcStatus(this.state, {this.message});

  final LiveAudioProbeRtcState state;
  final String? message;
}

typedef LiveAudioProbeTokenRefresher =
    Future<LiveAudioProbeCredentials> Function();

class LiveAudioProbeRtcController {
  LiveAudioProbeRtcController({required this.refreshToken});

  final LiveAudioProbeTokenRefresher refreshToken;
  final _statusController =
      StreamController<LiveAudioProbeRtcStatus>.broadcast();
  final _messageController =
      StreamController<LiveAudioProbeMessage>.broadcast();

  RtcEngine? _engine;
  LiveAudioProbeCredentials? _credentials;
  int? _dataStreamId;
  bool _disposed = false;
  bool _tokenRefreshInProgress = false;

  Stream<LiveAudioProbeRtcStatus> get statuses => _statusController.stream;
  Stream<LiveAudioProbeMessage> get messages => _messageController.stream;
  LiveAudioProbePermission? get permission => _credentials?.permission;

  Future<void> join(LiveAudioProbeCredentials credentials) async {
    if (_disposed) {
      throw StateError('破棄済みのAgora接続は再利用できません。');
    }
    if (_engine != null) {
      throw StateError('すでにAgoraへ接続しています。');
    }
    _credentials = credentials;
    _emitStatus(LiveAudioProbeRtcState.connecting);
    final engine = createAgoraRtcEngine();
    _engine = engine;
    try {
      await engine.initialize(
        RtcEngineContext(
          appId: credentials.appId,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (_, _) {
            _emitStatus(LiveAudioProbeRtcState.connected);
          },
          onRejoinChannelSuccess: (_, _) {
            _emitStatus(LiveAudioProbeRtcState.connected);
          },
          onConnectionInterrupted: (_) {
            _emitStatus(
              LiveAudioProbeRtcState.reconnecting,
              message: '通信が一時的に途切れました。再接続しています。',
            );
          },
          onConnectionLost: (_) {
            _emitStatus(
              LiveAudioProbeRtcState.reconnecting,
              message: '通信を再接続しています。',
            );
          },
          onLeaveChannel: (_, _) {
            _emitStatus(LiveAudioProbeRtcState.disconnected);
          },
          onError: (code, message) {
            _emitStatus(
              LiveAudioProbeRtcState.failed,
              message: 'Agoraエラー: ${code.name} $message',
            );
          },
          onStreamMessage: (_, _, _, data, length, _) {
            final safeLength = length.clamp(0, data.length);
            final message = LiveAudioProbeMessage.tryDecode(
              data.sublist(0, safeLength),
            );
            if (message != null && !_messageController.isClosed) {
              _messageController.add(message);
            }
          },
          onStreamMessageError: (_, _, _, code, missed, _) {
            _emitStatus(
              LiveAudioProbeRtcState.connected,
              message: '板書データを$missed件受信できませんでした（${code.name}）。',
            );
          },
          onTokenPrivilegeWillExpire: (_, _) {
            unawaited(_refreshCurrentToken());
          },
          onRequestToken: (_) {
            unawaited(_refreshCurrentToken());
          },
        ),
      );
      await engine.enableAudio();
      await engine.setClientRole(
        role: credentials.permission.canPublish
            ? ClientRoleType.clientRoleBroadcaster
            : ClientRoleType.clientRoleAudience,
        options: const ClientRoleOptions(
          audienceLatencyLevel:
              AudienceLatencyLevelType.audienceLatencyLevelUltraLowLatency,
        ),
      );
      if (credentials.permission.canPublish) {
        await _ensureDataStream();
      }
      await engine.joinChannel(
        token: credentials.token,
        channelId: credentials.channelName,
        uid: credentials.rtcUid,
        options: _mediaOptions(credentials.permission),
      );
    } catch (error) {
      _emitStatus(
        LiveAudioProbeRtcState.failed,
        message: _friendlyRtcError(error),
      );
      await _releaseEngine();
      rethrow;
    }
  }

  Future<void> applyCredentials(LiveAudioProbeCredentials credentials) async {
    final engine = _engine;
    final previous = _credentials;
    if (engine == null || previous == null) {
      throw StateError('Agoraへ接続していません。');
    }
    if (credentials.appId != previous.appId ||
        credentials.channelName != previous.channelName ||
        credentials.rtcUid != previous.rtcUid) {
      throw StateError('接続中の配信とは異なる接続情報です。');
    }
    await engine.renewToken(credentials.token);
    await engine.setClientRole(
      role: credentials.permission.canPublish
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
      options: const ClientRoleOptions(
        audienceLatencyLevel:
            AudienceLatencyLevelType.audienceLatencyLevelUltraLowLatency,
      ),
    );
    await engine.updateChannelMediaOptions(
      _mediaOptions(credentials.permission),
    );
    _credentials = credentials;
    if (credentials.permission.canPublish) {
      await _ensureDataStream();
    }
  }

  Future<void> setMicrophoneMuted(bool muted) async {
    final engine = _engine;
    if (engine == null || _credentials?.permission.canPublish != true) {
      return;
    }
    await engine.muteLocalAudioStream(muted);
  }

  Future<void> setLiveAudioMuted(bool muted) async {
    final engine = _engine;
    if (engine == null) {
      return;
    }
    await engine.muteAllRemoteAudioStreams(muted);
  }

  Future<void> sendWhiteboardMessage(LiveAudioProbeMessage message) async {
    final engine = _engine;
    if (engine == null || _credentials?.permission.canPublish != true) {
      throw StateError('発表を許可された人だけが板書できます。');
    }
    await _ensureDataStream();
    final streamId = _dataStreamId;
    if (streamId == null) {
      throw StateError('音声同期の板書データストリームを作成できません。');
    }
    final data = message.encode();
    if (data.length > 1024) {
      throw StateError('板書データがAgoraの上限を超えました。');
    }
    await engine.sendStreamMessage(
      streamId: streamId,
      data: data,
      length: data.length,
    );
  }

  Future<void> leave() async {
    await _releaseEngine();
    _emitStatus(LiveAudioProbeRtcState.disconnected);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _releaseEngine();
    await _statusController.close();
    await _messageController.close();
  }

  Future<void> _ensureDataStream() async {
    if (_dataStreamId != null) {
      return;
    }
    final engine = _engine;
    if (engine == null) {
      return;
    }
    _dataStreamId = await engine.createDataStream(
      const DataStreamConfig(syncWithAudio: true, ordered: true),
    );
  }

  Future<void> _refreshCurrentToken() async {
    if (_tokenRefreshInProgress || _disposed || _engine == null) {
      return;
    }
    _tokenRefreshInProgress = true;
    try {
      final credentials = await refreshToken();
      await applyCredentials(credentials);
    } catch (error) {
      _emitStatus(
        LiveAudioProbeRtcState.failed,
        message: '接続の更新に失敗しました: $error',
      );
    } finally {
      _tokenRefreshInProgress = false;
    }
  }

  ChannelMediaOptions _mediaOptions(LiveAudioProbePermission permission) {
    return ChannelMediaOptions(
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      clientRoleType: permission.canPublish
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
      audienceLatencyLevel:
          AudienceLatencyLevelType.audienceLatencyLevelUltraLowLatency,
      publishMicrophoneTrack: permission.canPublish,
      publishCameraTrack: false,
      autoSubscribeAudio: true,
      autoSubscribeVideo: false,
      enableAudioRecordingOrPlayout: true,
    );
  }

  Future<void> _releaseEngine() async {
    final engine = _engine;
    _engine = null;
    _dataStreamId = null;
    if (engine == null) {
      return;
    }
    try {
      await engine.leaveChannel();
    } finally {
      await engine.release();
    }
  }

  void _emitStatus(LiveAudioProbeRtcState state, {String? message}) {
    if (!_disposed && !_statusController.isClosed) {
      _statusController.add(LiveAudioProbeRtcStatus(state, message: message));
    }
  }
}

String _friendlyRtcError(Object error) {
  if (error is AgoraRtcException && error.code == -4) {
    return 'この端末では、Agoraの必要な機能がまだ対応していません（エラー -4）。';
  }
  return 'Agoraへの接続に失敗しました: $error';
}
