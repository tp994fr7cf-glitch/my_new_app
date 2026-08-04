import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
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

      await tester.tap(find.byKey(const ValueKey('prelive-add-image-file')));
      await tester.pumpAndSettle();

      expect(find.text('diagram.png'), findsOneWidget);
      expect(find.text('2/20枚'), findsOneWidget);
      expect(find.textContaining('下書き保存しました'), findsOneWidget);
    },
  );
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
    return const LessonMaterialUploadResult(
      backgrounds: [
        LessonWhiteboardBoardBackground(
          assetId: 'material-1',
          storagePath:
              'courseMedia/course-1/lessons/lesson-1/materials/'
              'material-1/shared/image.png',
          mediaType: lessonWhiteboardBackgroundImage,
          aspectRatio: 1.5,
        ),
      ],
      titles: ['diagram.png'],
    );
  }
}
