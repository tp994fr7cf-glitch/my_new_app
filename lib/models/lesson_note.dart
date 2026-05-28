import 'package:cloud_firestore/cloud_firestore.dart';

enum LessonNoteVisibility { private, public }

const String lessonNoteVisibilityPrivate = 'private';
const String lessonNoteVisibilityPublic = 'public';
const String lessonNoteAttachmentPdf = 'pdf';
const String lessonNoteAttachmentImage = 'image';
const String lessonNoteAttachmentAudio = 'audio';

class LessonNoteFolder {
  const LessonNoteFolder({
    this.id,
    required this.name,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String name;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  factory LessonNoteFolder.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return LessonNoteFolder(
      id: doc.id,
      name: data['name'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }
}

class LessonNote {
  const LessonNote({
    this.id,
    required this.authorId,
    required this.authorName,
    required this.courseId,
    required this.courseTitle,
    required this.lessonNumber,
    required this.lessonTitle,
    required this.title,
    required this.body,
    required this.folderId,
    required this.folderName,
    required this.visibility,
    required this.tags,
    required this.attachmentTypes,
    required this.hasAudioAttachment,
    this.sourceNoteId,
    this.sourceAuthorId,
    required this.isCopied,
    required this.canPublish,
    this.createdAt,
    this.updatedAt,
    this.favoriteCount = 0,
    this.ratingAverage = 0,
    this.ratingCount = 0,
    this.copyCount = 0,
  });

  final String? id;
  final String authorId;
  final String authorName;
  final String courseId;
  final String courseTitle;
  final int lessonNumber;
  final String lessonTitle;
  final String title;
  final String body;
  final String folderId;
  final String folderName;
  final LessonNoteVisibility visibility;
  final List<String> tags;
  final List<String> attachmentTypes;
  final bool hasAudioAttachment;
  final String? sourceNoteId;
  final String? sourceAuthorId;
  final bool isCopied;
  final bool canPublish;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final int favoriteCount;
  final double ratingAverage;
  final int ratingCount;
  final int copyCount;

  bool get isPublic => visibility == LessonNoteVisibility.public;

  factory LessonNote.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return LessonNote.fromMap(doc.data() ?? {}, id: doc.id);
  }

  factory LessonNote.fromMap(Map data, {String? id}) {
    final visibilityText =
        data['visibility'] as String? ?? lessonNoteVisibilityPrivate;
    final attachmentData = data['attachmentTypes'];
    return LessonNote(
      id: id ?? data['id'] as String?,
      authorId: data['authorId'] as String? ?? data['userId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '',
      courseId: data['courseId'] as String? ?? '',
      courseTitle: data['courseTitle'] as String? ?? '',
      lessonNumber: (data['lessonNumber'] as num?)?.toInt() ?? 1,
      lessonTitle: data['lessonTitle'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      folderId: data['folderId'] as String? ?? '',
      folderName: data['folderName'] as String? ?? '',
      visibility: visibilityText == lessonNoteVisibilityPublic
          ? LessonNoteVisibility.public
          : LessonNoteVisibility.private,
      tags: _stringList(data['tags']),
      attachmentTypes: _stringList(attachmentData),
      hasAudioAttachment:
          data['hasAudioAttachment'] == true ||
          _stringList(attachmentData).contains(lessonNoteAttachmentAudio),
      sourceNoteId: data['sourceNoteId'] as String?,
      sourceAuthorId: data['sourceAuthorId'] as String?,
      isCopied: data['isCopied'] == true,
      canPublish: data['canPublish'] != false,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
      favoriteCount: (data['favoriteCount'] as num?)?.toInt() ?? 0,
      ratingAverage: (data['ratingAverage'] as num?)?.toDouble() ?? 0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      copyCount: (data['copyCount'] as num?)?.toInt() ?? 0,
    );
  }
}

List<String> parseLessonNoteTags(String input) {
  return input
      .split(RegExp(r'[\s,、]+'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .map((tag) => tag.startsWith('#') ? tag.substring(1) : tag)
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
}

bool canPublishLessonNote({
  required bool hasAudioAttachment,
  required bool isCopied,
  required bool canPublish,
}) {
  return !hasAudioAttachment && !isCopied && canPublish;
}

bool lessonNoteMatchesQuery(LessonNote note, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }

  return [
    note.title,
    note.body,
    note.courseTitle,
    note.lessonTitle,
    note.folderName,
    ...note.tags,
  ].any((value) => value.toLowerCase().contains(normalized));
}

List<LessonNote> sortLessonNotesByUpdatedAt(List<LessonNote> notes) {
  return [...notes]..sort((a, b) {
    final aUpdatedAt =
        a.updatedAt?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bUpdatedAt =
        b.updatedAt?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bUpdatedAt.compareTo(aUpdatedAt);
  });
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<String>().toList();
}
