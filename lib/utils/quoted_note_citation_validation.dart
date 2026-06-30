import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/lesson_note.dart';
import '../services/lesson_interaction_service.dart';

const Duration quotedNoteCitationCommitRetryDelay = Duration(milliseconds: 400);

class QuotedNoteCitationSnapshotFields {
  const QuotedNoteCitationSnapshotFields({
    required this.quotedNoteId,
    this.quotedNoteTitle,
    this.quotedNoteBody,
  });

  final String quotedNoteId;
  final String? quotedNoteTitle;
  final String? quotedNoteBody;
}

class QuotedNoteCitationPreflightResult {
  const QuotedNoteCitationPreflightResult._({
    this.errorMessage,
    this.snapshot,
  });

  final String? errorMessage;
  final QuotedNoteCitationSnapshotFields? snapshot;

  bool get isValid => errorMessage == null && snapshot != null;

  factory QuotedNoteCitationPreflightResult.valid(
    QuotedNoteCitationSnapshotFields snapshot,
  ) {
    return QuotedNoteCitationPreflightResult._(snapshot: snapshot);
  }

  factory QuotedNoteCitationPreflightResult.invalid(String errorMessage) {
    return QuotedNoteCitationPreflightResult._(errorMessage: errorMessage);
  }
}

bool quotedNoteSnapshotMatches({
  required LessonNote note,
  required String? selectedTitle,
  required String? selectedBody,
}) {
  final title = (selectedTitle ?? '').trim();
  final body = (selectedBody ?? '').trim();
  return title == note.title.trim() && body == note.body.trim();
}

QuotedNoteCitationSnapshotFields quotedNoteCitationSnapshotFromNote(
  LessonNote note,
) {
  final noteId = (note.id ?? '').trim();
  final title = note.title.trim();
  final body = note.body.trim();
  return QuotedNoteCitationSnapshotFields(
    quotedNoteId: noteId,
    quotedNoteTitle: title.isEmpty ? null : title,
    quotedNoteBody: body.isEmpty ? null : body,
  );
}

Future<bool> lessonNotesPublicEnabledForInteractionSetting(
  String? interactionSettingId,
) async {
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
        .get(const GetOptions(source: Source.server));
    final data = snapshot.data();
    return data == null ||
        data[LessonInteractionService.lessonNotesPublicEnabledField] != false;
  } on FirebaseException {
    return true;
  }
}

bool isCourseInstructorForQuotedNoteCitation({
  required String? currentUserId,
  required String? courseInstructorId,
  required bool isActiveTeacher,
}) {
  final safeUserId = (currentUserId ?? '').trim();
  final safeInstructorId = (courseInstructorId ?? '').trim();
  return isActiveTeacher &&
      safeUserId.isNotEmpty &&
      safeInstructorId.isNotEmpty &&
      safeUserId == safeInstructorId;
}

String quotedNotePublicAudienceErrorMessage(LessonNote note) {
  if (note.isStudentTeacherOnly) {
    return '引用しようとしているメモは先生だけに公開されているため、公開コメントには使えません。';
  }
  return '引用しようとしているメモは公開コメントに使える条件を満たしていません。';
}

String quotedNoteTeacherOnlyThirdPartyErrorMessage() {
  return '引用しようとしているメモは、コース担当の先生だけが引用できます。';
}

String quotedNotePlatformDisabledErrorMessage() {
  return 'このレッスンでは公開メモ機能がオフになっているため、引用できません。';
}

