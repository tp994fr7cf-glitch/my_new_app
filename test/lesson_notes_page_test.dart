import 'package:cloud_firestore/cloud_firestore.dart';
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

  testWidgets('Embedded notes editor opens without navigation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoLessonPage(course: course, lesson: lesson, lessonNumber: 1),
      ),
    );

    await tester.scrollUntilVisible(find.text('レッスンメモを開く'), 500);
    await tester.tap(find.text('レッスンメモを開く'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('メモを作成'));
    await tester.pumpAndSettle();

    expect(find.text('タイトル'), findsOneWidget);
    expect(find.text('本文'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('作成'), findsOneWidget);
    expect(find.text('動画視聴', skipOffstage: false), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(find.byTooltip('メモ一覧に戻る'));
    await tester.pumpAndSettle();

    expect(find.text('メモを検索'), findsOneWidget);
    expect(find.text('レッスンメモを閉じる', skipOffstage: false), findsOneWidget);
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
    final publicNote = LessonNote(
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
      allowsQuestionCitation: true,
      publicPublishedAt: Timestamp.fromDate(DateTime(2026, 6, 2, 9, 15)),
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
    expect(find.text('公開:OFF / 引用:OFF'), findsOneWidget);

    await tester.tap(find.text('公開メモ'));
    await tester.pumpAndSettle();

    expect(find.text('他の学習者'), findsOneWidget);
    expect(find.text('6/2 09:15'), findsOneWidget);
    expect(find.text('両辺に同じ計算をする'), findsOneWidget);
    expect(find.text('コピー・評価・お気に入りは後で追加します。'), findsOneWidget);

    await tester.tap(find.text('両辺に同じ計算をする'));
    await tester.pumpAndSettle();

    expect(find.text('公開メモ'), findsWidgets);
    expect(find.text('他の学習者'), findsOneWidget);
    expect(find.text('両辺に同じ計算をする'), findsOneWidget);
    expect(find.text('このメモを引用して質問する'), findsOneWidget);

    await tester.tap(find.text('このメモを引用して質問する'));
    await tester.pumpAndSettle();

    expect(find.text('質問を作成'), findsOneWidget);
    expect(find.text('質問本文'), findsOneWidget);
    expect(find.text('引用するメモ'), findsOneWidget);
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(dropdown.initialValue, 'public-note');
  });

  testWidgets('Teacher preview shows public note moderation actions', (
    tester,
  ) async {
    const visibleNote = LessonNote(
      id: 'visible-public-note',
      authorId: 'user-b',
      authorName: '他の学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '表示中の公開メモ',
      body: '先生が確認できます。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
    );
    const hiddenNote = LessonNote(
      id: 'hidden-public-note',
      authorId: 'user-c',
      authorName: '別の学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '非公開化した公開メモ',
      body: '先生だけが管理できます。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      moderationStatus: lessonNoteModerationHiddenByTeacher,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonNotesPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            publicNotesStream: Stream.value(const [visibleNote, hiddenNote]),
            isTeacherPreview: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('表示中の公開メモ'), findsOneWidget);
    expect(find.text('非公開化した公開メモ'), findsOneWidget);
    expect(find.text('非公開にする'), findsOneWidget);
    expect(find.text('公開に戻す'), findsOneWidget);
    expect(find.text('先生が非公開化中'), findsOneWidget);
  });

  testWidgets('Teacher preview shows teacher-only note scope label', (
    tester,
  ) async {
    const teacherOnlyNote = LessonNote(
      id: 'teacher-only-note',
      authorId: 'user-b',
      authorName: '他の学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '先生だけ公開メモ',
      body: '先生向けの共有です。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      studentVisibility: LessonNoteVisibility.teacherOnly,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonNotesPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            publicNotesStream: Stream.value(const [teacherOnlyNote]),
            isTeacherPreview: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('先生だけ公開メモ'), findsOneWidget);
    expect(find.text('先生にだけ公開'), findsOneWidget);
  });

  testWidgets('Public note card shows edited badge and history sheet', (
    tester,
  ) async {
    final publicNote = LessonNote(
      id: 'edited-public-note',
      authorId: 'user-b',
      authorName: '他の学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '編集済み公開メモ',
      body: '更新後の本文です。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      allowsQuestionCitation: true,
      hasPublicMirror: true,
      citationEditCount: 2,
      lastCitationEditedAt: Timestamp.fromDate(DateTime(2026, 6, 4, 11, 45)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LessonNotesPage(
          course: course,
          lesson: lesson,
          lessonNumber: 1,
          notesStream: Stream.value(const []),
          publicNotesStream: Stream.value([publicNote]),
          foldersStream: Stream.value(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('公開メモ'));
    await tester.pumpAndSettle();

    expect(find.text('編集済'), findsOneWidget);
    await tester.tap(find.text('編集済'));
    await tester.pumpAndSettle();

    expect(find.text('メモ編集履歴'), findsOneWidget);
  });

  testWidgets('Public note detail explains when citation is not allowed', (
    tester,
  ) async {
    const publicNote = LessonNote(
      id: 'public-note-not-allowed',
      authorId: 'user-b',
      authorName: '他の学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '引用不可の公開メモ',
      body: '質問には引用しないでほしい内容です。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: [],
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
          notesStream: Stream.value(const []),
          publicNotesStream: Stream.value(const [publicNote]),
          foldersStream: Stream.value(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('公開メモ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('引用不可の公開メモ'));
    await tester.pumpAndSettle();

    expect(find.text('このメモの作成者は引用を許可していません。'), findsOneWidget);
    expect(find.text('このメモを引用して質問する'), findsNothing);
  });

  testWidgets('Lesson notes page groups notes under folders', (tester) async {
    const folder = LessonNoteFolder(id: 'folder-a', name: '復習フォルダ');
    const folderNote = LessonNote(
      id: 'folder-note',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: 'フォルダ内メモ',
      body: 'フォルダから開く',
      folderId: 'folder-a',
      folderName: '復習フォルダ',
      visibility: LessonNoteVisibility.private,
      tags: [],
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
          notesStream: Stream.value([folderNote]),
          publicNotesStream: Stream.value(const []),
          foldersStream: Stream.value(const [folder]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('復習フォルダ'), findsOneWidget);
    expect(find.text('1件のメモ'), findsOneWidget);
    expect(find.text('フォルダ内メモ'), findsNothing);

    await tester.tap(find.text('復習フォルダ'));
    await tester.pumpAndSettle();

    expect(find.text('フォルダ内メモ'), findsOneWidget);
  });

  testWidgets('Lesson notes page focuses and highlights requested note', (
    tester,
  ) async {
    final notes = List<LessonNote>.generate(36, (index) {
      return LessonNote(
        id: 'note-$index',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: 'メモ$index',
        body: '本文$index',
        folderId: '',
        folderName: '',
        visibility: LessonNoteVisibility.private,
        tags: const [],
        attachmentTypes: const [],
        hasAudioAttachment: false,
        isCopied: false,
        canPublish: true,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: LessonNotesPage(
          course: course,
          lesson: lesson,
          lessonNumber: 1,
          notesStream: Stream.value(notes),
          publicNotesStream: Stream.value(const []),
          foldersStream: Stream.value(const []),
          initialFocusNoteId: 'note-30',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final focusedTileFinder = find.byKey(const ValueKey('lesson-note-card-note-30'));
    expect(focusedTileFinder, findsOneWidget);
    expect(find.text('メモ30'), findsOneWidget);

    final focusedCardFinder = find.descendant(
      of: focusedTileFinder,
      matching: find.byType(Card),
    );
    final focusedCard = tester.widget<Card>(focusedCardFinder.first);
    final expectedColor =
        Theme.of(tester.element(find.byType(LessonNotesPage)))
            .colorScheme
            .secondaryContainer;
    expect(focusedCard.color, expectedColor);

    final focusedTop = tester.getTopLeft(focusedTileFinder).dy;
    expect(focusedTop, lessThan(560));
  });

  testWidgets('Self memo list shows first line and latest toggle status', (
    tester,
  ) async {
    const ownPublicNote = LessonNote(
      id: 'own-public-note',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '整理メモ',
      body: '1行目だけ見せたい\n2行目は一覧に出さない',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      allowsQuestionCitation: true,
      hasPublicMirror: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LessonNotesPage(
          course: course,
          lesson: lesson,
          lessonNumber: 1,
          notesStream: Stream.value(const [ownPublicNote]),
          publicNotesStream: Stream.value(const []),
          foldersStream: Stream.value(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('整理メモ'), findsOneWidget);
    expect(find.text('1行目だけ見せたい'), findsOneWidget);
    expect(find.text('2行目は一覧に出さない'), findsNothing);
    expect(find.text('公開:ON / 引用:ON'), findsOneWidget);
  });

  testWidgets('Own note tap opens shared preview before editor', (tester) async {
    const ownNote = LessonNote(
      id: 'own-note-preview',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '自分の下書きメモ',
      body: '先にプレビューを確認する',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.private,
      tags: [],
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
          notesStream: Stream.value(const [ownNote]),
          publicNotesStream: Stream.value(const []),
          foldersStream: Stream.value(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('自分の下書きメモ'));
    await tester.pumpAndSettle();

    expect(find.text('先にプレビューを確認する'), findsOneWidget);
    expect(find.text('このメモを編集'), findsOneWidget);
    expect(find.text('タイトル'), findsNothing);
  });

  testWidgets('Embedded own note tap opens preview before editor', (tester) async {
    const ownNote = LessonNote(
      id: 'embedded-own-note-preview',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '埋め込みメモ',
      body: '埋め込みでもプレビューを先に表示する',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.private,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonNotesPanel(
            course: course,
            lesson: lesson,
            lessonNumber: 1,
            isEmbedded: true,
            notesStream: Stream.value(const [ownNote]),
            publicNotesStream: Stream.value(const []),
            foldersStream: Stream.value(const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('埋め込みメモ'));
    await tester.pumpAndSettle();

    expect(find.text('埋め込みでもプレビューを先に表示する'), findsOneWidget);
    expect(find.text('このメモを編集'), findsOneWidget);
    expect(find.byTooltip('メモ一覧に戻る'), findsOneWidget);
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

  testWidgets('Published notes keep visibility locked while editing', (
    tester,
  ) async {
    const publicNote = LessonNote(
      id: 'locked-public-note',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '公開済みメモ',
      body: '一度公開した内容です。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      hasPublicMirror: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LessonNotesPage(
          course: course,
          lesson: lesson,
          lessonNumber: 1,
          notesStream: Stream.value(const [publicNote]),
          publicNotesStream: Stream.value(const []),
          foldersStream: Stream.value(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('公開済みメモ'));
    await tester.pumpAndSettle();
    expect(find.text('このメモを編集'), findsOneWidget);
    await tester.tap(find.text('このメモを編集'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('一度公開したメモは後から非公開に戻せません。本文などは編集できます。'), findsOneWidget);
    final switchTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '受講者と先生に公開する'),
    );
    expect(switchTile.value, isTrue);
    expect(switchTile.onChanged, isNull);

    final citationSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '質問での引用を許可する'),
    );
    expect(citationSwitch.value, isFalse);
    expect(citationSwitch.onChanged, isNotNull);

    await tester.tap(find.text('質問での引用を許可する'));
    await tester.pumpAndSettle();

    final allowedCitationSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '質問での引用を許可する'),
    );
    expect(allowedCitationSwitch.value, isTrue);
    expect(allowedCitationSwitch.onChanged, isNull);
  });

  testWidgets('Allowed question citation cannot be turned off while editing', (
    tester,
  ) async {
    const publicNote = LessonNote(
      id: 'citation-allowed-public-note',
      authorId: 'user-a',
      authorName: '学習者',
      courseId: 'course-a',
      courseTitle: '数学 方程式入門',
      lessonNumber: 1,
      lessonTitle: '一次方程式の基本',
      title: '引用許可済みメモ',
      body: '質問で引用できます。',
      folderId: '',
      folderName: '',
      visibility: LessonNoteVisibility.public,
      tags: [],
      attachmentTypes: [],
      hasAudioAttachment: false,
      isCopied: false,
      canPublish: true,
      allowsQuestionCitation: true,
      hasPublicMirror: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LessonNotesPage(
          course: course,
          lesson: lesson,
          lessonNumber: 1,
          notesStream: Stream.value(const [publicNote]),
          publicNotesStream: Stream.value(const []),
          foldersStream: Stream.value(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('引用許可済みメモ'));
    await tester.pumpAndSettle();
    expect(find.text('このメモを編集'), findsOneWidget);
    await tester.tap(find.text('このメモを編集'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();

    final citationSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '質問での引用を許可する'),
    );
    expect(citationSwitch.value, isTrue);
    expect(citationSwitch.onChanged, isNull);
    expect(find.text('一度許可した引用は後から取り消せません。'), findsOneWidget);
  });

  testWidgets('Embedded notes folder dialog can be cancelled safely', (
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

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('フォルダを作成'));
    await tester.pumpAndSettle();
    expect(find.text('フォルダ名'), findsOneWidget);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('自分のメモ', skipOffstage: false), findsWidgets);
  });
}
