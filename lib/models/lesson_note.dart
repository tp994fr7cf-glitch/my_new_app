import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/firestore_parsing.dart';
import 'lesson_interaction_constants.dart';
export 'lesson_interaction_constants.dart'
    show
        lessonInteractionModerationHiddenByTeacher,
        lessonInteractionModerationVisible;

enum LessonNoteVisibility { private, public }

enum LessonNotePublicSort { newest, popular }

const String lessonNoteVisibilityPrivate = 'private';
const String lessonNoteVisibilityPublic = 'public';
const String lessonNoteAttachmentPdf = 'pdf';
const String lessonNoteAttachmentImage = 'image';
const String lessonNoteAttachmentAudio = 'audio';
const String lessonNoteModerationVisible = lessonInteractionModerationVisible;
const String lessonNoteModerationHiddenByTeacher =
    lessonInteractionModerationHiddenByTeacher;

class LessonNoteFolder {
  const LessonNoteFolder({
    this.id,
    required this.name,
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
  });

  final String? id;
  final String name;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final bool isDeleted;
  final Timestamp? deletedAt;

  factory LessonNoteFolder.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return LessonNoteFolder(
      id: doc.id,
      name: data['name'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
      isDeleted: data['isDeleted'] == true,
      deletedAt: data['deletedAt'] as Timestamp?,
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
    this.studentVisibility,
    required this.tags,
    required this.attachmentTypes,
    required this.hasAudioAttachment,
    this.sourceNoteId,
    this.sourceAuthorId,
    required this.isCopied,
    required this.canPublish,
    this.hasPublicMirror = false,
    this.createdAt,
    this.updatedAt,
    this.publicPublishedAt,
    this.favoriteCount = 0,
    this.ratingAverage = 0,
    this.ratingCount = 0,
    this.copyCount = 0,
    this.isDeleted = false,
    this.deletedAt,
    this.moderationStatus = lessonNoteModerationVisible,
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
  final LessonNoteVisibility? studentVisibility;
  final List<String> tags;
  final List<String> attachmentTypes;
  final bool hasAudioAttachment;
  final String? sourceNoteId;
  final String? sourceAuthorId;
  final bool isCopied;
  final bool canPublish;
  final bool hasPublicMirror;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final Timestamp? publicPublishedAt;
  final int favoriteCount;
  final double ratingAverage;
  final int ratingCount;
  final int copyCount;
  final bool isDeleted;
  final Timestamp? deletedAt;
  final String moderationStatus;

  bool get isPublic => visibility == LessonNoteVisibility.public;
  bool get isStudentPublic =>
      (studentVisibility ?? visibility) == LessonNoteVisibility.public;
  bool get isTeacherHidden =>
      moderationStatus == lessonNoteModerationHiddenByTeacher;
  bool get isPubliclyVisible =>
      isStudentPublic && !isDeleted && !isTeacherHidden;

  factory LessonNote.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return LessonNote.fromMap(doc.data() ?? {}, id: doc.id);
  }

  factory LessonNote.fromMap(Map data, {String? id}) {
    final visibilityText =
        data['visibility'] as String? ?? lessonNoteVisibilityPrivate;
    final studentVisibilityText =
        data['studentVisibility'] as String? ?? visibilityText;
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
      studentVisibility: studentVisibilityText == lessonNoteVisibilityPublic
          ? LessonNoteVisibility.public
          : LessonNoteVisibility.private,
      tags: parseStringList(data['tags']),
      attachmentTypes: parseStringList(attachmentData),
      hasAudioAttachment:
          data['hasAudioAttachment'] == true ||
          parseStringList(attachmentData).contains(lessonNoteAttachmentAudio),
      sourceNoteId: data['sourceNoteId'] as String?,
      sourceAuthorId: data['sourceAuthorId'] as String?,
      isCopied: data['isCopied'] == true,
      canPublish: data['canPublish'] != false,
      hasPublicMirror:
          data['hasPublicMirror'] == true ||
          visibilityText == lessonNoteVisibilityPublic,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
      publicPublishedAt: data['publicPublishedAt'] as Timestamp?,
      favoriteCount: (data['favoriteCount'] as num?)?.toInt() ?? 0,
      ratingAverage: (data['ratingAverage'] as num?)?.toDouble() ?? 0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      copyCount: (data['copyCount'] as num?)?.toInt() ?? 0,
      isDeleted: data['isDeleted'] == true,
      deletedAt: data['deletedAt'] as Timestamp?,
      moderationStatus:
          data['moderationStatus'] as String? ?? lessonNoteModerationVisible,
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
  return sortByUpdatedAt(notes, (note) => note.updatedAt);
}

List<LessonNote> sortPublicLessonNotes(
  List<LessonNote> notes,
  LessonNotePublicSort sort,
) {
  final visibleNotes = notes.where((note) => !note.isDeleted).toList();
  return switch (sort) {
    LessonNotePublicSort.newest => sortLessonNotesByUpdatedAt(visibleNotes),
    LessonNotePublicSort.popular =>
      visibleNotes..sort((a, b) {
        final popularityCompare = _lessonNotePopularityScore(
          b,
        ).compareTo(_lessonNotePopularityScore(a));
        if (popularityCompare != 0) {
          return popularityCompare;
        }
        return timestampOrEpoch(
          b.updatedAt,
        ).compareTo(timestampOrEpoch(a.updatedAt));
      }),
  };
}

int _lessonNotePopularityScore(LessonNote note) {
  return (note.ratingAverage * 100).round() +
      note.ratingCount * 10 +
      note.favoriteCount * 5 +
      note.copyCount * 20;
}
