import '../models/lesson_whiteboard_board_set.dart';
import 'lesson_material_cache_types.dart';

class LessonMaterialCacheService {
  const LessonMaterialCacheService();

  bool get supported => false;

  Future<LessonMaterialCacheStatus> status({
    required String courseId,
    required String lessonId,
    required BoardSet boardSet,
  }) async => const LessonMaterialCacheStatus.unsupported();

  Future<String?> localPath({
    required String courseId,
    required String lessonId,
    required BoardSet boardSet,
    required String storagePath,
  }) async => null;

  Future<void> downloadLesson({
    required String courseId,
    required String lessonId,
    required BoardSet boardSet,
    required void Function(LessonMaterialDownloadProgress progress) onProgress,
    required bool Function() isCancelled,
  }) async {}

  Future<void> deleteLesson({
    required String courseId,
    required String lessonId,
  }) async {}

  Future<void> deleteAll() async {}
}
