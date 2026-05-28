import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/comment_identity.dart';
import 'package:my_new_app/models/lesson_question.dart';

void main() {
  group('lesson question helpers', () {
    test('matches questions by title body course lesson and quoted note', () {
      const question = LessonQuestion(
        id: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '移項の質問',
        body: 'なぜ符号が変わりますか？',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: [],
        quotedNoteTitle: '移項メモ',
      );

      expect(lessonQuestionMatchesQuery(question, '符号'), isTrue);
      expect(lessonQuestionMatchesQuery(question, '移項メモ'), isTrue);
      expect(lessonQuestionMatchesQuery(question, '英語'), isFalse);
    });

    test('uses teacher label and stable student number identity', () {
      final teacher = commentIdentityFor(
        authorId: 'teacher-a',
        authorName: '先生',
        authorRole: 'teacher',
      );
      final firstStudent = commentIdentityFor(
        authorId: 'student-a',
        authorName: 'naonaonaoya70833@gmail.com',
      );

      expect(teacher.displayName, '先生');
      expect(firstStudent.displayName, '1');
      expect(
        commentIdentityFor(
          authorId: 'student-a',
          authorName: 'naonaonaoya70833@gmail.com',
        ).color,
        firstStudent.color,
      );
    });
  });
}
