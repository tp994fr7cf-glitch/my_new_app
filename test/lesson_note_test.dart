import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_new_app/models/lesson_note.dart';

void main() {
  group('lesson note helpers', () {
    test('parses tags from hashes spaces and Japanese commas', () {
      expect(parseLessonNoteTags('#重要 復習、数学 #重要'), ['復習', '数学', '重要']);
    });

    test('blocks publishing audio and copied notes', () {
      expect(
        canPublishLessonNote(
          hasAudioAttachment: false,
          isCopied: false,
          canPublish: true,
        ),
        isTrue,
      );
      expect(
        canPublishLessonNote(
          hasAudioAttachment: true,
          isCopied: false,
          canPublish: true,
        ),
        isFalse,
      );
      expect(
        canPublishLessonNote(
          hasAudioAttachment: false,
          isCopied: true,
          canPublish: true,
        ),
        isFalse,
      );
    });

    test('keeps audio notes private while allowing edits', () {
      const note = LessonNote(
        id: 'audio-note',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '音声つきメモ',
        body: 'あとで音声を確認する',
        folderId: '',
        folderName: '',
        visibility: LessonNoteVisibility.private,
        tags: [],
        attachmentTypes: [lessonNoteAttachmentAudio],
        hasAudioAttachment: true,
        isCopied: false,
        canPublish: false,
      );

      expect(note.isPublic, isFalse);
      expect(note.hasAudioAttachment, isTrue);
      expect(note.canPublish, isFalse);
    });

    test('blocks public mirror writes for audio notes', () {
      expect(
        canPublishLessonNote(
          hasAudioAttachment: true,
          isCopied: false,
          canPublish: false,
        ),
        isFalse,
      );
    });

    test('matches notes by title body course lesson folder and tags', () {
      const note = LessonNote(
        id: 'note-a',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学 方程式入門',
        lessonNumber: 1,
        lessonTitle: '一次方程式の基本',
        title: '移項のメモ',
        body: '両辺に同じ計算をする',
        folderId: 'folder-a',
        folderName: '復習',
        visibility: LessonNoteVisibility.private,
        tags: ['重要'],
        attachmentTypes: [],
        hasAudioAttachment: false,
        isCopied: false,
        canPublish: true,
      );

      expect(lessonNoteMatchesQuery(note, '方程式'), isTrue);
      expect(lessonNoteMatchesQuery(note, '重要'), isTrue);
      expect(lessonNoteMatchesQuery(note, '英語'), isFalse);
    });

    test('hides public notes moderated by teacher', () {
      const note = LessonNote(
        id: 'note-a',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '公開メモ',
        body: '両辺に同じ計算をする',
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

      expect(note.isTeacherHidden, isTrue);
      expect(note.isPubliclyVisible, isFalse);
    });

    test(
      'keeps student-private public mirror hidden even when teacher visible',
      () {
        const note = LessonNote(
          id: 'note-a',
          authorId: 'user-a',
          authorName: '学習者',
          courseId: 'course-a',
          courseTitle: '数学',
          lessonNumber: 1,
          lessonTitle: '一次方程式',
          title: '公開後に非公開化したメモ',
          body: '自分だけで見る',
          folderId: '',
          folderName: '',
          visibility: LessonNoteVisibility.public,
          studentVisibility: LessonNoteVisibility.private,
          tags: [],
          attachmentTypes: [],
          hasAudioAttachment: false,
          isCopied: false,
          canPublish: true,
        );

        expect(note.isTeacherHidden, isFalse);
        expect(note.isStudentPublic, isFalse);
        expect(note.isPubliclyVisible, isFalse);
      },
    );

    test('treats missing studentVisibility as existing visibility', () {
      final note = LessonNote.fromMap({
        'authorId': 'user-a',
        'authorName': '学習者',
        'courseId': 'course-a',
        'courseTitle': '数学',
        'lessonNumber': 1,
        'lessonTitle': '一次方程式',
        'title': '既存の公開メモ',
        'body': 'studentVisibility 追加前のデータ',
        'folderId': '',
        'folderName': '',
        'visibility': lessonNoteVisibilityPublic,
        'tags': <String>[],
        'attachmentTypes': <String>[],
        'hasAudioAttachment': false,
        'isCopied': false,
        'canPublish': true,
      });

      expect(note.isStudentPublic, isTrue);
      expect(note.isPubliclyVisible, isTrue);
    });

    test('supports teacher-only visibility for notes', () {
      final note = LessonNote.fromMap({
        'authorId': 'user-a',
        'authorName': '学習者',
        'courseId': 'course-a',
        'courseTitle': '数学',
        'lessonNumber': 1,
        'lessonTitle': '一次方程式',
        'title': '先生向けメモ',
        'body': '先生にだけ見せる内容',
        'folderId': '',
        'folderName': '',
        'visibility': lessonNoteVisibilityTeacherOnly,
        'studentVisibility': lessonNoteVisibilityTeacherOnly,
        'allowsQuestionCitation': true,
      });

      expect(note.isTeacherOnly, isTrue);
      expect(note.isStudentTeacherOnly, isTrue);
      expect(note.isStudentPublic, isFalse);
      expect(note.isPubliclyVisible, isFalse);
      expect(note.hasPublicMirror, isTrue);
    });

    test('parses and normalizes public approval status', () {
      final pendingNote = LessonNote.fromMap({
        'visibility': lessonNoteVisibilityTeacherOnly,
        'studentVisibility': lessonNoteVisibilityTeacherOnly,
        'publicApprovalStatus': lessonNotePublicApprovalPending,
      });
      final rejectedNote = LessonNote.fromMap({
        'visibility': lessonNoteVisibilityTeacherOnly,
        'publicApprovalStatus': lessonNotePublicApprovalRejected,
      });
      final unknownStatusNote = LessonNote.fromMap({
        'visibility': lessonNoteVisibilityTeacherOnly,
        'publicApprovalStatus': 'unexpected',
      });

      expect(pendingNote.publicApprovalStatus, lessonNotePublicApprovalPending);
      expect(pendingNote.isPublicApprovalPending, isTrue);
      expect(pendingNote.isPublicApprovalRejected, isFalse);
      expect(rejectedNote.isPublicApprovalPending, isFalse);
      expect(rejectedNote.isPublicApprovalRejected, isTrue);
      expect(
        unknownStatusNote.publicApprovalStatus,
        lessonNotePublicApprovalNone,
      );
    });

    test('treats missing question citation permission as not allowed', () {
      final note = LessonNote.fromMap({
        'visibility': lessonNoteVisibilityPublic,
      });
      final allowedNote = LessonNote.fromMap({
        'visibility': lessonNoteVisibilityPublic,
        'allowsQuestionCitation': true,
      });

      expect(note.allowsQuestionCitation, isFalse);
      expect(allowedNote.allowsQuestionCitation, isTrue);
    });

    test('tracks whether a note can have a public mirror', () {
      final privateNote = LessonNote.fromMap({
        'visibility': lessonNoteVisibilityPrivate,
      });
      final publicNote = LessonNote.fromMap({
        'visibility': lessonNoteVisibilityPublic,
      });
      final previouslyPublicNote = LessonNote.fromMap({
        'visibility': lessonNoteVisibilityPrivate,
        'hasPublicMirror': true,
      });

      expect(privateNote.hasPublicMirror, isFalse);
      expect(publicNote.hasPublicMirror, isTrue);
      expect(previouslyPublicNote.hasPublicMirror, isTrue);
    });

    test('sorts public notes by popularity score', () {
      const copiedOften = LessonNote(
        id: 'copy',
        authorId: 'user-a',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: 'コピーされるメモ',
        body: '',
        folderId: '',
        folderName: '',
        visibility: LessonNoteVisibility.public,
        tags: [],
        attachmentTypes: [],
        hasAudioAttachment: false,
        isCopied: false,
        canPublish: true,
        copyCount: 20,
      );
      const ratedHighly = LessonNote(
        id: 'rating',
        authorId: 'user-b',
        authorName: '学習者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '一次方程式',
        title: '高評価メモ',
        body: '',
        folderId: '',
        folderName: '',
        visibility: LessonNoteVisibility.public,
        tags: [],
        attachmentTypes: [],
        hasAudioAttachment: false,
        isCopied: false,
        canPublish: true,
        ratingAverage: 5,
        ratingCount: 1,
      );

      final sorted = sortPublicLessonNotes([
        copiedOften,
        ratedHighly,
      ], LessonNotePublicSort.popular);

      expect(sorted.first.id, 'rating');
    });

    test('resolves citation free edit window from enabled timestamp', () {
      final enabledAt = Timestamp.fromDate(DateTime.utc(2026, 6, 1, 10, 0));
      final freeUntil = resolveLessonNoteCitationFreeEditUntil(
        allowsQuestionCitation: true,
        citationEnabledAt: enabledAt,
        citationFreeEditUntil: null,
        publicPublishedAt: null,
        createdAt: null,
      );

      expect(freeUntil, isNotNull);
      expect(freeUntil!.toDate().toUtc(), DateTime.utc(2026, 6, 1, 10, 30));
      expect(
        isWithinLessonNoteCitationFreeEditWindow(
          nowUtc: DateTime.utc(2026, 6, 1, 10, 10),
          citationFreeEditUntil: freeUntil,
        ),
        isTrue,
      );
      expect(
        isWithinLessonNoteCitationFreeEditWindow(
          nowUtc: DateTime.utc(2026, 6, 1, 10, 31),
          citationFreeEditUntil: freeUntil,
        ),
        isFalse,
      );
    });

    test('locks edit when three countable edits exist in seven days', () {
      final now = DateTime.utc(2026, 6, 10, 12, 0);
      final lockUntil = lessonNoteEditLockUntil(
        now: now,
        countableEditTimes: [
          Timestamp.fromDate(now.subtract(const Duration(days: 1))),
          Timestamp.fromDate(now.subtract(const Duration(days: 2))),
          Timestamp.fromDate(now.subtract(const Duration(days: 3))),
        ],
      );
      expect(lockUntil, isNotNull);
      expect(
        lockUntil!.toUtc(),
        now
            .subtract(const Duration(days: 1))
            .add(lessonNoteCitationCompareRetentionWindow),
      );
    });
  });
}
