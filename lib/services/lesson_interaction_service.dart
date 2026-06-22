import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/lesson_interaction_constants.dart';
import '../models/lesson_note.dart';

class LessonPublicModerationState {
  const LessonPublicModerationState({
    required this.hiddenByTeacherIndividual,
    required this.hiddenByTeacherBulk,
    required this.moderationStatus,
  });

  final bool hiddenByTeacherIndividual;
  final bool hiddenByTeacherBulk;
  final String moderationStatus;
}

class LessonInteractionService {
  const LessonInteractionService();

  static const lessonNotesPublicEnabledField = 'lessonNotesPublicEnabled';
  static const lessonQuestionsPublicEnabledField =
      'lessonQuestionsPublicEnabled';
  static const learnerRestrictionsCollectionName = 'learnerRestrictions';
  static const learnerRestrictionModeField = 'restrictionMode';
  static const learnerRestrictionModeNone = 'none';
  static const learnerRestrictionModeNoPublicPost = 'noPublicPost';
  static const learnerRestrictionModeNoPublicReadOrPost = 'noPublicReadOrPost';
  static const bulkUnhideKeepIndividualHidden = 'keepIndividualHidden';
  static const bulkUnhideForceAllVisible = 'forceAllVisible';
  static const moderationSourceIndividual = 'individual';
  static const moderationSourceBulk = 'bulk';
  static const hiddenByTeacherIndividualField = 'hiddenByTeacherIndividual';
  static const hiddenByTeacherBulkField = 'hiddenByTeacherBulk';
  static const _batchWriteLimit = 450;

  int get bulkWriteChunkSize => _batchWriteLimit;

  String settingDocumentId({
    required String courseId,
    required int lessonNumber,
  }) {
    return '${courseId}_$lessonNumber';
  }

