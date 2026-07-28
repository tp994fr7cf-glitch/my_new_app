import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/course.dart';

bool isCourseLearnerAccessibleData(Map<String, dynamic>? data) {
  return data?['status'] == courseStatusPublished;
}

class CourseAccessService {
  const CourseAccessService();

  Future<bool> isLearnerAccessible(String courseId) async {
    if (courseId.isEmpty) {
      return false;
    }
    if (Firebase.apps.isEmpty) {
      return true;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('courses')
          .doc(courseId)
          .get();
      return snapshot.exists && isCourseLearnerAccessibleData(snapshot.data());
    } on FirebaseException {
      return false;
    }
  }

  Stream<bool> watchLearnerAccessible(String courseId) async* {
    if (courseId.isEmpty) {
      yield false;
      return;
    }
    if (Firebase.apps.isEmpty) {
      yield true;
      return;
    }
    try {
      await for (final snapshot
          in FirebaseFirestore.instance
              .collection('courses')
              .doc(courseId)
              .snapshots()) {
        yield snapshot.exists && isCourseLearnerAccessibleData(snapshot.data());
      }
    } on FirebaseException {
      yield false;
    }
  }
}
