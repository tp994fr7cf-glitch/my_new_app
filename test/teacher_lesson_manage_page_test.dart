import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_payload_size_validator.dart';
import 'package:my_new_app/models/lesson_playback_mode.dart';
import 'package:my_new_app/models/lesson_publication_validator.dart';
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

Course _courseWithLesson(
  CourseLesson lesson, {
  String description = 'テスト用講座',
  int lessonContentVersion = 0,
}) {
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
    description: description,
    lessons: [lesson],
    lessonContentVersion: lessonContentVersion,
  );
}

void main() {
  test('external lesson drafts overlay legacy data and promote atomically', () {
    const legacyDraft = BoardSet(
      boards: [LessonWhiteboardBoard(id: 'legacy', order: 0)],
    );
    const externalDraft = BoardSet(
      boards: [LessonWhiteboardBoard(id: 'external', order: 0)],
    );
    const lesson = CourseLesson(
      title: 'Draft',
      duration: '10秒',
      draftBoardSet: legacyDraft,
    );

    final overlaid = overlayLessonDraftBoardSets(
      const [lesson],
      const {1: externalDraft},
    );
    expect(overlaid.single.draftBoardSet.boardById('external'), isNotNull);

    final promoted = promoteLessonDraftBoardSets(overlaid, const {
      1: externalDraft,
    });
    expect(promoted.single.publishedBoardSet.boardById('external'), isNotNull);
    expect(promoted.single.draftBoardSet, isEmpty);
    expect(promoted.single.toMap(), isNot(contains('draftBoardSet')));
  });

  test('uses fallback duration when a playable part has no measured length', () {
    expect(
      resolvedLessonMediaDurationSec(
        isRetired: false,
        hasUrl: true,
        durationSec: 0,
        fallbackDurationSec: 90,
      ),
      90,
    );
    expect(
      resolvedLessonMediaDurationSec(
        isRetired: false,
        hasUrl: true,
        durationSec: 12,
        fallbackDurationSec: 90,
      ),
      12,
    );
    expect(
      resolvedLessonMediaDurationSec(
        isRetired: true,
        hasUrl: true,
        durationSec: 12,
        fallbackDurationSec: 90,
      ),
      0,
    );
  });

  test(
    'external lesson drafts are accepted only for the loaded course version',
    () {
      final matching = matchingLessonDraft({
        'baseLessonContentVersion': 4,
        'draftRevision': 2,
        'boardSet': const BoardSet(
          boards: [LessonWhiteboardBoard(id: 'matching', order: 0)],
        ).toMap(),
      }, lessonContentVersion: 4);
      final stale = matchingLessonDraft({
        'baseLessonContentVersion': 3,
        'draftRevision': 7,
        'boardSet': const BoardSet(
          boards: [LessonWhiteboardBoard(id: 'stale', order: 0)],
        ).toMap(),
      }, lessonContentVersion: 4);

      expect(matching?.draftRevision, 2);
      expect(matching?.boardSet.boardById('matching'), isNotNull);
      expect(stale, isNull);
    },
  );

  test(
    'publication ignores a vanished external draft but preserves embedded fallback',
    () {
      const published = BoardSet(
        boards: [LessonWhiteboardBoard(id: 'published', order: 0)],
      );
      const vanished = BoardSet(
        boards: [LessonWhiteboardBoard(id: 'vanished', order: 0)],
      );
      const legacy = BoardSet(
        boards: [LessonWhiteboardBoard(id: 'legacy', order: 0)],
      );
      final retained = retainPersistedLessonBoardSets(
        latestLessons: const [
          CourseLesson(
            title: 'external',
            duration: '1秒',
            publishedBoardSet: published,
          ),
          CourseLesson(
            title: 'legacy',
            duration: '1秒',
            publishedBoardSet: published,
            draftBoardSet: legacy,
          ),
        ],
        editedLessons: const [
          CourseLesson(
            title: 'external edit',
            duration: '1秒',
            publishedBoardSet: vanished,
          ),
          CourseLesson(
            title: 'legacy edit',
            duration: '1秒',
            publishedBoardSet: vanished,
          ),
        ],
      );

      expect(
        retained.first.publishedBoardSet.boardById('published'),
        isNotNull,
      );
      expect(retained.first.publishedBoardSet.boardById('vanished'), isNull);
      expect(retained.last.publishedBoardSet.boardById('legacy'), isNotNull);
    },
  );

  test('lesson content versions initialize, increment, and stop at max', () {
    expect(logicalLessonContentVersion(null), 0);
    expect(lessonContentVersionMatches(null, 0), isTrue);
    expect(lessonContentVersionMatches(7, 6), isFalse);
    expect(nextLessonContentVersion(null), 1);
    expect(nextLessonContentVersion(7), 8);
    expect(nextLessonDraftRevision(null), 1);
    expect(nextLessonDraftRevision(3), 4);
    expect(
      () => nextLessonContentVersion(2147483647),
      throwsA(isA<StateError>()),
    );
  });

  test('two stale tabs cannot overwrite a newer whiteboard draft revision', () {
    final firstTabRevision = nextExpectedLessonDraftRevision(
      storedValue: 3,
      expectedRevision: 3,
    );
    expect(firstTabRevision, 4);

    expect(
      () => nextExpectedLessonDraftRevision(
        storedValue: firstTabRevision,
        expectedRevision: 3,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          lessonDraftRevisionConflictMessage,
        ),
      ),
    );
  });

  test('publication rejects a draft changed by a second tab after load', () {
    Map<String, dynamic> draftData(int revision) => {
      'baseLessonContentVersion': 8,
      'draftRevision': revision,
      'boardSet': const BoardSet(
        boards: [LessonWhiteboardBoard(id: 'draft', order: 0)],
      ).toMap(),
    };

    expect(
      lessonDraftForPublication(
        draftData(2),
        lessonContentVersion: 8,
        expectedDraftRevision: 2,
      ),
      isNotNull,
    );
    expect(
      () => lessonDraftForPublication(
        draftData(3),
        lessonContentVersion: 8,
        expectedDraftRevision: 2,
      ),
      throwsA(
        isA<LessonPublicationValidationException>().having(
          (error) => error.message,
          'message',
          lessonDraftRevisionConflictMessage,
        ),
      ),
    );
    expect(
      () => lessonDraftForPublication(
        draftData(1),
        lessonContentVersion: 8,
        expectedDraftRevision: 0,
      ),
      throwsA(isA<LessonPublicationValidationException>()),
    );
    expect(
      () => lessonDraftForPublication(
        null,
        lessonContentVersion: 8,
        expectedDraftRevision: 2,
      ),
      throwsA(isA<LessonPublicationValidationException>()),
    );
  });

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
      await tester.drag(find.byType(ListView).first, const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(find.text('ファイル選択をキャンセルしました。'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(storageService.cancelCount, 1);
    });
  }

  testWidgets('録音しながら書くはファイル選択を開始せず録音画面を追加する', (tester) async {
    final storageService = _RecordingMediaStorageService();
    final course = _courseWithLesson(
      const CourseLesson(id: 'lesson-1', title: 'レッスン1', duration: '10分'),
    );
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: course,
          lessonId: 'lesson-1',
          mediaStorageService: storageService,
          onSaveOverride: (_) async {},
        ),
      ),
    );

    await tester.tap(find.text('パートを追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('録音しながら書く'));
    await tester.pumpAndSettle();

    expect(storageService.pickCount, 0);
    expect(
      find.byKey(const ValueKey('audio-whiteboard-recorder')),
      findsOneWidget,
    );
    expect(find.text('音声をアップロード'), findsOneWidget);
  });

  testWidgets('再生可能メディアがなくても配信前の資料準備を表示する', (tester) async {
    final course = _courseWithLesson(
      const CourseLesson(id: 'lesson-1', title: 'ライブ予定', duration: '10分'),
    );
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: course,
          lessonId: 'lesson-1',
          onSaveOverride: (_) async {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('prelive-material-preparation-panel')),
      findsOneWidget,
    );
    expect(find.text('配信・録音前のPDF／画像資料'), findsOneWidget);
    expect(find.text('PDFを追加'), findsOneWidget);
  });

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
    expect(find.text('公開済み（タイトルと板書タイミング補正を変更できます）'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>).first,
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

  testWidgets('一定補正と2点補正をパートへ保存する', (tester) async {
    final course = _courseWithLesson(
      const CourseLesson(
        title: '補正',
        duration: '30秒',
        mediaSegments: [_lockedSegment],
        publishedSegmentIds: ['locked'],
      ),
    );
    CourseLesson? saved;
    await tester.binding.setSurfaceSize(const Size(800, 2200));
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

    final uniformFinder = find.byKey(
      const ValueKey('segment-locked-uniform-correction'),
    );
    await tester.ensureVisible(uniformFinder);
    tester.widget<Slider>(uniformFinder).onChanged!(0.5);
    await tester.pump();

    await tester.tap(find.text('開始・終了を別々に補正（2点補正）'));
    await tester.pumpAndSettle();
    final endFinder = find.byKey(
      const ValueKey('segment-locked-end-correction'),
    );
    await tester.ensureVisible(endFinder);
    tester.widget<Slider>(endFinder).onChanged!(1.5);
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('レッスン情報を保存'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();

    expect(saved?.mediaSegments.single.whiteboardStartCorrectionMs, 500);
    expect(saved?.mediaSegments.single.whiteboardEndCorrectionMs, 1500);
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

    await tester.scrollUntilVisible(
      find.text('レッスン情報を保存'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選んだパートを公開'));
    await tester.pumpAndSettle();

    expect(saves, hasLength(1));
    expect(saves.single.single.publishedSegmentIds, ['locked', 'tail']);
    expect(saves.single.single.contentRevision, 5);
    final deleteButtons = find.widgetWithIcon(IconButton, Icons.delete_outline);
    expect(tester.widget<IconButton>(deleteButtons.at(1)).onPressed, isNull);

    await tester.scrollUntilVisible(
      find.text('レッスン情報を保存'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
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
    await tester.scrollUntilVisible(
      find.text('レッスン情報を保存'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
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
      ),
    );
    CourseLesson? saved;
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: course,
          initialLessonDrafts: const {1: draftBoardSet},
          onSaveOverride: (lessons) async {
            saved = lessons.single;
          },
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('レッスン情報を保存'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
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

  testWidgets(
    'lesson override validates the complete prospective course payload',
    (tester) async {
      var saveCalled = false;
      final course = _courseWithLesson(
        const CourseLesson(title: '大きな講座', duration: '10秒'),
        description: List.filled(300000, 'あ').join(),
      );
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: TeacherLessonManagePage(
            course: course,
            onSaveOverride: (_) async {
              saveCalled = true;
            },
          ),
        ),
      );

      await tester.ensureVisible(find.text('レッスン情報を保存'));
      await tester.tap(find.text('レッスン情報を保存'));
      await tester.pumpAndSettle();

      expect(saveCalled, isFalse);
      expect(find.text(lessonPayloadTooLargeMessage), findsOneWidget);
    },
  );

  test('未ログインや録音中は新規配信画面を開けない', () {
    expect(
      canOpenTeacherLiveReservation(
        hasCourseId: true,
        hasLessonId: true,
        isSignedIn: false,
        isSaving: false,
        isRecordingOrUploading: false,
        hasExistingLiveSession: false,
      ),
      isFalse,
    );
    expect(
      canOpenTeacherLiveReservation(
        hasCourseId: true,
        hasLessonId: true,
        isSignedIn: true,
        isSaving: false,
        isRecordingOrUploading: true,
        hasExistingLiveSession: false,
      ),
      isFalse,
    );
    expect(
      canOpenTeacherLiveReservation(
        hasCourseId: true,
        hasLessonId: true,
        isSignedIn: true,
        isSaving: true,
        isRecordingOrUploading: false,
        hasExistingLiveSession: false,
      ),
      isFalse,
    );
    expect(
      canOpenTeacherLiveReservation(
        hasCourseId: true,
        hasLessonId: true,
        isSignedIn: true,
        isSaving: false,
        isRecordingOrUploading: true,
        hasExistingLiveSession: true,
      ),
      isTrue,
    );
  });

  test('予約保存に失敗したら未開始の配信画面は開かない', () {
    expect(
      shouldOpenTeacherLiveScreen(
        reservationSaved: false,
        hasExistingLiveSession: false,
      ),
      isFalse,
    );
    expect(
      shouldOpenTeacherLiveScreen(
        reservationSaved: true,
        hasExistingLiveSession: false,
      ),
      isTrue,
    );
    expect(
      shouldOpenTeacherLiveScreen(
        reservationSaved: false,
        hasExistingLiveSession: true,
      ),
      isTrue,
    );
  });

  testWidgets('ライブ予約パートの配信ボタンを表示する', (tester) async {
    final course = _courseWithLesson(
      const CourseLesson(
        id: 'lesson-1',
        title: 'ライブ予定',
        duration: '10分',
        mediaSegments: [
          LessonMediaSegment(
            id: 'live-1',
            order: 0,
            mediaType: 'audio',
            sourceKind: lessonMediaSourceLiveArchive,
          ),
        ],
      ),
    );
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: course,
          lessonId: 'lesson-1',
          onSaveOverride: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('配信画面を開く'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('ライブ配信パート（未開始）'), findsOneWidget);
    expect(find.text('配信画面を開く'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '配信画面を開く'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('保存失敗時はレッスン情報を保存のメッセージを残す', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: _course,
          onSaveOverride: (_) async {
            throw StateError('下書きの版が変わりました。画面を開き直してください。');
          },
        ),
      ),
    );

    await tester.ensureVisible(find.text('レッスン情報を保存'));
    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('下書きの版が変わりました'), findsOneWidget);
    expect(find.text('先生として配信を開始'), findsNothing);
  });

  testWidgets('空の動画パート枠を未公開のまま保存できる', (tester) async {
    CourseLesson? saved;
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: _course,
          mediaStorageService: _RecordingMediaStorageService(),
          onSaveOverride: (lessons) async {
            saved = lessons.single;
          },
        ),
      ),
    );

    await tester.tap(find.text('パートを追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('動画'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('レッスン情報を保存'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();

    expect(find.text('選んだパートを公開'), findsNothing);
    expect(saved?.publishedSegmentIds, isEmpty);
    expect(saved?.mediaSegments, hasLength(1));
    expect(saved?.mediaSegments.single.mediaType, 'video');
    expect(saved?.mediaSegments.single.hasUrl, isFalse);
  });

  testWidgets('完成パートのうち選んだものだけ公開できる', (tester) async {
    const videoHole = LessonMediaSegment(
      id: 'video',
      order: 0,
      mediaType: 'video',
    );
    const firstReady = LessonMediaSegment(
      id: 'first',
      order: 1,
      title: '動画A',
      mediaType: 'video',
      url: 'https://example.com/first.mp4',
      durationSec: 10,
    );
    const secondReady = LessonMediaSegment(
      id: 'second',
      order: 2,
      title: '動画B',
      mediaType: 'video',
      url: 'https://example.com/second.mp4',
      durationSec: 20,
    );
    CourseLesson? saved;
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: _courseWithLesson(
            const CourseLesson(
              title: '複数パート',
              duration: '30秒',
              mediaSegments: [videoHole, firstReady, secondReady],
              publishedSegmentIds: [],
            ),
          ),
          onSaveOverride: (lessons) async {
            saved = lessons.single;
          },
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('レッスン情報を保存'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();

    expect(find.text('公開するパートを選んでください'), findsOneWidget);
    await tester.tap(find.text('パート2（動画A）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選んだパートを公開'));
    await tester.pumpAndSettle();

    expect(saved?.publishedSegmentIds, ['second']);
    expect(saved?.mediaSegments.map((segment) => segment.id), [
      'video',
      'first',
      'second',
    ]);
    expect(saved?.mediaSegments[1].hasUrl, isFalse);
    expect(saved?.mediaSegments[1].durationSec, 10);
    expect(saved?.visibleLessonPartSegments, hasLength(3));
  });

  testWidgets('未公開の仮作成パートを保存前に削除できる', (tester) async {
    CourseLesson? saved;
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: _courseWithLesson(
            const CourseLesson(
              title: '仮作成',
              duration: '10分',
              mediaSegments: [
                LessonMediaSegment(id: 'one', order: 0, mediaType: 'video'),
                LessonMediaSegment(id: 'two', order: 1, mediaType: 'audio'),
                LessonMediaSegment(
                  id: 'three',
                  order: 2,
                  mediaType: 'audio',
                  sourceKind: lessonMediaSourceLiveArchive,
                ),
              ],
              publishedSegmentIds: [],
            ),
          ),
          onSaveOverride: (lessons) async {
            saved = lessons.single;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final enabledDelete = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          widget.tooltip == '削除' &&
          widget.onPressed != null,
    );
    expect(enabledDelete, findsNWidgets(3));
    await tester.tap(enabledDelete.at(1));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('レッスン情報を保存'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();

    expect(saved?.mediaSegments.map((segment) => segment.id), ['one', 'three']);
    expect(saved?.mediaSegments.any((segment) => segment.isRetired), isFalse);
  });

  testWidgets('公開済みに挟まった未公開枠を消すと欠番になり番号は詰めて見える', (tester) async {
    const later = LessonMediaSegment(
      id: 'later',
      order: 2,
      title: '後半',
      mediaType: 'audio',
      url: 'https://example.com/later.m4a',
      durationSec: 12,
    );
    CourseLesson? saved;
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: _courseWithLesson(
            const CourseLesson(
              title: '挟まった穴',
              duration: '20分',
              mediaSegments: [
                _lockedSegment,
                LessonMediaSegment(
                  id: 'hole',
                  order: 1,
                  mediaType: 'audio',
                  durationSec: 18,
                ),
                later,
              ],
              publishedSegmentIds: ['locked', 'later'],
            ),
          ),
          onSaveOverride: (lessons) async {
            saved = lessons.single;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('パート1'), findsOneWidget);
    expect(find.text('パート2'), findsOneWidget);
    expect(find.text('パート3'), findsOneWidget);

    final enabledDelete = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          widget.tooltip == '削除' &&
          widget.onPressed != null,
    );
    expect(enabledDelete, findsOneWidget);
    await tester.tap(enabledDelete);
    await tester.pumpAndSettle();

    expect(find.text('パート3'), findsNothing);
    expect(find.text('パート2'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('レッスン情報を保存'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();

    expect(saved?.mediaSegments.map((segment) => segment.id), [
      'locked',
      'hole',
      'later',
    ]);
    expect(saved?.mediaSegments[1].isRetired, isTrue);
    expect(saved?.mediaSegments[1].durationSec, 0);
    expect(saved?.visibleLessonPartSegments.map((segment) => segment.id), [
      'locked',
      'later',
    ]);
  });

  testWidgets('本作成済みの未公開パートを保護パートの前で消すと公開確認は出ず録音も残らない', (
    tester,
  ) async {
    const recorded = LessonMediaSegment(
      id: 'recorded',
      order: 1,
      title: '録音',
      mediaType: 'audio',
      url: 'https://example.com/recorded.m4a',
      durationSec: 9,
      sourceKind: lessonMediaSourceAudioRecording,
    );
    const later = LessonMediaSegment(
      id: 'later',
      order: 2,
      title: '後半',
      mediaType: 'audio',
      url: 'https://example.com/later.m4a',
      durationSec: 12,
    );
    CourseLesson? saved;
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherLessonManagePage(
          course: _courseWithLesson(
            CourseLesson(
              title: '録音を消す',
              duration: '20分',
              mediaSegments: [
                _lockedSegment,
                recorded.copyWith(url: ''),
                later,
              ],
              publishedSegmentIds: const ['locked', 'later'],
            ),
          ),
          onSaveOverride: (lessons) async {
            saved = lessons.single;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('パート2'), findsOneWidget);
    expect(find.text('パート3'), findsOneWidget);

    final enabledDelete = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          widget.tooltip == '削除' &&
          widget.onPressed != null,
    );
    expect(enabledDelete, findsOneWidget);
    await tester.tap(enabledDelete);
    await tester.pumpAndSettle();

    expect(find.text('パート2'), findsOneWidget);
    expect(find.text('パート3'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('レッスン情報を保存'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('レッスン情報を保存'));
    await tester.pumpAndSettle();

    expect(find.text('公開するパートを選んでください'), findsNothing);
    expect(find.textContaining('パート0'), findsNothing);
    expect(saved?.mediaSegments.map((segment) => segment.id), [
      'locked',
      'recorded',
      'later',
    ]);
    expect(saved?.mediaSegments[1].isRetired, isTrue);
    expect(saved?.mediaSegments[1].hasUrl, isFalse);
    expect(saved?.publishedSegmentIds, ['locked', 'later']);
    expect(saved?.visibleLessonPartSegments.map((segment) => segment.id), [
      'locked',
      'later',
    ]);
  });
}
