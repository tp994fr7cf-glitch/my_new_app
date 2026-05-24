import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_new_app/main.dart';
import 'package:my_new_app/screens/course_list_page.dart';

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
    await tester.pumpWidget(const MaterialApp(home: CourseListPage()));

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
}
