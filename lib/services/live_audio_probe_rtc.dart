import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';

import 'live_audio_probe_message.dart';
import 'live_audio_rtc_connection_confirmation.dart';
import 'live_audio_rtc_backend.dart';
import 'live_audio_rtc_backend_factory.dart';
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
  LiveAudioProbeRtcController({
    required this.refreshToken,
    LiveAudioRtcBackend Function()? createBackend,
  }) : _createBackend = createBackend ?? createLiveAudioRtcBackend;

  final LiveAudioProbeTokenRefresher refreshToken;
  final LiveAudioRtcBackend Function() _createBackend;
  final _statusController =
      StreamController<LiveAudioProbeRtcStatus>.broadcast();
  final _messageController =
      StreamController<LiveAudioProbeMessage>.broadcast();

  LiveAudioRtcBackend? _backend;
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
    if (_backend != null) {
      throw StateError('すでにAgoraへ接続しています。');
    }
    _credentials = credentials;
    _emitStatus(LiveAudioProbeRtcState.connecting);
    final backend = _createBackend();
    _backend = backend;
    final joined = Completer<void>();
    backend.setEventHandler(
      LiveAudioRtcEventHandler(
        onJoined: () {
          if (!joined.isCompleted) {
            joined.complete();
          }
        },
        onRejoined: () {
          _emitStatus(LiveAudioProbeRtcState.connected);
        },
        onConnectionInterrupted: () {
          _emitStatus(
            LiveAudioProbeRtcState.reconnecting,
            message: '通信が一時的に途切れました。再接続しています。',
          );
        },
        onConnectionLost: () {
          _emitStatus(
            LiveAudioProbeRtcState.reconnecting,
            message: '通信を再接続しています。',
          );
        },
        onLeft: () {
          _emitStatus(LiveAudioProbeRtcState.disconnected);
        },
        onError: (code, message) {
          _emitStatus(
            LiveAudioProbeRtcState.failed,
            message: 'Agoraエラー: $code $message',
          );
        },
        onStreamMessage: (data) {
          final message = LiveAudioProbeMessage.tryDecode(data);
          if (message != null && !_messageController.isClosed) {
            _messageController.add(message);
          }
        },
        onStreamMessageError: (code, missed) {
          _emitStatus(
            LiveAudioProbeRtcState.connected,
            message: '板書データを$missed件受信できませんでした（$code）。',
          );
        },
        onTokenRefreshRequired: () {
          unawaited(_refreshCurrentToken());
        },
      ),
    );
    try {
      await liveAudioRtcInitializationGuard.initialize(
        () => backend.initialize(credentials.appId),
      );
      await backend.enableAudio().timeout(_rtcCommandTimeout);
      await backend
          .setClientRole(canPublish: credentials.permission.canPublish)
          .timeout(_rtcCommandTimeout);
      await confirmLiveAudioRtcConnection(
        joinCommand: backend.join(
          token: credentials.token,
          channelName: credentials.channelName,
          uid: credentials.rtcUid,
          canPublish: credentials.permission.canPublish,
        ),
        callbackSignal: joined.future,
        isConnected: backend.isConnected,
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
        // A timed-out native initialization may still be active. Do not race it
        // with release; leave cleanup to the Android process restart.
        _backend = null;
      }
      await _releaseEngine();
      rethrow;
    }
  }

  Future<void> applyCredentials(LiveAudioProbeCredentials credentials) async {
    final backend = _backend;
    final previous = _credentials;
    if (backend == null || previous == null) {
      throw StateError('Agoraへ接続していません。');
    }
    if (credentials.appId != previous.appId ||
        credentials.channelName != previous.channelName ||
        credentials.rtcUid != previous.rtcUid) {
      throw StateError('接続中の配信とは異なる接続情報です。');
    }
    await backend.renewToken(credentials.token);
    await backend.setClientRole(canPublish: credentials.permission.canPublish);
    await backend.updateMediaOptions(
      canPublish: credentials.permission.canPublish,
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
    final backend = _backend;
    if (backend == null || _credentials?.permission.canPublish != true) {
      return;
    }
    await backend.muteLocalAudioStream(muted);
  }

  Future<void> setLiveAudioMuted(bool muted) async {
    final backend = _backend;
    if (backend == null) {
      return;
    }
    await backend.muteAllRemoteAudioStreams(muted);
  }

  Future<void> sendWhiteboardMessage(LiveAudioProbeMessage message) async {
    final backend = _backend;
    if (backend == null || _credentials?.permission.canPublish != true) {
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
    await backend.sendStreamMessage(streamId, data);
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
    final backend = _backend;
    if (backend == null) {
      return;
    }
    _dataStreamId = await backend.createDataStream();
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
    if (_tokenRefreshInProgress || _disposed || _backend == null) {
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

  Future<void> _releaseEngine() async {
    final backend = _backend;
    _backend = null;
    _dataStreamId = null;
    _dataStreamUnavailable = false;
    if (backend == null) {
      return;
    }
    try {
      await backend.leave().timeout(_rtcCleanupTimeout);
    } catch (error) {
      debugPrint('[LiveAudioRtc] leave timeout/error: $error');
    }
    try {
      await backend.release().timeout(_rtcCleanupTimeout);
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
