import 'lesson_whiteboard_board_set.dart';

class LessonMaterialLibrarySource {
  const LessonMaterialLibrarySource({
    required this.courseId,
    required this.courseTitle,
    required this.lessonId,
    required this.lessonTitle,
    required this.boardSets,
  });

  final String courseId;
  final String courseTitle;
  final String lessonId;
  final String lessonTitle;
  final Iterable<BoardSet> boardSets;
}

class LessonMaterialLibraryItem {
  const LessonMaterialLibraryItem({
    required this.courseId,
    required this.lessonId,
    required this.assetId,
    required this.courseTitle,
    required this.lessonTitle,
    required this.mediaType,
    required this.sharedStoragePath,
    required this.sourceStoragePath,
    required this.fileName,
    required this.uploadedAt,
  });

  final String courseId;
  final String lessonId;
  final String assetId;
  final String courseTitle;
  final String lessonTitle;
  final String mediaType;
  final String sharedStoragePath;
  final String sourceStoragePath;
  final String fileName;
  final DateTime uploadedAt;

  String get id => '$courseId/$lessonId/$assetId';

  bool get isPdf => mediaType == lessonWhiteboardBackgroundPdf;

  bool get isImage => mediaType == lessonWhiteboardBackgroundImage;

  LessonMaterialLibraryItem copyWith({String? fileName, DateTime? uploadedAt}) {
    return LessonMaterialLibraryItem(
      courseId: courseId,
      lessonId: lessonId,
      assetId: assetId,
      courseTitle: courseTitle,
      lessonTitle: lessonTitle,
      mediaType: mediaType,
      sharedStoragePath: sharedStoragePath,
      sourceStoragePath: sourceStoragePath,
      fileName: fileName ?? this.fileName,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }
}

class ParsedLessonMaterialSharedPath {
  const ParsedLessonMaterialSharedPath({
    required this.courseId,
    required this.lessonId,
    required this.assetId,
    required this.mediaType,
    required this.sharedStoragePath,
    required this.sourceStoragePath,
  });

  final String courseId;
  final String lessonId;
  final String assetId;
  final String mediaType;
  final String sharedStoragePath;
  final String sourceStoragePath;
}

final _sharedMaterialPathPattern = RegExp(
  r'^courseMedia/([^/]+)/lessons/([^/]+)/materials/([^/]+)/shared/([^/]+)$',
);

final _assetIdTimestampPattern = RegExp(r'^material-(\d+)(?:-|$)');

ParsedLessonMaterialSharedPath? parseLessonMaterialSharedPath(
  String storagePath,
) {
  final match = _sharedMaterialPathPattern.firstMatch(storagePath.trim());
  if (match == null) {
    return null;
  }
  final sharedFileName = match[4]!;
  final String mediaType;
  final String sourceRelativePath;
  if (sharedFileName == 'selected.pdf') {
    mediaType = lessonWhiteboardBackgroundPdf;
    sourceRelativePath = 'source/original.pdf';
  } else if (sharedFileName.startsWith('image.')) {
    final extension = sharedFileName.substring('image.'.length).toLowerCase();
    if (extension != 'jpg' &&
        extension != 'jpeg' &&
        extension != 'png' &&
        extension != 'webp') {
      return null;
    }
    mediaType = lessonWhiteboardBackgroundImage;
    sourceRelativePath = 'source/original.$extension';
  } else {
    return null;
  }
  return ParsedLessonMaterialSharedPath(
    courseId: match[1]!,
    lessonId: match[2]!,
    assetId: match[3]!,
    mediaType: mediaType,
    sharedStoragePath: match.input.substring(match.start, match.end),
    sourceStoragePath:
        'courseMedia/${match[1]!}/lessons/${match[2]!}/materials/'
        '${match[3]!}/$sourceRelativePath',
  );
}

DateTime? uploadedAtFromMaterialAssetId(String assetId) {
  final match = _assetIdTimestampPattern.firstMatch(assetId.trim());
  if (match == null) {
    return null;
  }
  final micros = int.tryParse(match[1]!);
  if (micros == null || micros <= 0) {
    return null;
  }
  return DateTime.fromMicrosecondsSinceEpoch(micros);
}

List<LessonMaterialLibraryItem> collectLessonMaterialLibraryItems(
  Iterable<LessonMaterialLibrarySource> sources,
) {
  final byKey = <String, LessonMaterialLibraryItem>{};
  for (final source in sources) {
    for (final boardSet in source.boardSets) {
      for (final board in boardSet.boards) {
        final background = board.background;
        if (background == null) {
          continue;
        }
        final parsed = parseLessonMaterialSharedPath(background.storagePath);
        if (parsed == null) {
          continue;
        }
        if (byKey.containsKey(
          '${parsed.courseId}/${parsed.lessonId}/${parsed.assetId}',
        )) {
          continue;
        }
        final uploadedAt =
            uploadedAtFromMaterialAssetId(parsed.assetId) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        byKey['${parsed.courseId}/${parsed.lessonId}/${parsed.assetId}'] =
            LessonMaterialLibraryItem(
              courseId: parsed.courseId,
              lessonId: parsed.lessonId,
              assetId: parsed.assetId,
              courseTitle: source.courseTitle.trim().isEmpty
                  ? '講座'
                  : source.courseTitle.trim(),
              lessonTitle: source.lessonTitle.trim().isEmpty
                  ? 'レッスン'
                  : source.lessonTitle.trim(),
              mediaType: parsed.mediaType,
              sharedStoragePath: parsed.sharedStoragePath,
              sourceStoragePath: parsed.sourceStoragePath,
              fileName: _fallbackLibraryFileName(
                parsed: parsed,
                boardTitle: board.title,
              ),
              uploadedAt: uploadedAt,
            );
      }
    }
  }
  return sortLessonMaterialLibraryItems(byKey.values);
}

List<LessonMaterialLibraryItem> sortLessonMaterialLibraryItems(
  Iterable<LessonMaterialLibraryItem> items,
) {
  final sorted = [...items]
    ..sort((a, b) {
      final timeComparison = b.uploadedAt.compareTo(a.uploadedAt);
      if (timeComparison != 0) {
        return timeComparison;
      }
      return a.id.compareTo(b.id);
    });
  return sorted;
}

String formatLessonMaterialLibraryDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}/$month/$day $hour:$minute';
}

String _fallbackLibraryFileName({
  required ParsedLessonMaterialSharedPath parsed,
  required String boardTitle,
}) {
  final trimmedTitle = boardTitle.trim();
  if (parsed.mediaType == lessonWhiteboardBackgroundImage) {
    if (trimmedTitle.isNotEmpty) {
      return trimmedTitle;
    }
    final extension = parsed.sourceStoragePath.split('.').last;
    return 'image.$extension';
  }
  return 'document.pdf';
}
