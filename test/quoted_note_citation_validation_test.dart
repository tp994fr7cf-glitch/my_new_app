import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_note.dart';
import 'package:my_new_app/utils/quoted_note_citation_validation.dart';

void main() {
  group('quoted note citation validation helpers', () {
    test('snapshot matches empty title and body', () {
      const note = LessonNote(
        authorId: 'author-a',
        authorName: '作成者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '基本',
        title: '',
        body: '',
        folderId: '',
        folderName: '',
        visibility: LessonNoteVisibility.public,
        tags: [],
        attachmentTypes: [],
        hasAudioAttachment: false,
        isCopied: false,
        canPublish: true,
        allowsQuestionCitation: true,
      );

      expect(
        quotedNoteSnapshotMatches(
          note: note,
          selectedTitle: null,
          selectedBody: null,
        ),
        isTrue,
      );
      expect(
        quotedNoteCitationSnapshotFromNote(note),
        const QuotedNoteCitationSnapshotFields(
          quotedNoteId: '',
          quotedNoteTitle: null,
          quotedNoteBody: null,
        ),
      );
    });

    test('course instructor check mirrors server rule intent', () {
      expect(
        isCourseInstructorForQuotedNoteCitation(
          currentUserId: 'teacher-a',
          courseInstructorId: 'teacher-a',
          isActiveTeacher: true,
        ),
        isTrue,
      );
      expect(
        isCourseInstructorForQuotedNoteCitation(
          currentUserId: 'teacher-a',
          courseInstructorId: 'teacher-a',
          isActiveTeacher: false,
        ),
        isFalse,
      );
      expect(
        isCourseInstructorForQuotedNoteCitation(
          currentUserId: 'student-a',
          courseInstructorId: 'teacher-a',
          isActiveTeacher: true,
        ),
        isFalse,
      );
    });

    test('public audience error message distinguishes teacher-only notes', () {
      const teacherOnlyNote = LessonNote(
        authorId: 'author-a',
        authorName: '作成者',
        courseId: 'course-a',
        courseTitle: '数学',
        lessonNumber: 1,
        lessonTitle: '基本',
        title: 'メモ',
        body: '本文',
        folderId: '',
        folderName: '',
        visibility: LessonNoteVisibility.teacherOnly,
        studentVisibility: LessonNoteVisibility.teacherOnly,
        tags: [],
        attachmentTypes: [],
        hasAudioAttachment: false,
        isCopied: false,
        canPublish: true,
        allowsQuestionCitation: true,
      );

      expect(
        quotedNotePublicAudienceErrorMessage(teacherOnlyNote),
        contains('先生だけに公開'),
      );
    });
  });
}
