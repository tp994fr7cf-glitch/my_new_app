import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firestore.rules').readAsStringSync().replaceAll('\r\n', '\n');
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

  test('course metadata requires the individual lesson schema', () {
    expect(rules, contains('data.lessonSchemaVersion == 2'));
    expect(rules, contains("!data.keys().hasAny(['lessons', 'lessonEvents'])"));
    expect(rules, contains('validCourseLessonUpdateInvariant()'));
  });

  test('individual lesson writes require a monotonic document version', () {
    expect(rules, contains('match /lessons/{lessonId}'));
    expect(rules, contains('request.resource.data.schemaVersion == 2'));
    expect(rules, contains('request.resource.data.documentVersion == 1'));
    expect(rules, contains('request.resource.data.quizVersion == 1'));
    expect(rules, contains('function validLessonVersionUpdate()'));
    expect(rules, contains('resource.data.documentVersion + 1'));
    expect(rules, contains('resource.data.quizVersion + 1'));
    expect(rules, contains("!request.resource.data.keys().hasAny(["));
    expect(rules, contains("'draftBoardSet'"));
  });

  test('lesson drafts are instructor-only and structurally bounded', () {
    expect(rules, contains('match /lessonDrafts/{lessonId}'));
    expect(rules, contains('allow read: if isCourseInstructor(courseId);'));
    expect(
      rules,
      contains('request.resource.data.boardSet.boards.size() <= 20'),
    );
    expect(
      rules,
      contains('request.resource.data.mediaSegments.size() <= 100'),
    );
    expect(
      rules,
      contains(
        'request.resource.data.baseLessonDocumentVersion\n'
        '              == currentLessonDocumentVersion()',
      ),
    );
    expect(rules, contains('request.resource.data.draftRevision == 1'));
    expect(
      rules,
      contains(
        'request.resource.data.draftRevision\n'
        '                == resource.data.draftRevision + 1',
      ),
    );
    expect(rules, contains('allow delete: if isCourseInstructor(courseId);'));
  });
}
