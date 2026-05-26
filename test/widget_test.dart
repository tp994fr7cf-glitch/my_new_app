import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_new_app/main.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/screens/course_detail_page.dart';
import 'package:my_new_app/screens/course_list_page.dart';
import 'package:my_new_app/screens/home_page.dart';
import 'package:my_new_app/screens/teacher_application_page.dart';
import 'package:my_new_app/screens/teacher_course_list_page.dart';
import 'package:my_new_app/screens/teacher_quiz_manage_page.dart';
import 'package:my_new_app/screens/video_lesson_page.dart';

void main() {
  testWidgets('Firebase setup guidance is shown when setup fails', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(firebaseError: 'test error'));

    expect(find.text('Firebase設定が必要です'), findsOneWidget);
    expect(find.textContaining('ログイン機能を使うには'), findsOneWidget);
  });

  testWidgets('Course list opens course detail page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CourseListPage(courseStream: Stream.value(sampleCourses)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Flutter入門: はじめてのスマホアプリ開発'));
    await tester.pumpAndSettle();

    expect(find.text('講座詳細'), findsOneWidget);
    expect(find.text('講座概要'), findsOneWidget);
    await tester.drag(find.byType(Scrollable), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Flutterで作るアプリの全体像'), findsOneWidget);
    await tester.drag(find.byType(Scrollable), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('受講を開始する'), findsOneWidget);
    await tester.tap(find.text('受講を開始する'));
    await tester.pumpAndSettle();

    expect(find.text('動画視聴'), findsOneWidget);
    expect(find.text('動画プレイヤー仮UI'), findsOneWidget);
    expect(find.text('レッスン1: Flutterで作るアプリの全体像'), findsOneWidget);
  });

  testWidgets('Teacher application page shows application action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherApplicationPage(
          user: _FakeUser(),
          profile: const {
            'roles': ['student'],
            'teacherApplicationStatus': 'none',
          },
          profileStream: Stream.value(const {
            'roles': ['student'],
            'teacherApplicationStatus': 'none',
          }),
        ),
      ),
    );

    expect(find.text('先生申請'), findsOneWidget);
    expect(find.text('未申請'), findsOneWidget);
    expect(find.text('先生として申請する'), findsOneWidget);
  });

  testWidgets('Teacher application page opens input form when not applied', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherApplicationPage(
          user: _FakeUser(),
          profile: const {
            'roles': ['student'],
            'teacherApplicationStatus': 'none',
          },
          profileStream: Stream.value(const {
            'roles': ['student'],
            'teacherApplicationStatus': 'none',
          }),
        ),
      ),
    );

    await tester.tap(find.text('先生として申請する'));
    await tester.pumpAndSettle();

    expect(find.text('先生情報の入力'), findsOneWidget);
    expect(find.text('氏名または表示名'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('申請を送信する'), findsOneWidget);
  });

  testWidgets('Teacher application page reflects latest profile stream', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherApplicationPage(
          user: _FakeUser(),
          profile: const {
            'roles': ['student'],
            'teacherApplicationStatus': 'none',
          },
          profileStream: Stream.value(const {
            'roles': ['student'],
            'teacherApplicationStatus': 'pending',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('申請中'), findsOneWidget);
    await tester.tap(find.text('先生として申請する'));
    await tester.pump();

    expect(find.text('申請中です'), findsOneWidget);
    expect(find.text('先生情報の入力'), findsNothing);
  });

  testWidgets('Teacher application page keeps rejected status', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherApplicationPage(
          user: _FakeUser(),
          profile: const {
            'roles': ['student'],
            'teacherApplicationStatus': 'none',
          },
          profileStream: Stream.value(const {
            'roles': ['student'],
            'teacherApplicationStatus': 'rejected',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('申請却下'), findsOneWidget);
    await tester.tap(find.text('先生として申請する'));
    await tester.pump();

    expect(find.text('申請は却下されました'), findsOneWidget);
    expect(find.text('先生情報の入力'), findsNothing);
  });

  testWidgets('Teacher home opens course creation page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherHomePage(
          user: _FakeUser(),
          profile: const {
            'roles': ['student', 'teacher'],
            'activeRole': 'teacher',
          },
          roles: const ['student', 'teacher'],
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('講座作成へ'));
    await tester.pumpAndSettle();

    expect(find.text('講座作成'), findsOneWidget);
    expect(find.text('講座タイトル'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.text('講座を保存する'), findsOneWidget);
  });

  testWidgets('Teacher course list shows own courses', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherCourseListPage(
          user: _FakeUser(),
          courseStream: Stream.value(sampleCourses.take(1).toList()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('作成した講座'), findsOneWidget);
    expect(find.text('Flutter入門: はじめてのスマホアプリ開発'), findsOneWidget);
    expect(find.text('講座詳細を見る'), findsOneWidget);

    await tester.tap(find.text('講座詳細を見る'));
    await tester.pumpAndSettle();

    expect(find.text('講座確認'), findsOneWidget);
    expect(find.text('この画面は先生用の確認画面です。編集機能は後で追加します。'), findsOneWidget);
    expect(find.text('受講を開始する'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('講座を編集'),
      500,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('講座を編集'), findsOneWidget);
    expect(find.text('レッスンを管理'), findsOneWidget);
    expect(find.text('プレビューを見る'), findsOneWidget);

    await tester.tap(find.text('レッスンを管理'));
    await tester.pumpAndSettle();

    expect(find.text('レッスン管理'), findsOneWidget);
    expect(find.text('授業形式'), findsWidgets);
    expect(find.text('動画・音声URL（仮）'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('クイズを管理').first,
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('クイズを管理').first);
    await tester.pumpAndSettle();

    expect(find.text('クイズ管理'), findsOneWidget);
    expect(find.text('授業の何秒地点でクイズを表示するかを設定できます。'), findsOneWidget);
    expect(find.text('クイズ1'), findsOneWidget);
    expect(find.text('表示タイミング（秒）'), findsOneWidget);
  });

  testWidgets('Course detail shows course code for learners and teachers', (
    WidgetTester tester,
  ) async {
    const course = Course(
      id: 'test-course',
      courseCode: 'ABC123',
      title: '講座コード確認用',
      instructorName: '先生',
      category: 'テスト',
      level: '初級',
      duration: '1時間',
      lessonCount: 1,
      rating: 0,
      priceLabel: '無料',
      description: '講座コードの表示確認',
      lessons: [CourseLesson(title: 'レッスン1', duration: '10分')],
    );

    await tester.pumpWidget(
      const MaterialApp(home: CourseDetailPage(course: course)),
    );
    expect(find.text('講座コード: ABC123'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: CourseDetailPage(course: course, isTeacherMode: true),
      ),
    );
    expect(find.text('講座コード: ABC123'), findsOneWidget);
  });

  testWidgets('Audio lesson page shows audio placeholder', (
    WidgetTester tester,
  ) async {
    final audioCourse = sampleCourses[2];
    final audioLesson = audioCourse.lessons.first;

    await tester.pumpWidget(
      MaterialApp(
        home: VideoLessonPage(
          course: audioCourse,
          lesson: audioLesson,
          lessonNumber: 1,
        ),
      ),
    );

    expect(find.text('音声授業'), findsOneWidget);
    expect(find.text('音声プレイヤー仮UI'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('授業形式: 音声のみ'),
      500,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('授業形式: 音声のみ'), findsOneWidget);
    expect(find.text('動画プレイヤー仮UI'), findsNothing);
  });

  testWidgets('Quiz manage page disables save until quiz is valid', (
    WidgetTester tester,
  ) async {
    var savedEvents = <LessonEvent>[];
    const course = Course(
      id: 'test-course',
      title: 'テスト講座',
      instructorName: '先生',
      category: 'テスト',
      level: '初級',
      duration: '1時間',
      lessonCount: 1,
      rating: 0,
      priceLabel: '無料',
      description: 'テスト用',
      lessons: [CourseLesson(title: 'テストレッスン', duration: '10分')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherQuizManagePage(
          course: course,
          lessonNumber: 1,
          onSaveOverride: (events) async {
            savedEvents = events;
          },
        ),
      ),
    );

    expect(find.text('まだクイズがありません。「クイズを追加」から作成してください。'), findsOneWidget);
    FilledButton saveButton() => tester
        .widgetList<FilledButton>(
          find.byType(FilledButton, skipOffstage: false),
        )
        .last;
    expect(saveButton().onPressed, isNull);

    await tester.tap(find.text('クイズを追加'));
    await tester.pumpAndSettle();
    expect(saveButton().onPressed, isNull);

    await tester.enterText(find.bySemanticsLabel('問題文'), 'Flutterの基本単位は？');
    await tester.enterText(find.bySemanticsLabel('選択肢1'), 'Widget');
    await tester.enterText(find.bySemanticsLabel('選択肢2'), 'Database');
    await tester.pumpAndSettle();

    expect(saveButton().onPressed, isNotNull);
    await tester.ensureVisible(find.text('クイズを保存'));
    await tester.tap(find.text('クイズを保存'));
    await tester.pumpAndSettle();

    expect(savedEvents, hasLength(1));
    expect(savedEvents.first.quiz?.question, 'Flutterの基本単位は？');
  });

  testWidgets('Video lesson page shows and answers quiz event', (
    WidgetTester tester,
  ) async {
    LessonEvent? savedEvent;
    int? savedChoiceIndex;
    bool? savedIsCorrect;

    final course = sampleCourses.first;

    await tester.pumpWidget(
      MaterialApp(
        home: VideoLessonPage(
          course: course,
          lesson: course.lessons.first,
          lessonNumber: 1,
          onQuizAnswerSaveOverride:
              ({
                required event,
                required selectedChoiceIndex,
                required isCorrect,
              }) async {
                savedEvent = event;
                savedChoiceIndex = selectedChoiceIndex;
                savedIsCorrect = isCorrect;
              },
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('授業中クイズ'),
      500,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('授業中クイズ'), findsOneWidget);
    expect(find.text('Flutterで画面を作るときの基本単位はどれですか？'), findsOneWidget);

    await tester.tap(find.text('Widget'));
    await tester.tap(find.text('回答する'));
    await tester.pumpAndSettle();

    expect(find.text('結果: 正解'), findsOneWidget);
    expect(savedEvent?.id, 'sample-flutter-quiz-1');
    expect(savedChoiceIndex, 0);
    expect(savedIsCorrect, isTrue);
  });
}

class _FakeUser implements User {
  @override
  String get uid => 'test-user';

  @override
  String? get displayName => 'テストユーザー';

  @override
  String? get email => 'test@example.com';

  @override
  String? get phoneNumber => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
