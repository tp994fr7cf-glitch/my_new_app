import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_new_app/main.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/screens/course_list_page.dart';
import 'package:my_new_app/screens/home_page.dart';
import 'package:my_new_app/screens/teacher_application_page.dart';
import 'package:my_new_app/screens/teacher_course_list_page.dart';

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
