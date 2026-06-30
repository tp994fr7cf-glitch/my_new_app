import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/utils/lesson_question_answer_write_preflight.dart';
import 'package:my_new_app/utils/quoted_note_citation_validation.dart';

void main() {
  group('lesson question answer write preflight helpers', () {
    test('snapshot field helper preserves exact Firestore strings', () {
      expect(quotedNoteSnapshotFieldFromFirestore(null), isNull);
      expect(quotedNoteSnapshotFieldFromFirestore(''), isNull);
      expect(quotedNoteSnapshotFieldFromFirestore('hello '), 'hello ');
    });

    test('snapshot from Firestore data keeps empty fields as null', () {
      expect(
        quotedNoteCitationSnapshotFromFirestoreData(
          const {},
          noteId: 'note-a',
        ),
        const QuotedNoteCitationSnapshotFields(
          quotedNoteId: 'note-a',
          quotedNoteTitle: null,
          quotedNoteBody: null,
        ),
      );
      expect(
        quotedNoteCitationSnapshotFromFirestoreData(
          const {'title': '  ', 'body': '本文'},
          noteId: 'note-b',
        ),
        const QuotedNoteCitationSnapshotFields(
          quotedNoteId: 'note-b',
          quotedNoteTitle: '  ',
          quotedNoteBody: '本文',
        ),
      );
    });

    test('parent question visibility mirrors moderation rules', () {
      expect(
        parentPublicQuestionVisible({
          'moderationStatus': 'visible',
          'isDeleted': false,
        }),
        isTrue,
      );
      expect(
        parentPublicQuestionVisible({
          'moderationStatus': 'hiddenByTeacher',
          'isDeleted': false,
        }),
        isFalse,
      );
    });

    test('learnerPublicPostBlocked matches service semantics', () {
      expect(
        learnerPublicPostBlocked('noPublicPost'),
        isTrue,
      );
      expect(
        learnerPublicPostBlocked('none'),
        isFalse,
      );
    });
  });
}
