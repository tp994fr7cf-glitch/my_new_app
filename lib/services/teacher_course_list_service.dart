import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/course.dart';

const int _firestoreBatchWriteLimit = 500;

typedef TeacherCourseRawArchiveCleanup =
    Future<void> Function({
      required String courseId,
      required bool deleteArchives,
    });

class LiveCourseDeletionBlockedException implements Exception {
  const LiveCourseDeletionBlockedException([
    this.message = '配信を終了してから削除してください。',
  ]);

  final String message;

  @override
  String toString() => message;
}

@visibleForTesting
Future<void> runTeacherCourseDeletion({
  required bool isAlreadyDeleting,
  required Future<void> Function() assertRawArchivesIdle,
  required Future<void> Function() markDeleting,
  required Future<void> Function() deleteCourseMedia,
  required Future<void> Function() deleteRawArchives,
  required Future<void> Function() markDeleted,
}) async {
  await assertRawArchivesIdle();
  if (!isAlreadyDeleting) {
    await markDeleting();
  }
  await deleteCourseMedia();
  await deleteRawArchives();
  await markDeleted();
}

class TeacherCourseListService {
  const TeacherCourseListService({this.rawArchiveCleanup});

  final TeacherCourseRawArchiveCleanup? rawArchiveCleanup;

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

  Future<void> deleteCourse({
    required Course course,
    required String instructorId,
  }) async {
    final courseId = course.id;
    if (courseId == null || courseId.isEmpty) {
      throw StateError('講座IDがないため削除できません。');
    }

    final courseRef = FirebaseFirestore.instance
        .collection('courses')
        .doc(courseId);
    await runTeacherCourseDeletion(
      isAlreadyDeleting: course.isDeleting,
      assertRawArchivesIdle: () => _cleanupRawArchives(
        courseId: courseId,
        deleteArchives: false,
      ),
      markDeleting: () => courseRef.update({
        'status': courseStatusDeleting,
        'deletionRequestedAt': FieldValue.serverTimestamp(),
        'deletedByUserId': instructorId,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      deleteCourseMedia: () => _deleteStoragePrefix(
        FirebaseStorage.instance.ref('courseMedia/$courseId'),
      ),
      deleteRawArchives: () => _cleanupRawArchives(
        courseId: courseId,
        deleteArchives: true,
      ),
      markDeleted: () => courseRef.update({
        'status': courseStatusDeleted,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  Future<void> _cleanupRawArchives({
    required String courseId,
    required bool deleteArchives,
  }) async {
    try {
      await (rawArchiveCleanup ?? _defaultRawArchiveCleanup)(
        courseId: courseId,
        deleteArchives: deleteArchives,
      );
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'failed-precondition') {
        throw LiveCourseDeletionBlockedException(
          error.message ?? '配信を終了してから削除してください。',
        );
      }
      rethrow;
    }
  }

  Future<void> _defaultRawArchiveCleanup({
    required String courseId,
    required bool deleteArchives,
  }) async {
    await FirebaseFunctions.instanceFor(region: 'asia-northeast1')
        .httpsCallable(
          'deleteLiveAudioProbeRawArchivesForCourse',
          options: HttpsCallableOptions(
            timeout: const Duration(seconds: 540),
          ),
        )
        .call({
          'courseId': courseId,
          'mode': deleteArchives ? 'delete' : 'check',
        });
  }

  Future<void> _deleteStoragePrefix(Reference reference) async {
    final result = await reference.listAll();
    for (final prefix in result.prefixes) {
      await _deleteStoragePrefix(prefix);
    }
    for (final item in result.items) {
      await item.delete();
    }
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
