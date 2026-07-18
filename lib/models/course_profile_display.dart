import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'course_participant_identity.dart';
import 'public_user_profile.dart';

String? _authenticatedUserId() {
  if (Firebase.apps.isEmpty) {
    return null;
  }
  return FirebaseAuth.instance.currentUser?.uid;
}

String authorProfileRoleFor(String? authorRole) {
  return authorRole == publicUserProfileRoleTeacher || authorRole == 'teacher'
      ? publicUserProfileRoleTeacher
      : publicUserProfileRoleStudent;
}

Stream<PublicUserProfile> courseSharedPublicProfileStream({
  required String courseId,
  required String userId,
  String? fallbackDisplayName,
}) {
  if (Firebase.apps.isEmpty || courseId.isEmpty || userId.isEmpty) {
    return Stream.value(
      fallbackPublicUserProfile(
        userId: userId,
        role: publicUserProfileRoleStudent,
        displayName: fallbackDisplayName,
      ),
    );
  }
  return FirebaseFirestore.instance
      .collection('courses')
      .doc(courseId)
      .collection('participantIdentities')
      .doc(userId)
      .snapshots()
      .map((snapshot) {
        if (!snapshot.exists) {
          return fallbackPublicUserProfile(
            userId: userId,
            role: publicUserProfileRoleStudent,
            displayName: fallbackDisplayName,
          );
        }
        final identity = CourseParticipantIdentity.fromFirestore(snapshot);
        if (!identity.hasSharedProfileMirror) {
          return fallbackPublicUserProfile(
            userId: userId,
            role: publicUserProfileRoleStudent,
            displayName: fallbackDisplayName ?? identity.safeAliasDisplayName,
          );
        }
        return identity.toSharedPublicUserProfile(
          fallbackDisplayName: fallbackDisplayName,
        );
      });
}

bool shouldUseCourseSharedStudentProfile({
  required String authorId,
  required String authorRole,
  required bool authorProfileVisible,
  required String? courseId,
}) {
  if (!authorProfileVisible) {
    return false;
  }
  if (authorProfileRoleFor(authorRole) == publicUserProfileRoleTeacher) {
    return false;
  }
  if ((courseId ?? '').trim().isEmpty) {
    return false;
  }
  final currentUserId = _authenticatedUserId();
  if (currentUserId != null && currentUserId == authorId) {
    return false;
  }
  return true;
}

Stream<PublicUserProfile> authorPublicProfileStream({
  required String? courseId,
  required String authorId,
  required String authorRole,
  required bool authorProfileVisible,
  String? fallbackDisplayName,
}) {
  final profileRole = authorProfileRoleFor(authorRole);
  if (profileRole == publicUserProfileRoleTeacher) {
    return publicUserProfileStream(
      userId: authorId,
      role: profileRole,
      fallbackDisplayName: fallbackDisplayName,
    );
  }

  final currentUserId = _authenticatedUserId();
  if (currentUserId != null && currentUserId == authorId) {
    return publicUserProfileStream(
      userId: authorId,
      role: profileRole,
      fallbackDisplayName: fallbackDisplayName,
    );
  }

  if (shouldUseCourseSharedStudentProfile(
    authorId: authorId,
    authorRole: authorRole,
    authorProfileVisible: authorProfileVisible,
    courseId: courseId,
  )) {
    return courseSharedPublicProfileStream(
      courseId: courseId!.trim(),
      userId: authorId,
      fallbackDisplayName: fallbackDisplayName,
    );
  }

  return Stream.value(
    fallbackPublicUserProfile(
      userId: authorId,
      role: profileRole,
      displayName: fallbackDisplayName,
    ),
  );
}

Future<PublicUserProfile> resolveAuthorPublicProfile({
  required String? courseId,
  required String authorId,
  required String authorRole,
  required bool authorProfileVisible,
  String? fallbackDisplayName,
}) async {
  final profileRole = authorProfileRoleFor(authorRole);
  final fallback = fallbackPublicUserProfile(
    userId: authorId,
    role: profileRole,
    displayName: fallbackDisplayName,
  );
  if (profileRole == publicUserProfileRoleTeacher) {
    return await loadPublicUserProfile(userId: authorId, role: profileRole) ??
        fallback;
  }
  final currentUserId = _authenticatedUserId();
  if (currentUserId != null && currentUserId == authorId) {
    return await loadPublicUserProfile(userId: authorId, role: profileRole) ??
        fallback;
  }
  if (!shouldUseCourseSharedStudentProfile(
    authorId: authorId,
    authorRole: authorRole,
    authorProfileVisible: authorProfileVisible,
    courseId: courseId,
  )) {
    return fallback;
  }
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('courses')
        .doc(courseId!.trim())
        .collection('participantIdentities')
        .doc(authorId)
        .get();
    if (!snapshot.exists) {
      return fallback;
    }
    final identity = CourseParticipantIdentity.fromFirestore(snapshot);
    if (!identity.hasSharedProfileMirror) {
      return fallback;
    }
    return identity.toSharedPublicUserProfile(
      fallbackDisplayName: fallbackDisplayName,
    );
  } on FirebaseException {
    return fallback;
  }
}

Future<PublicUserProfile?> loadPublicUserProfile({
  required String userId,
  required String role,
}) async {
  if (Firebase.apps.isEmpty || userId.isEmpty) {
    return null;
  }
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('publicUserProfiles')
        .doc(publicUserProfileDocumentId(userId, role))
        .get();
    if (!snapshot.exists) {
      return null;
    }
    return PublicUserProfile.fromFirestore(snapshot);
  } on FirebaseException {
    return null;
  }
}

Map<String, dynamic> sharedProfileMirrorFieldsFrom(PublicUserProfile profile) {
  return {
    'sharedDisplayName': profile.displayName.trim(),
    'sharedAvatarColorName': profile.avatarColorName,
    'sharedBio': profile.bio.trim(),
  };
}

Map<String, dynamic> get clearSharedProfileMirrorFields => {
  'sharedDisplayName': FieldValue.delete(),
  'sharedAvatarColorName': FieldValue.delete(),
  'sharedBio': FieldValue.delete(),
};
