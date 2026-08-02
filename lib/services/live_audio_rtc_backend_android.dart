import 'package:flutter/services.dart';

import 'live_audio_rtc_backend.dart';

const _channelName = 'com.example.my_new_app/live_audio_native_rtc';

class LiveAudioAndroidRtcBackend implements LiveAudioRtcBackend {
  LiveAudioAndroidRtcBackend({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  final MethodChannel _channel;
  LiveAudioRtcEventHandler _handler = const LiveAudioRtcEventHandler();
  bool _released = false;

  @override
  void setEventHandler(LiveAudioRtcEventHandler handler) {
    _handler = handler;
  }

  @override
  Future<void> initialize(String appId) {
    return _invoke('initialize', {'appId': appId});
  }

  @override
  Future<void> enableAudio() => _invoke('enableAudio');

  @override
  Future<void> setClientRole({required bool canPublish}) {
    return _invoke('setClientRole', {'canPublish': canPublish});
  }

  @override
  Future<void> join({
    required String token,
    required String channelName,
    required int uid,
    required bool canPublish,
  }) {
    return _invoke('join', {
      'token': token,
      'channelName': channelName,
      'uid': uid,
      'canPublish': canPublish,
    });
  }

  @override
  Future<bool> isConnected() async {
    return await _channel.invokeMethod<bool>('isConnected') ?? false;
  }

  @override
  Future<void> renewToken(String token) {
    return _invoke('renewToken', {'token': token});
  }

  @override
  Future<void> updateMediaOptions({required bool canPublish}) {
    return _invoke('updateMediaOptions', {'canPublish': canPublish});
  }

  @override
  Future<void> muteLocalAudioStream(bool muted) {
    return _invoke('muteLocalAudioStream', {'muted': muted});
  }

  @override
  Future<void> muteAllRemoteAudioStreams(bool muted) {
    return _invoke('muteAllRemoteAudioStreams', {'muted': muted});
  }

  @override
  Future<int> createDataStream() async {
    final streamId = await _channel.invokeMethod<int>('createDataStream');
    if (streamId == null || streamId < 0) {
      throw PlatformException(
        code: 'create_data_stream_failed',
        message: 'Agoraの板書データストリームを作成できませんでした。',
        details: streamId,
      );
    }
    return streamId;
  }

  @override
  Future<void> sendStreamMessage(int streamId, Uint8List data) {
    return _invoke('sendStreamMessage', {'streamId': streamId, 'data': data});
  }

  @override
  Future<void> leave() => _invoke('leave');

  @override
  Future<void> release() async {
    if (_released) {
      return;
    }
    await _invoke('release');
    _released = true;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) {
    return _channel.invokeMethod<void>(method, arguments);
  }

  Future<void> _handleNativeEvent(MethodCall call) async {
    if (call.method != 'event') {
      throw MissingPluginException('Unknown native RTC event: ${call.method}');
    }
    final arguments = Map<Object?, Object?>.from(call.arguments as Map);
    switch (arguments['type']) {
      case 'joined':
        _handler.onJoined?.call();
      case 'rejoined':
        _handler.onRejoined?.call();
      case 'connectionInterrupted':
        _handler.onConnectionInterrupted?.call();
      case 'connectionLost':
        _handler.onConnectionLost?.call();
      case 'left':
        _handler.onLeft?.call();
      case 'error':
        _handler.onError?.call(
          '${arguments['code']}',
          '${arguments['message'] ?? ''}',
        );
      case 'streamMessage':
        final data = arguments['data'];
        if (data is Uint8List) {
          _handler.onStreamMessage?.call(data);
        }
      case 'streamMessageError':
        _handler.onStreamMessageError?.call(
          '${arguments['code']}',
          arguments['missed'] as int? ?? 0,
        );
      case 'tokenRefreshRequired':
        _handler.onTokenRefreshRequired?.call();
    }
  }
}
