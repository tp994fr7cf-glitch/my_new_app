import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/course.dart';

class CourseCatalogService {
  const CourseCatalogService();

  Stream<Course>? watchCourse(Course fallback) {
    final courseId = fallback.id;
    if (courseId == null || courseId.isEmpty || Firebase.apps.isEmpty) {
      return null;
    }

    return FirebaseFirestore.instance
        .collection('courses')
        .doc(courseId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) {
            return fallback;
          }
          return Course.tryFromFirestore(snapshot) ?? fallback;
        });
  }

  Future<Course> fetchCourse(String courseId, {required Course fallback}) async {
    if (courseId.isEmpty || Firebase.apps.isEmpty) {
      return fallback;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('courses')
          .doc(courseId)
          .get();
      if (!snapshot.exists) {
        return fallback;
      }
      return Course.tryFromFirestore(snapshot) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }
}
