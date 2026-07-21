import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/screens/course_create_page.dart';
import 'package:my_new_app/screens/course_detail_page.dart';
import 'package:my_new_app/screens/teacher_course_list_page.dart';
import 'package:my_new_app/screens/teacher_lesson_list_page.dart';
import 'package:my_new_app/services/course_lesson_repository.dart';
import 'package:my_new_app/services/teacher_course_list_service.dart';

void main() {
  test('Course parses teacher list settings and timestamps', () {
    final createdAt = Timestamp.fromDate(DateTime.utc(2026, 7, 20, 9, 30));
    final updatedAt = Timestamp.fromDate(DateTime.utc(2026, 7, 20, 10, 45));

    final course = Course.fromMap({
      'id': 'course-a',
      'title': '講座A',
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'teacherListHidden': true,
      'teacherListOrder': 4,
      'lessons': const [],
    });

    expect(course.createdAt, createdAt);
    expect(course.updatedAt, updatedAt);
    expect(course.teacherListHidden, isTrue);
    expect(course.teacherListOrder, 4);
  });

  test('teacher courses use saved order with title fallback', () {
    final courses = [
      _course(id: 'title-last', title: 'C'),
      _course(id: 'second', title: 'B', teacherListOrder: 1),
      _course(id: 'first', title: 'A', teacherListOrder: 0),
    ];

    expect(sortTeacherCourses(courses).map((course) => course.id), [
      'first',
      'second',
      'title-last',
    ]);
    expect(
      sortTeacherCourses(
        courses,
        preferredIds: ['second', 'first'],
      ).map((course) => course.id),
      ['second', 'first', 'title-last'],
    );
  });

  test('individual lesson documents parse identity, order, and quizzes', () {
    final lesson = CourseLesson.fromMap({
      'title': '個別レッスン',
      'duration': '5分',
      'order': 2,
      'documentVersion': 7,
      'quizVersion': 4,
      'lessonEvents': [
        {
          'id': 'quiz-1',
          'lessonNumber': 3,
          'timestampSec': 5,
          'type': 'quiz',
          'quiz': {
            'question': '問題',
            'choices': ['A', 'B'],
            'correctChoiceIndex': 0,
          },
        },
      ],
    }, id: 'lesson-a');

    expect(lesson.id, 'lesson-a');
    expect(lesson.order, 2);
    expect(lesson.documentVersion, 7);
    expect(lesson.quizVersion, 4);
    expect(lesson.lessonEvents.single.id, 'quiz-1');
    expect(
      _course(id: 'course-1', title: '概要').toSummaryMap(),
      isNot(contains('lessons')),
    );
    expect(
      _course(id: 'course-1', title: '概要').toFirestore(),
      isNot(contains('lessons')),
    );
    expect(
      sortCourseLessons([
        lesson,
        const CourseLesson(
          id: 'lesson-b',
          order: 0,
          title: '先',
          duration: '1分',
        ),
      ]).map((item) => item.id),
      ['lesson-b', 'lesson-a'],
    );
  });

  testWidgets('teacher can hide and restore courses in management list', (
    tester,
  ) async {
    final updates = <({String? id, bool hidden})>[];
    final createdAt = Timestamp.fromDate(DateTime.utc(2026, 7, 20, 9, 30));
    final visible = _course(
      id: 'visible',
      title: '表示中の講座',
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final hidden = _course(
      id: 'hidden',
      title: '隠した講座',
      teacherListHidden: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherCourseListPage(
          user: _FakeUser(),
          courseStream: Stream.value([visible, hidden]),
          visibilityUpdater: (course, isHidden) async {
            updates.add((id: course.id, hidden: isHidden));
          },
          orderSaver: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('表示中の講座'), findsOneWidget);
    expect(find.text('非表示の講座（1件）'), findsOneWidget);
    expect(
      find.text('作成日時: ${formatTeacherCourseTimestamp(createdAt)}'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '非表示'));
    await tester.pumpAndSettle();
    expect(updates, [(id: 'visible', hidden: true)]);
    expect(find.text('非表示の講座（2件）'), findsOneWidget);

    await tester.tap(find.text('非表示の講座（2件）'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '再表示').first);
    await tester.pumpAndSettle();
    expect(updates.last.hidden, isFalse);
  });

  testWidgets('teacher course order is saved after reordering', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semanticsHandle = tester.ensureSemantics();
    List<Course>? savedOrder;

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherCourseListPage(
          user: _FakeUser(),
          courseStream: Stream.value([
            _course(id: 'a', title: '講座A', teacherListOrder: 0),
            _course(id: 'b', title: '講座B', teacherListOrder: 1),
          ]),
          visibilityUpdater: (_, _) async {},
          orderSaver: (courses) async {
            savedOrder = courses;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstCourseNode = tester.getSemantics(
      find.byKey(const ValueKey('a')),
    );
    final moveDownActionId = CustomSemanticsAction.getIdentifier(
      const CustomSemanticsAction(label: 'Move down'),
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.customAction,
        nodeId: firstCourseNode.id,
        viewId: tester.view.viewId,
        arguments: moveDownActionId,
      ),
    );
    await tester.pumpAndSettle();

    semanticsHandle.dispose();
    expect(savedOrder?.map((course) => course.id), ['b', 'a']);
  });

  testWidgets('new course starts with only one editable lesson', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CourseCreatePage(user: _FakeUser())),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.text('レッスン1'), findsWidgets);
    expect(find.text('レッスン2'), findsNothing);
    expect(find.text('レッスン3'), findsNothing);
  });

  testWidgets('teacher opens the selected lesson preview from lesson list', (
    tester,
  ) async {
    final course = _course(
      id: null,
      title: 'プレビュー講座',
      lessons: const [
        CourseLesson(title: '最初のレッスン', duration: '10分'),
        CourseLesson(title: '二番目のレッスン', duration: '20分'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: CourseDetailPage(course: course, isTeacherMode: true)),
    );
    await tester.scrollUntilVisible(
      find.text('二番目のレッスン'),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('プレビューを見る'), findsNothing);
    await tester.tap(find.text('二番目のレッスン'));
    await tester.pumpAndSettle();

    expect(find.text('レッスン2: 二番目のレッスン'), findsOneWidget);
    expect(find.textContaining('先生プレビュー中です'), findsOneWidget);
  });

  testWidgets('teacher selects one lesson before editing', (tester) async {
    final course = _course(
      id: 'course-1',
      title: '個別編集講座',
      lessons: const [
        CourseLesson(
          id: 'lesson-1',
          order: 0,
          title: '最初のレッスン',
          duration: '10分',
        ),
        CourseLesson(
          id: 'lesson-2',
          order: 1,
          title: '二番目のレッスン',
          duration: '20分',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonListPage(
          course: course,
          courseStream: Stream.value(course),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('二番目のレッスン'));
    await tester.pumpAndSettle();

    expect(find.text('レッスン管理'), findsOneWidget);
    expect(find.text('二番目のレッスン'), findsOneWidget);
    expect(find.text('最初のレッスン'), findsNothing);
  });

  testWidgets('teacher can add a lesson from the selection screen', (
    tester,
  ) async {
    var addCount = 0;
    final course = _course(id: 'course-1', title: '追加講座');

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonListPage(
          course: course,
          courseStream: Stream.value(course),
          onAddLessonOverride: () async {
            addCount++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'レッスンを追加'));
    await tester.pumpAndSettle();

    expect(addCount, 1);
  });
}

Course _course({
  required String? id,
  required String title,
  int? teacherListOrder,
  bool teacherListHidden = false,
  Timestamp? createdAt,
  Timestamp? updatedAt,
  List<CourseLesson> lessons = const [
    CourseLesson(title: 'レッスン1', duration: '10分'),
  ],
}) {
  return Course(
    id: id,
    courseCode: '${title}CODE',
    title: title,
    instructorName: '先生',
    category: 'テスト',
    level: '初級',
    duration: '${lessons.length}レッスン',
    lessonCount: lessons.length,
    rating: 0,
    priceLabel: '無料',
    description: 'テスト講座',
    lessons: lessons,
    createdAt: createdAt,
    updatedAt: updatedAt,
    teacherListHidden: teacherListHidden,
    teacherListOrder: teacherListOrder,
  );
}

class _FakeUser implements User {
  @override
  String get uid => 'teacher-user';

  @override
  String? get displayName => 'テスト先生';

  @override
  String? get email => 'teacher@example.com';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
