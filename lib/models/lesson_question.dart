import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/firestore_parsing.dart';
import 'lesson_interaction_constants.dart';

enum LessonQuestionVisibility { teacherOnly, public }

enum LessonQuestionTarget { teacher, everyone }

const String lessonQuestionVisibilityTeacherOnly = 'teacherOnly';
const String lessonQuestionVisibilityPublic = 'public';
const String lessonQuestionTargetTeacher = 'teacher';
const String lessonQuestionTargetEveryone = 'everyone';
const String lessonQuestionStatusOpen = 'open';
const String lessonQuestionStatusResolved = 'resolved';

class LessonQuestion {
  const LessonQuestion({
    this.id,
    required this.authorId,
    required this.authorName,
    this.authorDisplayName,
    this.authorRole = 'student',
    required this.courseId,
    required this.courseTitle,
    required this.lessonNumber,
    required this.lessonTitle,
    required this.title,
    required this.body,
    required this.visibility,
    this.studentVisibility,
    required this.target,
    required this.attachmentTypes,
    this.quotedNoteId,
    this.quotedNoteTitle,
    this.quotedNoteBody,
    this.createdAt,
    this.updatedAt,
    this.status = lessonQuestionStatusOpen,
    this.isDeleted = false,
    this.deletedAt,
    this.moderationStatus = lessonInteractionModerationVisible,
    this.answerCount = 0,
  });

  final String? id;
  final String authorId;
  final String authorName;
  final String? authorDisplayName;
  final String authorRole;
  final String courseId;
  final String courseTitle;
  final int lessonNumber;
  final String lessonTitle;
  final String title;
  final String body;
  final LessonQuestionVisibility visibility;
  final LessonQuestionVisibility? studentVisibility;
  final LessonQuestionTarget target;
  final List<String> attachmentTypes;
  final String? quotedNoteId;
  final String? quotedNoteTitle;
  final String? quotedNoteBody;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final String status;
  final bool isDeleted;
  final Timestamp? deletedAt;
  final String moderationStatus;
  final int answerCount;

  bool get isPublic => visibility == LessonQuestionVisibility.public;
  bool get isStudentPublic =>
      (studentVisibility ?? visibility) == LessonQuestionVisibility.public;
  bool get isTeacherHidden =>
      moderationStatus == lessonInteractionModerationHiddenByTeacher;
  bool get isPubliclyVisible =>
      isStudentPublic && !isDeleted && !isTeacherHidden;

