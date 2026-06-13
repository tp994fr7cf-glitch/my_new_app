import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/course_participant_identity.dart';
import '../models/public_user_profile.dart';

class CourseIdentityService {
  const CourseIdentityService();

  DocumentReference<Map<String, dynamic>> _identityRef({
    required String courseId,
    required String userId,
  }) {
    return FirebaseFirestore.instance
        .collection('courses')
        .doc(courseId)
        .collection('participantIdentities')
        .doc(userId);
  }

  Stream<CourseParticipantIdentity?> identityStream({
    required String courseId,
    required String userId,
  }) {
    if (Firebase.apps.isEmpty || courseId.isEmpty || userId.isEmpty) {
      return Stream.value(null);
    }
    return _identityRef(courseId: courseId, userId: userId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) {
        return null;
      }
      return CourseParticipantIdentity.fromFirestore(snapshot);
    });
  }

  Future<CourseParticipantIdentity?> loadIdentity({
    required String courseId,
    required String userId,
  }) async {
    if (Firebase.apps.isEmpty || courseId.isEmpty || userId.isEmpty) {
      return null;
    }
    try {
      final snapshot = await _identityRef(
        courseId: courseId,
        userId: userId,
      ).get();
      if (!snapshot.exists) {
        return null;
      }
      return CourseParticipantIdentity.fromFirestore(snapshot);
    } on FirebaseException {
      return null;
    }
  }

  Future<CourseParticipantIdentity> ensureIdentityAtEnrollment({
    required String courseId,
    required String userId,
    required bool useCourseAlias,
    required String? aliasDisplayName,
    required String? aliasAvatarColorName,
    required String updatedByUserId,
    required String updatedByRole,
  }) async {
    if (Firebase.apps.isEmpty) {
      return CourseParticipantIdentity(
        courseId: courseId,
        userId: userId,
        identityMode: courseIdentityModeProfile,
        aliasConfiguredAtEnrollment: false,
        aliasRetired: false,
      );
    }
    final ref = _identityRef(courseId: courseId, userId: userId);
    final result = await FirebaseFirestore.instance.runTransaction((
      transaction,
    ) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        return CourseParticipantIdentity.fromFirestore(snapshot);
      }

      final aliasName = (aliasDisplayName ?? '').trim();
      final shouldUseAlias = useCourseAlias && aliasName.isNotEmpty;
      final aliasColor = profileAvatarColors.containsKey(aliasAvatarColorName)
          ? aliasAvatarColorName
          : defaultProfileColorName;
      final created = CourseParticipantIdentity(
        courseId: courseId,
        userId: userId,
        identityMode: shouldUseAlias
            ? courseIdentityModeAlias
            : courseIdentityModeProfile,
        aliasConfiguredAtEnrollment: shouldUseAlias,
        aliasRetired: !shouldUseAlias,
        aliasDisplayName: shouldUseAlias ? aliasName : null,
        aliasAvatarColorName: shouldUseAlias
            ? aliasColor
            : defaultProfileColorName,
        updatedByUserId: updatedByUserId,
        updatedByRole: updatedByRole,
      );
      transaction.set(ref, created.toMap(), SetOptions(merge: true));
      return created;
    });
    return result;
  }

  Future<void> updateAlias({
    required String courseId,
    required String userId,
    required String aliasDisplayName,
    required String aliasAvatarColorName,
    required String updatedByUserId,
    required String updatedByRole,
    required bool force,
  }) async {
    if (Firebase.apps.isEmpty) {
      return;
    }
    final safeName = aliasDisplayName.trim();
    if (safeName.isEmpty) {
      throw ArgumentError('aliasDisplayName is empty');
    }
    final safeColor = profileAvatarColors.containsKey(aliasAvatarColorName)
        ? aliasAvatarColorName
        : defaultProfileColorName;
    final ref = _identityRef(courseId: courseId, userId: userId);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        throw StateError('講座専用の名前は受講開始時のみ設定できます。');
      }
      final identity = CourseParticipantIdentity.fromFirestore(snapshot);
      if (!identity.canEditAlias) {
        throw StateError('講座専用の名前は変更できない状態です。');
      }
      if (!force && identity.userId != updatedByUserId) {
        throw StateError('他の受講者の講座専用名は変更できません。');
      }
      transaction.set(ref, {
        'identityMode': courseIdentityModeAlias,
        'aliasDisplayName': safeName,
        'aliasAvatarColorName': safeColor,
        'aliasConfiguredAtEnrollment': true,
        'aliasRetired': false,
        'updatedByUserId': updatedByUserId,
        'updatedByRole': updatedByRole,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> revealProfileIdentity({
    required String courseId,
    required String userId,
    required String updatedByUserId,
    required String updatedByRole,
  }) async {
    if (Firebase.apps.isEmpty) {
      return;
    }
    final ref = _identityRef(courseId: courseId, userId: userId);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        throw StateError('講座専用表示の情報が見つかりません。');
      }
      final identity = CourseParticipantIdentity.fromFirestore(snapshot);
      if (!identity.aliasConfiguredAtEnrollment || identity.aliasRetired) {
        return;
      }
      transaction.set(ref, {
        'identityMode': courseIdentityModeProfile,
        'aliasRetired': true,
        'updatedByUserId': updatedByUserId,
        'updatedByRole': updatedByRole,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<CourseAuthorSnapshot> resolveAuthorSnapshot({
    required String courseId,
    required String userId,
    required String fallbackDisplayName,
    required String role,
  }) async {
    if (Firebase.apps.isEmpty) {
      return CourseAuthorSnapshot(
        displayName: fallbackDisplayName.trim().isEmpty
            ? '学習者'
            : fallbackDisplayName,
        avatarColorName: defaultProfileColorName,
        profileVisible: true,
        identityMode: courseIdentityModeProfile,
      );
    }
    final identity = await loadIdentity(courseId: courseId, userId: userId);
    if (identity != null && identity.isAliasMode) {
      return CourseAuthorSnapshot(
        displayName: identity.safeAliasDisplayName,
        avatarColorName: identity.safeAliasAvatarColorName,
        profileVisible: false,
        identityMode: courseIdentityModeAlias,
      );
    }
    final profileRole = role == publicUserProfileRoleTeacher
        ? publicUserProfileRoleTeacher
        : publicUserProfileRoleStudent;
    String profileName = fallbackDisplayName.trim();
    String profileColor = defaultProfileColorName;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('publicUserProfiles')
          .doc(publicUserProfileDocumentId(userId, profileRole))
          .get();
      if (snapshot.exists) {
        final profile = PublicUserProfile.fromFirestore(snapshot);
        profileName = profile.displayName.trim();
        profileColor = profile.avatarColorName;
      }
    } on FirebaseException {
      // keep fallback values
    }
    if (profileName.isEmpty) {
      profileName = profileRole == publicUserProfileRoleTeacher ? '先生' : '学習者';
    }
    return CourseAuthorSnapshot(
      displayName: profileName,
      avatarColorName: profileColor,
      profileVisible: true,
      identityMode: courseIdentityModeProfile,
    );
  }

  Future<void> rewriteCourseAuthorSnapshots({
    required String courseId,
    required String userId,
    required CourseAuthorSnapshot snapshot,
  }) async {
    if (Firebase.apps.isEmpty || courseId.isEmpty || userId.isEmpty) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final authUserId = Firebase.apps.isNotEmpty
        ? FirebaseAuth.instance.currentUser?.uid
        : null;
    final canWriteOwnerCollections = authUserId != null && authUserId == userId;
    final updates = {
      'authorName': snapshot.displayName,
      'authorAvatarColorName': snapshot.avatarColorName,
      'authorProfileVisible': snapshot.profileVisible,
      'authorIdentityMode': snapshot.identityMode,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    Future<void> rewriteCollection(
      Query<Map<String, dynamic>> query, {
      bool ignorePermissionDenied = false,
    }) async {
      final docs = await (() async {
        try {
          return await query.get();
        } on FirebaseException catch (error) {
          if (ignorePermissionDenied && error.code == 'permission-denied') {
            return null;
          }
          rethrow;
        }
      })();
      if (docs == null) {
        return;
      }
      for (final doc in docs.docs) {
        try {
          await doc.reference.set(updates, SetOptions(merge: true));
        } on FirebaseException catch (error) {
          if (ignorePermissionDenied && error.code == 'permission-denied') {
            continue;
          }
          rethrow;
        }
      }
    }

    await rewriteCollection(
      firestore
          .collection('publicLessonNotes')
          .where('courseId', isEqualTo: courseId)
          .where('authorId', isEqualTo: userId),
      ignorePermissionDenied: true,
    );
    await rewriteCollection(
      firestore
          .collection('publicLessonQuestions')
          .where('courseId', isEqualTo: courseId)
          .where('authorId', isEqualTo: userId)
          .where('authorRole', isEqualTo: 'student'),
      ignorePermissionDenied: true,
    );
    await rewriteCollection(
      firestore
          .collection('publicLessonQuestionAnswers')
          .where('courseId', isEqualTo: courseId)
          .where('authorId', isEqualTo: userId)
          .where('authorRole', isEqualTo: 'student'),
      ignorePermissionDenied: true,
    );
    if (canWriteOwnerCollections) {
      await rewriteCollection(
        firestore
            .collection('users')
            .doc(userId)
            .collection('lessonNotes')
            .where('courseId', isEqualTo: courseId),
        ignorePermissionDenied: true,
      );
      await rewriteCollection(
        firestore
            .collection('users')
            .doc(userId)
            .collection('lessonQuestions')
            .where('courseId', isEqualTo: courseId),
        ignorePermissionDenied: true,
      );
      await rewriteCollection(
        firestore
            .collection('users')
            .doc(userId)
            .collection('lessonQuestionAnswers')
            .where('courseId', isEqualTo: courseId),
        ignorePermissionDenied: true,
      );
    }
  }
}
