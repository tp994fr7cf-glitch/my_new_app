import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_question.dart';
import 'package:my_new_app/screens/lesson_questions_page.dart';

LessonQuestionAnswer _answer({
  required String id,
  bool isDeleted = false,
  String body = 'body',
}) {
  return LessonQuestionAnswer(
    id: id,
    questionId: 'question-a',
    authorId: 'student-a',
    authorName: '学習者A',
    authorRole: 'student',
    body: body,
    attachmentTypes: const [],
    isDeleted: isDeleted,
  );
}

void main() {
  test('partitionOwnMyAnswers separates active and deleted answers', () {
    final snapshot = partitionOwnMyAnswers([
      _answer(id: 'active-1'),
      _answer(id: 'deleted-1', isDeleted: true),
      _answer(id: 'active-2'),
      _answer(id: '', isDeleted: true),
    ]);

    expect(snapshot.activeAnswers.map((answer) => answer.id).toList(), [
      'active-1',
      'active-2',
    ]);
    expect(snapshot.deletedAnswerIds, {'deleted-1'});
  });

  test(
    'mergeMyAnswersStreamSnapshot excludes mirrored answers deleted in own stream',
    () {
      final mirrored = [
        _answer(id: 'ghost-answer', body: 'stale mirror'),
        _answer(id: 'visible-answer', body: 'still visible'),
      ];
      final ownActive = [_answer(id: 'visible-answer', body: 'own copy')];

      final merged = mergeMyAnswersStreamSnapshot(
        ownActiveAnswers: ownActive,
        ownDeletedAnswerIds: {'ghost-answer'},
        mirroredAnswers: mirrored,
        matchesActiveAnswerRole: (_) => true,
        sort: LessonQuestionSort.newest,
      );

      expect(merged.map((answer) => answer.id).toList(), ['visible-answer']);
      expect(merged.single.body, 'own copy');
    },
  );

  test('mergeMyAnswersStreamSnapshot prefers own stream over mirrored copy', () {
    final mirrored = [_answer(id: 'shared-answer', body: 'mirror body')];
    final ownActive = [_answer(id: 'shared-answer', body: 'own body')];

    final merged = mergeMyAnswersStreamSnapshot(
      ownActiveAnswers: ownActive,
      ownDeletedAnswerIds: const {},
      mirroredAnswers: mirrored,
      matchesActiveAnswerRole: (_) => true,
      sort: LessonQuestionSort.newest,
    );

    expect(merged.single.body, 'own body');
  });
}
