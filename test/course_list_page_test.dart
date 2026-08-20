import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/screens/course_list_page.dart';

void main() {
  test('learner course list puts newest created courses first', () {
    final newest = _course(
      id: 'newest',
      title: '新しい講座',
      createdAt: DateTime.utc(2026, 8, 20, 12),
    );
    final older = _course(
      id: 'older',
      title: '古い講座',
      createdAt: DateTime.utc(2026, 1, 1, 9),
    );
    final unknown = _course(id: 'unknown', title: '作成日時なし');

    expect(
      sortLearnerCourses([unknown, older, newest]).map((course) => course.id),
      ['newest', 'older', 'unknown'],
    );
  });

  testWidgets('Course list shows newest created course at the top', (
    WidgetTester tester,
  ) async {
    final courses = [
      _course(
        id: 'older',
        title: '古い講座',
        createdAt: DateTime.utc(2026, 1, 1, 9),
      ),
      _course(
        id: 'newest',
        title: '新しい講座',
        createdAt: DateTime.utc(2026, 8, 20, 12),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(home: CourseListPage(courseStream: Stream.value(courses))),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('新しい講座')).dy,
      lessThan(tester.getTopLeft(find.text('古い講座')).dy),
    );
  });
}

Course _course({
  required String id,
  required String title,
  DateTime? createdAt,
}) {
  return Course(
    id: id,
    title: title,
    instructorName: '先生',
    category: '数学',
    level: '初級',
    duration: '1時間',
    lessonCount: 1,
    rating: 0,
    priceLabel: '無料',
    description: '並び順テスト',
    createdAt: createdAt == null ? null : Timestamp.fromDate(createdAt),
    lessons: const [CourseLesson(title: 'レッスン1', duration: '10分')],
  );
}
