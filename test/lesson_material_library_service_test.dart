import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_material_library.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/lesson_material_library_service.dart';
import 'package:my_new_app/services/lesson_material_storage_service.dart';

void main() {
  test('listItems skips missing sources and sorts newest first', () async {
    const olderAssetId = 'material-1000-0';
    const newerAssetId = 'material-2000-0';
    const missingAssetId = 'material-3000-0';
    final service = LessonMaterialLibraryService(
      userIdProvider: () => 'teacher-1',
      loadLibrarySources: (_) async => [
        LessonMaterialLibrarySource(
          courseId: 'c1',
          courseTitle: '数学',
          lessonId: 'l1',
          lessonTitle: '導入',
          boardSets: [
            BoardSet(
              boards: [
                LessonWhiteboardBoard(
                  id: 'old-pdf',
                  order: 0,
                  title: 'PDF 1ページ',
                  background: LessonWhiteboardBoardBackground(
                    assetId: olderAssetId,
                    storagePath:
                        'courseMedia/c1/lessons/l1/materials/'
                        '$olderAssetId/shared/selected.pdf',
                    mediaType: lessonWhiteboardBackgroundPdf,
                    aspectRatio: 1.4,
                  ),
                ),
                LessonWhiteboardBoard(
                  id: 'new-image',
                  order: 1,
                  title: 'photo.png',
                  background: LessonWhiteboardBoardBackground(
                    assetId: newerAssetId,
                    storagePath:
                        'courseMedia/c1/lessons/l1/materials/'
                        '$newerAssetId/shared/image.png',
                    mediaType: lessonWhiteboardBackgroundImage,
                    aspectRatio: 1.5,
                  ),
                ),
                LessonWhiteboardBoard(
                  id: 'missing',
                  order: 2,
                  title: 'gone.pdf',
                  background: LessonWhiteboardBoardBackground(
                    assetId: missingAssetId,
                    storagePath:
                        'courseMedia/c1/lessons/l1/materials/'
                        '$missingAssetId/shared/selected.pdf',
                    mediaType: lessonWhiteboardBackgroundPdf,
                    aspectRatio: 1.4,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
      readSourceInfo: (path) async {
        if (path.contains(missingAssetId)) {
          return null;
        }
        if (path.contains(newerAssetId)) {
          return LessonMaterialSourceInfo(
            originalFileName: 'latest.png',
            timeCreated: DateTime.utc(2026, 8, 20, 12),
          );
        }
        return LessonMaterialSourceInfo(
          originalFileName: 'slides.pdf',
          timeCreated: DateTime.utc(2026, 8, 1, 9),
        );
      },
    );

    final items = await service.listItems();
    expect(items.map((item) => item.fileName), ['latest.png', 'slides.pdf']);
  });

  test('listItems requires a signed-in teacher', () async {
    final service = LessonMaterialLibraryService(userIdProvider: () => null);
    await expectLater(
      service.listItems(),
      throwsA(
        isA<LessonMaterialStorageException>().having(
          (error) => error.message,
          'message',
          'ログインが必要です。',
        ),
      ),
    );
  });
}
