import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/lesson_interaction_constants.dart';
import '../models/lesson_question.dart';
import '../services/lesson_interaction_service.dart';
import 'quoted_note_citation_validation.dart';

export 'quoted_note_citation_validation.dart' show lessonQuestionAnswerCommitRetryDelays;

enum LessonQuestionAnswerWriteFailureKind {
  quoteCitation,
  parentQuestion,
  publicMirrorRestriction,
}

class LessonQuestionAnswerWritePreflightResult {
  const LessonQuestionAnswerWritePreflightResult._({
    this.errorMessage,
    this.quoteSnapshot,
    required this.writePublicMirror,
    this.failureKind,
  });

  final String? errorMessage;
  final QuotedNoteCitationSnapshotFields? quoteSnapshot;
  final bool writePublicMirror;
  final LessonQuestionAnswerWriteFailureKind? failureKind;

  bool get isValid => errorMessage == null;

  bool get quotePreflightPassed =>
      quoteSnapshot != null ||
      failureKind != LessonQuestionAnswerWriteFailureKind.quoteCitation;

  bool get allWriteRulesPreflightPassed => isValid;

  factory LessonQuestionAnswerWritePreflightResult.success({
    QuotedNoteCitationSnapshotFields? quoteSnapshot,
    required bool writePublicMirror,
  }) {
    return LessonQuestionAnswerWritePreflightResult._(
      quoteSnapshot: quoteSnapshot,
      writePublicMirror: writePublicMirror,
    );
  }

  factory LessonQuestionAnswerWritePreflightResult.failure({
    required String errorMessage,
    required LessonQuestionAnswerWriteFailureKind failureKind,
    QuotedNoteCitationSnapshotFields? quoteSnapshot,
    bool writePublicMirror = false,
  }) {
    return LessonQuestionAnswerWritePreflightResult._(
      errorMessage: errorMessage,
      quoteSnapshot: quoteSnapshot,
      writePublicMirror: writePublicMirror,
      failureKind: failureKind,
    );
  }
}

Future<bool> lessonQuestionsPublicEnabledForInteractionSetting(
  String? interactionSettingId, {
  GetOptions getOptions = const GetOptions(source: Source.server),
}) async {
  final settingId = (interactionSettingId ?? '').trim();
  if (settingId.isEmpty) {
    return false;
  }
  if (Firebase.apps.isEmpty) {
    return true;
  }
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('lessonInteractionSettings')
        .doc(settingId)
        .get(getOptions);
    final data = snapshot.data();
    return data == null ||
        data[LessonInteractionService.lessonQuestionsPublicEnabledField] !=
            false;
  } on FirebaseException {
    return true;
  }
}

Future<String> learnerRestrictionModeForInteractionSetting({
  required FirebaseFirestore firestore,
  required String interactionSettingId,
  required String learnerId,
  GetOptions getOptions = const GetOptions(source: Source.server),
}) async {
  final safeSettingId = interactionSettingId.trim();
  final safeLearnerId = learnerId.trim();
  if (safeSettingId.isEmpty || safeLearnerId.isEmpty || Firebase.apps.isEmpty) {
    return LessonInteractionService.learnerRestrictionModeNone;
  }
  try {
    final snapshot = await firestore
        .collection('lessonInteractionSettings')
        .doc(safeSettingId)
        .collection(LessonInteractionService.learnerRestrictionsCollectionName)
        .doc(safeLearnerId)
        .get(getOptions);
    final data = snapshot.data();
    return const LessonInteractionService().normalizeLearnerRestrictionMode(
      data?[LessonInteractionService.learnerRestrictionModeField] as String?,
    );
  } on FirebaseException {
    return LessonInteractionService.learnerRestrictionModeNone;
  }
}

bool learnerPublicPostBlocked(String restrictionMode) {
  return const LessonInteractionService().blocksPublicPost(restrictionMode);
}

bool parentPublicQuestionVisible(Map<String, dynamic> data) {
  return data['moderationStatus'] == lessonInteractionModerationVisible &&
      data['isDeleted'] != true;
}

bool parentQuestionMatchesCourseLesson({
  required Map<String, dynamic> data,
  required String courseId,
  required int lessonNumber,
}) {
  return data['courseId'] == courseId &&
      (data['lessonNumber'] as num?)?.toInt() == lessonNumber;
}

Future<bool> publicQuestionMirrorWritableFromServer({
  required FirebaseFirestore firestore,
  required String questionId,
  GetOptions getOptions = const GetOptions(source: Source.server),
}) async {
  if (Firebase.apps.isEmpty || questionId.trim().isEmpty) {
    return false;
  }
  try {
    final snapshot = await firestore
        .collection('publicLessonQuestions')
        .doc(questionId)
        .get(getOptions);
    if (!snapshot.exists) {
      return false;
    }
    final data = snapshot.data();
    if (data == null) {
      return false;
    }
    return parentPublicQuestionVisible(data);
  } on FirebaseException {
    return false;
  }
}

