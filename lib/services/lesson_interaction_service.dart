import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

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
          .doc(settingDocumentId(courseId: courseId, lessonNumber: lessonNumber))
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
}

