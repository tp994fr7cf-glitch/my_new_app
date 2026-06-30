import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/comment_identity.dart';
import 'package:my_new_app/models/lesson_interaction_constants.dart';
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

    test('detects quoted note attachment from id even without title snapshot', () {
      expect(
        hasQuotedNoteAttachment(
          quotedNoteId: 'note-a',
          quotedNoteTitle: null,
          quotedNoteBody: null,
        ),
        isTrue,
      );
      expect(
        hasQuotedNoteAttachment(
          quotedNoteId: null,
          quotedNoteTitle: null,
          quotedNoteBody: null,
        ),
        isFalse,
      );
      expect(
        quotedNoteDisplayTitle(
          quotedNoteId: 'note-a',
          quotedNoteTitle: null,
        ),
        '無題のメモ',
      );
      expect(
        quotedNoteDisplayTitle(
          quotedNoteId: 'note-a',
          quotedNoteTitle: '移項メモ',
        ),
        '移項メモ',
      );
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
      expect(firstStudent.displayName, matches(RegExp(r'^\d+$')));
      expect(
        commentIdentityFor(
          authorId: 'student-a',
          authorName: 'naonaonaoya70833@gmail.com',
        ).color,
        firstStudent.color,
      );
    });

    test('hides public questions moderated by teacher', () {
      const question = LessonQuestion(
        id: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '公開質問',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: [],
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
      );

      expect(question.isTeacherHidden, isTrue);
      expect(question.isPubliclyVisible, isFalse);
    });

    test(
      'keeps student-private public question hidden when teacher visible',
      () {
        const question = LessonQuestion(
          id: 'question-a',
          authorId: 'user-a',
          authorName: '学習者',
          courseId: 'course-a',
          courseTitle: '数学',
          lessonNumber: 1,
          lessonTitle: '一次方程式',
          title: '',
          body: '公開後に先生だけへ戻した質問',
          visibility: LessonQuestionVisibility.public,
          studentVisibility: LessonQuestionVisibility.teacherOnly,
          target: LessonQuestionTarget.everyone,
          attachmentTypes: [],
        );

        expect(question.isTeacherHidden, isFalse);
        expect(question.isStudentPublic, isFalse);
        expect(question.isPubliclyVisible, isFalse);
      },
    );

    test('treats missing studentVisibility as existing visibility', () {
      final question = LessonQuestion.fromMap({
        'authorId': 'user-a',
        'authorName': '学習者',
        'courseId': 'course-a',
        'courseTitle': '数学',
        'lessonNumber': 1,
        'lessonTitle': '一次方程式',
        'title': '',
        'body': 'studentVisibility 追加前の質問',
        'visibility': lessonQuestionVisibilityPublic,
        'target': lessonQuestionTargetEveryone,
        'attachmentTypes': <String>[],
      });

      expect(question.isStudentPublic, isTrue);
      expect(question.isPubliclyVisible, isTrue);
    });

    test('parses author role for teacher-created questions', () {
      final explicitTeacher = LessonQuestion.fromMap({'authorRole': 'teacher'});
      final legacyTeacher = LessonQuestion.fromMap({'authorDisplayName': '先生'});
      final student = LessonQuestion.fromMap({});

      expect(explicitTeacher.authorRole, 'teacher');
      expect(legacyTeacher.authorRole, 'teacher');
      expect(student.authorRole, 'student');
    });

    test('sorts questions by updatedAt descending', () {
      final older = LessonQuestion(
        id: 'older',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '古い質問',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: const [],
        updatedAt: Timestamp.fromDate(DateTime(2026)),
      );
      final newer = LessonQuestion(
        id: 'newer',
        authorId: 'user-b',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '新しい質問',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: const [],
        updatedAt: Timestamp.fromDate(DateTime(2026, 1, 2)),
      );

      expect(sortLessonQuestionsByUpdatedAt([older, newer]).first.id, 'newer');
    });

    test('sorts newest by posted time and edited newest by updated time', () {
      final earlyPostedRecentlyEdited = LessonQuestion(
        id: 'early-posted',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '先に投稿して後で編集',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: const [],
        createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 1, 9)),
        updatedAt: Timestamp.fromDate(DateTime.utc(2026, 1, 3, 9)),
      );
      final latePostedOldEdited = LessonQuestion(
        id: 'late-posted',
        authorId: 'user-b',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '後に投稿',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: const [],
        createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 2, 9)),
        updatedAt: Timestamp.fromDate(DateTime.utc(2026, 1, 2, 10)),
      );

      final newest = sortLessonQuestions([
        earlyPostedRecentlyEdited,
        latePostedOldEdited,
      ], LessonQuestionSort.newest);
      final editedNewest = sortLessonQuestions([
        earlyPostedRecentlyEdited,
        latePostedOldEdited,
      ], LessonQuestionSort.editedNewest);
      final popularFallback = sortLessonQuestions([
        earlyPostedRecentlyEdited,
        latePostedOldEdited,
      ], LessonQuestionSort.popular);

      expect(newest.first.id, 'late-posted');
      expect(editedNewest.first.id, 'early-posted');
      expect(popularFallback.first.id, 'late-posted');
    });
  });
}
