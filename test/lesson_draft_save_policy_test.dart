import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_draft_save_policy.dart';

void main() {
  test('deletes a matching draft when publishing without keeping tails', () {
    final disposition = resolvePublishedLessonDraftDisposition(
      draftExists: true,
      actualDraftRevision: 2,
      expectedDraftRevision: 2,
    );
    expect(disposition.deleteDraft, isTrue);
    expect(disposition.savedDraftRevision, 0);
    expect(disposition.keptExistingDraft, isFalse);
  });

  test('keeps a newer draft so a delete save can still publish retired slots', () {
    final disposition = resolvePublishedLessonDraftDisposition(
      draftExists: true,
      actualDraftRevision: 3,
      expectedDraftRevision: 2,
    );
    expect(disposition.deleteDraft, isFalse);
    expect(disposition.savedDraftRevision, 3);
    expect(disposition.keptExistingDraft, isTrue);
  });

  test('does nothing when there is no draft', () {
    final disposition = resolvePublishedLessonDraftDisposition(
      draftExists: false,
      actualDraftRevision: 0,
      expectedDraftRevision: 0,
    );
    expect(disposition.deleteDraft, isFalse);
    expect(disposition.savedDraftRevision, 0);
    expect(disposition.keptExistingDraft, isFalse);
  });

  test('keeping unpublished tails still requires an exact draft revision', () {
    expect(
      () => ensureKeepDraftsRevisionMatches(
        actualDraftRevision: 3,
        expectedDraftRevision: 2,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          lessonDraftRevisionConflictMessage,
        ),
      ),
    );
    expect(
      () => ensureKeepDraftsRevisionMatches(
        actualDraftRevision: 2,
        expectedDraftRevision: 2,
      ),
      returnsNormally,
    );
  });

  test('publishes boards even when unpublished media tails stay in the draft', () {
    expect(shouldPublishLessonBoardSet(keepMediaDrafts: true), isTrue);
    expect(shouldPublishLessonBoardSet(keepMediaDrafts: false), isTrue);
  });
}
