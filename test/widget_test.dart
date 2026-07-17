import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_new_app/main.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_note.dart';
import 'package:my_new_app/models/lesson_playback_mode.dart';
import 'package:my_new_app/models/lesson_question.dart';
import 'package:my_new_app/models/lesson_timed_anchor.dart';
import 'package:my_new_app/screens/course_detail_page.dart';
import 'package:my_new_app/screens/course_list_page.dart';
import 'package:my_new_app/screens/home_page.dart';
import 'package:my_new_app/screens/learning_records_page.dart';
import 'package:my_new_app/screens/teacher_application_page.dart';
import 'package:my_new_app/screens/teacher_course_list_page.dart';
import 'package:my_new_app/screens/teacher_interaction_manage_page.dart';
import 'package:my_new_app/screens/teacher_quiz_manage_page.dart';
import 'package:my_new_app/screens/video_lesson_page.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/services/lesson_media_playlist_playback.dart';

void _completeSliderSeek(Slider slider, double value) {
  slider.onChangeStart?.call(value);
  slider.onChanged?.call(value);
  slider.onChangeEnd?.call(value);
}

Course _courseWithPlayableMedia(Course base) {
  final lesson = base.lessons.first;
  return Course(
    id: base.id,
    courseCode: base.courseCode,
    instructorId: base.instructorId,
    title: base.title,
    instructorName: base.instructorName,
    category: base.category,
    level: base.level,
    duration: base.duration,
    lessonCount: base.lessonCount,
    rating: base.rating,
    priceLabel: base.priceLabel,
    description: base.description,
    lessons: [
      CourseLesson(
        title: lesson.title,
        duration: lesson.duration,
        mediaSegments: const [
          LessonMediaSegment(
            id: 'test-segment',
            order: 0,
            mediaType: 'audio',
            url: 'https://example.com/test-lesson.mp3',
            durationSec: 90,
          ),
        ],
        isPreview: lesson.isPreview,
      ),
      ...base.lessons.skip(1),
    ],
    lessonEvents: base.lessonEvents,
  );
}

Widget _playableVideoLessonPage(
  Course course, {
  bool isTeacherPreview = false,
  LessonMediaPlaylistPlaybackFactory? playlistPlaybackFactory,
}) {
  final playableCourse = _courseWithPlayableMedia(course);
  return MaterialApp(
    home: VideoLessonPage(
      course: playableCourse,
      lesson: playableCourse.lessons.first,
      lessonNumber: 1,
      isTeacherPreview: isTeacherPreview,
      playlistPlaybackFactory:
          playlistPlaybackFactory ??
          (() => FakeLessonMediaPlaylistPlayback(totalDurationSec: 90)),
    ),
  );
}