Future<LessonQuestionAnswerWritePreflightResult> preflightLessonQuestionAnswerWrite({
  required FirebaseFirestore firestore,
  required String userId,
  required String courseId,
  required int lessonNumber,
  required String questionId,
  required String? courseInstructorId,
  required bool isCourseInstructor,
  required bool isTeacherAnswer,
  required String? quotedNoteId,
  required String? selectedQuotedTitle,
  required String? selectedQuotedBody,
  required bool requiresPublicQuoteAudience,
  GetOptions getOptions = const GetOptions(source: Source.server),
}) async {
  final safeQuestionId = questionId.trim();
  if (safeQuestionId.isEmpty) {
    return LessonQuestionAnswerWritePreflightResult.failure(
      errorMessage: '回答先の質問を確認できないため、もう一度お試しください。',
      failureKind: LessonQuestionAnswerWriteFailureKind.parentQuestion,
    );
  }

  DocumentSnapshot<Map<String, dynamic>>? parentSnapshot;
  try {
    parentSnapshot = await firestore
        .collection('publicLessonQuestions')
        .doc(safeQuestionId)
        .get(getOptions);
  } on FirebaseException {
    return LessonQuestionAnswerWritePreflightResult.failure(
      errorMessage: '回答先の質問を確認できないため、もう一度お試しください。',
      failureKind: LessonQuestionAnswerWriteFailureKind.parentQuestion,
    );
  }

  if (parentSnapshot == null || !parentSnapshot.exists) {
    return LessonQuestionAnswerWritePreflightResult.failure(
      errorMessage: '回答先の質問を確認できないため、もう一度お試しください。',
      failureKind: LessonQuestionAnswerWriteFailureKind.parentQuestion,
    );
  }

  final parentData = parentSnapshot.data() ?? {};
  if (!parentPublicQuestionVisible(parentData)) {
    return LessonQuestionAnswerWritePreflightResult.failure(
      errorMessage: '回答先の質問が非公開になったため、投稿できません。',
      failureKind: LessonQuestionAnswerWriteFailureKind.parentQuestion,
    );
  }

  if (!parentQuestionMatchesCourseLesson(
    data: parentData,
    courseId: courseId,
    lessonNumber: lessonNumber,
  )) {
    return LessonQuestionAnswerWritePreflightResult.failure(
      errorMessage: '回答先の質問を確認できないため、もう一度お試しください。',
      failureKind: LessonQuestionAnswerWriteFailureKind.parentQuestion,
    );
  }

  final interactionSettingId = parentData['interactionSettingId'] as String?;
  final studentVisibility =
      parentData['studentVisibility'] as String? ??
      parentData['visibility'] as String? ??
      lessonQuestionVisibilityTeacherOnly;
  final target =
      parentData['target'] as String? ?? lessonQuestionTargetTeacher;
  final authorId = (parentData['authorId'] as String? ?? '').trim();
  final authorRole = parentData['authorRole'] as String? ?? 'student';
  final writePublicMirror = parentPublicQuestionVisible(parentData);

  QuotedNoteCitationSnapshotFields? quoteSnapshot;
  final safeQuotedNoteId = (quotedNoteId ?? '').trim();
  if (safeQuotedNoteId.isNotEmpty) {
    final quotePreflight = await preflightQuotedNoteCitationForWrite(
      firestore: firestore,
      userId: userId,
      courseId: courseId,
      lessonNumber: lessonNumber,
      courseInstructorId: courseInstructorId,
      isCourseInstructor: isCourseInstructor,
      requiresPublicAudience: requiresPublicQuoteAudience,
      quotedNoteId: safeQuotedNoteId,
      selectedTitle: selectedQuotedTitle,
      selectedBody: selectedQuotedBody,
      getOptions: getOptions,
    );
    if (!quotePreflight.isValid) {
      return LessonQuestionAnswerWritePreflightResult.failure(
        errorMessage: quotePreflight.errorMessage!,
        failureKind: LessonQuestionAnswerWriteFailureKind.quoteCitation,
        writePublicMirror: writePublicMirror,
      );
    }
    quoteSnapshot = quotePreflight.snapshot;
  }

  if (!isTeacherAnswer &&
      studentVisibility == lessonQuestionVisibilityPublic &&
      authorRole != 'teacher' &&
      authorId.isNotEmpty &&
      authorId != userId &&
      !isCourseInstructor) {
    final authorRestriction = await learnerRestrictionModeForInteractionSetting(
      firestore: firestore,
      interactionSettingId: (interactionSettingId ?? '').trim(),
      learnerId: authorId,
      getOptions: getOptions,
    );
    if (learnerPublicPostBlocked(authorRestriction)) {
      return LessonQuestionAnswerWritePreflightResult.failure(
        errorMessage:
            'この公開質問は、質問投稿者が先生により公開欄への投稿を制限されているため、他の受講者は回答コメントできません。',
        failureKind: LessonQuestionAnswerWriteFailureKind.parentQuestion,
        quoteSnapshot: quoteSnapshot,
        writePublicMirror: writePublicMirror,
      );
    }
  }

  final questionsPublicEnabled = await lessonQuestionsPublicEnabledForInteractionSetting(
    interactionSettingId,
    getOptions: getOptions,
  );

  final allowsPublicAnswers =
      studentVisibility == lessonQuestionVisibilityPublic &&
      target == lessonQuestionTargetEveryone &&
      questionsPublicEnabled;
  final authorCanAnswerPublic =
      studentVisibility == lessonQuestionVisibilityPublic &&
      authorId == userId &&
      authorRole != 'teacher' &&
      questionsPublicEnabled;
  final teacherOnlyAuthorCanAnswer =
      studentVisibility == lessonQuestionVisibilityTeacherOnly &&
      authorId == userId &&
      authorRole != 'teacher';
  final instructorCanAnswer = isCourseInstructor;

  final parentAllowsPrivateWrite =
      (studentVisibility == lessonQuestionVisibilityPublic &&
          (allowsPublicAnswers ||
              authorCanAnswerPublic ||
              instructorCanAnswer)) ||
      (studentVisibility == lessonQuestionVisibilityTeacherOnly &&
          (teacherOnlyAuthorCanAnswer || instructorCanAnswer));

  if (!parentAllowsPrivateWrite) {
    if (!questionsPublicEnabled &&
        studentVisibility == lessonQuestionVisibilityPublic) {
      return LessonQuestionAnswerWritePreflightResult.failure(
        errorMessage: 'このレッスンでは公開質問機能がオフになっているため、回答できません。',
        failureKind: LessonQuestionAnswerWriteFailureKind.parentQuestion,
        quoteSnapshot: quoteSnapshot,
        writePublicMirror: writePublicMirror,
      );
    }
    return LessonQuestionAnswerWritePreflightResult.failure(
      errorMessage: '回答先の質問に投稿できない状態です。公開設定を確認して、もう一度お試しください。',
      failureKind: LessonQuestionAnswerWriteFailureKind.parentQuestion,
      quoteSnapshot: quoteSnapshot,
      writePublicMirror: writePublicMirror,
    );
  }

  if (writePublicMirror && !isTeacherAnswer) {
    final posterRestriction = await learnerRestrictionModeForInteractionSetting(
      firestore: firestore,
      interactionSettingId: (interactionSettingId ?? '').trim(),
      learnerId: userId,
      getOptions: getOptions,
    );
    if (learnerPublicPostBlocked(posterRestriction)) {
      return LessonQuestionAnswerWritePreflightResult.failure(
        errorMessage: '先生により公開回答への投稿が制限されています。先生のみ公開の質問には回答できます。',
        failureKind: LessonQuestionAnswerWriteFailureKind.publicMirrorRestriction,
        quoteSnapshot: quoteSnapshot,
        writePublicMirror: false,
      );
    }

    final publicMirrorAllowsWrite =
        (studentVisibility == lessonQuestionVisibilityPublic &&
            (allowsPublicAnswers ||
                authorCanAnswerPublic ||
                instructorCanAnswer)) ||
        (studentVisibility == lessonQuestionVisibilityTeacherOnly &&
            (teacherOnlyAuthorCanAnswer || instructorCanAnswer));

    if (!publicMirrorAllowsWrite) {
      return LessonQuestionAnswerWritePreflightResult.failure(
        errorMessage: '回答先の質問に投稿できない状態です。公開設定を確認して、もう一度お試しください。',
        failureKind: LessonQuestionAnswerWriteFailureKind.parentQuestion,
        quoteSnapshot: quoteSnapshot,
        writePublicMirror: false,
      );
    }
  }

  return LessonQuestionAnswerWritePreflightResult.success(
    quoteSnapshot: quoteSnapshot,
    writePublicMirror: writePublicMirror,
  );
}

String lessonQuestionAnswerPostFailureMessage({
  required FirebaseException error,
  required String fallback,
  required LessonQuestionAnswerWritePreflightResult? lastPreflight,
  required bool hadQuotedNote,
}) {
  if (error.code != 'permission-denied') {
    return error.message ?? fallback;
  }
  if (lastPreflight?.allWriteRulesPreflightPassed == true) {
    return '投稿できませんでした。通信状態を確認して、もう一度お試しください。';
  }
  if (hadQuotedNote &&
      lastPreflight?.failureKind !=
          LessonQuestionAnswerWriteFailureKind.quoteCitation) {
    return '投稿できませんでした。少し待ってから、もう一度お試しください。';
  }
  return '投稿できませんでした。引用メモの公開設定や公開範囲を確認して、もう一度お試しください。';
}
