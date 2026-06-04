import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_question.dart';
import 'package:my_new_app/screens/lesson_questions_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('Public question list restores scroll after returning', (
    tester,
  ) async {
    final controller = StreamController<List<LessonQuestion>>.broadcast();
    addTearDown(controller.close);
    final emptyQuestionsStream = Stream<List<LessonQuestion>>.value(
      const [],
    ).asBroadcastStream();

    final questions = List.generate(30, (index) {
      final number = index + 1;
      return LessonQuestion(
        id: 'public-q-$number',
        authorId: 'student-$number',
        authorName: '学習者$number',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '',
        body: '公開質問 $number',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: const [],
        updatedAt: Timestamp.fromDate(
          DateTime(2026, 5, 30, 8, 0, 30 - number),
        ),
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonQuestionsPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            questionsStream: emptyQuestionsStream,
            publicQuestionsStream: controller.stream,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('公開質問'));
    await tester.pumpAndSettle();
    controller.add(questions);
    await tester.pumpAndSettle();
    await _waitUntilVisible(tester, find.text('公開質問 1'));

    final targetQuestion = find.text('公開質問 20');
    final publicQuestionList = find.byKey(
      const PageStorageKey<String>('public-questions'),
    );
    expect(publicQuestionList, findsOneWidget);
    final publicQuestionScrollable = find.descendant(
      of: publicQuestionList,
      matching: find.byType(Scrollable),
    );
    expect(publicQuestionScrollable, findsOneWidget);
    await tester.scrollUntilVisible(
      targetQuestion,
      500,
      scrollable: publicQuestionScrollable,
    );
    await tester.ensureVisible(targetQuestion);
    await tester.pumpAndSettle();
    final offsetBeforeOpen =
        tester.state<ScrollableState>(publicQuestionScrollable).position.pixels;
    await tester.tap(targetQuestion);
    await tester.pumpAndSettle();

    expect(find.text('質問詳細'), findsOneWidget);
    controller.add(const []);
    await tester.pump(const Duration(milliseconds: 80));

    await tester.tap(find.byTooltip('質問一覧に戻る'));
    await tester.pump(const Duration(milliseconds: 120));
    controller.add(questions);
    await tester.pumpAndSettle();
    expect(publicQuestionScrollable, findsOneWidget);
    final offsetAfterReturn =
        tester.state<ScrollableState>(publicQuestionScrollable).position.pixels;
    expect(offsetAfterReturn, greaterThan(24));
    expect((offsetAfterReturn - offsetBeforeOpen).abs(), lessThan(280));
  });
}

Future<void> _waitUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final startedAt = DateTime.now();
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().difference(startedAt) > timeout) {
      fail('Timed out waiting for widget: $finder');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}
