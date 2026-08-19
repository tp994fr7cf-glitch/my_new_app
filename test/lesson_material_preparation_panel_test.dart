import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_material_library.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/lesson_material_library_service.dart';
import 'package:my_new_app/services/lesson_material_storage_service.dart';
import 'package:my_new_app/widgets/lesson_material_preparation_panel.dart';

void main() {
  testWidgets(
    'shows visible pre-live material actions and saves selected images',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: _MaterialPreparationHost()),
          ),
        ),
      );

      expect(find.text('配信・録音前のPDF／画像資料'), findsOneWidget);
      expect(find.text('PDFを追加'), findsOneWidget);
      expect(find.text('画像ファイルを追加'), findsOneWidget);
      expect(find.text('写真から追加'), findsOneWidget);
      expect(find.text('保存済みから選ぶ'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('prelive-add-image-file')));
      await tester.pumpAndSettle();

      expect(find.text('diagram.png'), findsOneWidget);
      expect(find.text('2/20枚'), findsOneWidget);
      expect(find.textContaining('下書き保存しました'), findsOneWidget);
    },
  );

  testWidgets('copies a saved image into the current lesson newest first', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: _MaterialPreparationHost()),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('prelive-add-saved-material')));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles.first.title as Text).data, 'latest.png');
    expect((tiles.last.title as Text).data, 'slides.pdf');

    await tester.tap(find.text('latest.png'));
    await tester.pumpAndSettle();

    expect(find.text('latest.png'), findsOneWidget);
    expect(find.text('2/20枚'), findsOneWidget);
    expect(find.textContaining('下書き保存しました'), findsOneWidget);
  });
}

class _MaterialPreparationHost extends StatefulWidget {
  const _MaterialPreparationHost();

  @override
  State<_MaterialPreparationHost> createState() =>
      _MaterialPreparationHostState();
}

class _MaterialPreparationHostState extends State<_MaterialPreparationHost> {
  BoardSet _boardSet = const BoardSet(
    boards: [
      LessonWhiteboardBoard(id: LessonWhiteboardBoard.defaultBoardId, order: 0),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return LessonMaterialPreparationPanel(
      courseId: 'course-1',
      lessonId: 'lesson-1',
      boardSet: _boardSet,
      publishedBoardSet: const BoardSet(),
      storageService: const _FakeMaterialStorageService(),
      libraryService: const _FakeMaterialLibraryService(),
      onBoardSetSaved: (boardSet) async {
        setState(() => _boardSet = boardSet);
      },
    );
  }
}

class _FakeMaterialStorageService extends LessonMaterialStorageService {
  const _FakeMaterialStorageService();

  @override
  Future<List<PickedLessonImage>> pickImageFiles({
    required int maximumCount,
  }) async {
    return [
      PickedLessonImage(
        fileName: 'diagram.png',
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/png',
        aspectRatio: 1.5,
      ),
    ];
  }

  @override
  Future<LessonMaterialUploadResult> uploadImages({
    required String courseId,
    required String lessonId,
    required List<PickedLessonImage> images,
  }) async {
    return LessonMaterialUploadResult(
      backgrounds: [
        for (final image in images)
          LessonWhiteboardBoardBackground(
            assetId: 'material-${image.fileName}',
            storagePath:
                'courseMedia/course-1/lessons/lesson-1/materials/'
                'material-${image.fileName}/shared/image.png',
            mediaType: lessonWhiteboardBackgroundImage,
            aspectRatio: image.aspectRatio,
          ),
      ],
      titles: [for (final image in images) image.fileName],
    );
  }

  @override
  Future<PickedLessonImage> openImageFromStorage({
    required String storagePath,
    required String fileName,
  }) async {
    return PickedLessonImage(
      fileName: fileName,
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'image/png',
      aspectRatio: 1.5,
    );
  }
}

class _FakeMaterialLibraryService extends LessonMaterialLibraryService {
  const _FakeMaterialLibraryService();

  @override
  Future<List<LessonMaterialLibraryItem>> listItems() async {
    return [
      LessonMaterialLibraryItem(
        courseId: 'c1',
        lessonId: 'l2',
        assetId: 'new',
        courseTitle: '数学',
        lessonTitle: '復習',
        mediaType: lessonWhiteboardBackgroundImage,
        sharedStoragePath:
            'courseMedia/c1/lessons/l2/materials/new/shared/image.png',
        sourceStoragePath:
            'courseMedia/c1/lessons/l2/materials/new/source/original.png',
        fileName: 'latest.png',
        uploadedAt: DateTime.utc(2026, 8, 20, 12),
      ),
      LessonMaterialLibraryItem(
        courseId: 'c1',
        lessonId: 'l1',
        assetId: 'old',
        courseTitle: '数学',
        lessonTitle: '導入',
        mediaType: lessonWhiteboardBackgroundPdf,
        sharedStoragePath:
            'courseMedia/c1/lessons/l1/materials/old/shared/selected.pdf',
        sourceStoragePath:
            'courseMedia/c1/lessons/l1/materials/old/source/original.pdf',
        fileName: 'slides.pdf',
        uploadedAt: DateTime.utc(2026, 8, 1, 9),
      ),
    ];
  }
}