  factory LessonQuestion.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return LessonQuestion.fromMap(doc.data() ?? {}, id: doc.id);
  }

  factory LessonQuestion.fromMap(Map data, {String? id}) {
    final visibilityText =
        data['visibility'] as String? ?? lessonQuestionVisibilityTeacherOnly;
    final studentVisibilityText =
        data['studentVisibility'] as String? ?? visibilityText;
    final targetText = data['target'] as String? ?? lessonQuestionTargetTeacher;
    return LessonQuestion(
      id: id ?? data['id'] as String?,
      authorId: data['authorId'] as String? ?? data['userId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '',
      authorDisplayName: data['authorDisplayName'] as String?,
      authorRole:
          data['authorRole'] as String? ??
          (data['authorDisplayName'] == '先生' ? 'teacher' : 'student'),
      courseId: data['courseId'] as String? ?? '',
      courseTitle: data['courseTitle'] as String? ?? '',
      lessonNumber: (data['lessonNumber'] as num?)?.toInt() ?? 1,
      lessonTitle: data['lessonTitle'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      visibility: visibilityText == lessonQuestionVisibilityPublic
          ? LessonQuestionVisibility.public
          : LessonQuestionVisibility.teacherOnly,
      studentVisibility:
          studentVisibilityText == lessonQuestionVisibilityPublic
          ? LessonQuestionVisibility.public
          : LessonQuestionVisibility.teacherOnly,
      target: targetText == lessonQuestionTargetEveryone
          ? LessonQuestionTarget.everyone
          : LessonQuestionTarget.teacher,
      attachmentTypes: parseStringList(data['attachmentTypes']),
      quotedNoteId: data['quotedNoteId'] as String?,
      quotedNoteTitle: data['quotedNoteTitle'] as String?,
      quotedNoteBody: data['quotedNoteBody'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
      status: data['status'] as String? ?? lessonQuestionStatusOpen,
      isDeleted: data['isDeleted'] == true,
      deletedAt: data['deletedAt'] as Timestamp?,
      moderationStatus:
          data['moderationStatus'] as String? ??
          lessonInteractionModerationVisible,
      answerCount: (data['answerCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class LessonQuestionAnswer {
  const LessonQuestionAnswer({
    this.id,
    required this.questionId,
    required this.authorId,
    required this.authorName,
    this.authorDisplayName,
    required this.authorRole,
    this.courseId = '',
    this.courseTitle = '',
    this.lessonNumber = 1,
    this.lessonTitle = '',
    required this.body,
    required this.attachmentTypes,
    this.parentCommentId,
    this.parentCommentType,
    this.replyToAuthorId,
    this.replyToAuthorRole,
    this.replyToDisplayName,
    this.replyToBodyPreview,
    this.replyToCreatedAt,
    this.quotedNoteId,
    this.quotedNoteTitle,
    this.quotedNoteBody,
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.moderationStatus = lessonInteractionModerationVisible,
  });

  final String? id;
  final String questionId;
  final String authorId;
  final String authorName;
  final String? authorDisplayName;
  final String authorRole;
  final String courseId;
  final String courseTitle;
  final int lessonNumber;
  final String lessonTitle;
  final String body;
  final List<String> attachmentTypes;
  final String? parentCommentId;
  final String? parentCommentType;
  final String? replyToAuthorId;
  final String? replyToAuthorRole;
  final String? replyToDisplayName;
  final String? replyToBodyPreview;
  final Timestamp? replyToCreatedAt;
  final String? quotedNoteId;
  final String? quotedNoteTitle;
  final String? quotedNoteBody;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final bool isDeleted;
  final Timestamp? deletedAt;
  final String moderationStatus;

  factory LessonQuestionAnswer.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return LessonQuestionAnswer(
      id: doc.id,
      questionId: data['questionId'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '',
      authorDisplayName: data['authorDisplayName'] as String?,
      authorRole: data['authorRole'] as String? ?? 'student',
      courseId: data['courseId'] as String? ?? '',
      courseTitle: data['courseTitle'] as String? ?? '',
      lessonNumber: (data['lessonNumber'] as num?)?.toInt() ?? 1,
      lessonTitle: data['lessonTitle'] as String? ?? '',
      body: data['body'] as String? ?? '',
      attachmentTypes: parseStringList(data['attachmentTypes']),
      parentCommentId: data['parentCommentId'] as String?,
      parentCommentType: data['parentCommentType'] as String?,
      replyToAuthorId: data['replyToAuthorId'] as String?,
      replyToAuthorRole: data['replyToAuthorRole'] as String?,
      replyToDisplayName: data['replyToDisplayName'] as String?,
      replyToBodyPreview: data['replyToBodyPreview'] as String?,
      replyToCreatedAt: data['replyToCreatedAt'] as Timestamp?,
      quotedNoteId: data['quotedNoteId'] as String?,
      quotedNoteTitle: data['quotedNoteTitle'] as String?,
      quotedNoteBody: data['quotedNoteBody'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
      isDeleted: data['isDeleted'] == true,
      deletedAt: data['deletedAt'] as Timestamp?,
      moderationStatus:
          data['moderationStatus'] as String? ??
          lessonInteractionModerationVisible,
    );
  }
}

bool lessonQuestionMatchesQuery(LessonQuestion question, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }
  return [
    question.body,
    question.courseTitle,
    question.lessonTitle,
    question.quotedNoteTitle ?? '',
    question.quotedNoteBody ?? '',
  ].any((value) => value.toLowerCase().contains(normalized));
}

bool lessonQuestionAnswerMatchesQuery(
  LessonQuestionAnswer answer,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }
  return [
    answer.body,
    answer.replyToDisplayName ?? '',
    answer.replyToBodyPreview ?? '',
    answer.quotedNoteTitle ?? '',
    answer.quotedNoteBody ?? '',
  ].any((value) => value.toLowerCase().contains(normalized));
}

List<LessonQuestion> sortLessonQuestionsByUpdatedAt(
  List<LessonQuestion> questions,
) {
  return sortByUpdatedAt(questions, (question) => question.updatedAt);
}
