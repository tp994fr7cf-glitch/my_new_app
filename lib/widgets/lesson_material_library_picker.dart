import 'package:flutter/material.dart';

import '../models/lesson_material_library.dart';

Future<LessonMaterialLibraryItem?> showLessonMaterialLibraryPicker({
  required BuildContext context,
  required List<LessonMaterialLibraryItem> items,
}) {
  return showDialog<LessonMaterialLibraryItem>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('保存済みから選ぶ'),
      content: SizedBox(
        width: 620,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('新しいアップロード順です。大きいファイルは読み込みに時間がかかることがあります。'),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Text('保存済みのPDF・画像はまだありません。')
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          key: ValueKey('saved-material-${item.id}'),
                          leading: Icon(
                            item.isPdf
                                ? Icons.picture_as_pdf_outlined
                                : Icons.image_outlined,
                          ),
                          title: Text(item.fileName),
                          subtitle: Text(
                            '${item.isPdf ? 'PDF' : '画像'} · '
                            '${item.courseTitle} / ${item.lessonTitle}\n'
                            '${formatLessonMaterialLibraryDate(item.uploadedAt)}',
                          ),
                          isThreeLine: true,
                          onTap: () => Navigator.of(dialogContext).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('キャンセル'),
        ),
      ],
    ),
  );
}
