import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
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
      expect(find.text('引用する公開メモ'), findsOneWidget);

      await tester.tap(find.text('全員に質問'));
      await tester.pumpAndSettle();

      final switchTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '他の学習者にも公開する'),
      );
      expect(switchTile.value, isTrue);
      expect(switchTile.onChanged, isNull);
    },
  );

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

    await tester.tap(find.text('先生にだけ回答してほしい質問です。'));
    await tester.pumpAndSettle();

    expect(find.text('質問詳細'), findsOneWidget);
    expect(find.text('回答コメントを書く'), findsNothing);
    expect(find.text('学習者にも公開 / 先生だけ回答可'), findsOneWidget);
  });

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
    expect(find.text('引用する公開メモ'), findsNothing);
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
}
