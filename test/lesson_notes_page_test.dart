import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_note.dart';
import 'package:my_new_app/screens/lesson_notes_page.dart';
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

  testWidgets('Video lesson page expands notes without navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoLessonPage(course: course, lesson: lesson, lessonNumber: 1),
      ),
    );

    await tester.scrollUntilVisible(find.text('レッスンメモを開く'), 500);
    await tester.tap(find.text('レッスンメモを開く'));
    await tester.pumpAndSettle();

    expect(find.text('レッスンメモ'), findsOneWidget);
    expect(find.text('自分のメモ'), findsWidgets);
    expect(find.text('公開メモ'), findsWidgets);
    expect(find.text('動画視聴', skipOffstage: false), findsOneWidget);
    expect(find.text('レッスンメモを閉じる'), findsOneWidget);
  });

  testWidgets('Lesson notes page shows private and public notes', (
    tester,
  ) async {
    const privateNote = LessonNote(
      id: 'private-note',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '自分のメモ',
      body: '移項を復習する',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.private,
      tags: ['復習'],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
    );
    const publicNote = LessonNote(
      id: 'public-note',
      authorId: 'user-b',
      authorName: '他の学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '公開メモ',
      body: '両辺に同じ計算をする',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: ['重要'],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LessonNotesPage(
          course: course,
          lesson: lesson,
          lessonNumber: 1,
          notesStream: Stream.value([privateNote]),
          publicNotesStream: Stream.value([publicNote]),
          foldersStream: Stream.value(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自分のメモ'), findsWidgets);
    expect(find.text('移項を復習する'), findsOneWidget);

    await tester.tap(find.text('公開メモ'));
    await tester.pumpAndSettle();

    expect(find.text('両辺に同じ計算をする'), findsOneWidget);
    expect(find.text('コピー・評価・お気に入りは後で追加します。'), findsOneWidget);
  });

  testWidgets('Audio attachments disable public note publishing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LessonNotesPage(
          course: course,
          lesson: lesson,
          lessonNumber: 1,
          notesStream: Stream.value(const []),
          publicNotesStream: Stream.value(const []),
          foldersStream: Stream.value(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('メモを作成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('音声'));
    await tester.pumpAndSettle();

    expect(find.text('音声添付またはコピー元メモは公開できません。'), findsOneWidget);
    final switchTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '受講者と先生に公開する'),
    );
    expect(switchTile.onChanged, isNull);
  });
}
