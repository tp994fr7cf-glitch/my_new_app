import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/lesson_material_cache_types.dart';

void main() {
  test('material fingerprint ignores writing and deduplicates PDF pages', () {
    const background = LessonWhiteboardBoardBackground(
      assetId: 'pdf',
      storagePath: 'courseMedia/course/lessons/lesson/shared/document.pdf',
      mediaType: lessonWhiteboardBackgroundPdf,
      aspectRatio: 4 / 3,
    );
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(id: 'page-1', order: 0, background: background),
        LessonWhiteboardBoard(
          id: 'page-2',
          order: 1,
          background: LessonWhiteboardBoardBackground(
            assetId: 'pdf',
            storagePath:
                'courseMedia/course/lessons/lesson/shared/document.pdf',
            mediaType: lessonWhiteboardBackgroundPdf,
            pageNumber: 2,
            aspectRatio: 4 / 3,
          ),
        ),
      ],
    );

    expect(lessonMaterialStoragePaths(boardSet), [background.storagePath]);
    expect(
      lessonMaterialFingerprint(boardSet),
      lessonMaterialFingerprint(
        boardSet.copyWith(
          switchEvents: const [
            LessonWhiteboardBoardSwitchEvent(
              boardId: 'page-2',
              globalTimestampSec: 10,
              sequence: 0,
            ),
          ],
        ),
      ),
    );
  });

  test('material fingerprint changes when a new file is added', () {
    const first = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: 'first',
          order: 0,
          background: LessonWhiteboardBoardBackground(
            assetId: 'first',
            storagePath: 'materials/first.png',
            mediaType: lessonWhiteboardBackgroundImage,
            aspectRatio: 1,
          ),
        ),
      ],
    );
    final second = first.copyWith(
      boards: [
        ...first.boards,
        const LessonWhiteboardBoard(
          id: 'second',
          order: 1,
          background: LessonWhiteboardBoardBackground(
            assetId: 'second',
            storagePath: 'materials/second.png',
            mediaType: lessonWhiteboardBackgroundImage,
            aspectRatio: 1,
          ),
        ),
      ],
    );

    expect(
      lessonMaterialFingerprint(second),
      isNot(lessonMaterialFingerprint(first)),
    );
  });
}
