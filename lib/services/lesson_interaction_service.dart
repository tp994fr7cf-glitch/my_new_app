import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/lesson_note.dart';

class LessonInteractionService {
  const LessonInteractionService();

  static const lessonNotesPublicEnabledField = 'lessonNotesPublicEnabled';
  static const lessonQuestionsPublicEnabledField =
      'lessonQuestionsPublicEnabled';

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

  Future<void> setPublicModeration({
    required String collectionPath,
    required String? documentId,
    required String moderationStatus,
  }) async {
    if (Firebase.apps.isEmpty || documentId == null) {
      return;
    }
    await FirebaseFirestore.instance
        .collection(collectionPath)
        .doc(documentId)
        .set({
          'moderationStatus': moderationStatus,
          'moderatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
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
