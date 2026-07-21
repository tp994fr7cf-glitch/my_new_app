import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/course.dart';
import 'course_lesson_repository.dart';

class CourseCatalogService {
  const CourseCatalogService({
    this.lessonRepository = const CourseLessonRepository(),
  });

  final CourseLessonRepository lessonRepository;

  Stream<Course>? watchCourse(Course fallback) {
    final courseId = fallback.id;
    if (courseId == null || courseId.isEmpty || Firebase.apps.isEmpty) {
      return null;
    }

    final courseReference = FirebaseFirestore.instance
        .collection('courses')
        .doc(courseId);
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    courseSubscription;
    StreamSubscription<List<CourseLesson>>? lessonSubscription;
    Course latestCourse = fallback;
    List<CourseLesson> latestLessons = fallback.lessons;
    var hasCourseSnapshot = false;
    var hasLessonSnapshot = false;
    late final StreamController<Course> controller;

    void emitIfReady() {
      if (hasCourseSnapshot && hasLessonSnapshot && !controller.isClosed) {
        controller.add(latestCourse.withLessonContent(latestLessons));
      }
    }

    controller = StreamController<Course>(
      onListen: () {
        courseSubscription = courseReference.snapshots().listen((snapshot) {
          latestCourse = snapshot.exists
              ? (Course.tryFromFirestore(snapshot) ?? fallback)
              : fallback;
          hasCourseSnapshot = true;
          emitIfReady();
        }, onError: controller.addError);
        lessonSubscription = lessonRepository.watchLessons(courseId).listen((
          lessons,
        ) {
          latestLessons = lessons;
          hasLessonSnapshot = true;
          emitIfReady();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await courseSubscription?.cancel();
        await lessonSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<Course> fetchCourse(
    String courseId, {
    required Course fallback,
  }) async {
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
      final course = Course.tryFromFirestore(snapshot) ?? fallback;
      final lessons = await lessonRepository.fetchLessons(courseId);
      return course.withLessonContent(lessons);
    } catch (_) {
      return fallback;
    }
  }
}
