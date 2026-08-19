import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_material_library.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';

void main() {
  test('parses shared PDF and image storage paths', () {
    final pdf = parseLessonMaterialSharedPath(
      'courseMedia/course-1/lessons/lesson-1/materials/'
      'material-1/shared/selected.pdf',
    );
    expect(pdf?.mediaType, lessonWhiteboardBackgroundPdf);
    expect(
      pdf?.sourceStoragePath,
      'courseMedia/course-1/lessons/lesson-1/materials/'
      'material-1/source/original.pdf',
    );

    final image = parseLessonMaterialSharedPath(
      'courseMedia/course-1/lessons/lesson-1/materials/'
      'material-2/shared/image.png',
    );
    expect(image?.mediaType, lessonWhiteboardBackgroundImage);
    expect(
      image?.sourceStoragePath,
      'courseMedia/course-1/lessons/lesson-1/materials/'
      'material-2/source/original.png',
    );

    expect(parseLessonMaterialSharedPath('courseMedia/other/file.pdf'), isNull);
  });

  test('collects unique materials and sorts newest uploads first', () {
    const olderAssetId = 'material-1000-0';
    const newerAssetId = 'material-2000-0';
    final olderPdf = LessonWhiteboardBoard(
      id: 'board-old',
      order: 0,
      title: 'PDF 1ページ',
      background: LessonWhiteboardBoardBackground(
        assetId: olderAssetId,
        storagePath:
            'courseMedia/c1/lessons/l1/materials/$olderAssetId/shared/selected.pdf',
        mediaType: lessonWhiteboardBackgroundPdf,
        aspectRatio: 1.4,
      ),
    );
    final newerImage = LessonWhiteboardBoard(
      id: 'board-new',
      order: 1,
      title: 'photo.png',
      background: LessonWhiteboardBoardBackground(
        assetId: newerAssetId,
        storagePath:
            'courseMedia/c1/lessons/l2/materials/$newerAssetId/shared/image.png',
        mediaType: lessonWhiteboardBackgroundImage,
        aspectRatio: 1.5,
      ),
    );
    final duplicateOlderPdf = LessonWhiteboardBoard(
      id: 'board-old-page-2',
      order: 2,
      title: 'PDF 2ページ',
      background: LessonWhiteboardBoardBackground(
        assetId: olderAssetId,
        storagePath:
            'courseMedia/c1/lessons/l1/materials/$olderAssetId/shared/selected.pdf',
        mediaType: lessonWhiteboardBackgroundPdf,
        pageNumber: 2,
        aspectRatio: 1.4,
      ),
    );

    final items = collectLessonMaterialLibraryItems([
      LessonMaterialLibrarySource(
        courseId: 'c1',
        courseTitle: '数学',
        lessonId: 'l1',
        lessonTitle: '導入',
        boardSets: [
          BoardSet(boards: [olderPdf, duplicateOlderPdf]),
        ],
      ),
      LessonMaterialLibrarySource(
        courseId: 'c1',
        courseTitle: '数学',
        lessonId: 'l2',
        lessonTitle: '復習',
        boardSets: [
          BoardSet(boards: [newerImage]),
        ],
      ),
    ]);

    expect(items, hasLength(2));
    expect(items.first.fileName, 'photo.png');
    expect(items.first.isImage, isTrue);
    expect(items.last.fileName, 'document.pdf');
    expect(items.last.isPdf, isTrue);
    expect(items.last.courseTitle, '数学');
    expect(items.last.lessonTitle, '導入');
  });

  test('sorts library items by uploadedAt newest first', () {
    final older = LessonMaterialLibraryItem(
      courseId: 'c1',
      lessonId: 'l1',
      assetId: 'a',
      courseTitle: '講座A',
      lessonTitle: 'レッスン1',
      mediaType: lessonWhiteboardBackgroundPdf,
      sharedStoragePath: 'shared-a',
      sourceStoragePath: 'source-a',
      fileName: 'old.pdf',
      uploadedAt: DateTime.utc(2026, 8, 1, 10),
    );
    final newer = LessonMaterialLibraryItem(
      courseId: 'c1',
      lessonId: 'l1',
      assetId: 'b',
      courseTitle: '講座A',
      lessonTitle: 'レッスン1',
      mediaType: lessonWhiteboardBackgroundImage,
      sharedStoragePath: 'shared-b',
      sourceStoragePath: 'source-b',
      fileName: 'new.png',
      uploadedAt: DateTime.utc(2026, 8, 20, 9),
    );

    final sorted = sortLessonMaterialLibraryItems([older, newer]);
    expect(sorted.map((item) => item.fileName), ['new.png', 'old.pdf']);
  });
}
