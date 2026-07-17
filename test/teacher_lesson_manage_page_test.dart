import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_playback_mode.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/screens/teacher_lesson_manage_page.dart';
import 'package:my_new_app/services/lesson_media_storage_service.dart';

class _RecordingMediaStorageService extends LessonMediaStorageService {
  int pickCount = 0;
  int cancelCount = 0;
  String? pickedMediaType;

  @override
  Future<PlatformFile?> pickLessonMediaFile({required String mediaType}) async {
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
  lessons: [CourseLesson(title: 'レッスン1', duration: '10分')],
);

const _lockedSegment = LessonMediaSegment(
  id: 'locked',
  order: 0,
  title: '公開済み',
  mediaType: 'video',
  url: 'https://example.com/locked.mp4',
  durationSec: 30,
);

Course _courseWithLesson(CourseLesson lesson) {
  return Course(
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
    lessons: [lesson],
  );
}

void main() {
  for (final testCase in [
    (buttonLabel: '音声', mediaType: 'audio', uploadLabel: '音声をアップロード'),
    (buttonLabel: '動画', mediaType: 'video', uploadLabel: '動画をアップロード'),
  ]) {
    testWidgets('パート追加の${testCase.buttonLabel}ボタンからファイル選択を開始する', (
      tester,
    ) async {
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
    });
  }

  testWidgets('再生モードに列挙値の日本語ラベルと説明を表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: _course,
          onSaveOverride: (_) async {},
        ),
      ),
    );

    final modeDropdown = find.byKey(const ValueKey('lesson-0-playback-mode'));
    expect(modeDropdown, findsOneWidget);
    expect(find.text('一貫再生'), findsOneWidget);
    expect(find.text('すべてのパートを順番に一貫して再生します。'), findsOneWidget);

    await tester.tap(modeDropdown);
    await tester.pumpAndSettle();
    expect(find.text('独立再生（単一画面）'), findsOneWidget);
    expect(find.text('独立再生（独立画面）'), findsOneWidget);
    await tester.tap(find.text('独立再生（独立画面）'));
    await tester.pumpAndSettle();
    expect(find.text('各パートをそれぞれ独立した画面で再生します。'), findsOneWidget);
  });

  testWidgets('公開済みパートの操作を無効化し新規パートは末尾にだけ追加する', (tester) async {
    final storageService = _RecordingMediaStorageService();
    final course = _courseWithLesson(
      const CourseLesson(
        title: 'ロック済み',
        duration: '30秒',
        mediaSegments: [_lockedSegment],
        publishedSegmentIds: ['locked'],
        playbackMode: LessonPlaybackMode.independentSingle,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: course,
          mediaStorageService: storageService,
          onSaveOverride: (_) async {},
        ),
      ),
    );

    final mode = tester.widget<DropdownButtonFormField<LessonPlaybackMode>>(
      find.byKey(const ValueKey('lesson-0-playback-mode')),
    );
    expect(mode.onChanged, isNull);
    expect(find.text('公開済みのパートがあるため、再生モードは変更できません。'), findsOneWidget);
    expect(find.text('公開済み（タイトルのみ変更できます）'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '動画をアップロード'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.arrow_upward),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.arrow_downward),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .onPressed,
      isNull,
    );

    await tester.ensureVisible(find.text('パートを追加'));
    await tester.tap(find.text('パートを追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('音声'));
    await tester.pumpAndSettle();

    expect(find.text('パート2'), findsOneWidget);
    final deleteButtons = find.widgetWithIcon(IconButton, Icons.delete_outline);
    expect(deleteButtons, findsNWidgets(2));
    expect(tester.widget<IconButton>(deleteButtons.at(0)).onPressed, isNull);
    expect(tester.widget<IconButton>(deleteButtons.at(1)).onPressed, isNotNull);
    final downButtons = find.widgetWithIcon(IconButton, Icons.arrow_downward);
    final upButtons = find.widgetWithIcon(IconButton, Icons.arrow_upward);
    expect(tester.widget<IconButton>(downButtons.at(0)).onPressed, isNull);
    expect(tester.widget<IconButton>(upButtons.at(1)).onPressed, isNull);
  });

  testWidgets('保存時に新しいURL付き末尾パートをロックしリビジョンを一度だけ増やす', (tester) async {
    const tail = LessonMediaSegment(
      id: 'tail',
      order: 1,
      title: '新規末尾',
      mediaType: 'video',
      url: 'https://example.com/tail.mp4',
      durationSec: 20,
    );
    final course = _courseWithLesson(
      const CourseLesson(
        title: '追記',
        duration: '50秒',
        mediaSegments: [_lockedSegment, tail],
        publishedSegmentIds: ['locked'],
        contentRevision: 4,
      ),
    );
    var saves = <List<CourseLesson>>[];
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: course,
          onSaveOverride: (lessons) async {
            saves.add(lessons);
          },
        ),
      ),
    );

    await tester.ensureVisible(find.text('レッスン情報を保存'));
    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();

    expect(saves, hasLength(1));
    expect(saves.single.single.publishedSegmentIds, ['locked', 'tail']);
    expect(saves.single.single.contentRevision, 5);
    final deleteButtons = find.widgetWithIcon(IconButton, Icons.delete_outline);
    expect(tester.widget<IconButton>(deleteButtons.at(1)).onPressed, isNull);

    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();
    expect(saves, hasLength(2));
    expect(saves.last.single.contentRevision, 5);
  });

  testWidgets('保存で再生・公開・リビジョンと複数ボード情報を保持する', (tester) async {
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          layerBundle: LessonWhiteboardLayerBundle(
            layers: [LessonWhiteboardLayer(id: 'default-layer', order: 0)],
          ),
        ),
        LessonWhiteboardBoard(id: 'second', order: 1, title: '二枚目'),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'second',
          globalTimestampSec: 5,
          sequence: 0,
        ),
      ],
    );
    CourseLesson? saved;
    final course = _courseWithLesson(
      const CourseLesson(
        title: 'メタデータ',
        duration: '10秒',
        playbackMode: LessonPlaybackMode.independentPanels,
        publishedSegmentIds: [],
        contentRevision: 9,
        publishedBoardSet: boardSet,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: course,
          onSaveOverride: (lessons) async {
            saved = lessons.single;
          },
        ),
      ),
    );
    await tester.ensureVisible(find.text('レッスン情報を保存'));
    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();

    expect(saved?.playbackMode, LessonPlaybackMode.independentPanels);
    expect(saved?.publishedSegmentIds, isEmpty);
    expect(saved?.contentRevision, 9);
    expect(saved?.publishedBoardSet.boards, hasLength(2));
    expect(saved?.publishedBoardSet.switchEvents, hasLength(1));
  });

  testWidgets('レッスン情報保存で複数ボード下書きを公開し下書きを消す', (tester) async {
    const draftBoardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          title: '下書き1',
        ),
        LessonWhiteboardBoard(id: 'draft-second', order: 1, title: '下書き2'),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'draft-second',
          globalTimestampSec: 4.25,
          sequence: 0,
        ),
      ],
    );
    final course = _courseWithLesson(
      const CourseLesson(
        title: '下書きあり',
        duration: '30秒',
        mediaSegments: [_lockedSegment],
        publishedSegmentIds: ['locked'],
        draftBoardSet: draftBoardSet,
      ),
    );
    CourseLesson? saved;
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: course,
          onSaveOverride: (lessons) async {
            saved = lessons.single;
          },
        ),
      ),
    );
    await tester.ensureVisible(find.text('レッスン情報を保存'));
    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();

    expect(saved?.mediaSegments.single.id, 'locked');
    expect(saved?.publishedBoardSet.boards, hasLength(2));
    expect(
      saved?.publishedBoardSet.switchEvents.single.globalTimestampSec,
      4.25,
    );
    expect(saved?.draftBoardSet, isEmpty);
  });
}
