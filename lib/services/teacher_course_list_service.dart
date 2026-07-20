import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/course.dart';

const int _firestoreBatchWriteLimit = 500;

class TeacherCourseListService {
  const TeacherCourseListService();

  Stream<List<Course>> watchOwnCourses(String instructorId) {
    return FirebaseFirestore.instance
        .collection('courses')
        .where('instructorId', isEqualTo: instructorId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(Course.tryFromFirestore)
              .whereType<Course>()
              .toList(),
        );
  }

  Future<void> setHidden({required Course course, required bool hidden}) async {
    final courseId = course.id;
    if (courseId == null || courseId.isEmpty) {
      throw StateError('講座IDがないため表示設定を保存できません。');
    }

    await FirebaseFirestore.instance.collection('courses').doc(courseId).update(
      {'teacherListHidden': hidden},
    );
  }

  Future<void> saveVisibleOrder(List<Course> orderedCourses) async {
    if (orderedCourses.length > _firestoreBatchWriteLimit) {
      throw StateError('一度に並び替えられる講座数（$_firestoreBatchWriteLimit件）を超えています。');
    }

    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    for (final entry in orderedCourses.indexed) {
      final courseId = entry.$2.id;
      if (courseId == null || courseId.isEmpty) {
        throw StateError('講座IDがないため並び順を保存できません。');
      }
      batch.update(firestore.collection('courses').doc(courseId), {
        'teacherListOrder': entry.$1,
      });
    }
    await batch.commit();
  }
}

List<Course> sortTeacherCourses(
  Iterable<Course> courses, {
  List<String>? preferredIds,
}) {
  final preferredRanks = <String, int>{
    for (final entry in (preferredIds ?? const <String>[]).indexed)
      entry.$2: entry.$1,
  };
  return [...courses]..sort((a, b) {
    final aPreferredRank = a.id == null ? null : preferredRanks[a.id];
    final bPreferredRank = b.id == null ? null : preferredRanks[b.id];
    if (aPreferredRank != null || bPreferredRank != null) {
      if (aPreferredRank == null) {
        return 1;
      }
      if (bPreferredRank == null) {
        return -1;
      }
      final preferredComparison = aPreferredRank.compareTo(bPreferredRank);
      if (preferredComparison != 0) {
        return preferredComparison;
      }
    }

    final aOrder = a.teacherListOrder;
    final bOrder = b.teacherListOrder;
    if (aOrder != null || bOrder != null) {
      if (aOrder == null) {
        return 1;
      }
      if (bOrder == null) {
        return -1;
      }
      final orderComparison = aOrder.compareTo(bOrder);
      if (orderComparison != 0) {
        return orderComparison;
      }
    }

    final titleComparison = a.title.compareTo(b.title);
    if (titleComparison != 0) {
      return titleComparison;
    }
    return (a.id ?? '').compareTo(b.id ?? '');
  });
}
