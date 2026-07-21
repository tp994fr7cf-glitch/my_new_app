import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/course.dart';
import '../models/lesson_payload_size_validator.dart';
import '../models/lesson_whiteboard_board_set.dart';

const String lessonDocumentVersionConflictMessage =
    'このレッスンは別の画面で更新されています。画面を開き直してから、もう一度編集してください。';
const String lessonQuizVersionConflictMessage =
    'このレッスンのクイズは別の画面で更新されています。画面を開き直してから、もう一度編集してください。';
const int maxLessonEventsPerLesson = 500;
const String lessonEventLimitMessage = '1レッスンに保存できるクイズは500件までです。';

class LessonDocumentVersionConflict implements Exception {
  const LessonDocumentVersionConflict([
    this.message = lessonDocumentVersionConflictMessage,
  ]);

  final String message;

  @override
  String toString() => message;
}

class LessonQuizVersionConflict implements Exception {
  const LessonQuizVersionConflict([
    this.message = lessonQuizVersionConflictMessage,
  ]);

  final String message;

  @override
  String toString() => message;
}

class CourseLessonSaveResult {
  const CourseLessonSaveResult({
    required this.previousLesson,
    required this.savedLesson,
  });

  final CourseLesson previousLesson;
  final CourseLesson savedLesson;
}

class CourseLessonRepository {
  const CourseLessonRepository();

  CollectionReference<Map<String, dynamic>> _lessons(String courseId) {
    return FirebaseFirestore.instance
        .collection('courses')
        .doc(courseId)
        .collection('lessons');
  }

  Stream<List<CourseLesson>> watchLessons(String courseId) {
    return _lessons(
      courseId,
    ).orderBy('order').snapshots().map(_parseLessonQuery);
  }

  Future<List<CourseLesson>> fetchLessons(String courseId) async {
    final snapshot = await _lessons(courseId).orderBy('order').get();
    return _parseLessonQuery(snapshot);
  }

  Future<CourseLesson?> fetchLesson({
    required String courseId,
    required String lessonId,
  }) async {
    final snapshot = await _lessons(courseId).doc(lessonId).get();
    if (!snapshot.exists) {
      return null;
    }
    return CourseLesson.fromMap(snapshot.data() ?? {}, id: snapshot.id);
  }

