import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';

import 'live_audio_probe_message.dart';
import 'live_audio_rtc_connection_confirmation.dart';
import 'live_audio_rtc_initialization_guard.dart';
import 'live_audio_probe_service.dart';

const Duration _rtcCommandTimeout = Duration(seconds: 10);
const Duration _rtcCleanupTimeout = Duration(seconds: 3);

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
  bool _dataStreamUnavailable = false;
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
    final joined = Completer<void>();
    try {
      await liveAudioRtcInitializationGuard.initialize(
        () => engine.initialize(
          RtcEngineContext(
            appId: credentials.appId,
            channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
            // Core RTC audio and data streams do not need Agora's optional
            // video/effect extensions. Keep this audio-only initialization
            // limited to the core modules that this feature actually uses.
            autoRegisterAgoraExtensions: false,
          ),
        ),
      );
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (_, _) {
            if (!joined.isCompleted) {
              joined.complete();
            }
          },
          onConnectionStateChanged: (_, state, _) {
            if (state == ConnectionStateType.connectionStateConnected &&
                !joined.isCompleted) {
              joined.complete();
            }
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
      await engine.enableAudio().timeout(_rtcCommandTimeout);
      await engine
          .setClientRole(
            role: credentials.permission.canPublish
                ? ClientRoleType.clientRoleBroadcaster
                : ClientRoleType.clientRoleAudience,
            options: const ClientRoleOptions(
              audienceLatencyLevel:
                  AudienceLatencyLevelType.audienceLatencyLevelUltraLowLatency,
            ),
          )
          .timeout(_rtcCommandTimeout);
      await confirmLiveAudioRtcConnection(
        joinCommand: engine.joinChannel(
          token: credentials.token,
          channelId: credentials.channelName,
          uid: credentials.rtcUid,
          options: _mediaOptions(credentials.permission),
        ),
        callbackSignal: joined.future,
        isConnected: () async {
          return await engine.getConnectionState() ==
              ConnectionStateType.connectionStateConnected;
        },
      );
      final warning = credentials.permission.canPublish
          ? await _preparePublisherDataStream()
          : null;
      _emitStatus(LiveAudioProbeRtcState.connected, message: warning);
    } catch (error) {
      _emitStatus(
        LiveAudioProbeRtcState.failed,
        message: _friendlyRtcError(error),
      );
      if (error is LiveAudioRtcInitializationException) {
        // Agora's internal initialization future remains pending after this
        // timeout. Releasing or initializing it again in the same process can
        // hang too, so leave cleanup to the Android process restart.
        _engine = null;
      }
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
      final warning = await _preparePublisherDataStream();
      if (warning != null) {
        _emitStatus(LiveAudioProbeRtcState.connected, message: warning);
      }
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
    if (_dataStreamUnavailable) {
      return;
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
    if (_dataStreamId != null || _dataStreamUnavailable) {
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

  Future<String?> _preparePublisherDataStream() async {
    try {
      await _ensureDataStream().timeout(_rtcCommandTimeout);
      return null;
    } catch (error) {
      _dataStreamUnavailable = true;
      debugPrint('[LiveAudioRtc] data stream unavailable: $error');
      return kIsWeb
          ? 'Webでは板書の途中経過を送信できないため、書き終えた線を共有します。'
          : '板書の途中経過を送信できないため、書き終えた線を共有します。';
    }
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
    _dataStreamUnavailable = false;
    if (engine == null) {
      return;
    }
    try {
      await engine.leaveChannel().timeout(_rtcCleanupTimeout);
    } catch (error) {
      debugPrint('[LiveAudioRtc] leave timeout/error: $error');
    }
    try {
      await engine.release().timeout(_rtcCleanupTimeout);
    } catch (error) {
      debugPrint('[LiveAudioRtc] release timeout/error: $error');
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
