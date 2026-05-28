import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/quiz_answer_key.dart';

void main() {
  group('buildCycleQuizKey', () {
    test('uses session id when available', () {
      final key = buildCycleQuizKey(
        courseId: 'course-a',
        lessonNumber: 2,
        cycleNumber: 3,
        eventId: 'event-1',
        sessionId: 'session-a',
      );

      expect(key, 'session-a_event-1');
    });

    test('falls back to course lesson cycle when session id is missing', () {
      final key = buildCycleQuizKey(
        courseId: 'course-a',
        lessonNumber: 2,
        cycleNumber: 3,
        eventId: 'event-1',
      );

      expect(key, 'course-a_2_3_event-1');
    });

    test('can include a quiz version for future edited quizzes', () {
      final key = buildCycleQuizKey(
        courseId: 'course-a',
        lessonNumber: 2,
        cycleNumber: 3,
        eventId: 'event-1',
        sessionId: 'session-a',
        quizVersion: 4,
      );

      expect(key, 'session-a_event-1:v4');
    });
  });
}
