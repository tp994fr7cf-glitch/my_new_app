import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_playback_mode.dart';
import 'package:my_new_app/models/lesson_timed_anchor.dart';
import 'package:my_new_app/screens/teacher_quiz_manage_page.dart';

void main() {
  const segmentA = LessonMediaSegment(
    id: 'a',
    order: 0,
    title: '導入',
    durationSec: 10,
  );
  const segmentB = LessonMediaSegment(
    id: 'b',
    order: 1,
    title: '演習',
    durationSec: 20,
  );
  const draftSegment = LessonMediaSegment(
    id: 'draft',
    order: 2,
    title: '未公開',
    durationSec: 30,
  );

  Course course({
    List<LessonEvent> events = const [],
    String lessonTitle = '最新レッスン名',
    List<LessonMediaSegment> segments = const [
      segmentA,
      segmentB,
      draftSegment,
    ],
    List<String> publishedSegmentIds = const ['a', 'b'],
    LessonPlaybackMode playbackMode = LessonPlaybackMode.continuous,
  }) {
    return Course(
      id: 'course',
      title: '講座',
      instructorName: '先生',
      category: 'テスト',
      level: '初級',
      duration: '30秒',
      lessonCount: 1,
      rating: 0,
      priceLabel: '無料',
      description: '',
      lessons: [
        CourseLesson(
          title: lessonTitle,
          duration: '30秒',
          mediaSegments: segments,
          publishedSegmentIds: publishedSegmentIds,
          playbackMode: playbackMode,
        ),
      ],
      lessonEvents: events,
    );
  }

  Future<void> enterQuizContent(WidgetTester tester) async {
    await tester.enterText(find.bySemanticsLabel('問題文'), '問題');
    await tester.enterText(find.bySemanticsLabel('選択肢1'), 'A');
    await tester.enterText(find.bySemanticsLabel('選択肢2'), 'B');
    await tester.pump();
  }

  testWidgets('new quiz defaults to first published part and can switch part', (
    tester,
  ) async {
    var saved = <LessonEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherQuizManagePage(
          course: course(),
          lessonNumber: 1,
          onSaveOverride: (events) async => saved = events,
        ),
      ),
    );

    expect(find.text('最新レッスン名'), findsOneWidget);
    await tester.tap(find.text('クイズを追加'));
    await tester.pumpAndSettle();
    expect(find.text('パート1：導入'), findsOneWidget);
    expect(find.text('未公開'), findsNothing);

    await tester.tap(find.text('パート1：導入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('パート2：演習').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('表示タイミング（秒）'), '20');
    await enterQuizContent(tester);

    await tester.ensureVisible(find.text('クイズを保存'));
    await tester.tap(find.text('クイズを保存'));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.anchorType, LessonTimedAnchorType.segment);
    expect(saved.single.segmentId, 'b');
    expect(saved.single.timestampSec, 20);
    expect(saved.single.globalTimestampSec, 30);
  });

  testWidgets('local seconds outside selected part disable save', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherQuizManagePage(
          course: course(),
          lessonNumber: 1,
          onSaveOverride: (_) async {},
        ),
      ),
    );
    await tester.tap(find.text('クイズを追加'));
    await tester.pumpAndSettle();
    await enterQuizContent(tester);
    await tester.enterText(find.bySemanticsLabel('表示タイミング（秒）'), '11');
    await tester.pump();

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'クイズを保存'),
    );
    expect(saveButton.onPressed, isNull);
    expect(find.text('選択したパートの開始位置から数えた秒数です。'), findsOneWidget);
  });

  testWidgets('loaded latest course supplies title and published parts', (
    tester,
  ) async {
    final stale = course(
      lessonTitle: '古いレッスン名',
      segments: const [segmentA],
      publishedSegmentIds: const ['a'],
    );
    final latest = course();
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherQuizManagePage(
          course: stale,
          lessonNumber: 1,
          onLoadCourseOverride: () async => latest,
          onSaveOverride: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最新レッスン名'), findsOneWidget);
    expect(find.text('古いレッスン名'), findsNothing);
    await tester.tap(find.text('クイズを追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('パート1：導入'));
    await tester.pumpAndSettle();
    expect(find.text('パート2：演習'), findsOneWidget);
  });

  testWidgets('independent mode requires a published part for new quizzes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherQuizManagePage(
          course: course(
            segments: const [draftSegment],
            publishedSegmentIds: const [],
            playbackMode: LessonPlaybackMode.independentSingle,
          ),
          lessonNumber: 1,
          onSaveOverride: (_) async {},
        ),
      ),
    );

    final addButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'クイズを追加'),
    );
    expect(addButton.onPressed, isNull);
    expect(find.text('独立再生では、クイズを追加する前にメディアパートを公開してください。'), findsOneWidget);
  });

  testWidgets('legacy global quiz keeps explicit legacy option and anchor', (
    tester,
  ) async {
    const legacy = LessonEvent(
      id: 'legacy',
      lessonNumber: 1,
      timestampSec: 12,
      type: 'quiz',
      quiz: LessonQuiz(
        question: '以前の問題',
        choices: ['A', 'B'],
        correctChoiceIndex: 0,
      ),
    );
    var saved = <LessonEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherQuizManagePage(
          course: course(events: const [legacy]),
          lessonNumber: 1,
          onSaveOverride: (events) async => saved = events,
        ),
      ),
    );

    expect(find.text('レッスン全体（以前の形式）'), findsOneWidget);
    await tester.ensureVisible(find.text('クイズを保存'));
    await tester.tap(find.text('クイズを保存'));
    await tester.pumpAndSettle();

    expect(saved.single.anchorType, LessonTimedAnchorType.global);
    expect(saved.single.segmentId, isNull);
    expect(saved.single.timestampSec, 12);
    expect(saved.single.quizVersion, 1);
  });
}
