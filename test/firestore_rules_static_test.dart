import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firestore.rules').readAsStringSync();
  });

  test(
    'lesson session rules recognize all optional playback progress fields',
    () {
      for (final field in [
        'requiredMediaSegmentIds',
        'completedMediaSegmentIds',
        'mediaSegmentResumePositionsSec',
        'contentRevision',
        'playbackMode',
      ]) {
        expect(rules, contains("data.keys().hasAny(['$field'])"));
      }
      for (final mode in [
        "'continuous'",
        "'independentSingle'",
        "'independentPanels'",
      ]) {
        expect(rules, contains(mode));
      }
    },
  );

  test('quiz attempts validate version and optional segment metadata', () {
    expect(rules, contains('validOptionalQuizVersion(request.resource.data)'));
    expect(
      rules,
      contains('validOptionalQuizSegmentMetadata(request.resource.data)'),
    );
    for (final field in [
      'anchorType',
      'segmentId',
      'timestampSec',
      'globalTimestampSec',
    ]) {
      expect(rules, contains("data.keys().hasAny(['$field'])"));
    }
  });

  test('lesson count equality applies when teacher lesson fields change', () {
    expect(rules, contains("hasAny(['lessons', 'lessonCount'])"));
    expect(rules, contains('data.lessonCount == data.lessons.size()'));
    expect(rules, contains('validCourseLessonUpdateInvariant()'));
  });
}