Course _courseWithIndependentLesson(
  Course base, {
  required LessonPlaybackMode playbackMode,
  List<LessonEvent> lessonEvents = const [],
}) {
  const segments = [
    LessonMediaSegment(
      id: 'published-a',
      order: 0,
      mediaType: 'audio',
      title: '公開パートA',
      url: 'https://example.com/a.mp3',
      durationSec: 5,
    ),
    LessonMediaSegment(
      id: 'published-b',
      order: 1,
      mediaType: 'audio',
      title: '公開パートB',
      url: 'https://example.com/b.mp3',
      durationSec: 5,
    ),
    LessonMediaSegment(
      id: 'draft-c',
      order: 2,
      mediaType: 'audio',
      title: '下書きパートC',
      url: 'https://example.com/c.mp3',
      durationSec: 5,
    ),
  ];
  final lesson = CourseLesson(
    title: '独立再生レッスン',
    duration: '10秒',
    mediaSegments: segments,
    publishedSegmentIds: const ['published-a', 'published-b'],
    playbackMode: playbackMode,
    contentRevision: 2,
  );
  return Course(
    id: base.id,
    courseCode: base.courseCode,
    instructorId: base.instructorId,
    title: base.title,
    instructorName: base.instructorName,
    category: base.category,
    level: base.level,
    duration: base.duration,
    lessonCount: 1,
    rating: base.rating,
    priceLabel: base.priceLabel,
    description: base.description,
    lessons: [lesson],
    lessonEvents: lessonEvents,
  );
}

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

    expect(find.text('レッスン視聴'), findsOneWidget);
    expect(find.text('メディアファイルが未設定です'), findsOneWidget);
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
    expect(find.text('質問・回答コメントを見る'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('7日間'), findsOneWidget);
    expect(find.text('Flutter入門'), findsOneWidget);
    expect(find.text('レッスン: 全体像'), findsOneWidget);

    await tester.tap(find.text('クイズ回答'));
    await tester.pumpAndSettle();

    expect(find.text('正解数 1 / 1'), findsOneWidget);
    expect(find.text('Widgetとは？'), findsOneWidget);

    await tester.tap(find.text('質問・回答コメントを見る'));
    await tester.pumpAndSettle();

    expect(find.text('この期間の質問コメントはまだありません。'), findsOneWidget);
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

  testWidgets('Learning records page shows notes and questions', (
    WidgetTester tester,
  ) async {
    final now = Timestamp.fromDate(DateTime.now());
    final note = LessonNote(
      id: 'note-a',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '移項メモ',
      body: '両辺に同じ計算',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.private,
      tags: const [],
      attachmentTypes: const [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      updatedAt: now,
    );
    final question = LessonQuestion(
      id: 'question-a',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '移項の質問',
      body: 'なぜ符号が変わりますか？',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      quotedNoteTitle: '移項メモ',
      quotedNoteBody: '両辺に同じ計算',
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          lessonViewSegmentsStream: const Stream.empty(),
          learningEventsStream: const Stream.empty(),
          quizAttemptsStream: const Stream.empty(),
          lessonNotesStream: Stream.value([note]),
          lessonQuestionsStream: Stream.value([question]),
          lessonQuestionAnswersStream: const Stream.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('レッスンメモ'));
    await tester.pumpAndSettle();
    expect(find.text('移項メモ'), findsOneWidget);
    expect(find.text('非公開メモ'), findsOneWidget);

    await tester.tap(find.text('質問・回答コメントを見る'));
    await tester.pumpAndSettle();
    expect(find.text('質問コメント'), findsWidgets);
    expect(find.text('移項の質問'), findsNothing);
    expect(find.text('なぜ符号が変わりますか？'), findsOneWidget);
    expect(find.text('引用メモ: 移項メモ'), findsOneWidget);
    expect(find.text('先生にだけ公開'), findsOneWidget);

    final detailsButton = find.text('詳しく見る').first;
    await tester.ensureVisible(detailsButton);
    await tester.pumpAndSettle();
    await tester.tap(detailsButton);
    await tester.pumpAndSettle();

    expect(find.text('質問コメントの記録'), findsOneWidget);
    expect(find.text('あなたの質問'), findsOneWidget);
    expect(find.text('引用メモ'), findsOneWidget);
    expect(find.text('移項メモ\n両辺に同じ計算'), findsOneWidget);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('なぜ符号が変わりますか？'));
    await tester.pumpAndSettle();

    expect(find.text('質問詳細'), findsOneWidget);
    expect(find.text('回答コメントはまだありません。'), findsOneWidget);
  });

  testWidgets('Learning records show only student comments in student mode', (
    WidgetTester tester,
  ) async {
    final now = Timestamp.fromDate(DateTime(2026, 6, 1, 10, 0));
    final studentQuestion = LessonQuestion(
      id: 'question-student',
      authorId: 'user-a',
      authorName: '学習者',
      authorRole: 'student',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '学習者として書いた質問',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      updatedAt: now,
    );
    final teacherQuestion = LessonQuestion(
      id: 'question-teacher',
      authorId: 'user-a',
      authorName: '先生',
      authorRole: 'teacher',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '先生として書いた質問',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      updatedAt: now,
    );
    final studentAnswer = LessonQuestionAnswer(
      id: 'answer-student',
      questionId: 'question-student',
      authorId: 'user-a',
      authorName: '学習者',
      authorRole: 'student',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      body: '学習者として書いた回答',
      attachmentTypes: const [],
      createdAt: now,
    );
    final teacherAnswer = LessonQuestionAnswer(
      id: 'answer-teacher',
      questionId: 'question-teacher',
      authorId: 'user-a',
      authorName: '先生',
      authorRole: 'teacher',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      body: '先生として書いた回答',
      attachmentTypes: const [],
      createdAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          activeCommentRole: 'student',
          lessonViewSegmentsStream: const Stream.empty(),
          learningEventsStream: const Stream.empty(),
          quizAttemptsStream: const Stream.empty(),
          lessonNotesStream: const Stream.empty(),
          lessonQuestionsStream: Stream.value([
            studentQuestion,
            teacherQuestion,
          ]),
          lessonQuestionAnswersStream: Stream.value([
            studentAnswer,
            teacherAnswer,
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('質問・回答コメントを見る'));
    await tester.pumpAndSettle();

    expect(find.text('学習者として書いた質問'), findsOneWidget);
    expect(find.text('先生として書いた質問'), findsNothing);

    await tester.tap(find.text('回答コメント'));
    await tester.pumpAndSettle();

    expect(find.text('学習者として書いた回答'), findsOneWidget);
    expect(find.text('先生として書いた回答'), findsNothing);
  });

  testWidgets('Learning records show only teacher comments in teacher mode', (
    WidgetTester tester,
  ) async {
    final now = Timestamp.fromDate(DateTime(2026, 6, 1, 11, 0));
    final studentQuestion = LessonQuestion(
      id: 'question-student-2',
      authorId: 'user-a',
      authorName: '学習者',
      authorRole: 'student',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '学習者側の質問',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      updatedAt: now,
    );
    final teacherQuestion = LessonQuestion(
      id: 'question-teacher-2',
      authorId: 'user-a',
      authorName: '先生',
      authorRole: 'teacher',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '先生側の質問',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      updatedAt: now,
    );
    final studentAnswer = LessonQuestionAnswer(
      id: 'answer-student-2',
      questionId: 'question-student-2',
      authorId: 'user-a',
      authorName: '学習者',
      authorRole: 'student',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      body: '学習者側の回答',
      attachmentTypes: const [],
      createdAt: now,
    );
    final teacherAnswer = LessonQuestionAnswer(
      id: 'answer-teacher-2',
      questionId: 'question-teacher-2',
      authorId: 'user-a',
      authorName: '先生',
      authorRole: 'teacher',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      body: '先生側の回答',
      attachmentTypes: const [],
      createdAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          activeCommentRole: 'teacher',
          lessonViewSegmentsStream: const Stream.empty(),
          learningEventsStream: const Stream.empty(),
          quizAttemptsStream: const Stream.empty(),
          lessonNotesStream: const Stream.empty(),
          lessonQuestionsStream: Stream.value([
            studentQuestion,
            teacherQuestion,
          ]),
          lessonQuestionAnswersStream: Stream.value([
            studentAnswer,
            teacherAnswer,
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('質問・回答コメントを見る'));
    await tester.pumpAndSettle();

    expect(find.text('先生側の質問'), findsOneWidget);
    expect(find.text('学習者側の質問'), findsNothing);

    await tester.tap(find.text('回答コメント'));
    await tester.pumpAndSettle();

    expect(find.text('先生側の回答'), findsOneWidget);
    expect(find.text('学習者側の回答'), findsNothing);
  });

  testWidgets(
    'Learning records hide delete action for different-role records',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 6, 1, 12, 0));
      final teacherQuestion = LessonQuestion(
        id: 'question-teacher-only',
        authorId: 'user-a',
        authorName: '先生',
        authorRole: 'teacher',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '先生だけの質問',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final teacherAnswer = LessonQuestionAnswer(
        id: 'answer-teacher-only',
        questionId: 'question-teacher-only',
        authorId: 'user-a',
        authorName: '先生',
        authorRole: 'teacher',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '先生だけの回答',
        attachmentTypes: const [],
        createdAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            activeCommentRole: 'student',
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([teacherQuestion]),
            lessonQuestionAnswersStream: Stream.value([teacherAnswer]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();

      expect(find.text('この期間の質問コメントはまだありません。'), findsOneWidget);
      expect(find.text('削除'), findsNothing);

      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      expect(find.text('この期間の回答コメントはまだありません。'), findsOneWidget);
      expect(find.text('削除'), findsNothing);
    },
  );

  testWidgets('Learning records page shows answer record previews', (
    WidgetTester tester,
  ) async {
    final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
    final question = LessonQuestion(
      id: 'question-a',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: 'なぜ符号が変わりますか？',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      updatedAt: now,
    );
    final answer = LessonQuestionAnswer(
      id: 'answer-a',
      questionId: 'question-a',
      authorId: 'user-a',
      authorName: '学習者',
      authorRole: 'student',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      body: '両辺に同じ計算をするからです。',
      attachmentTypes: const [],
      replyToDisplayName: '学習者2',
      replyToBodyPreview: 'なぜ符号が変わりますか？',
      createdAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          lessonViewSegmentsStream: const Stream.empty(),
          learningEventsStream: const Stream.empty(),
          quizAttemptsStream: const Stream.empty(),
          lessonNotesStream: const Stream.empty(),
          lessonQuestionsStream: Stream.value([question]),
          lessonQuestionAnswersStream: Stream.value([answer]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('質問・回答コメントを見る'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回答コメント'));
    await tester.pumpAndSettle();

    expect(find.text('回答コメント'), findsWidgets);
    expect(find.text('両辺に同じ計算をするからです。'), findsOneWidget);
    expect(find.text('返信先の控え:'), findsOneWidget);
    expect(find.text('学習者2 の「なぜ符号が変わりますか？」への返信'), findsOneWidget);

    final answerRecord = find.byKey(
      const ValueKey('answer-record-open-answer-a'),
    );
    await tester.ensureVisible(answerRecord);
    await tester.pumpAndSettle();
    await tester.tap(answerRecord);
    await tester.pumpAndSettle();

    expect(find.text('質問詳細'), findsOneWidget);
    expect(find.text('回答への返信'), findsNothing);
    expect(find.text('回答コメント'), findsWidgets);
    expect(find.text('両辺に同じ計算をするからです。'), findsOneWidget);
    expect(find.textContaining('なぜ符号が変わりますか？'), findsWidgets);
    expect(
      find.byKey(const ValueKey('parent-highlighted-question-question-a')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Learning records open reply thread view when highlighted direct answer has replies',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-thread-open',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '親質問です。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final directAnswer = LessonQuestionAnswer(
        id: 'answer-root',
        questionId: 'question-thread-open',
        authorId: 'user-b',
        authorName: '学習者B',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: 'これは親の回答です。',
        attachmentTypes: const [],
        parentCommentId: 'question-thread-open',
        parentCommentType: 'question',
        createdAt: now,
      );
      final reply = LessonQuestionAnswer(
        id: 'answer-reply',
        questionId: 'question-thread-open',
        authorId: 'user-c',
        authorName: '学習者C',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: 'これは親回答への返信です。',
        attachmentTypes: const [],
        parentCommentId: 'answer-root',
        parentCommentType: 'answer',
        replyToDisplayName: '学習者B',
        replyToBodyPreview: 'これは親の回答です。',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 31)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: Stream.value([directAnswer, reply]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      final answerRecord = find.byKey(
        const ValueKey('answer-record-open-answer-root'),
      );
      await tester.ensureVisible(answerRecord);
      await tester.pumpAndSettle();
      await tester.tap(answerRecord);
      await tester.pumpAndSettle();

      expect(find.text('回答への返信'), findsOneWidget);
      expect(find.text('これは親回答への返信です。'), findsOneWidget);
    },
  );

  testWidgets(
    'Learning records keep parent answer highlighted for highlighted reply',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-highlight-parent',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '親質問です。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final parentAnswer = LessonQuestionAnswer(
        id: 'answer-parent',
        questionId: 'question-highlight-parent',
        authorId: 'user-b',
        authorName: '学習者B',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '親回答です。',
        attachmentTypes: const [],
        parentCommentId: 'question-highlight-parent',
        parentCommentType: 'question',
        createdAt: now,
      );
      final highlightedReply = LessonQuestionAnswer(
        id: 'reply-highlighted',
        questionId: 'question-highlight-parent',
        authorId: 'user-c',
        authorName: '学習者C',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '親回答への返信です。',
        attachmentTypes: const [],
        parentCommentId: 'answer-parent',
        parentCommentType: 'answer',
        replyToDisplayName: '学習者B',
        replyToBodyPreview: '親回答です。',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 31)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: Stream.value([
              parentAnswer,
              highlightedReply,
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      final answerRecord = find.byKey(
        const ValueKey('answer-record-open-reply-highlighted'),
      );
      await tester.ensureVisible(answerRecord);
      await tester.pumpAndSettle();
      await tester.tap(answerRecord);
      await tester.pumpAndSettle();

      expect(find.text('回答への返信'), findsOneWidget);
      expect(find.text('親回答への返信です。'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('parent-highlighted-answer-answer-parent')),
        findsOneWidget,
      );
    },
  );

  testWidgets('Learning records keep hidden questions as static records', (
    WidgetTester tester,
  ) async {
    final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
    final question = LessonQuestion(
      id: 'question-hidden',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '先生が非公開化した質問です。',
      visibility: LessonQuestionVisibility.public,
      target: LessonQuestionTarget.everyone,
      attachmentTypes: const [],
      moderationStatus: lessonInteractionModerationHiddenByTeacher,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          lessonViewSegmentsStream: const Stream.empty(),
          learningEventsStream: const Stream.empty(),
          quizAttemptsStream: const Stream.empty(),
          lessonNotesStream: const Stream.empty(),
          lessonQuestionsStream: Stream.value([question]),
          lessonQuestionAnswersStream: const Stream.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('質問・回答コメントを見る'));
    await tester.pumpAndSettle();

    expect(find.text('先生が非公開化した質問です。'), findsOneWidget);
    expect(
      find.text('この質問コメントは削除済み、または現在は表示できません。学習記録として内容だけ表示しています。'),
      findsOneWidget,
    );
    expect(find.text('タップしてコメント欄を開けます。'), findsNothing);
    expect(find.text('削除'), findsOneWidget);

    final hiddenQuestionText = find.text('先生が非公開化した質問です。');
    await tester.ensureVisible(hiddenQuestionText);
    await tester.pumpAndSettle();
    await tester.tap(hiddenQuestionText);
    await tester.pumpAndSettle();

    expect(find.text('質問詳細'), findsNothing);
    expect(find.text('先生が非公開化した質問です。'), findsOneWidget);
  });

  testWidgets(
    'Learning records block public question thread when question platform is disabled',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-public-disabled',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '公開質問欄がオフのときは開けない質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: const [],
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: const Stream.empty(),
            questionPublicEnabledResolver: (_) async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();

      final questionRecord = find.byKey(
        const ValueKey('question-record-open-question-public-disabled'),
      );
      await tester.ensureVisible(questionRecord);
      await tester.pumpAndSettle();
      await tester.tap(questionRecord);
      await tester.pumpAndSettle();

      expect(find.text('質問詳細'), findsNothing);
      expect(find.text('先生により、このレッスンの公開質問欄は非公開化されています。'), findsOneWidget);
    },
  );

  testWidgets(
    'Learning records block public answer thread when question platform is disabled',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-public-answer-disabled',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '公開質問に対する回答カードの遷移確認です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final answer = LessonQuestionAnswer(
        id: 'answer-public-disabled',
        questionId: 'question-public-answer-disabled',
        authorId: 'user-a',
        authorName: '学習者',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '公開質問への回答です。',
        attachmentTypes: const [],
        parentCommentId: 'question-public-answer-disabled',
        parentCommentType: 'question',
        createdAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: Stream.value([answer]),
            questionPublicEnabledResolver: (_) async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      final answerRecord = find.byKey(
        const ValueKey('answer-record-open-answer-public-disabled'),
      );
      await tester.ensureVisible(answerRecord);
      await tester.pumpAndSettle();
      await tester.tap(answerRecord);
      await tester.pumpAndSettle();

      expect(find.text('質問詳細'), findsNothing);
      expect(find.text('先生により、このレッスンの公開質問欄は非公開化されています。'), findsOneWidget);
    },
  );

  testWidgets(
    'Learning records keep teacher-only question thread open even when question platform is disabled',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final teacherOnlyQuestion = LessonQuestion(
        id: 'question-teacher-only-open',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '先生にだけ公開の質問は開けるままにします。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([teacherOnlyQuestion]),
            lessonQuestionAnswersStream: const Stream.empty(),
            questionPublicEnabledResolver: (_) async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      final teacherOnlyRecord = find.byKey(
        const ValueKey('question-record-open-question-teacher-only-open'),
      );
      await tester.ensureVisible(teacherOnlyRecord);
      await tester.pumpAndSettle();
      await tester.tap(teacherOnlyRecord);
      await tester.pumpAndSettle();

      expect(find.text('質問詳細'), findsOneWidget);
      expect(find.text('先生にだけ公開の質問は開けるままにします。'), findsOneWidget);
    },
  );

  testWidgets('Learning records open hidden answers when parent is available', (
    WidgetTester tester,
  ) async {
    final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
    final question = LessonQuestion(
      id: 'question-a',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '親質問は表示できます。',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      updatedAt: now,
    );
    final answer = LessonQuestionAnswer(
      id: 'answer-hidden',
      questionId: 'question-a',
      authorId: 'user-a',
      authorName: '学習者',
      authorRole: 'student',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      body: '先生が非公開化した回答です。',
      attachmentTypes: const [],
      moderationStatus: lessonInteractionModerationHiddenByTeacher,
      createdAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          lessonViewSegmentsStream: const Stream.empty(),
          learningEventsStream: const Stream.empty(),
          quizAttemptsStream: const Stream.empty(),
          lessonNotesStream: const Stream.empty(),
          lessonQuestionsStream: Stream.value([question]),
          lessonQuestionAnswersStream: Stream.value([answer]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('質問・回答コメントを見る'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回答コメント'));
    await tester.pumpAndSettle();

    expect(find.text('先生が非公開化した回答です。'), findsOneWidget);
    expect(find.text('タップしてコメント欄を開けます。'), findsOneWidget);

    final answerRecord = find.byKey(
      const ValueKey('answer-record-open-answer-hidden'),
    );
    await tester.ensureVisible(answerRecord);
    await tester.pumpAndSettle();
    await tester.tap(answerRecord);
    await tester.pumpAndSettle();

    expect(find.text('質問詳細'), findsOneWidget);
    expect(find.text('先生が非公開化した回答です。'), findsOneWidget);
    expect(find.text('先生によって非公開中'), findsOneWidget);
  });

  testWidgets(
    'Learning records keep answer static with exact parent-question unavailable message',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final orphanAnswer = LessonQuestionAnswer(
        id: 'answer-orphan',
        questionId: 'missing-question',
        authorId: 'user-a',
        authorName: '学習者',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '元質問が表示できない回答です。',
        attachmentTypes: const [],
        createdAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: const Stream.empty(),
            lessonQuestionAnswersStream: Stream.value([orphanAnswer]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      expect(find.text('元質問が表示できない回答です。'), findsOneWidget);
      expect(
        find.text('元の質問は削除済み、または現在は表示できません。学習記録として内容だけ表示しています。'),
        findsOneWidget,
      );

      final answerRecord = find.byKey(
        const ValueKey('answer-record-open-answer-orphan'),
      );
      await tester.ensureVisible(answerRecord);
      await tester.pumpAndSettle();
      await tester.tap(answerRecord);
      await tester.pumpAndSettle();

      expect(find.text('質問詳細'), findsNothing);
      expect(find.text('元質問が表示できない回答です。'), findsOneWidget);
    },
  );

  testWidgets(
    'Learning records open hidden reply when parent answer is available',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-reply-hidden',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '親質問は表示できます。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final parentAnswer = LessonQuestionAnswer(
        id: 'answer-parent-visible',
        questionId: 'question-reply-hidden',
        authorId: 'user-b',
        authorName: '学習者B',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '親回答は表示できます。',
        attachmentTypes: const [],
        parentCommentId: 'question-reply-hidden',
        parentCommentType: 'question',
        moderationStatus: lessonInteractionModerationVisible,
        createdAt: now,
      );
      final hiddenReply = LessonQuestionAnswer(
        id: 'reply-hidden-owned',
        questionId: 'question-reply-hidden',
        authorId: 'user-a',
        authorName: '学習者',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '先生に非公開化された返信です。',
        attachmentTypes: const [],
        parentCommentId: 'answer-parent-visible',
        parentCommentType: 'answer',
        replyToDisplayName: '学習者B',
        replyToBodyPreview: '親回答は表示できます。',
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 31)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: Stream.value([
              parentAnswer,
              hiddenReply,
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      final replyRecord = find.byKey(
        const ValueKey('answer-record-open-reply-hidden-owned'),
      );
      await tester.ensureVisible(replyRecord);
      await tester.pumpAndSettle();
      await tester.tap(replyRecord);
      await tester.pumpAndSettle();

      expect(find.text('回答への返信'), findsOneWidget);
      expect(find.text('親回答は表示できます。'), findsOneWidget);
      expect(find.text('先生に非公開化された返信です。'), findsOneWidget);
      expect(find.text('先生によって非公開中'), findsOneWidget);
    },
  );

  testWidgets('Learning records hide self-deleted comments', (
    WidgetTester tester,
  ) async {
    final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
    final question = LessonQuestion(
      id: 'question-deleted',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '削除済みの質問です。',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      isDeleted: true,
      updatedAt: now,
    );
    final answer = LessonQuestionAnswer(
      id: 'answer-deleted',
      questionId: 'question-deleted',
      authorId: 'user-a',
      authorName: '学習者',
      authorRole: 'student',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      body: '削除済みの回答です。',
      attachmentTypes: const [],
      isDeleted: true,
      createdAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          lessonViewSegmentsStream: const Stream.empty(),
          learningEventsStream: const Stream.empty(),
          quizAttemptsStream: const Stream.empty(),
          lessonNotesStream: const Stream.empty(),
          lessonQuestionsStream: Stream.value([question]),
          lessonQuestionAnswersStream: Stream.value([answer]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('質問・回答コメントを見る'));
    await tester.pumpAndSettle();

    expect(find.text('削除済みの質問です。'), findsNothing);
    expect(find.text('削除済みの回答です。'), findsNothing);
    expect(find.text('この期間の質問コメントはまだありません。'), findsOneWidget);
  });

  testWidgets(
    'Learning records open thread when parent answer is deleted but question is available',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-parent-deleted',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '親質問は表示できます。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final deletedParentAnswer = LessonQuestionAnswer(
        id: 'answer-deleted-parent',
        questionId: 'question-parent-deleted',
        authorId: 'user-b',
        authorName: '学習者B',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '削除された親回答です。',
        attachmentTypes: const [],
        parentCommentId: 'question-parent-deleted',
        parentCommentType: 'question',
        isDeleted: true,
        createdAt: now,
      );
      final reply = LessonQuestionAnswer(
        id: 'reply-to-deleted-parent',
        questionId: 'question-parent-deleted',
        authorId: 'user-a',
        authorName: '学習者',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '親回答が削除されても開きたい返信です。',
        attachmentTypes: const [],
        parentCommentId: 'answer-deleted-parent',
        parentCommentType: 'answer',
        replyToDisplayName: '学習者B',
        replyToBodyPreview: '削除された親回答です。',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 31)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: Stream.value([
              deletedParentAnswer,
              reply,
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      final replyRecord = find.byKey(
        const ValueKey('answer-record-open-reply-to-deleted-parent'),
      );
      await tester.ensureVisible(replyRecord);
      await tester.pumpAndSettle();
      expect(
        find.text('返信先の回答は削除済み、または現在は表示できません。学習記録として内容だけ表示しています。'),
        findsOneWidget,
      );

      await tester.tap(replyRecord);
      await tester.pumpAndSettle();

      expect(find.text('質問詳細'), findsOneWidget);
      expect(find.text('親回答が削除されても開きたい返信です。'), findsOneWidget);
      expect(find.text('削除された親回答です。'), findsNothing);
    },
  );

  testWidgets(
    'Learning records keep thread closed when parent question is unavailable',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final hiddenQuestion = LessonQuestion(
        id: 'question-hidden-parent',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '現在は表示できない親質問です。',
        visibility: LessonQuestionVisibility.public,
        target: LessonQuestionTarget.everyone,
        attachmentTypes: const [],
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
        updatedAt: now,
      );
      final reply = LessonQuestionAnswer(
        id: 'reply-parent-question-hidden',
        questionId: 'question-hidden-parent',
        authorId: 'user-a',
        authorName: '学習者',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '親質問が見えない返信です。',
        attachmentTypes: const [],
        parentCommentId: 'missing-answer',
        parentCommentType: 'answer',
        replyToDisplayName: '学習者B',
        replyToBodyPreview: '見えない親回答です。',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 31)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([hiddenQuestion]),
            lessonQuestionAnswersStream: Stream.value([reply]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      final replyRecord = find.byKey(
        const ValueKey('answer-record-open-reply-parent-question-hidden'),
      );
      await tester.ensureVisible(replyRecord);
      await tester.pumpAndSettle();
      expect(
        find.text('元の質問は削除済み、または現在は表示できません。学習記録として内容だけ表示しています。'),
        findsOneWidget,
      );
      expect(find.text('タップしてコメント欄を開けます。'), findsNothing);

      await tester.tap(replyRecord);
      await tester.pumpAndSettle();

      expect(find.text('質問詳細'), findsNothing);
      expect(find.text('親質問が見えない返信です。'), findsOneWidget);
    },
  );

  testWidgets(
    'Learning records open thread even when parent answer is unavailable',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '親質問は表示できます。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final hiddenParentAnswer = LessonQuestionAnswer(
        id: 'answer-hidden-parent',
        questionId: 'question-a',
        authorId: 'user-b',
        authorName: '学習者B',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '表示できない親回答です。',
        attachmentTypes: const [],
        parentCommentId: 'question-a',
        parentCommentType: 'question',
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
        createdAt: now,
      );
      final reply = LessonQuestionAnswer(
        id: 'reply-c',
        questionId: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '親回答が見えなくても残したい返信です。',
        attachmentTypes: const [],
        parentCommentId: 'answer-hidden-parent',
        parentCommentType: 'answer',
        replyToDisplayName: '学習者B',
        replyToBodyPreview: '表示できない親回答です。',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 31)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: Stream.value([
              hiddenParentAnswer,
              reply,
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      final replyRecord = find.byKey(
        const ValueKey('answer-record-open-reply-c'),
      );
      await tester.ensureVisible(replyRecord);
      await tester.pumpAndSettle();
      expect(
        find.text('返信先の回答は削除済み、または現在は表示できません。学習記録として内容だけ表示しています。'),
        findsOneWidget,
      );
      await tester.tap(replyRecord);
      await tester.pumpAndSettle();

      expect(find.text('質問詳細'), findsOneWidget);
      expect(find.text('親回答が見えなくても残したい返信です。'), findsOneWidget);
      expect(find.text('表示できない親回答です。'), findsNothing);
    },
  );

  testWidgets(
    'Learning records open grouped thread when hidden parent is unavailable but root answer is visible',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-thread-root-visible',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '親質問は表示できます。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final rootAnswer = LessonQuestionAnswer(
        id: 'answer-root-visible',
        questionId: 'question-thread-root-visible',
        authorId: 'user-b',
        authorName: '学習者B',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '時系列の基準になる直接回答です。',
        attachmentTypes: const [],
        parentCommentId: 'question-thread-root-visible',
        parentCommentType: 'question',
        replyToDisplayName: '学習者',
        createdAt: now,
      );
      final hiddenParentAnswer = LessonQuestionAnswer(
        id: 'answer-hidden-middle',
        questionId: 'question-thread-root-visible',
        authorId: 'user-c',
        authorName: '学習者C',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '先生によって見えない中間回答です。',
        attachmentTypes: const [],
        parentCommentId: 'answer-root-visible',
        parentCommentType: 'answer',
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 31)),
      );
      final reply = LessonQuestionAnswer(
        id: 'reply-visible-under-root',
        questionId: 'question-thread-root-visible',
        authorId: 'user-a',
        authorName: '学習者',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '中間回答が見えなくても時系列に沿って表示したい返信です。',
        attachmentTypes: const [],
        parentCommentId: 'answer-hidden-middle',
        parentCommentType: 'answer',
        threadRootAnswerId: 'answer-root-visible',
        replyToDisplayName: '学習者C',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 32)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: Stream.value([
              rootAnswer,
              hiddenParentAnswer,
              reply,
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      final replyRecord = find.byKey(
        const ValueKey('answer-record-open-reply-visible-under-root'),
      );
      await tester.ensureVisible(replyRecord);
      await tester.pumpAndSettle();
      await tester.tap(replyRecord);
      await tester.pumpAndSettle();

      expect(find.text('回答への返信'), findsOneWidget);
      expect(find.text('時系列の基準になる直接回答です。'), findsOneWidget);
      expect(find.text('中間回答が見えなくても時系列に沿って表示したい返信です。'), findsOneWidget);
      expect(find.text('この記録の返信'), findsNothing);
      expect(find.text('先生によって見えない中間回答です。'), findsNothing);
    },
  );

  testWidgets(
    'Learning records open second answer detail without showing first question answers',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final questionA = LessonQuestion(
        id: 'record-switch-question-a',
        authorId: 'user-a',
        authorName: '学習者A',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '記録の質問Aです。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final questionB = LessonQuestion(
        id: 'record-switch-question-b',
        authorId: 'user-b',
        authorName: '学習者B',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '記録の質問Bです。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 40)),
      );
      final answerA = LessonQuestionAnswer(
        id: 'record-switch-answer-a',
        questionId: 'record-switch-question-a',
        authorId: 'user-a',
        authorName: '学習者A',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: 'A質問にだけ属する回答本文です。',
        attachmentTypes: const [],
        parentCommentId: 'record-switch-question-a',
        parentCommentType: 'question',
        createdAt: now,
      );
      final answerB = LessonQuestionAnswer(
        id: 'record-switch-answer-b',
        questionId: 'record-switch-question-b',
        authorId: 'user-b',
        authorName: '学習者B',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: 'B質問にだけ属する回答本文です。',
        attachmentTypes: const [],
        parentCommentId: 'record-switch-question-b',
        parentCommentType: 'question',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 41)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([questionA, questionB]),
            lessonQuestionAnswersStream: Stream.value([answerA, answerB]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      final answerARecord = find.byKey(
        const ValueKey('answer-record-open-record-switch-answer-a'),
      );
      await tester.ensureVisible(answerARecord);
      await tester.pumpAndSettle();
      await tester.tap(answerARecord);
      await tester.pumpAndSettle();
      expect(find.text('A質問にだけ属する回答本文です。'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      final answerBRecord = find.byKey(
        const ValueKey('answer-record-open-record-switch-answer-b'),
      );
      await tester.ensureVisible(answerBRecord);
      await tester.pumpAndSettle();
      await tester.tap(answerBRecord);
      await tester.pumpAndSettle();

      expect(find.text('A質問にだけ属する回答本文です。'), findsNothing);
      expect(find.text('B質問にだけ属する回答本文です。'), findsOneWidget);
    },
  );

  testWidgets(
    'Learning records use stored reply timestamp when parent answer is unavailable',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '親質問は表示できます。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final reply = LessonQuestionAnswer(
        id: 'reply-with-stored-time',
        questionId: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '返信先の日時を控えから表示したい返信です。',
        attachmentTypes: const [],
        parentCommentId: 'missing-parent-answer',
        parentCommentType: 'answer',
        replyToDisplayName: '学習者B',
        replyToBodyPreview: '取得不能の親回答です。',
        replyToCreatedAt: now,
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 31)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: Stream.value([reply]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      expect(find.textContaining('学習者B への返信'), findsOneWidget);
      expect(find.textContaining('現在は見ることができません。'), findsOneWidget);
    },
  );

  testWidgets(
    'Learning records prefer reply-time name over parent posted name when reply target is unavailable',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '親質問は表示できます。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final hiddenParentAnswer = LessonQuestionAnswer(
        id: 'answer-hidden-parent-name-priority',
        questionId: 'question-a',
        authorId: 'user-b',
        authorName: '親投稿時点名',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '表示できない親回答です。',
        attachmentTypes: const [],
        parentCommentId: 'question-a',
        parentCommentType: 'question',
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
        createdAt: now,
      );
      final reply = LessonQuestionAnswer(
        id: 'reply-priority-reply-time',
        questionId: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '返信時点名を優先したい返信です。',
        attachmentTypes: const [],
        parentCommentId: 'answer-hidden-parent-name-priority',
        parentCommentType: 'answer',
        replyToDisplayName: '返信時点名',
        replyToBodyPreview: '表示できない親回答です。',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 31)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: Stream.value([
              hiddenParentAnswer,
              reply,
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      expect(find.textContaining('返信時点名 への返信'), findsOneWidget);
      expect(find.textContaining('親投稿時点名 への返信'), findsNothing);
      expect(find.textContaining('現在は見ることができません。'), findsOneWidget);
    },
  );

  testWidgets(
    'Learning records use parent posted name when reply-time name is unavailable',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '親質問は表示できます。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final parentAnswer = LessonQuestionAnswer(
        id: 'answer-parent-fallback-name',
        questionId: 'question-a',
        authorId: 'user-b',
        authorName: '親投稿時点名',
        authorRole: 'student',
        authorProfileVisible: false,
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '親回答本文',
        attachmentTypes: const [],
        parentCommentId: 'question-a',
        parentCommentType: 'question',
        createdAt: now,
      );
      final reply = LessonQuestionAnswer(
        id: 'reply-parent-posted-fallback',
        questionId: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '返信時点名が欠けた返信です。',
        attachmentTypes: const [],
        parentCommentId: 'answer-parent-fallback-name',
        parentCommentType: 'answer',
        replyToDisplayName: '',
        replyToAuthorRole: 'student',
        replyToBodyPreview: '親回答本文',
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 31)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: Stream.value([parentAnswer, reply]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      expect(find.textContaining('親投稿時点名 の「親回答本文」への返信'), findsOneWidget);
    },
  );

  testWidgets(
    'Learning records use stored reply role when reply target name is missing',
    (WidgetTester tester) async {
      final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
      final question = LessonQuestion(
        id: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '',
        body: '親質問は表示できます。',
        visibility: LessonQuestionVisibility.teacherOnly,
        target: LessonQuestionTarget.teacher,
        attachmentTypes: const [],
        updatedAt: now,
      );
      final reply = LessonQuestionAnswer(
        id: 'reply-with-role',
        questionId: 'question-a',
        authorId: 'user-a',
        authorName: '学習者',
        authorRole: 'student',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        body: '返信先の表示名が欠けても役割で見分けたい返信です。',
        attachmentTypes: const [],
        parentCommentId: null,
        parentCommentType: 'answer',
        replyToDisplayName: '',
        replyToAuthorRole: 'teacher',
        replyToCreatedAt: now,
        createdAt: Timestamp.fromDate(DateTime(2026, 5, 31, 13, 31)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LearningRecordsPage(
            user: _FakeUser(),
            lessonViewSegmentsStream: const Stream.empty(),
            learningEventsStream: const Stream.empty(),
            quizAttemptsStream: const Stream.empty(),
            lessonNotesStream: const Stream.empty(),
            lessonQuestionsStream: Stream.value([question]),
            lessonQuestionAnswersStream: Stream.value([reply]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('質問・回答コメントを見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答コメント'));
      await tester.pumpAndSettle();

      expect(find.textContaining('先生 への返信'), findsOneWidget);
      expect(find.textContaining('現在は見ることができません。'), findsOneWidget);
    },
  );

  testWidgets('Learning records never show email in reply target display', (
    WidgetTester tester,
  ) async {
    final now = Timestamp.fromDate(DateTime(2026, 5, 31, 13, 30));
    final question = LessonQuestion(
      id: 'question-a',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '親質問は表示できます。',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      updatedAt: now,
    );
    final answer = LessonQuestionAnswer(
      id: 'answer-email-mask',
      questionId: 'question-a',
      authorId: 'user-a',
      authorName: '学習者',
      authorRole: 'student',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      body: '返信先表示の安全性確認です。',
      attachmentTypes: const [],
      parentCommentId: 'question-a',
      parentCommentType: 'question',
      replyToDisplayName: 'private-user@example.com',
      replyToAuthorRole: 'student',
      createdAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          lessonViewSegmentsStream: const Stream.empty(),
          learningEventsStream: const Stream.empty(),
          quizAttemptsStream: const Stream.empty(),
          lessonNotesStream: const Stream.empty(),
          lessonQuestionsStream: Stream.value([question]),
          lessonQuestionAnswersStream: Stream.value([answer]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('質問・回答コメントを見る'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回答コメント'));
    await tester.pumpAndSettle();

    expect(find.textContaining('学習者 の「親質問は表示できます。」への返信'), findsOneWidget);
    expect(find.textContaining('private-user@example.com'), findsNothing);
  });

  testWidgets('Learning records sort comment records by posted date', (
    WidgetTester tester,
  ) async {
    final older = Timestamp.fromDate(DateTime(2026, 5, 31, 10, 0));
    final newer = Timestamp.fromDate(DateTime(2026, 6, 1, 10, 0));
    final parentQuestion = LessonQuestion(
      id: 'question-root',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '親質問',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      createdAt: newer,
      updatedAt: newer,
    );
    final olderQuestion = LessonQuestion(
      id: 'question-old',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '古い質問です',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      createdAt: older,
      updatedAt: older,
    );
    final newerQuestion = LessonQuestion(
      id: 'question-new',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '新しい質問です',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: const [],
      createdAt: newer,
      updatedAt: newer,
    );
    const unknownQuestion = LessonQuestion(
      id: 'question-unknown',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      title: '',
      body: '日付不明の質問です',
      visibility: LessonQuestionVisibility.teacherOnly,
      target: LessonQuestionTarget.teacher,
      attachmentTypes: [],
    );
    final olderAnswer = LessonQuestionAnswer(
      id: 'answer-old',
      questionId: 'question-root',
      authorId: 'user-a',
      authorName: '学習者',
      authorRole: 'student',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      body: '古い回答です',
      attachmentTypes: const [],
      createdAt: older,
    );
    final newerAnswer = LessonQuestionAnswer(
      id: 'answer-new',
      questionId: 'question-root',
      authorId: 'user-a',
      authorName: '学習者',
      authorRole: 'student',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      body: '新しい回答です',
      attachmentTypes: const [],
      createdAt: newer,
    );
    const unknownAnswer = LessonQuestionAnswer(
      id: 'answer-unknown',
      questionId: 'question-root',
      authorId: 'user-a',
      authorName: '学習者',
      authorRole: 'student',
      courseId: 'course-a',
      courseTitle: '数学',
      lessonNumber: 1,
      lessonTitle: '一次方程式',
      body: '日付不明の回答です',
      attachmentTypes: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LearningRecordsPage(
          user: _FakeUser(),
          lessonViewSegmentsStream: const Stream.empty(),
          learningEventsStream: const Stream.empty(),
          quizAttemptsStream: const Stream.empty(),
          lessonNotesStream: const Stream.empty(),
          lessonQuestionsStream: Stream.value([
            olderQuestion,
            unknownQuestion,
            newerQuestion,
            parentQuestion,
          ]),
          lessonQuestionAnswersStream: Stream.value([
            olderAnswer,
            unknownAnswer,
            newerAnswer,
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('質問・回答コメントを見る'));
    await tester.pumpAndSettle();

    final newQuestionY = tester.getTopLeft(find.text('新しい質問です')).dy;
    final oldQuestionY = tester.getTopLeft(find.text('古い質問です')).dy;
    final unknownQuestionY = tester.getTopLeft(find.text('日付不明の質問です')).dy;
    expect(newQuestionY, lessThan(oldQuestionY));
    expect(oldQuestionY, lessThan(unknownQuestionY));
    expect(find.text('投稿日: 不明'), findsOneWidget);

    await tester.tap(find.text('回答コメント'));
    await tester.pumpAndSettle();

    final newAnswerY = tester.getTopLeft(find.text('新しい回答です')).dy;
    final oldAnswerY = tester.getTopLeft(find.text('古い回答です')).dy;
    final unknownAnswerY = tester.getTopLeft(find.text('日付不明の回答です')).dy;
    expect(newAnswerY, lessThan(oldAnswerY));
    expect(oldAnswerY, lessThan(unknownAnswerY));
    expect(find.text('投稿日: 不明'), findsOneWidget);
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
    expect(find.text('メディアパート'), findsWidgets);
    expect(find.text('パートを追加'), findsWidgets);
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

  testWidgets('Teacher course detail shows unified course settings button', (
    WidgetTester tester,
  ) async {
    const course = Course(
      id: 'test-course',
      courseCode: 'ABC123',
      title: '講座設定ボタン確認用',
      instructorName: '先生',
      category: 'テスト',
      level: '初級',
      duration: '1時間',
      lessonCount: 1,
      rating: 0,
      priceLabel: '無料',
      description: '講座設定ボタンの表示確認',
      lessons: [CourseLesson(title: 'レッスン1', duration: '10分')],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: CourseDetailPage(course: course, isTeacherMode: true),
      ),
    );

    expect(find.text('講座設定'), findsOneWidget);
    expect(find.text('公開メモ・質問を管理'), findsNothing);
    expect(find.text('本名同意設定を管理'), findsNothing);

    await tester.tap(find.text('講座設定'));
    await tester.pumpAndSettle();

    expect(find.text('本名同意・公開投稿の管理'), findsOneWidget);
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
    expect(find.text('メディアファイルが未設定です'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('パート数:'),
      500,
      scrollable: find.byType(Scrollable),
    );
    expect(find.textContaining('パート数:'), findsOneWidget);
    expect(find.text('動画プレイヤー'), findsNothing);
  });

  testWidgets('Video lesson placeholder advances playback time', (
    WidgetTester tester,
  ) async {
    final course = sampleCourses.first;

    await tester.pumpWidget(_playableVideoLessonPage(course));
    await tester.pumpAndSettle();

    expect(find.text('一貫再生'), findsOneWidget);
    expect(find.text('00:00 / 01:30'), findsOneWidget);
    expect(find.text('現在位置: 00:00', skipOffstage: false), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:01 / 01:30'), findsOneWidget);
    expect(find.text('現在位置: 00:01', skipOffstage: false), findsOneWidget);
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
    _completeSliderSeek(slider, 30);
    await tester.pumpAndSettle();

    expect(find.text('00:30 / 01:30'), findsOneWidget);
    expect(find.text('現在位置: 00:30', skipOffstage: false), findsOneWidget);
    expect(find.text('視聴時間: 1秒', skipOffstage: false), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:31 / 01:30'), findsOneWidget);
    expect(find.text('現在位置: 00:31', skipOffstage: false), findsOneWidget);
    expect(find.text('視聴時間: 2秒', skipOffstage: false), findsOneWidget);
  });

  testWidgets(
    'independent single keeps local resumes and auto-plays the next published part',
    (WidgetTester tester) async {
      final course = _courseWithIndependentLesson(
        sampleCourses.first,
        playbackMode: LessonPlaybackMode.independentSingle,
      );
      final segments = course.lessons.first.effectivePublishedMediaSegments;

      await tester.pumpWidget(
        MaterialApp(
          home: VideoLessonPage(
            course: course,
            lesson: course.lessons.first,
            lessonNumber: 1,
            playlistPlaybackFactory: () => FakeLessonMediaPlaylistPlayback(
              totalDurationSec: 10,
              segments: segments,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('独立再生（単一画面）'), findsOneWidget);
      expect(find.text('下書きパートC'), findsNothing);
      expect(
        find.byKey(const ValueKey('lesson-part-button-published-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('lesson-part-button-published-b')),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, '再生'));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.widgetWithText(FilledButton, '一時停止'));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('lesson-part-button-published-b')),
      );
      await tester.pumpAndSettle();
      expect(find.text('00:00 / 00:05'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('lesson-part-button-published-a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('00:02 / 00:05'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '再生'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('lesson-part-player-published-b')),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, '一時停止'), findsOneWidget);
      expect(find.textContaining('公開パートA\n完了'), findsOneWidget);
      expect(find.text('視聴時間: 5秒', skipOffstage: false), findsOneWidget);
    },
  );

  testWidgets('independent panels render one collapsible shared player', (
    WidgetTester tester,
  ) async {
    final course = _courseWithIndependentLesson(
      sampleCourses.first,
      playbackMode: LessonPlaybackMode.independentPanels,
    );
    final segments = course.lessons.first.effectivePublishedMediaSegments;

    await tester.pumpWidget(
      MaterialApp(
        home: VideoLessonPage(
          course: course,
          lesson: course.lessons.first,
          lessonNumber: 1,
          playlistPlaybackFactory: () => FakeLessonMediaPlaylistPlayback(
            totalDurationSec: 10,
            segments: segments,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('独立再生（独立画面）'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('lesson-part-panel-published-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lesson-part-panel-published-b')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lesson-part-player-published-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lesson-part-player-published-b')),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('lesson-part-player-published-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('lesson-part-player-published-b')),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, '一時停止'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '一時停止'));
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('lesson-part-panel-header-published-a')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('lesson-part-player-published-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lesson-part-player-published-b')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('lesson-part-panel-header-published-a')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('lesson-part-player-published-a')),
      findsNothing,
    );
  });

  testWidgets(
    'independent playback filters segment quizzes while retaining global quizzes',
    (WidgetTester tester) async {
      const quiz = LessonQuiz(
        question: 'placeholder',
        choices: ['A', 'B'],
        correctChoiceIndex: 0,
      );
      const events = [
        LessonEvent(
          id: 'segment-a-quiz',
          lessonNumber: 1,
          timestampSec: 0,
          type: 'quiz',
          quiz: LessonQuiz(
            question: 'パートAの問題',
            choices: ['A', 'B'],
            correctChoiceIndex: 0,
          ),
          anchorType: LessonTimedAnchorType.segment,
          segmentId: 'published-a',
        ),
        LessonEvent(
          id: 'segment-b-quiz',
          lessonNumber: 1,
          timestampSec: 0,
          type: 'quiz',
          quiz: LessonQuiz(
            question: 'パートBの問題',
            choices: ['A', 'B'],
            correctChoiceIndex: 0,
          ),
          anchorType: LessonTimedAnchorType.segment,
          segmentId: 'published-b',
        ),
        LessonEvent(
          id: 'global-quiz',
          lessonNumber: 1,
          timestampSec: 0,
          type: 'quiz',
          quiz: quiz,
        ),
      ];
      final course = _courseWithIndependentLesson(
        sampleCourses.first,
        playbackMode: LessonPlaybackMode.independentSingle,
        lessonEvents: events,
      );
      final segments = course.lessons.first.effectivePublishedMediaSegments;

      await tester.pumpWidget(
        MaterialApp(
          home: VideoLessonPage(
            course: course,
            lesson: course.lessons.first,
            lessonNumber: 1,
            playlistPlaybackFactory: () => FakeLessonMediaPlaylistPlayback(
              totalDurationSec: 10,
              segments: segments,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '再生'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('授業中クイズ'),
        500,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('パートAの問題'), findsOneWidget);
      expect(find.text('パートBの問題'), findsNothing);
      expect(find.text('placeholder'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('lesson-part-button-published-b')),
        -500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.byKey(const ValueKey('lesson-part-button-published-b')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('授業中クイズ'),
        500,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('パートAの問題'), findsNothing);
      expect(find.text('パートBの問題'), findsOneWidget);
      expect(find.text('placeholder'), findsOneWidget);
    },
  );

  testWidgets('Video lesson starts from preselected first playback position', (
    WidgetTester tester,
  ) async {
    final course = sampleCourses.first;

    await tester.pumpWidget(_playableVideoLessonPage(course));
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    _completeSliderSeek(slider, 30);
    await tester.pumpAndSettle();

    expect(find.text('00:30 / 01:30'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:31 / 01:30'), findsOneWidget);
    expect(find.text('視聴時間: 1秒', skipOffstage: false), findsOneWidget);
  });

  testWidgets('Video lesson completes cycle after threshold', (
    WidgetTester tester,
  ) async {
    final course = sampleCourses.first;

    await tester.pumpWidget(_playableVideoLessonPage(course));
    await tester.pumpAndSettle();

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

    await tester.pumpWidget(_playableVideoLessonPage(course));
    await tester.pumpAndSettle();

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

  testWidgets('Video lesson can replay after seeking to the end', (
    WidgetTester tester,
  ) async {
    final course = sampleCourses.first;

    await tester.pumpWidget(_playableVideoLessonPage(course));
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    _completeSliderSeek(slider, 90);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'もう一度再生'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'もう一度再生'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:01 / 01:30'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '一時停止'), findsOneWidget);
  });

  testWidgets('Video lesson can resume after rewinding from the end', (
    WidgetTester tester,
  ) async {
    final course = sampleCourses.first;

    await tester.pumpWidget(_playableVideoLessonPage(course));
    await tester.pumpAndSettle();

    final sliderFinder = find.byType(Slider);
    final sliderAtEnd = tester.widget<Slider>(sliderFinder);
    _completeSliderSeek(sliderAtEnd, 90);
    await tester.pumpAndSettle();

    final sliderRewound = tester.widget<Slider>(sliderFinder);
    _completeSliderSeek(sliderRewound, 30);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:31 / 01:30'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '一時停止'), findsOneWidget);
  });

  testWidgets('Teacher preview can replay after natural playback end', (
    WidgetTester tester,
  ) async {
    final course = sampleCourses.first;

    await tester.pumpWidget(
      _playableVideoLessonPage(
        course,
        isTeacherPreview: true,
        playlistPlaybackFactory: () =>
            FakeLessonMediaPlaylistPlayback(totalDurationSec: 90),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pump(const Duration(seconds: 91));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'もう一度再生'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'もう一度再生'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:01 / 01:30'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '一時停止'), findsOneWidget);
  });

  testWidgets('Teacher preview can resume after rewinding from the end', (
    WidgetTester tester,
  ) async {
    final course = sampleCourses.first;

    await tester.pumpWidget(
      _playableVideoLessonPage(course, isTeacherPreview: true),
    );
    await tester.pumpAndSettle();

    final sliderFinder = find.byType(Slider);
    final sliderAtEnd = tester.widget<Slider>(sliderFinder);
    _completeSliderSeek(sliderAtEnd, 90);
    await tester.pumpAndSettle();

    final sliderRewound = tester.widget<Slider>(sliderFinder);
    _completeSliderSeek(sliderRewound, 30);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:31 / 01:30'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '一時停止'), findsOneWidget);
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
    final playableCourse = _courseWithPlayableMedia(course);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoLessonPage(
          course: playableCourse,
          lesson: playableCourse.lessons.first,
          lessonNumber: 1,
          playlistPlaybackFactory: () => FakeLessonMediaPlaylistPlayback(),
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
          'mediaSegments': <Map<String, dynamic>>[],
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
