import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/live_audio_stroke_persistence.dart';

void main() {
  test('saves a new board snapshot before its first stroke', () async {
    final calls = <String>[];

    await persistLiveAudioStrokeInOrder(
      boardExistsOnServer: false,
      saveBoardSnapshot: () async => calls.add('snapshot'),
      saveStroke: () async => calls.add('stroke'),
    );

    expect(calls, ['snapshot', 'stroke']);
  });

  test(
    'saves an existing board stroke without waiting for a snapshot',
    () async {
      final calls = <String>[];

      await persistLiveAudioStrokeInOrder(
        boardExistsOnServer: true,
        saveBoardSnapshot: () async => calls.add('snapshot'),
        saveStroke: () async => calls.add('stroke'),
      );

      expect(calls, ['stroke']);
    },
  );

  test('does not save a stroke when the required snapshot fails', () async {
    var strokeSaved = false;

    await expectLater(
      persistLiveAudioStrokeInOrder(
        boardExistsOnServer: false,
        saveBoardSnapshot: () => Future<void>.error(StateError('failed')),
        saveStroke: () async => strokeSaved = true,
      ),
      throwsStateError,
    );

    expect(strokeSaved, isFalse);
  });
}
