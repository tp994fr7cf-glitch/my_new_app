import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

const String publicUserProfileRoleStudent = 'student';
const String publicUserProfileRoleTeacher = 'teacher';
const String defaultProfileColorName = 'blue';

const Map<String, Color> profileAvatarColors = {
  'blue': Colors.blue,
  'green': Colors.green,
  'orange': Colors.orange,
  'purple': Colors.purple,
  'pink': Colors.pink,
  'teal': Colors.teal,
  'brown': Colors.brown,
  'indigo': Colors.indigo,
};

class PublicUserProfile {
  const PublicUserProfile({
    required this.userId,
    required this.role,
    required this.displayName,
    required this.avatarColorName,
    required this.bio,
    this.updatedAt,
  });

  final String userId;
  final String role;
  final String displayName;
  final String avatarColorName;
  final String bio;
  final Timestamp? updatedAt;

  String get documentId => publicUserProfileDocumentId(userId, role);

  Color get avatarColor =>
      profileAvatarColors[avatarColorName] ??
      profileAvatarColors[defaultProfileColorName]!;

  String get initial {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      return role == publicUserProfileRoleTeacher ? '先' : '学';
    }
    return trimmed.substring(0, 1);
  }

  factory PublicUserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return PublicUserProfile.fromMap(data, fallbackId: doc.id);
  }

  factory PublicUserProfile.fromMap(Map data, {String? fallbackId}) {
    final role =
        data['role'] as String? ??
        (fallbackId?.endsWith('_teacher') == true
            ? publicUserProfileRoleTeacher
            : publicUserProfileRoleStudent);
    return PublicUserProfile(
      userId: data['userId'] as String? ?? _userIdFromProfileId(fallbackId),
      role: role,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : defaultProfileDisplayName(role),
      avatarColorName: profileAvatarColors.containsKey(data['avatarColorName'])
          ? data['avatarColorName'] as String
          : defaultProfileColorName,
      bio: data['bio'] as String? ?? '',
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }
}

String publicUserProfileDocumentId(String userId, String role) {
  return '${userId}_$role';
}

String defaultProfileDisplayName(String role) {
  return role == publicUserProfileRoleTeacher ? '先生' : '学習者';
}

PublicUserProfile fallbackPublicUserProfile({
  required String userId,
  required String role,
  String? displayName,
}) {
  return PublicUserProfile(
    userId: userId,
    role: role,
    displayName: (displayName ?? '').trim().isEmpty
        ? defaultProfileDisplayName(role)
        : displayName!.trim(),
    avatarColorName: defaultProfileColorName,
    bio: '',
  );
}

Stream<PublicUserProfile> publicUserProfileStream({
  required String userId,
  required String role,
  String? fallbackDisplayName,
}) {
  if (Firebase.apps.isEmpty || userId.isEmpty) {
    return Stream.value(
      fallbackPublicUserProfile(
        userId: userId,
        role: role,
        displayName: fallbackDisplayName,
      ),
    );
  }
  return FirebaseFirestore.instance
      .collection('publicUserProfiles')
      .doc(publicUserProfileDocumentId(userId, role))
      .snapshots()
      .map((snapshot) {
        if (!snapshot.exists) {
          return fallbackPublicUserProfile(
            userId: userId,
            role: role,
            displayName: fallbackDisplayName,
          );
        }
        return PublicUserProfile.fromFirestore(snapshot);
      });
}

String _userIdFromProfileId(String? profileId) {
  if (profileId == null || profileId.isEmpty) {
    return '';
  }
  final suffixIndex = profileId.lastIndexOf('_');
  if (suffixIndex <= 0) {
    return profileId;
  }
  return profileId.substring(0, suffixIndex);
}