  Stream<bool> publicFeatureEnabledStream({
    required String courseId,
    required int lessonNumber,
    required String fieldName,
  }) {
    if (Firebase.apps.isEmpty) {
      return Stream.value(true);
    }
    return FirebaseFirestore.instance
        .collection('lessonInteractionSettings')
        .doc(settingDocumentId(courseId: courseId, lessonNumber: lessonNumber))
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          return data == null || data[fieldName] != false;
        });
  }

  Future<bool> isPublicFeatureEnabled({
    required String courseId,
    required int lessonNumber,
    required String fieldName,
  }) async {
    if (Firebase.apps.isEmpty) {
      return true;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('lessonInteractionSettings')
          .doc(
            settingDocumentId(courseId: courseId, lessonNumber: lessonNumber),
          )
          .get();
      final data = snapshot.data();
      return data == null || data[fieldName] != false;
    } on FirebaseException {
      return true;
    }
  }

  String normalizeLearnerRestrictionMode(String? mode) {
    return switch (mode) {
      learnerRestrictionModeNoPublicPost => learnerRestrictionModeNoPublicPost,
      learnerRestrictionModeNoPublicReadOrPost =>
        learnerRestrictionModeNoPublicReadOrPost,
      _ => learnerRestrictionModeNone,
    };
  }

  bool blocksPublicRead(String restrictionMode) {
    return normalizeLearnerRestrictionMode(restrictionMode) ==
        learnerRestrictionModeNoPublicReadOrPost;
  }

  bool blocksPublicPost(String restrictionMode) {
    final normalized = normalizeLearnerRestrictionMode(restrictionMode);
    return normalized == learnerRestrictionModeNoPublicPost ||
        normalized == learnerRestrictionModeNoPublicReadOrPost;
  }

  Stream<String> learnerRestrictionModeStream({
    required String courseId,
    required int lessonNumber,
    required String learnerId,
  }) {
    if (Firebase.apps.isEmpty || learnerId.isEmpty) {
      return Stream.value(learnerRestrictionModeNone);
    }
    final settingId = settingDocumentId(
      courseId: courseId,
      lessonNumber: lessonNumber,
    );
    return FirebaseFirestore.instance
        .collection('lessonInteractionSettings')
        .doc(settingId)
        .collection(learnerRestrictionsCollectionName)
        .doc(learnerId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          return normalizeLearnerRestrictionMode(
            data?[learnerRestrictionModeField] as String?,
          );
        });
  }

  Future<String> learnerRestrictionMode({
    required String courseId,
    required int lessonNumber,
    required String learnerId,
  }) async {
    if (Firebase.apps.isEmpty || learnerId.isEmpty) {
      return learnerRestrictionModeNone;
    }
    final settingId = settingDocumentId(
      courseId: courseId,
      lessonNumber: lessonNumber,
    );
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('lessonInteractionSettings')
          .doc(settingId)
          .collection(learnerRestrictionsCollectionName)
          .doc(learnerId)
          .get();
      final data = snapshot.data();
      return normalizeLearnerRestrictionMode(
        data?[learnerRestrictionModeField] as String?,
      );
    } on FirebaseException {
      return learnerRestrictionModeNone;
    }
  }

  Future<void> setLearnerRestrictionMode({
    required String courseId,
    required int lessonNumber,
    required String learnerId,
    required String restrictionMode,
    required String updatedByUserId,
  }) async {
    if (Firebase.apps.isEmpty ||
        courseId.isEmpty ||
        learnerId.isEmpty ||
        updatedByUserId.isEmpty) {
      return;
    }
    final mode = normalizeLearnerRestrictionMode(restrictionMode);
    final settingId = settingDocumentId(
      courseId: courseId,
      lessonNumber: lessonNumber,
    );
    await FirebaseFirestore.instance
        .collection('lessonInteractionSettings')
        .doc(settingId)
        .collection(learnerRestrictionsCollectionName)
        .doc(learnerId)
        .set({
          'courseId': courseId,
          'lessonNumber': lessonNumber,
          'learnerId': learnerId,
          learnerRestrictionModeField: mode,
          'updatedByUserId': updatedByUserId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  bool _resolveIndividualHidden(Map<String, dynamic> data) {
    if (data.containsKey(hiddenByTeacherIndividualField)) {
      return data[hiddenByTeacherIndividualField] == true;
    }
    final moderationStatus = data['moderationStatus'] as String?;
    if (moderationStatus == lessonInteractionModerationHiddenByTeacher) {
      return data[hiddenByTeacherBulkField] != true;
    }
    return false;
  }

  bool _resolveBulkHidden(Map<String, dynamic> data) {
    return data[hiddenByTeacherBulkField] == true;
  }

  String effectiveModerationStatus({
    required bool hiddenByTeacherIndividual,
    required bool hiddenByTeacherBulk,
  }) {
    if (hiddenByTeacherIndividual || hiddenByTeacherBulk) {
      return lessonInteractionModerationHiddenByTeacher;
    }
    return lessonInteractionModerationVisible;
  }

  LessonPublicModerationState moderationStateFromData(
    Map<String, dynamic> data,
  ) {
    final hiddenByTeacherIndividual = _resolveIndividualHidden(data);
    final hiddenByTeacherBulk = _resolveBulkHidden(data);
    return LessonPublicModerationState(
      hiddenByTeacherIndividual: hiddenByTeacherIndividual,
      hiddenByTeacherBulk: hiddenByTeacherBulk,
      moderationStatus: effectiveModerationStatus(
        hiddenByTeacherIndividual: hiddenByTeacherIndividual,
        hiddenByTeacherBulk: hiddenByTeacherBulk,
      ),
    );
  }

  LessonPublicModerationState applyIndividualModeration({
    required LessonPublicModerationState current,
    required bool hide,
  }) {
    final hiddenByTeacherIndividual = hide ? true : false;
    final hiddenByTeacherBulk = hide ? current.hiddenByTeacherBulk : false;
    return LessonPublicModerationState(
      hiddenByTeacherIndividual: hiddenByTeacherIndividual,
      hiddenByTeacherBulk: hiddenByTeacherBulk,
      moderationStatus: effectiveModerationStatus(
        hiddenByTeacherIndividual: hiddenByTeacherIndividual,
        hiddenByTeacherBulk: hiddenByTeacherBulk,
      ),
    );
  }

  LessonPublicModerationState applyBulkModeration({
    required LessonPublicModerationState current,
    required bool hide,
    String unhidePolicy = bulkUnhideKeepIndividualHidden,
  }) {
    final normalizedUnhidePolicy = unhidePolicy == bulkUnhideForceAllVisible
        ? bulkUnhideForceAllVisible
        : bulkUnhideKeepIndividualHidden;
    if (hide) {
      return LessonPublicModerationState(
        hiddenByTeacherIndividual: current.hiddenByTeacherIndividual,
        hiddenByTeacherBulk: true,
        moderationStatus: lessonInteractionModerationHiddenByTeacher,
      );
    }
    final hiddenByTeacherIndividual =
        normalizedUnhidePolicy == bulkUnhideForceAllVisible
        ? false
        : current.hiddenByTeacherIndividual;
    final hiddenByTeacherBulk = false;
    return LessonPublicModerationState(
      hiddenByTeacherIndividual: hiddenByTeacherIndividual,
      hiddenByTeacherBulk: hiddenByTeacherBulk,
      moderationStatus: effectiveModerationStatus(
        hiddenByTeacherIndividual: hiddenByTeacherIndividual,
        hiddenByTeacherBulk: hiddenByTeacherBulk,
      ),
    );
  }

  Future<void> setPublicModeration({
    required String collectionPath,
    required String? documentId,
    required String moderationStatus,
    String source = moderationSourceIndividual,
  }) async {
    if (Firebase.apps.isEmpty || documentId == null) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final docRef = firestore.collection(collectionPath).doc(documentId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      return;
    }
    final data = snapshot.data() ?? const <String, dynamic>{};
    final current = moderationStateFromData(data);
    final shouldHide =
        moderationStatus == lessonInteractionModerationHiddenByTeacher;
    final nextState = source == moderationSourceBulk
        ? applyBulkModeration(current: current, hide: shouldHide)
        : applyIndividualModeration(current: current, hide: shouldHide);
    try {
      await docRef.set(
        _moderationUpdateMap(nextState: nextState, includeLayeredFlags: true),
        SetOptions(merge: true),
      );
    } on FirebaseException catch (error) {
      // Backward compatibility: older deployed Rules may still allow only
      // moderationStatus/moderatedAt. In that case, retry with legacy fields.
      if (!_isLegacyModerationFallbackTarget(error)) {
        rethrow;
      }
      await docRef.set(
        _moderationUpdateMap(nextState: nextState, includeLayeredFlags: false),
        SetOptions(merge: true),
      );
    }
  }

  Future<int> setBulkModerationByAuthor({
    required String collectionPath,
    required String courseId,
    required int lessonNumber,
    required String authorId,
    required bool hide,
    String unhidePolicy = bulkUnhideKeepIndividualHidden,
  }) async {
    if (Firebase.apps.isEmpty || courseId.isEmpty || authorId.isEmpty) {
      return 0;
    }
    final normalizedUnhidePolicy = unhidePolicy == bulkUnhideForceAllVisible
        ? bulkUnhideForceAllVisible
        : bulkUnhideKeepIndividualHidden;
    final firestore = FirebaseFirestore.instance;
    final querySnapshot = await firestore
        .collection(collectionPath)
        .where('courseId', isEqualTo: courseId)
        .where('lessonNumber', isEqualTo: lessonNumber)
        .where('authorId', isEqualTo: authorId)
        .where('isDeleted', isEqualTo: false)
        .get();

    var updatedCount = 0;
    var pendingWrites = 0;
    var batch = firestore.batch();
    final pendingEntries =
        <
          ({
            DocumentReference<Map<String, dynamic>> ref,
            LessonPublicModerationState state,
          })
        >[];
    var includeLayeredFlags = true;

    Future<void> flushBatch() async {
      if (pendingWrites == 0) {
        return;
      }
      try {
        await batch.commit();
      } on FirebaseException catch (error) {
        if (!includeLayeredFlags || !_isLegacyModerationFallbackTarget(error)) {
          rethrow;
        }
        // Retry current chunk with legacy fields only.
        includeLayeredFlags = false;
        batch = firestore.batch();
        for (final entry in pendingEntries) {
          batch.set(
            entry.ref,
            _moderationUpdateMap(
              nextState: entry.state,
              includeLayeredFlags: false,
            ),
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      }
      batch = firestore.batch();
      pendingWrites = 0;
      pendingEntries.clear();
    }

    for (final doc in querySnapshot.docs) {
      final data = doc.data();
      final current = moderationStateFromData(data);
      final nextState = applyBulkModeration(
        current: current,
        hide: hide,
        unhidePolicy: normalizedUnhidePolicy,
      );
      batch.set(
        doc.reference,
        _moderationUpdateMap(
          nextState: nextState,
          includeLayeredFlags: includeLayeredFlags,
        ),
        SetOptions(merge: true),
      );
      pendingEntries.add((ref: doc.reference, state: nextState));
      updatedCount += 1;
      pendingWrites += 1;
      if (pendingWrites >= _batchWriteLimit) {
        await flushBatch();
      }
    }
    await flushBatch();
    return updatedCount;
  }

  Future<int> setBulkModerationForLearnerPublicPosts({
    required String courseId,
    required int lessonNumber,
    required String learnerId,
    required bool hide,
    String unhidePolicy = bulkUnhideKeepIndividualHidden,
  }) async {
    var totalUpdated = 0;
    totalUpdated += await setBulkModerationByAuthor(
      collectionPath: 'publicLessonNotes',
      courseId: courseId,
      lessonNumber: lessonNumber,
      authorId: learnerId,
      hide: hide,
      unhidePolicy: unhidePolicy,
    );
    totalUpdated += await setBulkModerationByAuthor(
      collectionPath: 'publicLessonQuestions',
      courseId: courseId,
      lessonNumber: lessonNumber,
      authorId: learnerId,
      hide: hide,
      unhidePolicy: unhidePolicy,
    );
    totalUpdated += await setBulkModerationByAuthor(
      collectionPath: 'publicLessonQuestionAnswers',
      courseId: courseId,
      lessonNumber: lessonNumber,
      authorId: learnerId,
      hide: hide,
      unhidePolicy: unhidePolicy,
    );
    return totalUpdated;
  }

  bool _isLegacyModerationFallbackTarget(FirebaseException error) {
    return error.code == 'permission-denied' ||
        error.code == 'failed-precondition';
  }

  Map<String, Object?> _moderationUpdateMap({
    required LessonPublicModerationState nextState,
    required bool includeLayeredFlags,
  }) {
    return {
      'moderationStatus': nextState.moderationStatus,
      if (includeLayeredFlags)
        hiddenByTeacherIndividualField: nextState.hiddenByTeacherIndividual,
      if (includeLayeredFlags)
        hiddenByTeacherBulkField: nextState.hiddenByTeacherBulk,
      'moderatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> decidePublicNoteApproval({
    required String noteId,
    required String authorId,
    required bool approve,
  }) async {
    if (Firebase.apps.isEmpty || noteId.isEmpty || authorId.isEmpty) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();
    final ownerRef = firestore
        .collection('users')
        .doc(authorId)
        .collection('lessonNotes')
        .doc(noteId);
    final publicRef = firestore.collection('publicLessonNotes').doc(noteId);
    final batch = firestore.batch();
    if (approve) {
      batch.set(ownerRef, {
        'visibility': lessonNoteVisibilityPublic,
        'publicApprovalStatus': lessonNotePublicApprovalApproved,
        'updatedAt': now,
      }, SetOptions(merge: true));
      batch.set(publicRef, {
        'studentVisibility': lessonNoteVisibilityPublic,
        'publicApprovalStatus': lessonNotePublicApprovalApproved,
        'publicPublishedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    } else {
      batch.set(ownerRef, {
        'visibility': lessonNoteVisibilityTeacherOnly,
        'publicApprovalStatus': lessonNotePublicApprovalRejected,
        'updatedAt': now,
      }, SetOptions(merge: true));
      batch.set(publicRef, {
        'studentVisibility': lessonNoteVisibilityTeacherOnly,
        'publicApprovalStatus': lessonNotePublicApprovalRejected,
        'updatedAt': now,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> clearOwnPublicApprovalNotice({
    required String noteId,
    required String ownerId,
  }) async {
    if (Firebase.apps.isEmpty || noteId.isEmpty || ownerId.isEmpty) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();
    final ownerRef = firestore
        .collection('users')
        .doc(ownerId)
        .collection('lessonNotes')
        .doc(noteId);
    final publicRef = firestore.collection('publicLessonNotes').doc(noteId);
    final ownerSnapshot = await ownerRef.get();
    if (!ownerSnapshot.exists) {
      return;
    }
    final batch = firestore.batch()
      ..set(ownerRef, {
        'publicApprovalStatus': lessonNotePublicApprovalNone,
        'updatedAt': now,
      }, SetOptions(merge: true));
    final publicSnapshot = await publicRef.get();
    if (publicSnapshot.exists) {
      batch.set(publicRef, {
        'publicApprovalStatus': lessonNotePublicApprovalNone,
        'updatedAt': now,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