Future<QuotedNoteCitationPreflightResult> preflightQuotedNoteCitationForWrite({
  required FirebaseFirestore firestore,
  required String userId,
  required String courseId,
  required int lessonNumber,
  required String? courseInstructorId,
  required bool isCourseInstructor,
  required bool requiresPublicAudience,
  required String quotedNoteId,
  required String? selectedTitle,
  required String? selectedBody,
  GetOptions getOptions = const GetOptions(source: Source.server),
}) async {
  final safeQuotedNoteId = quotedNoteId.trim();
  if (safeQuotedNoteId.isEmpty) {
    return QuotedNoteCitationPreflightResult.invalid(
      '引用メモを確認できないため、選び直してください。',
    );
  }

  DocumentSnapshot<Map<String, dynamic>>? publicSnapshot;
  try {
    publicSnapshot = await firestore
        .collection('publicLessonNotes')
        .doc(safeQuotedNoteId)
        .get(getOptions);
  } on FirebaseException {
    return QuotedNoteCitationPreflightResult.invalid(
      '引用メモを確認できないため、選び直してください。',
    );
  }

  DocumentSnapshot<Map<String, dynamic>>? ownSnapshot;
  if (userId.isNotEmpty) {
    try {
      ownSnapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('lessonNotes')
          .doc(safeQuotedNoteId)
          .get(getOptions);
    } on FirebaseException {
      ownSnapshot = null;
    }
  }

  final publicNote = publicSnapshot.exists
      ? LessonNote.fromFirestore(publicSnapshot)
      : null;
  final ownNote = ownSnapshot?.exists == true
      ? LessonNote.fromFirestore(ownSnapshot!)
      : null;
  final publicInteractionSettingId =
      publicSnapshot.data()?['interactionSettingId'] as String?;

  if (publicNote == null && ownNote == null) {
    return QuotedNoteCitationPreflightResult.invalid(
      '引用メモを確認できないため、選び直してください。',
    );
  }

  Future<bool> publicNoteAllowsPublicCitation(LessonNote note) async {
    if (note.courseId != courseId || note.lessonNumber != lessonNumber) {
      return false;
    }
    if (note.isDeleted || note.isTeacherHidden || !note.isStudentPublic) {
      return false;
    }
    if (!note.allowsQuestionCitation) {
      return false;
    }
    return lessonNotesPublicEnabledForInteractionSetting(
      publicInteractionSettingId,
    );
  }

  bool publicNoteAllowsTeacherOnlyCitationByInstructor(LessonNote note) {
    if (!isCourseInstructor) {
      return false;
    }
    if (note.courseId != courseId || note.lessonNumber != lessonNumber) {
      return false;
    }
    if (note.isDeleted || note.isTeacherHidden || !note.isStudentTeacherOnly) {
      return false;
    }
    return note.allowsQuestionCitation;
  }

  bool ownNoteAllowsCitation(LessonNote note) {
    if (note.courseId != courseId || note.lessonNumber != lessonNumber) {
      return false;
    }
    if (note.isDeleted || !note.allowsQuestionCitation) {
      return false;
    }
    return true;
  }

  if (requiresPublicAudience) {
    if (publicNote == null || !publicNote.isStudentPublic) {
      if (publicNote != null && publicNote.isStudentTeacherOnly) {
        return QuotedNoteCitationPreflightResult.invalid(
          quotedNotePublicAudienceErrorMessage(publicNote),
        );
      }
      return QuotedNoteCitationPreflightResult.invalid(
        publicNote == null
            ? '引用メモを確認できないため、選び直してください。'
            : quotedNotePublicAudienceErrorMessage(publicNote),
      );
    }
    if (!await publicNoteAllowsPublicCitation(publicNote)) {
      if (!publicNote.allowsQuestionCitation) {
        return QuotedNoteCitationPreflightResult.invalid(
          '引用しようとしているメモは引用許可がオフになったため、使えません。',
        );
      }
      if (!await lessonNotesPublicEnabledForInteractionSetting(
        publicInteractionSettingId,
      )) {
        return QuotedNoteCitationPreflightResult.invalid(
          quotedNotePlatformDisabledErrorMessage(),
        );
      }
      return QuotedNoteCitationPreflightResult.invalid(
        '引用メモを確認できないため、選び直してください。',
      );
    }
    if (!quotedNoteSnapshotMatches(
      note: publicNote,
      selectedTitle: selectedTitle,
      selectedBody: selectedBody,
    )) {
      return QuotedNoteCitationPreflightResult.invalid(
        '引用しようとしているメモの内容が更新されたため、もう一度選び直してください。',
      );
    }
    return QuotedNoteCitationPreflightResult.valid(
      quotedNoteCitationSnapshotFromNote(publicNote),
    );
  }

  if (publicNote != null &&
      await publicNoteAllowsPublicCitation(publicNote) &&
      quotedNoteSnapshotMatches(
        note: publicNote,
        selectedTitle: selectedTitle,
        selectedBody: selectedBody,
      )) {
    return QuotedNoteCitationPreflightResult.valid(
      quotedNoteCitationSnapshotFromNote(publicNote),
    );
  }

  if (publicNote != null &&
      publicNoteAllowsTeacherOnlyCitationByInstructor(publicNote) &&
      quotedNoteSnapshotMatches(
        note: publicNote,
        selectedTitle: selectedTitle,
        selectedBody: selectedBody,
      )) {
    return QuotedNoteCitationPreflightResult.valid(
      quotedNoteCitationSnapshotFromNote(publicNote),
    );
  }

  if (ownNote != null &&
      ownNoteAllowsCitation(ownNote) &&
      quotedNoteSnapshotMatches(
        note: ownNote,
        selectedTitle: selectedTitle,
        selectedBody: selectedBody,
      )) {
    return QuotedNoteCitationPreflightResult.valid(
      quotedNoteCitationSnapshotFromNote(ownNote),
    );
  }

  if (publicNote != null &&
      publicNote.isStudentTeacherOnly &&
      !isCourseInstructorForQuotedNoteCitation(
        currentUserId: userId,
        courseInstructorId: courseInstructorId,
        isActiveTeacher: isCourseInstructor,
      )) {
    return QuotedNoteCitationPreflightResult.invalid(
      quotedNoteTeacherOnlyThirdPartyErrorMessage(),
    );
  }

  if (publicNote != null &&
      publicNote.isStudentPublic &&
      !await lessonNotesPublicEnabledForInteractionSetting(
        publicInteractionSettingId,
      )) {
    return QuotedNoteCitationPreflightResult.invalid(
      quotedNotePlatformDisabledErrorMessage(),
    );
  }

  if ((publicNote != null && !publicNote.allowsQuestionCitation) ||
      (ownNote != null && !ownNote.allowsQuestionCitation)) {
    return QuotedNoteCitationPreflightResult.invalid(
      '引用しようとしているメモは引用許可がオフになったため、使えません。',
    );
  }

  if ((publicNote != null &&
          !quotedNoteSnapshotMatches(
            note: publicNote,
            selectedTitle: selectedTitle,
            selectedBody: selectedBody,
          )) ||
      (ownNote != null &&
          !quotedNoteSnapshotMatches(
            note: ownNote,
            selectedTitle: selectedTitle,
            selectedBody: selectedBody,
          ))) {
    return QuotedNoteCitationPreflightResult.invalid(
      '引用しようとしているメモの内容が更新されたため、もう一度選び直してください。',
    );
  }

  return QuotedNoteCitationPreflightResult.invalid(
    '引用メモを確認できないため、選び直してください。',
  );
}
