import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/live_audio_rtc_backend_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/live_audio_native_rtc');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('forwards RTC operations to the Android native channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'isConnected' => true,
            'createDataStream' => 7,
            _ => null,
          };
        });
    final backend = LiveAudioAndroidRtcBackend(channel: channel);

    await backend.initialize('test-app-id');
    await backend.enableAudio();
    await backend.setClientRole(canPublish: true);
    await backend.join(
      token: 'token',
      channelName: 'channel',
      uid: 0xffffffff,
      canPublish: true,
    );
    expect(await backend.isConnected(), isTrue);
    expect(await backend.createDataStream(), 7);
    await backend.sendStreamMessage(7, Uint8List.fromList([1, 2, 3]));
    await backend.leave();
    await backend.release();

    expect(calls.map((call) => call.method), [
      'initialize',
      'enableAudio',
      'setClientRole',
      'join',
      'isConnected',
      'createDataStream',
      'sendStreamMessage',
      'leave',
      'release',
    ]);
    expect(calls[3].arguments, {
      'token': 'token',
      'channelName': 'channel',
      'uid': 0xffffffff,
      'canPublish': true,
    });
    final sendArguments = Map<Object?, Object?>.from(calls[6].arguments as Map);
    expect(sendArguments['streamId'], 7);
    expect(sendArguments['data'], [1, 2, 3]);
  });

  test('rejects an invalid data stream id', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => -2);
    final backend = LiveAudioAndroidRtcBackend(channel: channel);

    await expectLater(
      backend.createDataStream(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'create_data_stream_failed',
        ),
      ),
    );
  });
}
