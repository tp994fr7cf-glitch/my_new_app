import '../widgets/lesson_whiteboard_canvas.dart';
import 'lesson_material_cache_service.dart';

Future<LessonWhiteboardMaterialSource> resolveCachedLessonMaterialSource({
  required String courseId,
  required String lessonId,
  required String storagePath,
  LessonMaterialCacheService? cache,
  bool allowLocal = true,
}) async {
  if (allowLocal &&
      courseId.trim().isNotEmpty &&
      lessonId.trim().isNotEmpty &&
      storagePath.trim().isNotEmpty) {
    final localPath = await (cache ?? LessonMaterialCacheService()).localPath(
      courseId: courseId,
      lessonId: lessonId,
      storagePath: storagePath,
    );
    if (localPath != null) {
      return LessonWhiteboardMaterialSource.file(localPath);
    }
  }
  return resolveLessonWhiteboardMaterialUrl(storagePath);
}
