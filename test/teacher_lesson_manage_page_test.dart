import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/screens/teacher_lesson_manage_page.dart';
import 'package:my_new_app/services/lesson_media_storage_service.dart';

class _RecordingMediaStorageService extends LessonMediaStorageService {
  int pickCount = 0;
  int cancelCount = 0;
  String? pickedMediaType;

  @override
  Future<PlatformFile?> pickLessonMediaFile({
    required String mediaType,
  }) async {
    pickCount++;
    pickedMediaType = mediaType;
    return null;
  }

  @override
  void cancelActiveFilePicker() {
    cancelCount++;
  }
}

const _course = Course(
  id: 'course-1',
  title: 'テスト講座',
  instructorName: 'テスト先生',
  category: 'テスト',
  level: '初級',
  duration: '10分',
  lessonCount: 1,
  rating: 0,
  priceLabel: '無料',
  description: 'テスト用講座',
  lessons: [
    CourseLesson(title: 'レッスン1', duration: '10分'),
  ],
);

void main() {
  for (final testCase in [
    (buttonLabel: '音声', mediaType: 'audio', uploadLabel: '音声をアップロード'),
    (buttonLabel: '動画', mediaType: 'video', uploadLabel: '動画をアップロード'),
  ]) {
    testWidgets(
      'パート追加の${testCase.buttonLabel}ボタンからファイル選択を開始する',
      (tester) async {
        final storageService = _RecordingMediaStorageService();
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: TeacherLessonManagePage(
              course: _course,
              mediaStorageService: storageService,
              onSaveOverride: (_) async {},
            ),
          ),
        );

        await tester.tap(find.text('パートを追加'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(testCase.buttonLabel));
        await tester.pumpAndSettle();

        expect(storageService.pickCount, 1);
        expect(storageService.pickedMediaType, testCase.mediaType);
        expect(find.text(testCase.uploadLabel), findsOneWidget);
        expect(find.text('ファイル選択をキャンセルしました。'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        expect(storageService.cancelCount, 1);
      },
    );
  }
}
