import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_note.dart';
import 'package:my_new_app/models/lesson_question.dart';
import 'package:my_new_app/screens/lesson_questions_page.dart';
import 'package:my_new_app/screens/video_lesson_page.dart';

void main() {
  const course = Course(
    id: 'course-a',
    title: '数学 方程式入門',
    instructorName: '先生',
    category: '数学',
    level: '基礎',
    duration: '1レッスン',
    lessonCount: 1,
    rating: 0,
    priceLabel: '無料',
    description: '一次方程式を学びます。',
    lessons: [CourseLesson(title: '一次方程式の基本', duration: '1分30秒')],
  );
  const lesson = CourseLesson(title: '一次方程式の基本', duration: '1分30秒');

  test('quoted note availability detects deleted or hidden notes', () {
    expect(
      quotedNoteUnavailableForQuestion(
        {
          'isDeleted': false,
          'studentVisibility': lessonNoteVisibilityPublic,
          'moderationStatus': lessonNoteModerationVisible,
        },
        exists: true,
        hasError: false,
      ),
      isFalse,
    );
    expect(
      quotedNoteUnavailableForQuestion(
        {
          'isDeleted': true,
          'studentVisibility': lessonNoteVisibilityPublic,
          'moderationStatus': lessonNoteModerationVisible,
        },
        exists: true,
        hasError: false,
      ),
      isTrue,
    );
    expect(
      quotedNoteUnavailableForQuestion(null, exists: false, hasError: false),
      isTrue,
    );
  });

  test('own private quoted note can open detailed preview', () {
    const ownPrivateNote = LessonNote(
      id: 'own-private-note',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '自分の非公開メモ',
      body: '編集に進みたいメモです。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.private,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
    );

    expect(
      canOpenOwnQuotedNoteDetail(
        note: ownPrivateNote,
        currentUserId: 'student-a',
        isTeacherPreview: false,
      ),
      isTrue,
    );
  });

  test('teacher preview mode does not treat own note as editable detail', () {
    const ownPublicNote = LessonNote(
      id: 'own-public-note',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '自分の公開メモ',
      body: '先生表示中は特別表示しない。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      allowsQuestionCitation: true,
    );

    expect(
      canOpenOwnQuotedNoteDetail(
        note: ownPublicNote,
        currentUserId: 'student-a',
        isTeacherPreview: true,
      ),
      isFalse,
    );
  });

  test('own deleted quoted note blocks navigation before push', () {
    const deletedOwnNote = LessonNote(
      id: 'own-deleted-note',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '削除済みメモ',
      body: 'このメモは削除済みです。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      isDeleted: true,
    );

    expect(
      shouldBlockOwnDeletedQuotedNoteNavigation(
        note: deletedOwnNote,
        currentUserId: 'student-a',
      ),
      isTrue,
    );
    expect(
      shouldBlockOwnDeletedQuotedNoteNavigation(
        note: deletedOwnNote,
        currentUserId: 'student-b',
      ),
      isFalse,
    );
  });

  test('public audience can quote only student-visible notes', () {
    const publicNote = LessonNote(
      id: 'public-note',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '公開メモ',
      body: '公開引用可',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      studentVisibility: LessonNoteVisibility.public,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      allowsQuestionCitation: true,
    );
    const teacherOnlyNote = LessonNote(
      id: 'teacher-only-note',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '先生限定メモ',
      body: '先生向け',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.teacherOnly,
      studentVisibility: LessonNoteVisibility.teacherOnly,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      allowsQuestionCitation: true,
    );
    const privateNote = LessonNote(
      id: 'private-note',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '非公開メモ',
      body: '自分用',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.private,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      allowsQuestionCitation: true,
    );

    expect(canQuoteLessonNoteToPublicAudience(publicNote), isTrue);
    expect(canQuoteLessonNoteToPublicAudience(teacherOnlyNote), isFalse);
    expect(canQuoteLessonNoteToPublicAudience(privateNote), isFalse);
  });

  test('question author can answer teacher-target public question', () {
    const question = LessonQuestion(
      id: 'question-teacher',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '先生だけ回答可の公開質問です。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: [],
    );

    expect(
      canAnswerLessonQuestion(
        question: question,
        currentUserId: 'student-a',
        isCurrentUserTeacher: false,
        isTeacherPreview: false,
      ),
      isTrue,
    );
    expect(
      canAnswerLessonQuestion(
        question: question,
        currentUserId: 'student-b',
        isCurrentUserTeacher: false,
        isTeacherPreview: false,
      ),
      isFalse,
    );
  });

  test('teacher-only question allows only author to answer', () {
    const question = LessonQuestion(
      id: 'question-teacher-only',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '先生だけ表示の質問です。',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: [],
    );

    expect(
      canAnswerLessonQuestion(
        question: question,
        currentUserId: 'student-a',
        isCurrentUserTeacher: false,
        isTeacherPreview: false,
      ),
      isTrue,
    );
    expect(
      canAnswerLessonQuestion(
        question: question,
        currentUserId: 'student-b',
        isCurrentUserTeacher: false,
        isTeacherPreview: false,
      ),
      isFalse,
    );
  });

  test('teacher and learner cannot answer teacher-hidden question', () {
    const hiddenQuestion = LessonQuestion(
      id: 'hidden-question',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '先生が非公開化した質問です。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: [],
      moderationStatus: lessonNoteModerationHiddenByTeacher,
    );

    expect(
      canAnswerLessonQuestion(
        question: hiddenQuestion,
        currentUserId: 'teacher-a',
        isCurrentUserTeacher: true,
        isTeacherPreview: true,
      ),
      isFalse,
    );
    expect(
      canAnswerLessonQuestion(
        question: hiddenQuestion,
        currentUserId: 'student-a',
        isCurrentUserTeacher: false,
        isTeacherPreview: false,
      ),
      isFalse,
    );
  });

  test('answer scope label switches to teacher-only when hidden', () {
    const visibleAnswer = LessonQuestionAnswer(
      id: 'visible-answer',
      questionId: 'question-a',
      authorId: 'teacher-1',
      authorName: '先生',
      authorRole: 'teacher',
      body: '公開中の回答です。',
      attachmentTypes: [],
    );
    const hiddenAnswer = LessonQuestionAnswer(
      id: 'hidden-answer',
      questionId: 'question-a',
      authorId: 'teacher-1',
      authorName: '先生',
      authorRole: 'teacher',
      body: '非公開にした回答です。',
      attachmentTypes: [],
      moderationStatus: lessonNoteModerationHiddenByTeacher,
    );

    expect(
      answerScopeLabel(visibleAnswer, '学習者にも公開 / 先生だけ回答可'),
      '学習者にも公開 / 先生だけ回答可',
    );
    expect(answerScopeLabel(hiddenAnswer, '学習者にも公開 / 先生だけ回答可'), '先生だけ表示');
  });

  test('answer popular sort follows edited timestamp order', () {
    final oldestEdited = LessonQuestionAnswer(
      id: 'answer-oldest-edited',
      questionId: 'question-a',
      authorId: 'student-a',
      authorName: '学習者A',
      authorRole: 'student',
      body: 'oldest',
      attachmentTypes: const [],
      createdAt: Timestamp.fromDate(DateTime(2026, 6, 1, 10, 0)),
      updatedAt: Timestamp.fromDate(DateTime(2026, 6, 1, 10, 1)),
    );
    final newestEdited = LessonQuestionAnswer(
      id: 'answer-newest-edited',
      questionId: 'question-a',
      authorId: 'student-a',
      authorName: '学習者A',
      authorRole: 'student',
      body: 'newest',
      attachmentTypes: const [],
      createdAt: Timestamp.fromDate(DateTime(2026, 6, 1, 10, 2)),
      updatedAt: Timestamp.fromDate(DateTime(2026, 6, 1, 10, 30)),
    );
    final middleEdited = LessonQuestionAnswer(
      id: 'answer-middle-edited',
      questionId: 'question-a',
      authorId: 'student-a',
      authorName: '学習者A',
      authorRole: 'student',
      body: 'middle',
      attachmentTypes: const [],
      createdAt: Timestamp.fromDate(DateTime(2026, 6, 1, 10, 1)),
      updatedAt: Timestamp.fromDate(DateTime(2026, 6, 1, 10, 20)),
    );

    final sorted = sortLessonQuestionAnswers(
      [oldestEdited, newestEdited, middleEdited],
      LessonQuestionSort.popular,
    );

    expect(
      sorted.map((answer) => answer.id).toList(),
      ['answer-newest-edited', 'answer-middle-edited', 'answer-oldest-edited'],
    );
  });

  test('comment owner is decided by uid and active role', () {
    expect(
      isCommentOwnerForActiveRole(
        currentUserId: 'same-user',
        isCurrentUserTeacher: false,
        authorId: 'same-user',
        authorRole: 'student',
      ),
      isTrue,
    );
    expect(
      isCommentOwnerForActiveRole(
        currentUserId: 'same-user',
        isCurrentUserTeacher: true,
        authorId: 'same-user',
        authorRole: 'student',
      ),
      isFalse,
    );
    expect(
      isCommentOwnerForActiveRole(
        currentUserId: 'same-user',
        isCurrentUserTeacher: true,
        authorId: 'same-user',
        authorRole: 'teacher',
      ),
      isTrue,
    );
  });

  testWidgets(
    'Question editor uses post label and forces public for everyone',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VideoLessonPage(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
          ),
        ),
      );

      await tester.scrollUntilVisible(find.text('質問コメントを開く'), 500);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(find.text('質問コメントを開く'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('質問を作成'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -700));
      await tester.pumpAndSettle();

      expect(find.text('コメントを投稿'), findsOneWidget);
      expect(find.text('引用するメモ'), findsOneWidget);

      await tester.tap(find.text('全員に質問'));
      await tester.pumpAndSettle();

      final switchTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '他の学習者にも公開する'),
      );
      expect(switchTile.value, isTrue);
      expect(switchTile.onChanged, isNull);
    },
  );

  testWidgets('Question editor only lists quotable public notes', (
    tester,
  ) async {
    const allowedNote = LessonNote(
      id: 'allowed-note',
      authorId: 'student-a',
      authorName: 'Aさん',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '引用許可メモ',
      body: '質問で引用できます。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      allowsQuestionCitation: true,
    );
    const deniedNote = LessonNote(
      id: 'denied-note',
      authorId: 'student-b',
      authorName: 'Bさん',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '引用不可メモ',
      body: '質問では引用できません。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
    );
    const teacherOnlyOtherNote = LessonNote(
      id: 'teacher-only-other-note',
      authorId: 'student-c',
      authorName: 'Cさん',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '先生向けメモ',
      body: '先生にだけ見せるメモです。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.teacherOnly,
      studentVisibility: LessonNoteVisibility.teacherOnly,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      allowsQuestionCitation: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            questionsStream: Stream.value(const []),
            publicQuestionsStream: Stream.value(const []),
            quotableNotesStream: Stream.value(const [
              allowedNote,
              deniedNote,
              teacherOnlyOtherNote,
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('質問を作成'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('引用許可メモ'), findsOneWidget);
    expect(find.text('引用不可メモ'), findsNothing);
    expect(find.text('先生向けメモ'), findsNothing);
  });

  testWidgets('Question list uses comment bubbles and opens detail in panel', (
    tester,
  ) async {
    final question = LessonQuestion(
      id: 'question-a',
      authorId: 'student-a',
      authorName: 'naonaonaoya70833@gmail.com',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '古いタイトル',
      body: '符号が変わる理由を知りたいです。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.everyone,
      attachmentTypes: [],
      quotedNoteTitle: '移項メモ',
      quotedNoteBody: '両辺に同じ計算をする',
      createdAt: Timestamp.fromDate(DateTime(2026, 5, 30, 8, 27)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            questionsStream: Stream.value([question]),
            publicQuestionsStream: Stream.value(const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1'), findsWidgets);
    expect(find.text('5/30 08:27'), findsOneWidget);
    expect(find.text('学習者にも公開 / 全員が回答可'), findsOneWidget);
    expect(find.text('符号が変わる理由を知りたいです。'), findsOneWidget);
    expect(find.text('古いタイトル'), findsNothing);
    expect(find.text('レッスンメモ'), findsOneWidget);

    await tester.tap(find.text('符号が変わる理由を知りたいです。'));
    await tester.pumpAndSettle();

    expect(find.text('質問詳細'), findsOneWidget);
    expect(find.text('回答コメントを書く'), findsOneWidget);
  });

  testWidgets(
    'My comments tab switches to answers and shows own answer records',
    (tester) async {
      const question = LessonQuestion(
        id: 'my-answer-parent-question',
        authorId: 'student-a',
        authorName: '学習者A',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '回答一覧の親質問です。',
        visibility: LessonQuestionVisibility.public,
        studentVisibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: [],
      );
      const directAnswer = LessonQuestionAnswer(
        id: 'my-answer-direct',
        questionId: 'my-answer-parent-question',
        authorId: 'student-a',
        authorName: '学習者A',
        authorRole: 'student',
        body: '自分の直接回答です。',
        attachmentTypes: [],
        parentCommentId: 'my-answer-parent-question',
        parentCommentType: 'question',
      );
      const hiddenReplyAnswer = LessonQuestionAnswer(
        id: 'my-answer-reply-hidden',
        questionId: 'my-answer-parent-question',
        authorId: 'student-a',
        authorName: '学習者A',
        authorRole: 'student',
        body: '自分の返信回答です。',
        attachmentTypes: [],
        parentCommentId: 'my-answer-direct',
        parentCommentType: 'answer',
        replyToDisplayName: '学習者A',
        moderationStatus: lessonNoteModerationHiddenByTeacher,
      );
      const deletedAnswer = LessonQuestionAnswer(
        id: 'my-answer-deleted',
        questionId: 'my-answer-parent-question',
        authorId: 'student-a',
        authorName: '学習者A',
        authorRole: 'student',
        body: '削除済み回答です。',
        attachmentTypes: [],
        isDeleted: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              questionsStream: Stream.value(const [question]),
              publicQuestionsStream: Stream.value(const []),
              answersStream: Stream.value(
                const [directAnswer, hiddenReplyAnswer, deletedAnswer],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('自分の質問・回答'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '回答'));
      await tester.pumpAndSettle();

      expect(find.text('自分の直接回答です。'), findsOneWidget);
      expect(find.text('自分の返信回答です。'), findsOneWidget);
      expect(find.text('削除済み回答です。'), findsNothing);
      expect(find.text('先生だけ表示'), findsWidgets);
      expect(find.text('先生によって非公開中'), findsOneWidget);
    },
  );

  testWidgets(
    'Opening my direct answer from my answers list opens question detail',
    (tester) async {
      const question = LessonQuestion(
        id: 'my-answer-open-question',
        authorId: 'student-a',
        authorName: '学習者A',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: 'タップ遷移を確認する質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: [],
      );
      final answers = [
        LessonQuestionAnswer(
          id: 'my-open-root',
          questionId: 'my-answer-open-question',
          authorId: 'student-a',
          authorName: '学習者A',
          authorRole: 'student',
          body: '遷移元の自分の回答です。',
          attachmentTypes: const [],
          parentCommentId: 'my-answer-open-question',
          parentCommentType: 'question',
          createdAt: Timestamp.fromDate(DateTime(2026, 6, 1, 11, 0)),
        ),
        LessonQuestionAnswer(
          id: 'my-open-reply',
          questionId: 'my-answer-open-question',
          authorId: 'student-a',
          authorName: '学習者A',
          authorRole: 'student',
          body: '自分の返信です。',
          attachmentTypes: const [],
          parentCommentId: 'my-open-root',
          parentCommentType: 'answer',
          replyToDisplayName: '学習者A',
          createdAt: Timestamp.fromDate(DateTime(2026, 6, 1, 11, 1)),
        ),
      ];
      final answersController = StreamController<List<LessonQuestionAnswer>>.broadcast();
      addTearDown(answersController.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              questionsStream: Stream.value(const [question]),
              publicQuestionsStream: Stream.value(const []),
              answersStream: answersController.stream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, '回答'));
      await tester.pumpAndSettle();
      answersController.add(answers);
      await tester.pumpAndSettle();
      await tester.tap(find.text('遷移元の自分の回答です。'));
      await tester.pumpAndSettle();
      answersController.add(answers);
      await tester.pumpAndSettle();

      final openedQuestionDetail =
          find.byTooltip('質問一覧に戻る').evaluate().isNotEmpty;
      final openedReplyDetail =
          find.byTooltip('質問詳細に戻る').evaluate().isNotEmpty;
      expect(openedQuestionDetail || openedReplyDetail, isTrue);
      expect(find.text('遷移元の自分の回答です。'), findsOneWidget);
    },
  );

  testWidgets(
    'Teacher preview can open own answers from my comments tab',
    (tester) async {
      const publicQuestion = LessonQuestion(
        id: 'teacher-preview-open-public-question',
        authorId: 'student-a',
        authorName: '学習者A',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '公開質問タブ側の質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: [],
      );
      const teacherQuestion = LessonQuestion(
        id: 'teacher-own-question',
        authorId: 'teacher-a',
        authorName: '先生',
        authorRole: 'teacher',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '先生の質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: [],
      );
      const teacherAnswer = LessonQuestionAnswer(
        id: 'teacher-own-answer',
        questionId: 'teacher-own-question',
        authorId: 'teacher-a',
        authorName: '先生',
        authorRole: 'teacher',
        body: '先生の回答です。',
        attachmentTypes: [],
        parentCommentId: 'teacher-own-question',
        parentCommentType: 'question',
      );
      const studentAnswer = LessonQuestionAnswer(
        id: 'student-answer-hidden-in-teacher-own-list',
        questionId: 'teacher-own-question',
        authorId: 'student-a',
        authorName: '学習者A',
        authorRole: 'student',
        body: '学習者の回答です。',
        attachmentTypes: [],
        parentCommentId: 'teacher-own-question',
        parentCommentType: 'question',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              questionsStream: Stream.value(const [teacherQuestion]),
              publicQuestionsStream: Stream.value(const [publicQuestion]),
              answersStream: Stream.value(const [teacherAnswer, studentAnswer]),
              isTeacherPreview: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('公開質問タブ側の質問です。'), findsOneWidget);
      await tester.tap(find.text('自分の質問・回答'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '回答'));
      await tester.pumpAndSettle();

      expect(find.text('先生の回答です。'), findsOneWidget);
      expect(find.text('学習者の回答です。'), findsNothing);
    },
  );

  testWidgets(
    'Own and public question cards show teacher-hidden notice from mirror ids',
    (tester) async {
      const question = LessonQuestion(
        id: 'question-hidden-by-teacher',
        authorId: 'student-a',
        authorName: '学習者A',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '先生が非公開にしたことを表示したい質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              questionsStream: Stream.value(const [question]),
              publicQuestionsStream: Stream.value(const [question]),
              teacherHiddenOwnQuestionIdsStream: Stream.value(const {
                'question-hidden-by-teacher',
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('先生によって非公開中'), findsOneWidget);
      expect(find.text('先生だけ表示 / 先生だけ回答可'), findsOneWidget);

      await tester.tap(find.text('公開質問'));
      await tester.pumpAndSettle();

      expect(find.text('先生によって非公開中'), findsOneWidget);
      expect(find.text('先生だけ表示 / 先生だけ回答可'), findsOneWidget);
    },
  );

  testWidgets(
    'Teacher-hidden question notice clears when mirror ids stream updates',
    (tester) async {
      const question = LessonQuestion(
        id: 'question-hidden-live',
        authorId: 'student-a',
        authorName: '学習者A',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '公開に戻したら表示が戻る質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: [],
      );
      final hiddenIdsController = StreamController<Set<String>>();
      addTearDown(hiddenIdsController.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              questionsStream: Stream.value(const [question]),
              publicQuestionsStream: Stream.value(const [question]),
              teacherHiddenOwnQuestionIdsStream: hiddenIdsController.stream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      hiddenIdsController.add(const {'question-hidden-live'});
      await tester.pumpAndSettle();

      expect(find.text('先生によって非公開中'), findsOneWidget);
      expect(find.text('先生だけ表示 / 先生だけ回答可'), findsOneWidget);
      expect(find.text('学習者にも公開 / 全員が回答可'), findsNothing);

      hiddenIdsController.add(const <String>{});
      await tester.pumpAndSettle();

      expect(find.text('先生によって非公開中'), findsNothing);
      expect(find.text('先生だけ表示 / 先生だけ回答可'), findsNothing);
      expect(find.text('学習者にも公開 / 全員が回答可'), findsOneWidget);

      await tester.tap(find.text('公開質問'));
      await tester.pumpAndSettle();
      expect(find.text('先生によって非公開中'), findsNothing);
      expect(find.text('学習者にも公開 / 全員が回答可'), findsOneWidget);
    },
  );

  testWidgets(
    'Teacher-hidden mirror notice stays after opening detail and returning',
    (tester) async {
      const question = LessonQuestion(
        id: 'question-hidden-persist',
        authorId: 'student-a',
        authorName: '学習者A',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '戻ったあとも非公開表示を維持したい質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: [],
      );
      final hiddenIdsController = StreamController<Set<String>>();
      addTearDown(hiddenIdsController.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              questionsStream: Stream.value(const [question]),
              publicQuestionsStream: Stream.value(const []),
              teacherHiddenOwnQuestionIdsStream: hiddenIdsController.stream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      hiddenIdsController.add(const {'question-hidden-persist'});
      await tester.pumpAndSettle();
      expect(find.text('先生によって非公開中'), findsOneWidget);
      expect(find.text('先生だけ表示 / 先生だけ回答可'), findsOneWidget);

      await tester.tap(find.text('戻ったあとも非公開表示を維持したい質問です。'));
      await tester.pumpAndSettle();
      expect(find.text('質問詳細'), findsOneWidget);

      await tester.tap(find.byTooltip('質問一覧に戻る'));
      await tester.pumpAndSettle();

      expect(find.text('先生によって非公開中'), findsOneWidget);
      expect(find.text('先生だけ表示 / 先生だけ回答可'), findsOneWidget);
      expect(find.text('学習者にも公開 / 全員が回答可'), findsNothing);
    },
  );

  testWidgets('Question detail shows teacher-hidden moderation notice', (
    tester,
  ) async {
    const hiddenQuestion = LessonQuestion(
      id: 'question-hidden-detail',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '詳細画面で非公開注意を表示したい質問です。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: [],
      moderationStatus: lessonNoteModerationHiddenByTeacher,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            questionsStream: Stream.value(const [hiddenQuestion]),
            publicQuestionsStream: Stream.value(const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('詳細画面で非公開注意を表示したい質問です。'));
    await tester.pumpAndSettle();

    expect(find.text('質問詳細'), findsOneWidget);
    expect(find.text('先生によって非公開中'), findsOneWidget);
    expect(find.text('先生だけ表示 / 先生だけ回答可'), findsOneWidget);
  });

  testWidgets(
    'Hidden answer notice clears when moderation returns to visible',
    (tester) async {
      const question = LessonQuestion(
        id: 'question-answer-live',
        authorId: 'student-a',
        authorName: '学習者A',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '回答の公開復帰を確認する質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: [],
      );
      const hiddenAnswer = LessonQuestionAnswer(
        id: 'answer-live',
        questionId: 'question-answer-live',
        authorId: 'student-a',
        authorName: '学習者A',
        authorRole: 'student',
        body: '最初は先生に非公開化された回答です。',
        attachmentTypes: [],
        moderationStatus: lessonNoteModerationHiddenByTeacher,
      );
      const visibleAnswer = LessonQuestionAnswer(
        id: 'answer-live',
        questionId: 'question-answer-live',
        authorId: 'student-a',
        authorName: '学習者A',
        authorRole: 'student',
        body: '最初は先生に非公開化された回答です。',
        attachmentTypes: [],
        moderationStatus: lessonNoteModerationVisible,
      );
      final answersController = StreamController<List<LessonQuestionAnswer>>();
      addTearDown(answersController.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              questionsStream: Stream.value(const []),
              publicQuestionsStream: Stream.value(const [question]),
              answersStream: answersController.stream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      answersController.add(const [hiddenAnswer]);
      await tester.pumpAndSettle();

      await tester.tap(find.text('公開質問'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答の公開復帰を確認する質問です。'));
      await tester.pumpAndSettle();
      expect(find.text('最初は先生に非公開化された回答です。'), findsOneWidget);
      expect(find.text('先生によって非公開中'), findsOneWidget);
      expect(find.text('先生だけ表示'), findsOneWidget);

      answersController.add(const [visibleAnswer]);
      await tester.pumpAndSettle();

      expect(find.text('最初は先生に非公開化された回答です。'), findsOneWidget);
      expect(find.text('先生によって非公開中'), findsNothing);
      expect(find.text('先生だけ表示'), findsNothing);
      expect(find.text('学習者にも公開 / 先生だけ回答可'), findsWidgets);
    },
  );

  testWidgets('Returning from detail keeps my-questions scroll position', (
    tester,
  ) async {
    final base = DateTime(2026, 6, 1, 9, 0);
    final questions = List.generate(60, (index) {
      final postedAt = Timestamp.fromDate(base.add(Duration(minutes: index)));
      return LessonQuestion(
        id: 'my-scroll-$index',
        authorId: 'student-a',
        authorName: '学習者A',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '自分一覧 スクロール確認 $index',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: const [],
        createdAt: postedAt,
        updatedAt: postedAt,
      );
    });
    const myListKey = PageStorageKey<String>('my-questions');

    double myListOffset() {
      final scrollable = find.descendant(
        of: find.byKey(myListKey),
        matching: find.byType(Scrollable),
      );
      return tester.state<ScrollableState>(scrollable).position.pixels;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            questionsStream: Stream.value(questions),
            publicQuestionsStream: Stream.value(const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byKey(myListKey), const Offset(0, -1600));
    await tester.pumpAndSettle();

    final visibleQuestion = find.textContaining('自分一覧 スクロール確認').first;
    await tester.ensureVisible(visibleQuestion);
    await tester.pumpAndSettle();
    final beforeOpenOffset = myListOffset();
    await tester.tap(visibleQuestion);
    await tester.pumpAndSettle();
    expect(find.text('質問詳細'), findsOneWidget);

    await tester.tap(find.byTooltip('質問一覧に戻る'));
    await tester.pumpAndSettle();

    final afterBackOffset = myListOffset();
    expect((afterBackOffset - beforeOpenOffset).abs(), lessThanOrEqualTo(2.0));
  });

  testWidgets('Teacher preview keeps scroll position after returning', (
    tester,
  ) async {
    final publicController = StreamController<List<LessonQuestion>>();
    addTearDown(publicController.close);
    final base = DateTime(2026, 6, 1, 10, 0);
    final questions = List.generate(80, (index) {
      final postedAt = Timestamp.fromDate(base.add(Duration(minutes: index)));
      final suffix = index.toString().padLeft(3, '0');
      return LessonQuestion(
        id: 'teacher-preview-scroll-$suffix',
        authorId: 'student-a',
        authorName: '学習者A',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '先生プレビュー スクロール確認 $suffix',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: const [],
        createdAt: postedAt,
        updatedAt: postedAt,
      );
    });
    const teacherPreviewListKey = PageStorageKey<String>(
      'teacher-preview-public-questions',
    );

    double teacherPreviewListOffset() {
      final scrollable = find.descendant(
        of: find.byKey(teacherPreviewListKey),
        matching: find.byType(Scrollable),
      );
      return tester.state<ScrollableState>(scrollable).position.pixels;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            questionsStream: Stream.value(const []),
            publicQuestionsStream: publicController.stream,
            isTeacherPreview: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    publicController.add(questions);
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(teacherPreviewListKey), const Offset(0, -1800));
    await tester.pumpAndSettle();
    const targetQuestionText = '先生プレビュー スクロール確認 045';
    final teacherPreviewScrollable = find.descendant(
      of: find.byKey(teacherPreviewListKey),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text(targetQuestionText),
      300,
      scrollable: teacherPreviewScrollable,
    );
    await tester.pumpAndSettle();
    final beforeOpenOffset = teacherPreviewListOffset();
    await tester.tap(find.text(targetQuestionText));
    await tester.pumpAndSettle();
    expect(find.text('質問詳細'), findsOneWidget);

    await tester.tap(find.byTooltip('質問一覧に戻る'));
    await tester.pumpAndSettle();

    final afterBackOffset = teacherPreviewListOffset();
    expect(
      (afterBackOffset - beforeOpenOffset).abs(),
      lessThanOrEqualTo(2.0),
    );
  });

  testWidgets(
    'Returning from detail keeps public-questions offset after stream re-emits',
    (tester) async {
      final publicController = StreamController<List<LessonQuestion>>();
      addTearDown(publicController.close);
      final base = DateTime(2026, 6, 1, 11, 0);
      final questions = List.generate(70, (index) {
        final postedAt = Timestamp.fromDate(base.add(Duration(minutes: index)));
        return LessonQuestion(
          id: 'public-scroll-$index',
          authorId: 'student-a',
          authorName: '学習者A',
          courseId: 'course-a',
          courseTitle: '数学 方程式入門',
          lessonNumber: 1,
          lessonTitle: '一次方程式の基本',
          title: '',
          body: '公開一覧 スクロール確認 $index',
          visibility: LessonQuestionVisibility.public,
          target: LessonQuestionTarget.everyone,
          attachmentTypes: const [],
          createdAt: postedAt,
          updatedAt: postedAt,
        );
      });
      const publicListKey = PageStorageKey<String>('public-questions');

      double publicListOffset() {
        final scrollable = find.descendant(
          of: find.byKey(publicListKey),
          matching: find.byType(Scrollable),
        );
        return tester.state<ScrollableState>(scrollable).position.pixels;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              questionsStream: Stream.value(const []),
              publicQuestionsStream: publicController.stream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('公開質問'));
      await tester.pumpAndSettle();
      publicController.add(questions);
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(publicListKey), const Offset(0, -1800));
      await tester.pumpAndSettle();

      final visibleQuestion = find.textContaining('公開一覧 スクロール確認').first;
      await tester.ensureVisible(visibleQuestion);
      await tester.pumpAndSettle();
      final beforeOpenOffset = publicListOffset();
      await tester.tap(visibleQuestion);
      await tester.pumpAndSettle();
      expect(find.text('質問詳細'), findsOneWidget);

      await tester.tap(find.byTooltip('質問一覧に戻る'));
      await tester.pumpAndSettle();
      final afterBackOffset = publicListOffset();
      expect(
        (afterBackOffset - beforeOpenOffset).abs(),
        lessThanOrEqualTo(2.0),
      );

      publicController.add(List<LessonQuestion>.from(questions));
      await tester.pumpAndSettle();
      final afterReemitOffset = publicListOffset();
      expect(
        (afterReemitOffset - beforeOpenOffset).abs(),
        lessThanOrEqualTo(2.0),
      );
    },
  );

  testWidgets(
    'Public-questions offset stays stable through burst stream updates',
    (tester) async {
      final publicController = StreamController<List<LessonQuestion>>();
      addTearDown(publicController.close);
      final postedAt = Timestamp.fromDate(DateTime(2026, 6, 1, 12, 0));
      final questions = List.generate(90, (index) {
        final suffix = index.toString().padLeft(3, '0');
        return LessonQuestion(
          id: 'public-burst-$suffix',
          authorId: 'student-a',
          authorName: '学習者A',
          courseId: 'course-a',
          courseTitle: '数学 方程式入門',
          lessonNumber: 1,
          lessonTitle: '一次方程式の基本',
          title: '',
          body: '公開一覧 バースト確認 $suffix',
          visibility: LessonQuestionVisibility.public,
          target: LessonQuestionTarget.everyone,
          attachmentTypes: const [],
          createdAt: postedAt,
          updatedAt: postedAt,
        );
      });
      const publicListKey = PageStorageKey<String>('public-questions');

      double publicListOffset() {
        final scrollable = find.descendant(
          of: find.byKey(publicListKey),
          matching: find.byType(Scrollable),
        );
        return tester.state<ScrollableState>(scrollable).position.pixels;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              questionsStream: Stream.value(const []),
              publicQuestionsStream: publicController.stream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('公開質問'));
      await tester.pumpAndSettle();
      publicController.add(questions);
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(publicListKey), const Offset(0, -2000));
      await tester.pumpAndSettle();
      const targetQuestionText = '公開一覧 バースト確認 050';
      final publicScrollable = find.descendant(
        of: find.byKey(publicListKey),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text(targetQuestionText),
        300,
        scrollable: publicScrollable,
      );
      await tester.pumpAndSettle();
      final beforeOpenOffset = publicListOffset();
      await tester.tap(find.text(targetQuestionText));
      await tester.pumpAndSettle();
      expect(find.text('質問詳細'), findsOneWidget);

      await tester.tap(find.byTooltip('質問一覧に戻る'));
      await tester.pumpAndSettle();
      final afterBackOffset = publicListOffset();
      expect(
        (afterBackOffset - beforeOpenOffset).abs(),
        lessThanOrEqualTo(2.0),
      );

      for (var burstIndex = 0; burstIndex < 6; burstIndex++) {
        final emission = burstIndex.isEven
            ? List<LessonQuestion>.from(questions.reversed)
            : List<LessonQuestion>.from(questions);
        publicController.add(emission);
      }
      await tester.pumpAndSettle();

      final afterBurstOffset = publicListOffset();
      expect(
        (afterBurstOffset - beforeOpenOffset).abs(),
        lessThanOrEqualTo(2.0),
      );
    },
  );

  testWidgets('Quoted note bubble shows memo status action', (tester) async {
    const question = LessonQuestion(
      id: 'question-note-status',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '引用メモの編集状態を確認したいです。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.everyone,
      attachmentTypes: [],
      quotedNoteId: 'public-note-1',
      quotedNoteTitle: '引用メモ',
      quotedNoteBody: '引用時の本文',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            questionsStream: Stream.value(const [question]),
            publicQuestionsStream: Stream.value(const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('メモ: 状態確認'), findsOneWidget);
    await tester.tap(find.textContaining('メモ: 状態確認'));
    await tester.pumpAndSettle();
    expect(find.text('メモ編集履歴'), findsOneWidget);
  });

  testWidgets('Quoted note chip opens latest view and hides stale snapshot', (
    tester,
  ) async {
    const question = LessonQuestion(
      id: 'question-latest-note',
      authorId: 'student-a',
      authorName: '学習者A',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '引用メモを確認します。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.everyone,
      attachmentTypes: [],
      quotedNoteId: 'public-note-latest',
      quotedNoteTitle: '引用メモタイトル',
      quotedNoteBody: '古い引用本文',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            questionsStream: Stream.value(const [question]),
            publicQuestionsStream: Stream.value(const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('レッスンメモ'));
    await tester.pumpAndSettle();

    expect(find.text('引用元メモは削除されたか、現在は表示できません。'), findsOneWidget);
    expect(find.text('古い引用本文'), findsNothing);
  });

  testWidgets('Learner cannot answer teacher-target public question', (
    tester,
  ) async {
    const question = LessonQuestion(
      id: 'question-teacher',
      authorId: 'student-a',
      authorName: 'naonaonaoya70833@gmail.com',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '先生にだけ回答してほしい質問です。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: [],
    );
    const teacherAnswer = LessonQuestionAnswer(
      id: 'teacher-answer',
      questionId: 'question-teacher',
      authorId: 'teacher-a',
      authorName: '田中（先生）',
      authorDisplayName: '田中（先生）',
      authorRole: 'teacher',
      body: '先生からの公開回答です。',
      attachmentTypes: [],
      parentCommentId: 'question-teacher',
      parentCommentType: 'question',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            questionsStream: Stream.value(const [question]),
            publicQuestionsStream: Stream.value(const []),
            answersStream: Stream.value(const [teacherAnswer]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('先生にだけ回答してほしい質問です。'));
    await tester.pumpAndSettle();

    expect(find.text('質問詳細'), findsOneWidget);
    expect(find.text('回答コメントを書く'), findsNothing);
    expect(find.text('先生からの公開回答です。'), findsOneWidget);
    expect(find.text('学習者にも公開 / 先生だけ回答可'), findsWidgets);
  });

  testWidgets('Teacher preview opens public question detail with moderation', (
    tester,
  ) async {
    const question = LessonQuestion(
      id: 'teacher-preview-question',
      authorId: 'student-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '先生プレビューで確認する公開質問です。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: [],
    );
    const hiddenAnswer = LessonQuestionAnswer(
      id: 'hidden-answer',
      questionId: 'teacher-preview-question',
      authorId: 'student-b',
      authorName: '別の学習者',
      authorRole: 'student',
      body: '先生が確認できる非公開回答です。',
      attachmentTypes: [],
      moderationStatus: lessonNoteModerationHiddenByTeacher,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            publicQuestionsStream: Stream.value(const [question]),
            answersStream: Stream.value(const [hiddenAnswer]),
            isTeacherPreview: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('質問コメントを確認し、返信や公開状態の管理ができます。'), findsOneWidget);
    await tester.tap(find.text('先生プレビューで確認する公開質問です。'));
    await tester.pumpAndSettle();

    expect(find.text('質問詳細'), findsOneWidget);
    expect(find.text('回答コメントを書く'), findsOneWidget);
    expect(find.text('先生が確認できる非公開回答です。'), findsOneWidget);

    await tester.tap(find.byTooltip('コメント操作').last);
    await tester.pumpAndSettle();
    expect(find.text('公開に戻す'), findsOneWidget);
  });

  testWidgets('Teacher preview hides answer box for teacher-hidden question', (
    tester,
  ) async {
    const question = LessonQuestion(
      id: 'teacher-preview-hidden-question',
      authorId: 'student-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '先生が非公開化した公開質問です。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: [],
      moderationStatus: lessonNoteModerationHiddenByTeacher,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            publicQuestionsStream: Stream.value(const [question]),
            answersStream: Stream.value(const []),
            isTeacherPreview: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('先生が非公開化した公開質問です。'));
    await tester.pumpAndSettle();

    expect(find.text('質問詳細'), findsOneWidget);
    expect(find.text('回答コメントを書く'), findsNothing);
  });

  testWidgets('Teacher preview lists teacher-only question mirror', (
    tester,
  ) async {
    const question = LessonQuestion(
      id: 'teacher-only-preview-question',
      authorId: 'student-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '先生だけに見える質問です。',
      visibility: LessonQuestionVisibility.public,
      studentVisibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            publicQuestionsStream: Stream.value(const [question]),
            answersStream: Stream.value(const []),
            isTeacherPreview: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('先生だけに見える質問です。'), findsOneWidget);
    expect(find.text('先生だけ表示 / 先生だけ回答可'), findsWidgets);

    await tester.tap(find.text('先生だけに見える質問です。'));
    await tester.pumpAndSettle();
    expect(find.text('質問詳細'), findsOneWidget);
    expect(find.text('先生だけ表示 / 先生だけ回答可'), findsWidgets);
  });

  testWidgets(
    'Teacher preview can quote learner teacher-only memo when replying',
    (tester) async {
      const question = LessonQuestion(
        id: 'teacher-preview-public-question',
        authorId: 'student-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '公開質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: [],
      );
      const learnerTeacherOnlyNote = LessonNote(
        id: 'learner-teacher-only-note',
        authorId: 'student-b',
        authorName: '別の学習者',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '学習者の先生向けメモ',
        body: '先生だけ引用可',
        folderId: '',
        folderName: '',
        visibility: LessonNoteVisibility.teacherOnly,
        studentVisibility: LessonNoteVisibility.teacherOnly,
        tags: [],
        attachmentTypes: [],
        hasAudioAttachment: false,
        isCopied: false,
        canPublish: true,
        allowsQuestionCitation: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              publicQuestionsStream: Stream.value(const [question]),
              answersStream: Stream.value(const []),
              quotableNotesStream: Stream.value(const [learnerTeacherOnlyNote]),
              isTeacherPreview: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('公開質問です。'));
      await tester.pumpAndSettle();
      expect(find.text('回答コメントを書く'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      expect(find.text('学習者の先生向けメモ'), findsOneWidget);
    },
  );

  testWidgets(
    'Reply composer updates quotable memo options after delayed stream emission',
    (tester) async {
      const question = LessonQuestion(
        id: 'teacher-preview-public-question-delayed-notes',
        authorId: 'student-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '公開質問です（遅延候補）。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: [],
      );
      const delayedNote = LessonNote(
        id: 'learner-teacher-only-note-delayed',
        authorId: 'student-b',
        authorName: '別の学習者',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '遅延で届く先生向けメモ',
        body: 'あとから候補に表示される',
        folderId: '',
        folderName: '',
        visibility: LessonNoteVisibility.teacherOnly,
        studentVisibility: LessonNoteVisibility.teacherOnly,
        tags: [],
        attachmentTypes: [],
        hasAudioAttachment: false,
        isCopied: false,
        canPublish: true,
        allowsQuestionCitation: true,
      );
      final notesController = StreamController<List<LessonNote>>();
      addTearDown(notesController.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              publicQuestionsStream: Stream.value(const [question]),
              answersStream: Stream.value(const []),
              quotableNotesStream: notesController.stream,
              isTeacherPreview: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('公開質問です（遅延候補）。'));
      await tester.pumpAndSettle();
      final dropdownFinder = find.byType(DropdownButtonFormField<String>).last;

      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      expect(find.text('遅延で届く先生向けメモ'), findsNothing);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      notesController.add(const [delayedNote]);
      await tester.pumpAndSettle();

      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      expect(find.text('遅延で届く先生向けメモ'), findsOneWidget);
    },
  );

  testWidgets('Question editor locks scope after posting', (tester) async {
    const question = LessonQuestion(
      id: 'question-locked',
      authorId: 'student-a',
      authorName: 'naonaonaoya70833@gmail.com',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '投稿後は本文だけ編集できます。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.everyone,
      attachmentTypes: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            initialEditingQuestion: question,
            questionsStream: Stream.value(const []),
            publicQuestionsStream: Stream.value(const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('質問を編集'), findsOneWidget);
    expect(find.text('公開範囲と宛先は投稿後に変更できません。'), findsOneWidget);
    expect(find.text('公開範囲: 学習者にも公開'), findsOneWidget);
    expect(find.text('宛先: 全員に質問'), findsOneWidget);
    expect(find.text('他の学習者にも公開する'), findsNothing);
    expect(find.text('引用するメモ'), findsNothing);
  });

  testWidgets('Deleted parent question hides normal answer thread', (
    tester,
  ) async {
    const question = LessonQuestion(
      id: 'question-deleted',
      authorId: 'student-a',
      authorName: 'naonaonaoya70833@gmail.com',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '削除された親質問です。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.everyone,
      attachmentTypes: [],
      isDeleted: true,
    );
    const answer = LessonQuestionAnswer(
      id: 'answer-a',
      questionId: 'question-deleted',
      authorId: 'student-b',
      authorName: '学習者',
      authorRole: 'student',
      body: '親質問が削除されたら通常コメント欄では見せない回答です。',
      attachmentTypes: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            initialSelectedQuestion: question,
            questionsStream: Stream.value(const []),
            publicQuestionsStream: Stream.value(const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('この質問は削除済みのため、コメント欄では表示できません。'), findsOneWidget);
    expect(find.text(answer.body), findsNothing);
  });

  testWidgets('Answer replies are grouped under their direct answer', (
    tester,
  ) async {
    const question = LessonQuestion(
      id: 'question-thread',
      authorId: 'student-a',
      authorName: 'Aさん',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '',
      body: '親質問です。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.everyone,
      attachmentTypes: [],
    );
    final answers = [
      LessonQuestionAnswer(
        id: 'answer-b',
        questionId: 'question-thread',
        authorId: 'student-b',
        authorName: 'Bさん',
        authorRole: 'student',
        body: 'Bさんの直接回答です。',
        attachmentTypes: const [],
        parentCommentId: 'question-thread',
        parentCommentType: 'question',
        replyToDisplayName: 'Aさん',
        replyToBodyPreview: '親質問です。',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 30, 8)),
      ),
      LessonQuestionAnswer(
        id: 'answer-c',
        questionId: 'question-thread',
        authorId: 'student-c',
        authorName: 'Cさん',
        authorRole: 'student',
        body: 'CさんからBさんへの返信です。',
        attachmentTypes: const [],
        parentCommentId: 'answer-b',
        parentCommentType: 'answer',
        replyToDisplayName: 'Bさん',
        replyToBodyPreview: 'Bさんの直接回答です。',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 30, 8, 5)),
      ),
      LessonQuestionAnswer(
        id: 'answer-d',
        questionId: 'question-thread',
        authorId: 'student-d',
        authorName: 'Dさん',
        authorRole: 'student',
        body: 'DさんからCさんへの返信です。',
        attachmentTypes: const [],
        parentCommentId: 'answer-c',
        parentCommentType: 'answer',
        replyToDisplayName: 'Cさん',
        replyToBodyPreview: 'CさんからBさんへの返信です。',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 30, 8, 10)),
      ),
      LessonQuestionAnswer(
        id: 'answer-e',
        questionId: 'question-thread',
        authorId: 'student-e',
        authorName: 'Eさん',
        authorRole: 'student',
        body: 'Eさんの別の直接回答です。',
        attachmentTypes: const [],
        parentCommentId: 'question-thread',
        parentCommentType: 'question',
        replyToDisplayName: 'Aさん',
        replyToBodyPreview: '親質問です。',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 30, 8, 15)),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            initialSelectedQuestion: question,
            questionsStream: Stream.value(const []),
            publicQuestionsStream: Stream.value(const []),
            answersStream: Stream.value(answers),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bさんの直接回答です。'), findsOneWidget);
    expect(find.text('Eさんの別の直接回答です。'), findsOneWidget);
    expect(find.text('返信 2件表示'), findsOneWidget);
    expect(find.text('CさんからBさんへの返信です。'), findsNothing);
    expect(find.text('DさんからCさんへの返信です。'), findsNothing);

    await tester.tap(find.text('返信 2件表示'));
    await tester.pumpAndSettle();

    expect(find.text('回答への返信'), findsOneWidget);
    expect(find.text('CさんからBさんへの返信です。'), findsOneWidget);
    expect(find.text('DさんからCさんへの返信です。'), findsOneWidget);
    expect(find.textContaining('Bさん への返信'), findsOneWidget);
    expect(find.textContaining('Cさん への返信'), findsOneWidget);
  });

  testWidgets(
    'Highlighted direct answer repositions after delayed answer stream updates',
    (tester) async {
      const question = LessonQuestion(
        id: 'question-highlight-reposition',
        authorId: 'student-a',
        authorName: 'Aさん',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '親質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: [],
      );
      final answersController = StreamController<List<LessonQuestionAnswer>>();
      addTearDown(answersController.close);
      final answersStream = answersController.stream.asBroadcastStream();
      final quotableNotesStream =
          Stream<List<LessonNote>>.value(const <LessonNote>[])
              .asBroadcastStream();
      final base = DateTime(2026, 6, 5, 10, 0);
      final answers = List.generate(24, (index) {
        final suffix = index.toString().padLeft(2, '0');
        return LessonQuestionAnswer(
          id: 'answer-$suffix',
          questionId: 'question-highlight-reposition',
          authorId: 'student-$suffix',
          authorName: '学習者$suffix',
          authorRole: 'student',
          body: index == 18 ? 'ハイライト対象 18' : '通常回答 $suffix',
          attachmentTypes: const [],
          parentCommentId: 'question-highlight-reposition',
          parentCommentType: 'question',
          createdAt: Timestamp.fromDate(base.add(Duration(minutes: index))),
          updatedAt: Timestamp.fromDate(base.add(Duration(minutes: index))),
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              initialSelectedQuestion: question,
              initialHighlightedAnswerId: 'answer-18',
              questionsStream: Stream.value(const []),
              publicQuestionsStream: Stream.value(const []),
              answersStream: answersStream,
              quotableNotesStream: quotableNotesStream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      answersController.add([answers[18]]);
      await tester.pumpAndSettle();

      answersController.add(answers);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();

      final highlightedFinder = find.text('ハイライト対象 18');
      expect(highlightedFinder, findsOneWidget);
      final highlightedTop = tester.getTopLeft(highlightedFinder).dy;
      expect(highlightedTop, greaterThanOrEqualTo(0));
      expect(highlightedTop, lessThanOrEqualTo(260));
    },
  );

  testWidgets(
    'Reply thread falls back to teacher label when reply target name is missing',
    (tester) async {
      const question = LessonQuestion(
        id: 'question-reply-fallback-teacher',
        authorId: 'student-a',
        authorName: 'Aさん',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '親質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: [],
      );
      final answers = [
        LessonQuestionAnswer(
          id: 'answer-root',
          questionId: 'question-reply-fallback-teacher',
          authorId: 'student-b',
          authorName: 'Bさん',
          authorRole: 'student',
          body: '直接回答です。',
          attachmentTypes: const [],
          parentCommentId: 'question-reply-fallback-teacher',
          parentCommentType: 'question',
          replyToDisplayName: 'Aさん',
          replyToBodyPreview: '親質問です。',
          createdAt: Timestamp.fromDate(DateTime(2026, 5, 30, 8)),
        ),
        LessonQuestionAnswer(
          id: 'reply-missing-teacher-name',
          questionId: 'question-reply-fallback-teacher',
          authorId: 'student-c',
          authorName: 'Cさん',
          authorRole: 'student',
          body: '返信先名が空でも先生表示にします。',
          attachmentTypes: const [],
          parentCommentId: 'answer-root',
          parentCommentType: 'answer',
          replyToAuthorId: 'teacher-a',
          replyToAuthorRole: 'teacher',
          replyToDisplayName: '',
          replyToBodyPreview: '直接回答です。',
          createdAt: Timestamp.fromDate(DateTime(2026, 5, 30, 8, 5)),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              initialSelectedQuestion: question,
              questionsStream: Stream.value(const []),
              publicQuestionsStream: Stream.value(const []),
              answersStream: Stream.value(answers),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('返信 1件表示'));
      await tester.pumpAndSettle();

      expect(find.text('回答への返信'), findsOneWidget);
      expect(find.textContaining('先生 への返信'), findsOneWidget);
    },
  );

  testWidgets(
    'Reply thread masks email-like reply target when profile is unavailable',
    (tester) async {
      const question = LessonQuestion(
        id: 'question-reply-email-mask',
        authorId: 'student-a',
        authorName: 'Aさん',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '親質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: [],
      );
      final answers = [
        LessonQuestionAnswer(
          id: 'answer-root-email',
          questionId: 'question-reply-email-mask',
          authorId: 'student-b',
          authorName: 'Bさん',
          authorRole: 'student',
          body: '直接回答です。',
          attachmentTypes: const [],
          parentCommentId: 'question-reply-email-mask',
          parentCommentType: 'question',
          replyToDisplayName: 'Aさん',
          replyToBodyPreview: '親質問です。',
          createdAt: Timestamp.fromDate(DateTime(2026, 5, 30, 9)),
        ),
        LessonQuestionAnswer(
          id: 'reply-email-target',
          questionId: 'question-reply-email-mask',
          authorId: 'student-c',
          authorName: 'Cさん',
          authorRole: 'student',
          body: 'メール形式の表示名は画面に出しません。',
          attachmentTypes: const [],
          parentCommentId: 'answer-root-email',
          parentCommentType: 'answer',
          replyToAuthorId: 'student-z',
          replyToAuthorRole: 'student',
          replyToDisplayName: 'private-user@example.com',
          replyToBodyPreview: '直接回答です。',
          createdAt: Timestamp.fromDate(DateTime(2026, 5, 30, 9, 5)),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonQuestionsPanel(
              course: course,
              lesson: lesson,
              lessonNumber: 1,
              initialSelectedQuestion: question,
              questionsStream: Stream.value(const []),
              publicQuestionsStream: Stream.value(const []),
              answersStream: Stream.value(answers),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('返信 1件表示'));
      await tester.pumpAndSettle();

      expect(find.text('回答への返信'), findsOneWidget);
      expect(find.textContaining('学習者 への返信'), findsOneWidget);
      expect(find.textContaining('private-user@example.com'), findsNothing);
    },
  );
}
