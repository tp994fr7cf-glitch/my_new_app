import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/course.dart';
import '../models/lesson_material_library.dart';
import '../models/lesson_whiteboard_board_set.dart';
import 'course_lesson_repository.dart';
import 'lesson_material_storage_service.dart';

class LessonMaterialSourceInfo {
  const LessonMaterialSourceInfo({this.originalFileName, this.timeCreated});

  final String? originalFileName;
  final DateTime? timeCreated;
}

typedef LessonMaterialLibraryUserIdProvider = String? Function();
typedef LessonMaterialLibrarySourcesLoader =
    Future<List<LessonMaterialLibrarySource>> Function(String userId);
typedef LessonMaterialSourceInfoReader =
    Future<LessonMaterialSourceInfo?> Function(String sourceStoragePath);

class LessonMaterialLibraryService {
  const LessonMaterialLibraryService({
    this.userIdProvider,
    this.loadLibrarySources,
    this.readSourceInfo,
    this.lessonRepository = const CourseLessonRepository(),
  });

  final LessonMaterialLibraryUserIdProvider? userIdProvider;
  final LessonMaterialLibrarySourcesLoader? loadLibrarySources;
  final LessonMaterialSourceInfoReader? readSourceInfo;
  final CourseLessonRepository lessonRepository;

  Future<List<LessonMaterialLibraryItem>> listItems() async {
    final userId = (userIdProvider ?? _defaultUserId)();
    if (userId == null || userId.isEmpty) {
      throw const LessonMaterialStorageException('ログインが必要です。');
    }
    final sources = await (loadLibrarySources ?? _loadSourcesFromFirebase)(
      userId,
    );
    final collected = collectLessonMaterialLibraryItems(sources);
    final reader = readSourceInfo ?? _readSourceInfoFromStorage;
    final enriched = await Future.wait(
      collected.map((item) async {
        final info = await reader(item.sourceStoragePath);
        if (info == null) {
          return null;
        }
        final originalFileName = info.originalFileName?.trim();
        return item.copyWith(
          fileName: (originalFileName != null && originalFileName.isNotEmpty)
              ? originalFileName
              : item.fileName,
          uploadedAt: info.timeCreated ?? item.uploadedAt,
        );
      }),
    );
    return sortLessonMaterialLibraryItems([for (final item in enriched) ?item]);
  }

  String? _defaultUserId() {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    return FirebaseAuth.instance.currentUser?.uid;
  }

  Future<List<LessonMaterialLibrarySource>> _loadSourcesFromFirebase(
    String userId,
  ) async {
    if (Firebase.apps.isEmpty) {
      throw const LessonMaterialStorageException('Firebase が初期化されていません。');
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('courses')
        .where('instructorId', isEqualTo: userId)
        .get();
    final courses = snapshot.docs
        .map(Course.tryFromFirestore)
        .whereType<Course>()
        .where((course) => !course.isDeleted && !course.isDeleting);
    final perCourse = await Future.wait([
      for (final course in courses) _sourcesForCourse(course),
    ]);
    return [for (final sources in perCourse) ...sources];
  }

  Future<List<LessonMaterialLibrarySource>> _sourcesForCourse(
    Course course,
  ) async {
    final courseId = course.id;
    if (courseId == null || courseId.isEmpty) {
      return const [];
    }
    final courseTitle = course.title.trim().isEmpty
        ? '講座'
        : course.title.trim();
    final lessonsById = <String, CourseLesson>{};
    final lessonsWithoutId = <CourseLesson>[];
    for (final lesson in course.lessons) {
      final lessonId = lesson.id?.trim();
      if (lessonId == null || lessonId.isEmpty) {
        lessonsWithoutId.add(lesson);
      } else {
        lessonsById[lessonId] = lesson;
      }
    }
    try {
      for (final lesson in await lessonRepository.fetchLessons(courseId)) {
        final lessonId = lesson.id?.trim();
        if (lessonId != null && lessonId.isNotEmpty) {
          lessonsById[lessonId] = lesson;
        }
      }
    } catch (_) {
      // Nested course.lessons still contribute materials when the
      // lessons subcollection cannot be read.
    }

    final allLessons = [...lessonsById.values, ...lessonsWithoutId];
    final sources = <LessonMaterialLibrarySource>[
      for (final lesson in allLessons)
        LessonMaterialLibrarySource(
          courseId: courseId,
          courseTitle: courseTitle,
          lessonId: lesson.id?.trim() ?? '',
          lessonTitle: lesson.title.trim().isEmpty
              ? 'レッスン'
              : lesson.title.trim(),
          boardSets: [lesson.publishedBoardSet, lesson.draftBoardSet],
        ),
    ];

    try {
      final drafts = await FirebaseFirestore.instance
          .collection('courses')
          .doc(courseId)
          .collection('lessonDrafts')
          .get();
      for (final doc in drafts.docs) {
        final data = doc.data();
        final boardSetData = data['boardSet'];
        if (boardSetData is! Map) {
          continue;
        }
        final boardSet = BoardSet.fromMap(boardSetData);
        final matched = _matchDraftLesson(
          docId: doc.id,
          data: data,
          lessonsById: lessonsById,
          allLessons: allLessons,
        );
        final lessonIdField = data['lessonId'];
        sources.add(
          LessonMaterialLibrarySource(
            courseId: courseId,
            courseTitle: courseTitle,
            lessonId:
                matched?.id?.trim() ??
                (lessonIdField is String ? lessonIdField.trim() : doc.id),
            lessonTitle: matched == null || matched.title.trim().isEmpty
                ? 'レッスン'
                : matched.title.trim(),
            boardSets: [boardSet],
          ),
        );
      }
    } catch (_) {
      // Published lesson boards are still listed if drafts cannot be read.
    }
    return sources;
  }

  CourseLesson? _matchDraftLesson({
    required String docId,
    required Map<String, dynamic> data,
    required Map<String, CourseLesson> lessonsById,
    required List<CourseLesson> allLessons,
  }) {
    final byDocId = lessonsById[docId];
    if (byDocId != null) {
      return byDocId;
    }
    final lessonIdField = data['lessonId'];
    if (lessonIdField is String && lessonsById.containsKey(lessonIdField)) {
      return lessonsById[lessonIdField];
    }
    final lessonNumber = int.tryParse(docId);
    if (lessonNumber == null || lessonNumber < 1) {
      return null;
    }
    for (final lesson in allLessons) {
      if (lesson.order == lessonNumber - 1) {
        return lesson;
      }
    }
    if (lessonNumber <= allLessons.length) {
      return allLessons[lessonNumber - 1];
    }
    return null;
  }

  Future<LessonMaterialSourceInfo?> _readSourceInfoFromStorage(
    String sourceStoragePath,
  ) async {
    try {
      final metadata = await FirebaseStorage.instance
          .ref(sourceStoragePath)
          .getMetadata();
      final originalFileName = metadata.customMetadata?['originalFileName']
          ?.trim();
      return LessonMaterialSourceInfo(
        originalFileName:
            (originalFileName != null && originalFileName.isNotEmpty)
            ? originalFileName
            : null,
        timeCreated: metadata.timeCreated,
      );
    } catch (_) {
      return null;
    }
  }
}
