import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/lesson_material_cache_service_io.dart';
import 'package:my_new_app/services/lesson_material_cache_types.dart';

void main() {
  late Directory root;
  late LessonMaterialCacheService cache;
  final downloaded = <String>[];

  BoardSet boardSetWith(List<String> storagePaths) {
    return BoardSet(
      boards: [
        for (final entry in storagePaths.indexed)
          LessonWhiteboardBoard(
            id: 'board-${entry.$1}',
            order: entry.$1,
            background: LessonWhiteboardBoardBackground(
              assetId: 'asset-${entry.$1}',
              storagePath: entry.$2,
              mediaType: lessonWhiteboardBackgroundImage,
              aspectRatio: 1,
            ),
          ),
      ],
    );
  }

  setUp(() async {
    downloaded.clear();
    root = await Directory.systemTemp.createTemp('lesson-material-cache-test');
    cache = LessonMaterialCacheService(
      supportedOverride: true,
      userIdOverride: 'teacher-1',
      rootDirectoryOverride: root,
      downloader: (storagePath, destination) async {
        downloaded.add(storagePath);
        await destination.writeAsBytes(storagePath.codeUnits, flush: true);
      },
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('putFiles keeps older files when a new file is added', () async {
    const firstPath = 'courseMedia/c/lessons/l/materials/a/shared/image.png';
    const secondPath = 'courseMedia/c/lessons/l/materials/b/shared/image.png';
    await cache.putFiles(
      courseId: 'c',
      lessonId: 'l',
      files: {
        firstPath: [1, 2, 3],
      },
    );
    await cache.putFiles(
      courseId: 'c',
      lessonId: 'l',
      files: {
        secondPath: [4, 5],
      },
    );

    expect(
      await cache.localPath(
        courseId: 'c',
        lessonId: 'l',
        storagePath: firstPath,
      ),
      isNotNull,
    );
    expect(
      await cache.localPath(
        courseId: 'c',
        lessonId: 'l',
        storagePath: secondPath,
      ),
      isNotNull,
    );
    final status = await cache.status(
      courseId: 'c',
      lessonId: 'l',
      boardSet: boardSetWith([firstPath, secondPath]),
    );
    expect(status.hasCurrentCache, isTrue);
    expect(status.hasStaleCache, isFalse);
  });

  test('status stays current for a subset when extra files remain', () async {
    const published = 'courseMedia/c/lessons/l/materials/a/shared/image.png';
    const unpublished = 'courseMedia/c/lessons/l/materials/b/shared/image.png';
    await cache.putFiles(
      courseId: 'c',
      lessonId: 'l',
      files: {
        published: [1],
        unpublished: [2],
      },
    );

    final status = await cache.status(
      courseId: 'c',
      lessonId: 'l',
      boardSet: boardSetWith([published]),
    );
    expect(status.hasCurrentCache, isTrue);
    expect(
      await cache.localPath(
        courseId: 'c',
        lessonId: 'l',
        storagePath: unpublished,
      ),
      isNotNull,
    );
  });

  test('download skips when requested files are already present', () async {
    const path = 'courseMedia/c/lessons/l/materials/a/shared/image.png';
    await cache.putFiles(
      courseId: 'c',
      lessonId: 'l',
      files: {
        path: [9],
      },
    );

    final outcome = await cache.downloadLesson(
      courseId: 'c',
      lessonId: 'l',
      boardSet: boardSetWith([path]),
      onProgress: (_) {},
      isCancelled: () => false,
      overwriteExisting: false,
      deleteUnlistedFiles: false,
      skipIfCurrent: true,
    );

    expect(outcome, LessonMaterialDownloadOutcome.skippedAlreadyCurrent);
    expect(downloaded, isEmpty);
  });

  test('download fills missing files without deleting extras', () async {
    const kept = 'courseMedia/c/lessons/l/materials/a/shared/image.png';
    const extra = 'courseMedia/c/lessons/l/materials/b/shared/image.png';
    const missing = 'courseMedia/c/lessons/l/materials/c/shared/image.png';
    await cache.putFiles(
      courseId: 'c',
      lessonId: 'l',
      files: {
        kept: [1],
        extra: [2],
      },
    );

    final outcome = await cache.downloadLesson(
      courseId: 'c',
      lessonId: 'l',
      boardSet: boardSetWith([kept, missing]),
      onProgress: (_) {},
      isCancelled: () => false,
      overwriteExisting: false,
      deleteUnlistedFiles: false,
      skipIfCurrent: true,
    );

    expect(outcome, LessonMaterialDownloadOutcome.downloaded);
    expect(downloaded, [missing]);
    expect(
      await cache.localPath(courseId: 'c', lessonId: 'l', storagePath: extra),
      isNotNull,
    );
    expect(
      await cache.localPath(courseId: 'c', lessonId: 'l', storagePath: missing),
      isNotNull,
    );
  });

  test('learner download can replace and drop unlisted files', () async {
    const kept = 'courseMedia/c/lessons/l/materials/a/shared/image.png';
    const extra = 'courseMedia/c/lessons/l/materials/b/shared/image.png';
    await cache.putFiles(
      courseId: 'c',
      lessonId: 'l',
      files: {
        kept: [1],
        extra: [2],
      },
    );

    await cache.downloadLesson(
      courseId: 'c',
      lessonId: 'l',
      boardSet: boardSetWith([kept]),
      onProgress: (_) {},
      isCancelled: () => false,
    );

    expect(downloaded, [kept]);
    expect(
      await cache.localPath(courseId: 'c', lessonId: 'l', storagePath: extra),
      isNull,
    );
  });
}
