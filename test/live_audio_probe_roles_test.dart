import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/live_audio_probe_service.dart';

void main() {
  test('teacher can speak while a co-speaker student draws', () {
    final session = _session(
      ownerUid: 'teacher',
      presenterUids: {'student-a'},
      activePresenterUid: 'student-a',
    );

    expect(session.canSpeak('teacher'), isTrue);
    expect(session.canSpeak('student-a'), isTrue);
    expect(session.canSpeak('student-b'), isFalse);
    expect(session.coSpeakerUid, 'student-a');
    expect(session.isDrawer('teacher'), isFalse);
    expect(session.isDrawer('student-a'), isTrue);
  });

  test('drawing stays with the teacher until it is handed over', () {
    final session = _session(
      ownerUid: 'teacher',
      presenterUids: {'student-a'},
      activePresenterUid: 'teacher',
    );

    expect(session.canSpeak('student-a'), isTrue);
    expect(session.isDrawer('teacher'), isTrue);
    expect(session.isDrawer('student-a'), isFalse);
  });
}

LiveAudioProbeSession _session({
  required String ownerUid,
  required Set<String> presenterUids,
  required String activePresenterUid,
}) {
  return LiveAudioProbeSession(
    id: 'session',
    joinCode: '1234',
    ownerUid: ownerUid,
    status: 'live',
    presenterUids: presenterUids,
    activePresenterUid: activePresenterUid,
    startedAtMs: 1,
    archiveStatus: 'recording',
    boardSet: const BoardSet(),
  );
}
