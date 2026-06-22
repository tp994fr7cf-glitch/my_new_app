import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_interaction_constants.dart';
import 'package:my_new_app/services/lesson_interaction_service.dart';

void main() {
  const service = LessonInteractionService();

  group('LessonInteractionService restriction mode helpers', () {
    test('bulk chunk size stays below Firestore 500 limit', () {
      expect(service.bulkWriteChunkSize, lessThan(500));
    });

    test('normalizeLearnerRestrictionMode keeps known modes', () {
      expect(
        service.normalizeLearnerRestrictionMode(
          LessonInteractionService.learnerRestrictionModeNoPublicPost,
        ),
        LessonInteractionService.learnerRestrictionModeNoPublicPost,
      );
      expect(
        service.normalizeLearnerRestrictionMode(
          LessonInteractionService.learnerRestrictionModeNoPublicReadOrPost,
        ),
        LessonInteractionService.learnerRestrictionModeNoPublicReadOrPost,
      );
    });

    test('normalizeLearnerRestrictionMode falls back to none', () {
      expect(
        service.normalizeLearnerRestrictionMode('unknown'),
        LessonInteractionService.learnerRestrictionModeNone,
      );
      expect(
        service.normalizeLearnerRestrictionMode(null),
        LessonInteractionService.learnerRestrictionModeNone,
      );
    });

    test('blocksPublicRead and blocksPublicPost match mode semantics', () {
      expect(
        service.blocksPublicRead(
          LessonInteractionService.learnerRestrictionModeNoPublicReadOrPost,
        ),
        isTrue,
      );
      expect(
        service.blocksPublicRead(
          LessonInteractionService.learnerRestrictionModeNoPublicPost,
        ),
        isFalse,
      );
      expect(
        service.blocksPublicPost(
          LessonInteractionService.learnerRestrictionModeNoPublicReadOrPost,
        ),
        isTrue,
      );
      expect(
        service.blocksPublicPost(
          LessonInteractionService.learnerRestrictionModeNoPublicPost,
        ),
        isTrue,
      );
      expect(
        service.blocksPublicPost(
          LessonInteractionService.learnerRestrictionModeNone,
        ),
        isFalse,
      );
    });
  });

  group('LessonInteractionService moderation state helpers', () {
    test('moderationStateFromData treats legacy hidden status as individual hide', () {
      final state = service.moderationStateFromData(const {
        'moderationStatus': lessonInteractionModerationHiddenByTeacher,
      });
      expect(state.hiddenByTeacherIndividual, isTrue);
      expect(state.hiddenByTeacherBulk, isFalse);
      expect(state.moderationStatus, lessonInteractionModerationHiddenByTeacher);
    });

    test('applyIndividualModeration hide keeps existing bulk flag', () {
      const current = LessonPublicModerationState(
        hiddenByTeacherIndividual: false,
        hiddenByTeacherBulk: true,
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
      );
      final next = service.applyIndividualModeration(current: current, hide: true);
      expect(next.hiddenByTeacherIndividual, isTrue);
      expect(next.hiddenByTeacherBulk, isTrue);
      expect(next.moderationStatus, lessonInteractionModerationHiddenByTeacher);
    });

    test('applyIndividualModeration unhide clears both flags', () {
      const current = LessonPublicModerationState(
        hiddenByTeacherIndividual: true,
        hiddenByTeacherBulk: true,
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
      );
      final next = service.applyIndividualModeration(current: current, hide: false);
      expect(next.hiddenByTeacherIndividual, isFalse);
      expect(next.hiddenByTeacherBulk, isFalse);
      expect(next.moderationStatus, lessonInteractionModerationVisible);
    });

    test('applyBulkModeration hide only sets bulk flag', () {
      const current = LessonPublicModerationState(
        hiddenByTeacherIndividual: true,
        hiddenByTeacherBulk: false,
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
      );
      final next = service.applyBulkModeration(current: current, hide: true);
      expect(next.hiddenByTeacherIndividual, isTrue);
      expect(next.hiddenByTeacherBulk, isTrue);
      expect(next.moderationStatus, lessonInteractionModerationHiddenByTeacher);
    });

    test('applyBulkModeration unhide with A keeps individual hidden', () {
      const current = LessonPublicModerationState(
        hiddenByTeacherIndividual: true,
        hiddenByTeacherBulk: true,
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
      );
      final next = service.applyBulkModeration(
        current: current,
        hide: false,
        unhidePolicy: LessonInteractionService.bulkUnhideKeepIndividualHidden,
      );
      expect(next.hiddenByTeacherIndividual, isTrue);
      expect(next.hiddenByTeacherBulk, isFalse);
      expect(next.moderationStatus, lessonInteractionModerationHiddenByTeacher);
    });

    test('applyBulkModeration unhide with B clears all hidden flags', () {
      const current = LessonPublicModerationState(
        hiddenByTeacherIndividual: true,
        hiddenByTeacherBulk: true,
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
      );
      final next = service.applyBulkModeration(
        current: current,
        hide: false,
        unhidePolicy: LessonInteractionService.bulkUnhideForceAllVisible,
      );
      expect(next.hiddenByTeacherIndividual, isFalse);
      expect(next.hiddenByTeacherBulk, isFalse);
      expect(next.moderationStatus, lessonInteractionModerationVisible);
    });
  });
}
