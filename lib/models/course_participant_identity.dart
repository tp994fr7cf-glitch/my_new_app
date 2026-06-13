import 'package:cloud_firestore/cloud_firestore.dart';

import 'public_user_profile.dart';

const String courseIdentityModeProfile = 'profile';
const String courseIdentityModeAlias = 'courseAlias';

class CourseParticipantIdentity {
  const CourseParticipantIdentity({
    this.id,
    required this.courseId,
    required this.userId,
    required this.identityMode,
    required this.aliasConfiguredAtEnrollment,
    required this.aliasRetired,
    this.aliasDisplayName,
    this.aliasAvatarColorName,
    this.createdAt,
    this.updatedAt,
    this.updatedByUserId,
    this.updatedByRole,
  });

  final String? id;
  final String courseId;
  final String userId;
  final String identityMode;
  final bool aliasConfiguredAtEnrollment;
  final bool aliasRetired;
  final String? aliasDisplayName;
  final String? aliasAvatarColorName;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final String? updatedByUserId;
  final String? updatedByRole;

  bool get isAliasMode =>
      identityMode == courseIdentityModeAlias && !aliasRetired;

  bool get isProfileMode => !isAliasMode;

  bool get canEditAlias => aliasConfiguredAtEnrollment && !aliasRetired;

  String get safeAliasDisplayName {
    final trimmed = (aliasDisplayName ?? '').trim();
    return trimmed.isEmpty ? '受講者' : trimmed;
  }

  String get safeAliasAvatarColorName {
    if (profileAvatarColors.containsKey(aliasAvatarColorName)) {
      return aliasAvatarColorName!;
    }
    return defaultProfileColorName;
  }

  Map<String, dynamic> toMap() {
    return {
      'courseId': courseId,
      'userId': userId,
      'identityMode': identityMode,
      'aliasConfiguredAtEnrollment': aliasConfiguredAtEnrollment,
      'aliasRetired': aliasRetired,
      'aliasDisplayName': (aliasDisplayName ?? '').trim(),
      'aliasAvatarColorName': safeAliasAvatarColorName,
      if ((updatedByUserId ?? '').trim().isNotEmpty)
        'updatedByUserId': updatedByUserId!.trim(),
      if ((updatedByRole ?? '').trim().isNotEmpty)
        'updatedByRole': updatedByRole!.trim(),
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory CourseParticipantIdentity.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final identityMode =
        data['identityMode'] as String? ?? courseIdentityModeProfile;
    final aliasRetired = data['aliasRetired'] == true;
    return CourseParticipantIdentity(
      id: doc.id,
      courseId: data['courseId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      identityMode: identityMode == courseIdentityModeAlias && !aliasRetired
          ? courseIdentityModeAlias
          : courseIdentityModeProfile,
      aliasConfiguredAtEnrollment: data['aliasConfiguredAtEnrollment'] == true,
      aliasRetired: aliasRetired,
      aliasDisplayName: data['aliasDisplayName'] as String?,
      aliasAvatarColorName: data['aliasAvatarColorName'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
      updatedByUserId: data['updatedByUserId'] as String?,
      updatedByRole: data['updatedByRole'] as String?,
    );
  }
}

class CourseAuthorSnapshot {
  const CourseAuthorSnapshot({
    required this.displayName,
    required this.avatarColorName,
    required this.profileVisible,
    required this.identityMode,
  });

  final String displayName;
  final String avatarColorName;
  final bool profileVisible;
  final String identityMode;
}
