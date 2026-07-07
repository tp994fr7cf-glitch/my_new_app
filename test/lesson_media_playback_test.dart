import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/lesson_media_playback.dart';

void main() {
  test('fake audio playback emits monotonic positions while playing', () async {
    final player = FakeLessonMediaPlayback();
    final positions = <Duration>[];
    final sub = player.positionStream.listen(positions.add);

    await player.open(Uri.parse('https://example.com/audio.mp3'));
    await player.play();
    await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 500));
    await player.pause();
    await sub.cancel();

    expect(positions.length, greaterThan(1));
    for (var index = 1; index < positions.length; index++) {
      expect(
        positions[index].inMilliseconds,
        greaterThanOrEqualTo(positions[index - 1].inMilliseconds),
      );
    }
  });
}
