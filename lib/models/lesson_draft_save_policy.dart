import 'course.dart';

/// How to treat an existing lesson draft when publishing the lesson document
/// without keeping unpublished media tails (`keepDrafts: false`).
class PublishedLessonDraftDisposition {
  const PublishedLessonDraftDisposition({
    required this.deleteDraft,
    required this.savedDraftRevision,
  });

  /// True when the draft document should be deleted in the same write.
  final bool deleteDraft;

  /// Revision the client should remember. `0` means no draft remains.
  final int savedDraftRevision;

  /// True when a newer draft was left in place so live-archive URLs are not
  /// discarded by a part-deletion save.
  bool get keptExistingDraft => !deleteDraft && savedDraftRevision > 0;
}

/// Publishes lesson changes even when the draft revision moved, but does not
/// delete that newer draft. Keeping unpublished tails still requires an exact
/// revision match.
PublishedLessonDraftDisposition resolvePublishedLessonDraftDisposition({
  required bool draftExists,
  required int actualDraftRevision,
  required int expectedDraftRevision,
}) {
  if (actualDraftRevision != expectedDraftRevision) {
    return PublishedLessonDraftDisposition(
      deleteDraft: false,
      savedDraftRevision: actualDraftRevision,
    );
  }
  return PublishedLessonDraftDisposition(
    deleteDraft: draftExists,
    savedDraftRevision: 0,
  );
}

void ensureKeepDraftsRevisionMatches({
  required int actualDraftRevision,
  required int expectedDraftRevision,
}) {
  if (actualDraftRevision != expectedDraftRevision) {
    throw StateError(lessonDraftRevisionConflictMessage);
  }
}

/// Preview reads only the published board set. Unpublished media can stay in
/// the lesson draft, but boards created during a live part must still be
/// copied onto the published lesson or learners cannot switch to them.
bool shouldPublishLessonBoardSet({required bool keepMediaDrafts}) {
  return true;
}
