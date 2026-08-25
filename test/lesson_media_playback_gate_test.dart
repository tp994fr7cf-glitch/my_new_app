import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/widgets/lesson_media_playback_gate.dart';

void main() {
  test('claiming a second owner pauses the first', () async {
    final gate = LessonMediaPlaybackGate();
    final paused = <String>[];
    gate.register(ownerId: 'part-1', pause: () async => paused.add('part-1'));
    gate.register(ownerId: 'part-2', pause: () async => paused.add('part-2'));
    gate.register(
      ownerId: 'overview',
      pause: () async => paused.add('overview'),
    );

    await gate.claim('part-1');
    expect(paused, isEmpty);

    await gate.claim('part-2');
    expect(paused, ['part-1']);

    await gate.claim('part-2');
    expect(paused, ['part-1']);

    await gate.claim('overview');
    expect(paused, ['part-1', 'part-2']);
  });

  test('unregistering the active owner lets the next claim start cleanly', () async {
    final gate = LessonMediaPlaybackGate();
    final paused = <String>[];
    gate.register(ownerId: 'a', pause: () async => paused.add('a'));
    gate.register(ownerId: 'b', pause: () async => paused.add('b'));

    await gate.claim('a');
    gate.unregister('a');
    await gate.claim('b');
    expect(paused, isEmpty);
  });
}
