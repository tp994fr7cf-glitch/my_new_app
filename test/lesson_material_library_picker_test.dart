import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_material_library.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/widgets/lesson_material_library_picker.dart';

void main() {
  testWidgets('shows saved materials in the given newest-first order', (
    tester,
  ) async {
    final items = [
      LessonMaterialLibraryItem(
        courseId: 'c1',
        lessonId: 'l2',
        assetId: 'new',
        courseTitle: '数学',
        lessonTitle: '復習',
        mediaType: lessonWhiteboardBackgroundImage,
        sharedStoragePath: 'shared-new',
        sourceStoragePath: 'source-new',
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
        sharedStoragePath: 'shared-old',
        sourceStoragePath: 'source-old',
        fileName: 'slides.pdf',
        uploadedAt: DateTime.utc(2026, 8, 1, 9),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showLessonMaterialLibraryPicker(context: context, items: items);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('保存済みから選ぶ'), findsOneWidget);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles, hasLength(2));
    expect((tiles.first.title as Text).data, 'latest.png');
    expect((tiles.last.title as Text).data, 'slides.pdf');
  });
}