  Future<String> createLesson({required String courseId, String? title}) async {
    final firestore = FirebaseFirestore.instance;
    final courseReference = firestore.collection('courses').doc(courseId);
    final lessonReference = courseReference.collection('lessons').doc();

    await firestore.runTransaction<void>((transaction) async {
      final courseSnapshot = await transaction.get(courseReference);
      if (!courseSnapshot.exists) {
        throw StateError('講座が見つかりません。');
      }
      final currentCount = _nonNegativeInt(
        courseSnapshot.data()?['lessonCount'],
      );
      final lesson = CourseLesson(
        id: lessonReference.id,
        order: currentCount,
        title: title?.trim().isNotEmpty == true
            ? title!.trim()
            : 'レッスン${currentCount + 1}',
        duration: '1分30秒',
      );
      transaction.set(lessonReference, {
        ...lesson.toDocumentMap(),
        'schemaVersion': 2,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(courseReference, {
        'lessonCount': currentCount + 1,
        'duration': '${currentCount + 1}レッスン',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return lessonReference.id;
  }

  Future<CourseLessonSaveResult> saveLesson({
    required String courseId,
    required CourseLesson editedLesson,
    required int expectedDocumentVersion,
    int expectedDraftRevision = 0,
  }) async {
    final lessonId = editedLesson.id;
    if (lessonId == null || lessonId.isEmpty) {
      throw StateError('レッスンIDがないため保存できません。');
    }
    validateLessonsForPersistence([editedLesson]);

    final firestore = FirebaseFirestore.instance;
    final courseReference = firestore.collection('courses').doc(courseId);
    final lessonReference = courseReference.collection('lessons').doc(lessonId);
    final draftReference = courseReference
        .collection('lessonDrafts')
        .doc(lessonId);
    return firestore.runTransaction<CourseLessonSaveResult>((
      transaction,
    ) async {
      final snapshot = await transaction.get(lessonReference);
      final draftSnapshot = await transaction.get(draftReference);
      if (!snapshot.exists) {
        throw StateError('レッスンが見つかりません。');
      }
      final previous = CourseLesson.fromMap(
        snapshot.data() ?? {},
        id: snapshot.id,
      );
      if (previous.documentVersion != expectedDocumentVersion) {
        throw const LessonDocumentVersionConflict();
      }
      final draftData = draftSnapshot.data();
      final storedDraftRevision = draftData?['draftRevision'];
      final actualDraftRevision = storedDraftRevision == null
          ? 0
          : _positiveInt(storedDraftRevision);
      if (actualDraftRevision != expectedDraftRevision) {
        throw StateError(lessonDraftRevisionConflictMessage);
      }
      BoardSet? persistedDraft;
      if (draftData != null) {
        if (draftData['baseLessonDocumentVersion'] !=
            previous.documentVersion) {
          throw const LessonDocumentVersionConflict();
        }
        final boardSetData = draftData['boardSet'];
        if (boardSetData is! Map) {
          throw StateError('書き物の下書きデータが不正です。');
        }
        persistedDraft = BoardSet.fromMap(boardSetData);
      }
      final saved = editedLesson.copyWith(
        order: previous.order,
        documentVersion: _nextDocumentVersion(previous.documentVersion),
        quizVersion: previous.quizVersion,
        lessonEvents: previous.lessonEvents,
        createdAt: previous.createdAt,
        publishedBoardSet: persistedDraft ?? editedLesson.publishedBoardSet,
        clearDraftBoardSet: true,
      );
      final lessonData = {
        ...saved.toDocumentMap(),
        'schemaVersion': 2,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      validateCourseDocumentForPersistence(lessonData);
      transaction.update(lessonReference, lessonData);
      transaction.update(courseReference, {
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (draftSnapshot.exists) {
        transaction.delete(draftReference);
      }
      return CourseLessonSaveResult(
        previousLesson: previous,
        savedLesson: saved,
      );
    });
  }

  Future<int> saveLessonDraft({
    required String courseId,
    required String lessonId,
    required int expectedDocumentVersion,
    required int expectedDraftRevision,
    required BoardSet boardSet,
  }) async {
    validateBoardSetForPersistence(boardSet);
    final courseReference = FirebaseFirestore.instance
        .collection('courses')
        .doc(courseId);
    final lessonReference = courseReference.collection('lessons').doc(lessonId);
    final draftReference = courseReference
        .collection('lessonDrafts')
        .doc(lessonId);
    return FirebaseFirestore.instance.runTransaction<int>((transaction) async {
      final lessonSnapshot = await transaction.get(lessonReference);
      if (!lessonSnapshot.exists) {
        throw StateError('レッスンが見つかりません。');
      }
      final lesson = CourseLesson.fromMap(
        lessonSnapshot.data() ?? {},
        id: lessonSnapshot.id,
      );
      if (lesson.documentVersion != expectedDocumentVersion) {
        throw const LessonDocumentVersionConflict();
      }
      final draftSnapshot = await transaction.get(draftReference);
      final currentDraftRevision = draftSnapshot.exists
          ? _positiveInt(draftSnapshot.data()?['draftRevision'])
          : 0;
      if (currentDraftRevision != expectedDraftRevision) {
        throw StateError(lessonDraftRevisionConflictMessage);
      }
      final nextDraftRevision = currentDraftRevision + 1;
      transaction.set(draftReference, {
        'lessonId': lessonId,
        'boardSet': boardSet.toMap(),
        'baseLessonDocumentVersion': lesson.documentVersion,
        'draftRevision': nextDraftRevision,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return nextDraftRevision;
    });
  }

  Future<CourseLesson> saveLessonEvents({
    required String courseId,
    required String lessonId,
    required int expectedQuizVersion,
    required List<LessonEvent> lessonEvents,
  }) async {
    if (lessonEvents.length > maxLessonEventsPerLesson) {
      throw const LessonPayloadValidationException(lessonEventLimitMessage);
    }
    final firestore = FirebaseFirestore.instance;
    final courseReference = firestore.collection('courses').doc(courseId);
    final lessonReference = courseReference.collection('lessons').doc(lessonId);
    return firestore.runTransaction<CourseLesson>((transaction) async {
      final snapshot = await transaction.get(lessonReference);
      if (!snapshot.exists) {
        throw StateError('レッスンが見つかりません。');
      }
      final previous = CourseLesson.fromMap(
        snapshot.data() ?? {},
        id: snapshot.id,
      );
      if (previous.quizVersion != expectedQuizVersion) {
        throw const LessonQuizVersionConflict();
      }
      final saved = previous.copyWith(
        quizVersion: _nextDocumentVersion(previous.quizVersion),
        lessonEvents: lessonEvents,
      );
      final lessonData = {
        ...saved.toDocumentMap(),
        'schemaVersion': 2,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      validateCourseDocumentForPersistence(lessonData);
      transaction.update(lessonReference, lessonData);
      transaction.update(courseReference, {
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return saved;
    });
  }
}

List<CourseLesson> sortCourseLessons(Iterable<CourseLesson> lessons) {
  return [...lessons]..sort((a, b) {
    final orderComparison = a.order.compareTo(b.order);
    if (orderComparison != 0) {
      return orderComparison;
    }
    return (a.id ?? '').compareTo(b.id ?? '');
  });
}

List<CourseLesson> _parseLessonQuery(
  QuerySnapshot<Map<String, dynamic>> snapshot,
) {
  return sortCourseLessons([
    for (final document in snapshot.docs)
      CourseLesson.fromMap(document.data(), id: document.id),
  ]);
}

int _nonNegativeInt(Object? value) {
  if (value is int && value >= 0) {
    return value;
  }
  if (value is num && value.isFinite && value >= 0) {
    return value.toInt();
  }
  return 0;
}

int _nextDocumentVersion(int current) {
  if (current < 1 || current >= 2147483647) {
    throw StateError('レッスンの更新回数が上限に達しています。');
  }
  return current + 1;
}

int _positiveInt(Object? value) {
  if (value is int && value >= 1 && value <= 2147483647) {
    return value;
  }
  throw StateError('書き物の下書きリビジョンが不正です。');
}
