import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('storage.rules').readAsStringSync();
  });

  test('lesson uploads use at most two distinct Firestore documents', () {
    expect(RegExp('/documents/users/').allMatches(rules).length, 1);
    expect(
      rules,
      contains('/documents/courses/\$(courseId)).data.instructorId'),
    );
    expect(
      rules,
      contains('/documents/courses/\$(courseId)/lessons/\$(lessonId)'),
    );
  });

  test('lesson media keeps owner, lesson, type, and size checks', () {
    expect(rules, contains('request.auth.uid'));
    expect(rules, contains('lessonExists(courseId, lessonId)'));
    expect(rules, contains("request.resource.contentType.matches('video/.*')"));
    expect(rules, contains('request.resource.size <= 50 * 1024 * 1024'));
  });

  test('enrolled learners remain eligible to read course media', () {
    expect(rules, contains('userHasCourseEnrollment(courseId)'));
    expect(
      rules,
      contains(
        '/documents/users/\$(request.auth.uid)/enrollments/\$(courseId)',
      ),
    );
  });
}
