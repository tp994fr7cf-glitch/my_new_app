import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:my_new_app/services/live_audio_catchup_backend_io.dart';

void main() {
  test('uses HLS for an extensionless signed manifest URL', () {
    const url =
        'https://asia-northeast1-example.cloudfunctions.net/'
        'liveAudioProbeHls?path=archive%2Findex.m3u8&'
        'token=header.payload.signature%2Btail';

    final source = createLiveAudioCatchupAudioSource(url);

    expect(source, isA<HlsAudioSource>());
    expect((source as HlsAudioSource).uri, Uri.parse(url));
    expect(source.uri.path, endsWith('/liveAudioProbeHls'));
    expect(
      source.uri.queryParameters['token'],
      'header.payload.signature+tail',
    );
  });
}
