import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_new_app/main.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/screens/course_detail_page.dart';
import 'package:my_new_app/screens/course_list_page.dart';
import 'package:my_new_app/screens/home_page.dart';
import 'package:my_new_app/screens/learning_records_page.dart';
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

  testWidgets('Course list filters by course code', (
    WidgetTester tester,
  ) async {
    const courses = [
      Course(
        id: 'course-a',
        courseCode: 'ABC123',
        title: 'コードで探せる講座',
        instructorName: '先生A',
        category: '数学',
        level: '初級',
        duration: '1時間',
        lessonCount: 1,
        rating: 0,
        priceLabel: '無料',
        description: '講座コード検索テスト',
        lessons: [CourseLesson(title: 'レッスン1', duration: '10分')],
      ),
      Course(
        id: 'course-b',
        courseCode: 'XYZ789',
        title: '別の講座',
        instructorName: '先生B',
        category: '英語',
        level: '初級',
        duration: '1時間',
        lessonCount: 1,
        rating: 0,
        priceLabel: '無料',
        description: '別講座',
        lessons: [CourseLesson(title: 'レッスン1', duration: '10分')],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(home: CourseListPage(courseStream: Stream.value(courses))),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.bySemanticsLabel('講座コード・講座名・先生名・カテゴリで検索'),
      'ABC123',
    );
    await tester.pumpAndSettle();

    expect(find.text('コードで探せる講座'), findsOneWidget);
    expect(find.text('別の講座'), findsNothing);

    await tester.enterText(
      find.bySemanticsLabel('講座コード・講座名・先生名・カテゴリで検索'),
      'NOPE',
    );
    await tester.pumpAndSettle();

    expect(find.text('「NOPE」に一致する講座は見つかりませんでした。'), findsOneWidget);
  });

  testWidgets('Learning records page shows view and quiz records', (
    WidgetTester tester,
  ) async {
    final now = Timestamp.fromDate(DateTime.now());

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          learningEventsStream: Stream.value([
            {
              'courseTitle': 'Flutter入門',
              'lessonTitle': '全体像',
              'createdAt': now,
            },
          ]),
          quizAttemptsStream: Stream.value([
            {
              'courseTitle': 'Flutter入門',
              'lessonTitle': '全体像',
              'question': 'Widgetとは？',
              'isCorrect': true,
              'answeredAt': now,
            },
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('学習記録'), findsWidgets);
    expect(find.text('視聴記録'), findsWidgets);
    expect(find.text('クイズ回答'), findsOneWidget);
    expect(find.text('質問コメント'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('7日間'), findsOneWidget);
    expect(find.text('Flutter入門'), findsOneWidget);
    expect(find.text('レッスン: 全体像'), findsOneWidget);

    await tester.tap(find.text('クイズ回答'));
    await tester.pumpAndSettle();

    expect(find.text('正解数 1 / 1'), findsOneWidget);
    expect(find.text('Widgetとは？'), findsOneWidget);

    await tester.tap(find.text('質問コメント'));
    await tester.pumpAndSettle();

    expect(find.text('質問コメント記録は、質問コメント機能の実装後にここへ表示します。'), findsOneWidget);
  });

  testWidgets('Learning records page keeps repeated course views', (
    WidgetTester tester,
  ) async {
    final now = Timestamp.fromDate(DateTime.now());

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          learningEventsStream: Stream.value([
            {
              'courseTitle': 'Flutter入門',
              'lessonTitle': '全体像',
              'createdAt': now,
            },
            {
              'courseTitle': 'Flutter入門',
              'lessonTitle': '全体像',
              'createdAt': now,
            },
          ]),
          quizAttemptsStream: const Stream.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Flutter入門'), findsNWidgets(2));
    expect(find.text('レッスン: 全体像'), findsNWidgets(2));
  });

  testWidgets('Learning records page shows lesson cycle sessions', (
    WidgetTester tester,
  ) async {
    final startedAt = Timestamp.fromDate(DateTime.now());
    final completedAt = Timestamp.fromDate(DateTime.now());

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          lessonViewSegmentsStream: Stream.value([
            {
              'id': 'segment-1',
              'courseTitle': 'Flutter入門',
              'lessonNumber': 1,
              'lessonTitle': '全体像',
              'cycleNumber': 1,
              'status': 'inProgress',
              'startedAt': startedAt,
              'studySeconds': 61,
              'watchSeconds': 30,
            },
            {
              'id': 'segment-2',
              'courseTitle': 'Flutter入門',
              'lessonNumber': 1,
              'lessonTitle': '全体像',
              'cycleNumber': 2,
              'status': 'completed',
              'completedAt': completedAt,
              'studySeconds': 120,
              'watchSeconds': 90,
            },
          ]),
          learningEventsStream: const Stream.empty(),
          quizAttemptsStream: const Stream.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('レッスン1 1周目'), findsOneWidget);
    expect(find.text('レッスン1 2周目終了'), findsOneWidget);
    expect(find.text('学習時間: 120秒'), findsOneWidget);
    expect(find.text('視聴時間: 90秒'), findsOneWidget);
  });

  testWidgets(
    'Learning records page does not show legacy records after segment deletion',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime.now());

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: Stream.value([
              {
                'id': 'deleted-segment',
                'courseTitle': '削除済み講座',
                'lessonNumber': 1,
                'lessonTitle': '削除済みレッスン',
                'cycleNumber': 1,
                'status': 'completed',
                'completedAt': now,
                'studySeconds': 120,
                'watchSeconds': 90,
                'isDeleted': true,
              },
            ]),
            learningEventsStream: Stream.value([
              {
                'courseTitle': '古い講座',
                'lessonTitle': '古いレッスン',
                'createdAt': now,
              },
            ]),
            quizAttemptsStream: const Stream.empty(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('この期間の視聴記録はまだありません。'), findsOneWidget);
      expect(find.text('古い講座'), findsNothing);
      expect(find.text('削除済み講座'), findsNothing);
    },
  );

  testWidgets(
    'Learning records page renumbers cycles after a full cycle deletion',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime.now());

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: Stream.value([
              {
                'id': 'cycle-5',
                'courseId': 'course-a',
                'courseTitle': '講座A',
                'lessonNumber': 1,
                'lessonTitle': 'レッスン1',
                'cycleNumber': 5,
                'status': 'completed',
                'completedAt': now,
                'studySeconds': 50,
                'watchSeconds': 10,
              },
              {
                'id': 'cycle-4',
                'courseId': 'course-a',
                'courseTitle': '講座A',
                'lessonNumber': 1,
                'lessonTitle': 'レッスン1',
                'cycleNumber': 4,
                'status': 'completed',
                'completedAt': now,
                'studySeconds': 40,
                'watchSeconds': 10,
              },
              {
                'id': 'cycle-3-deleted-1',
                'courseId': 'course-a',
                'courseTitle': '講座A',
                'lessonNumber': 1,
                'lessonTitle': 'レッスン1',
                'cycleNumber': 3,
                'status': 'completed',
                'completedAt': now,
                'studySeconds': 30,
                'watchSeconds': 10,
                'isDeleted': true,
              },
              {
                'id': 'cycle-3-deleted-2',
                'courseId': 'course-a',
                'courseTitle': '講座A',
                'lessonNumber': 1,
                'lessonTitle': 'レッスン1',
                'cycleNumber': 3,
                'status': 'inProgress',
                'startedAt': now,
                'studySeconds': 20,
                'watchSeconds': 5,
                'isDeleted': true,
              },
              {
                'id': 'cycle-2',
                'courseId': 'course-a',
                'courseTitle': '講座A',
                'lessonNumber': 1,
                'lessonTitle': 'レッスン1',
                'cycleNumber': 2,
                'status': 'completed',
                'completedAt': now,
                'studySeconds': 20,
                'watchSeconds': 10,
              },
            ]),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('レッスン1 4周目終了'), findsOneWidget);
      expect(find.text('レッスン1 3周目終了'), findsOneWidget);
      expect(find.text('レッスン1 2周目終了'), findsOneWidget);
      expect(find.text('レッスン1 5周目終了'), findsNothing);
    },
  );

  testWidgets(
    'Learning records page keeps cycle numbers after a partial cycle deletion',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime.now());

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: Stream.value([
              {
                'id': 'cycle-4',
                'courseId': 'course-a',
                'courseTitle': '講座A',
                'lessonNumber': 1,
                'lessonTitle': 'レッスン1',
                'cycleNumber': 4,
                'status': 'completed',
                'completedAt': now,
                'studySeconds': 40,
                'watchSeconds': 10,
              },
              {
                'id': 'cycle-3-visible',
                'courseId': 'course-a',
                'courseTitle': '講座A',
                'lessonNumber': 1,
                'lessonTitle': 'レッスン1',
                'cycleNumber': 3,
                'status': 'inProgress',
                'startedAt': now,
                'studySeconds': 20,
                'watchSeconds': 5,
              },
              {
                'id': 'cycle-3-deleted',
                'courseId': 'course-a',
                'courseTitle': '講座A',
                'lessonNumber': 1,
                'lessonTitle': 'レッスン1',
                'cycleNumber': 3,
                'status': 'completed',
                'completedAt': now,
                'studySeconds': 30,
                'watchSeconds': 10,
                'isDeleted': true,
              },
            ]),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('レッスン1 4周目終了'), findsOneWidget);
      expect(find.text('レッスン1 3周目'), findsOneWidget);
    },
  );

  testWidgets('Student home opens learning records page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StudentHomePage(
          user: _FakeUser(),
          profile: const {
            'roles': ['student'],
            'activeRole': 'student',
          },
          roles: const ['student'],
        ),
      ),
    );

    final recordsButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '学習記録を見る'),
    );
    recordsButton.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('視聴記録'), findsWidgets);
    expect(find.text('クイズ回答'), findsOneWidget);
  });

  testWidgets('Student home limits resume courses and opens full list', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final enrollments = [
      _enrollmentData('講座1', now),
      _enrollmentData('講座2', now.subtract(const Duration(minutes: 1))),
      _enrollmentData('講座3', now.subtract(const Duration(minutes: 2))),
      _enrollmentData('講座4', now.subtract(const Duration(minutes: 3))),
    ];
    final enrollmentStream = Stream<List<Map<String, dynamic>>>.multi((
      controller,
    ) {
      controller.add(enrollments);
      controller.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StudentHomePage(
          user: _FakeUser(),
          profile: const {
            'roles': ['student'],
            'activeRole': 'student',
          },
          roles: const ['student'],
          enrollmentRecordsStream: enrollmentStream,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('講座1'), findsOneWidget);
    expect(find.text('講座2'), findsOneWidget);
    expect(find.text('講座3'), findsOneWidget);
    expect(find.text('講座4'), findsNothing);
    expect(find.text('もっと見る（全4件）'), findsOneWidget);

    await tester.drag(find.byType(Scrollable), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'もっと見る（全4件）'));
    await tester.pumpAndSettle();

    expect(find.text('すべての学習中講座'), findsOneWidget);
    expect(find.text('講座4'), findsOneWidget);
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

  testWidgets('Video lesson placeholder advances playback time', (
    WidgetTester tester,
  ) async {
    final course = sampleCourses.first;

    await tester.pumpWidget(
      MaterialApp(
        home: VideoLessonPage(
          course: course,
          lesson: course.lessons.first,
          lessonNumber: 1,
        ),
      ),
    );

    expect(find.text('00:00 / 01:30'), findsOneWidget);
    expect(find.text('現在位置: 00:00'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:01 / 01:30'), findsOneWidget);
    expect(find.text('現在位置: 00:01'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '一時停止'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '一時停止'));
    await tester.pump();

    final forwardFiveButton = find.widgetWithText(OutlinedButton, '5秒進める（開発用）');
    await tester.scrollUntilVisible(
      forwardFiveButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(forwardFiveButton);
    await tester.pumpAndSettle();

    expect(find.text('現在位置: 00:06', skipOffstage: false), findsOneWidget);
    expect(find.text('視聴時間: 1秒', skipOffstage: false), findsOneWidget);

    final rewindOneButton = find.widgetWithText(OutlinedButton, '1秒巻き戻す（開発用）');
    await tester.tap(rewindOneButton);
    await tester.pumpAndSettle();

    expect(find.text('現在位置: 00:05', skipOffstage: false), findsOneWidget);
    expect(find.text('視聴時間: 1秒', skipOffstage: false), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(Slider),
      -500,
      scrollable: find.byType(Scrollable).first,
    );
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(30);
    await tester.pumpAndSettle();

    expect(find.text('現在位置: 00:30', skipOffstage: false), findsOneWidget);
    expect(find.text('視聴時間: 1秒', skipOffstage: false), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('現在位置: 00:31', skipOffstage: false), findsOneWidget);
    expect(find.text('視聴時間: 2秒', skipOffstage: false), findsOneWidget);
  });

  testWidgets('Video lesson starts from preselected first playback position', (
    WidgetTester tester,
  ) async {
    final course = sampleCourses.first;

    await tester.pumpWidget(
      MaterialApp(
        home: VideoLessonPage(
          course: course,
          lesson: course.lessons.first,
          lessonNumber: 1,
        ),
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(30);
    await tester.pumpAndSettle();

    expect(find.text('現在位置: 00:30'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('現在位置: 00:31'), findsOneWidget);
    expect(find.text('視聴時間: 1秒', skipOffstage: false), findsOneWidget);
  });

  testWidgets('Video lesson completes cycle after threshold', (
    WidgetTester tester,
  ) async {
    final course = sampleCourses.first;

    await tester.pumpWidget(
      MaterialApp(
        home: VideoLessonPage(
          course: course,
          lesson: course.lessons.first,
          lessonNumber: 1,
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pump();
    for (var i = 0; i < 85; i += 1) {
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.scrollUntilVisible(
      find.textContaining('視聴終了地点に到達しました'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('視聴終了地点に到達しました'), findsOneWidget);
  });

  testWidgets('Video lesson manual completion finishes cycle', (
    WidgetTester tester,
  ) async {
    final course = sampleCourses.first;

    await tester.pumpWidget(
      MaterialApp(
        home: VideoLessonPage(
          course: course,
          lesson: course.lessons.first,
          lessonNumber: 1,
        ),
      ),
    );

    final completionButton = find.widgetWithText(OutlinedButton, '視聴終了として記録');
    await tester.scrollUntilVisible(
      completionButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(completionButton);
    await tester.pumpAndSettle();

    expect(find.text('レッスン1 1周目終了として記録しました。'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('授業中クイズ'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('授業中クイズ'), findsOneWidget);
    expect(find.text('Flutterで画面を作るときの基本単位はどれですか？'), findsOneWidget);

    await tester.tap(find.text('Widget'));
    final answerButton = find.widgetWithText(FilledButton, '回答する');
    await tester.scrollUntilVisible(
      answerButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<FilledButton>(answerButton).onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('結果: 正解'), findsOneWidget);
    expect(savedEvent?.id, 'sample-flutter-quiz-1');
    expect(savedChoiceIndex, 0);
    expect(savedIsCorrect, isTrue);
    expect(find.widgetWithText(FilledButton, '回答する'), findsNothing);
    expect(find.text('この周では回答済みです。'), findsOneWidget);
  });
}

Map<String, dynamic> _enrollmentData(String courseTitle, DateTime updatedAt) {
  return {
    'courseId': courseTitle,
    'status': 'inProgress',
    'updatedAt': Timestamp.fromDate(updatedAt),
    'lastLessonNumber': 1,
    'lastLessonTitle': 'レッスン1',
    'course': {
      'id': courseTitle,
      'title': courseTitle,
      'instructorName': '先生',
      'category': 'テスト',
      'level': '初級',
      'duration': '1レッスン',
      'lessonCount': 1,
      'rating': 0,
      'priceLabel': '無料',
      'description': 'テスト用',
      'lessons': [
        {
          'title': 'レッスン1',
          'duration': '1分30秒',
          'mediaType': 'video',
          'mediaUrl': '',
          'isPreview': false,
        },
      ],
      'lessonEvents': [],
    },
  };
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
