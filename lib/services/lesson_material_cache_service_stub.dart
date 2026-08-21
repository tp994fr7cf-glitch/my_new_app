import '../models/lesson_whiteboard_board_set.dart';
import 'lesson_material_cache_types.dart';

typedef LessonMaterialCacheDownloader =
    Future<void> Function(String storagePath, Object destination);

class LessonMaterialCacheService {
  const LessonMaterialCacheService({
    this.supportedOverride,
    this.userIdOverride,
    this.rootDirectoryOverride,
    this.downloader,
  });

  final bool? supportedOverride;
  final String? userIdOverride;
  final Object? rootDirectoryOverride;
  final LessonMaterialCacheDownloader? downloader;

  bool get supported => false;

  Future<LessonMaterialCacheStatus> status({
    required String courseId,
    required String lessonId,
    required BoardSet boardSet,
  }) async => const LessonMaterialCacheStatus.unsupported();

  Future<String?> localPath({
    required String courseId,
    required String lessonId,
    required String storagePath,
  }) async => null;

  Future<void> putFiles({
    required String courseId,
    required String lessonId,
    required Map<String, List<int>> files,
  }) async {}

  Future<void> removeFiles({
    required String courseId,
    required String lessonId,
    required Iterable<String> storagePaths,
  }) async {}

  Future<LessonMaterialDownloadOutcome> downloadLesson({
    required String courseId,
    required String lessonId,
    required BoardSet boardSet,
    required void Function(LessonMaterialDownloadProgress progress) onProgress,
    required bool Function() isCancelled,
    bool overwriteExisting = true,
    bool deleteUnlistedFiles = true,
    bool skipIfCurrent = false,
  }) async => LessonMaterialDownloadOutcome.nothingToDownload;

  Future<void> deleteLesson({
    required String courseId,
    required String lessonId,
  }) async {}

  Future<void> deleteAll() async {}
}
