import '../models/lesson_whiteboard_board_set.dart';

class LessonMaterialCacheStatus {
  const LessonMaterialCacheStatus({
    required this.supported,
    required this.hasCurrentCache,
    required this.hasStaleCache,
    required this.totalBytes,
  });

  const LessonMaterialCacheStatus.unsupported()
    : supported = false,
      hasCurrentCache = false,
      hasStaleCache = false,
      totalBytes = 0;

  final bool supported;
  final bool hasCurrentCache;
  final bool hasStaleCache;
  final int totalBytes;
}

class LessonMaterialDownloadProgress {
  const LessonMaterialDownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.completedFiles,
    required this.totalFiles,
  });

  final int downloadedBytes;
  final int totalBytes;
  final int completedFiles;
  final int totalFiles;

  double get fraction {
    if (totalBytes > 0) {
      return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
    }
    if (totalFiles > 0) {
      return (completedFiles / totalFiles).clamp(0.0, 1.0);
    }
    return 0;
  }
}

class LessonMaterialCacheCancelled implements Exception {
  const LessonMaterialCacheCancelled();
}

enum LessonMaterialDownloadOutcome {
  skippedAlreadyCurrent,
  downloaded,
  nothingToDownload,
}

List<String> lessonMaterialStoragePaths(BoardSet boardSet) {
  final paths = <String>{
    for (final board in boardSet.boards)
      if (board.background case final background?)
        background.storagePath.trim(),
  }..removeWhere((path) => path.isEmpty);
  return paths.toList()..sort();
}

String lessonMaterialFingerprint(BoardSet boardSet) =>
    lessonMaterialStoragePaths(boardSet).join('\n');
