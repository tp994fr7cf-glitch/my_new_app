import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/screens/video_lesson_page.dart';
import 'package:my_new_app/services/lesson_media_playlist_playback.dart';

Course _twoPartCourse() {
  const lesson = CourseLesson(
    title: 'プレビュー検証',
    duration: '4秒',
    mediaSegments: [
      LessonMediaSegment(
        id: 'live-archive',
        order: 0,
        mediaType: 'audio',
        title: 'パート1',
        url: 'https://example.com/live-archive.mp3',
        durationSec: 2,
      ),
      LessonMediaSegment(
        id: 'record-while-writing',
        order: 1,
        mediaType: 'audio',
        title: 'パート2',
        url: 'https://example.com/record.mp3',
        durationSec: 2,
      ),
    ],
  );
  return const Course(
    id: 'preview-course',
    title: 'プレビュー講座',
    instructorName: '先生',
    category: 'テスト',
    level: '初級',
    duration: '4秒',
    lessonCount: 1,
    rating: 0,
    priceLabel: '無料',
    description: '教師プレビュー検証',
    lessons: [lesson],
  );
}

Finder get _filledReplay => find.widgetWithText(FilledButton, 'もう一度再生');
Finder get _filledPause => find.widgetWithText(FilledButton, '一時停止');
Finder get _filledPlay => find.widgetWithText(FilledButton, '再生');

void main() {
  testWidgets(
    'teacher preview replay still starts after part buttons at the end',
    (tester) async {
      final course = _twoPartCourse();
      await tester.pumpWidget(
        MaterialApp(
          home: VideoLessonPage(
            course: course,
            lesson: course.lessons.first,
            lessonNumber: 1,
            isTeacherPreview: true,
            playlistPlaybackFactory: () => FakeLessonMediaPlaylistPlayback(
              totalDurationSec: 4,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_filledPlay);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(_filledReplay, findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'パート2'));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'パート1'));
      await tester.pump();

      if (tester.any(_filledReplay)) {
        await tester.tap(_filledReplay);
      } else {
        expect(_filledPlay, findsOneWidget);
        await tester.tap(_filledPlay);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_filledPause, findsOneWidget);
    },
  );

  testWidgets(
    'teacher preview play-again after natural end still starts playback',
    (tester) async {
      final course = _twoPartCourse();
      await tester.pumpWidget(
        MaterialApp(
          home: VideoLessonPage(
            course: course,
            lesson: course.lessons.first,
            lessonNumber: 1,
            isTeacherPreview: true,
            playlistPlaybackFactory: () => FakeLessonMediaPlaylistPlayback(
              totalDurationSec: 4,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_filledPlay);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(_filledReplay, findsOneWidget);

      await tester.tap(_filledReplay);
      await tester.pump(const Duration(seconds: 1));

      expect(_filledPause, findsOneWidget);
    },
  );

  testWidgets(
    'teacher preview keeps only the latest end-of-lesson command',
    (tester) async {
      final course = _twoPartCourse();
      await tester.pumpWidget(
        MaterialApp(
          home: VideoLessonPage(
            course: course,
            lesson: course.lessons.first,
            lessonNumber: 1,
            isTeacherPreview: true,
            playlistPlaybackFactory: () => FakeLessonMediaPlaylistPlayback(
              totalDurationSec: 4,
              seekDelay: const Duration(milliseconds: 200),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_filledPlay);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(_filledReplay, findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'パート2'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'パート1'));
      await tester.tap(_filledReplay);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 50));

      expect(_filledPause, findsOneWidget);
      expect(find.textContaining('00:00'), findsWidgets);
    },
  );
}
