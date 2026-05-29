import 'package:flutter_test/flutter_test.dart';
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
  });
}
