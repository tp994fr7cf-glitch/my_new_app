import 'package:cloud_firestore/cloud_firestore.dart';

import 'course_privacy_policy.dart';

class CoursePrivacyConsent {
  const CoursePrivacyConsent({
    this.id,
    required this.courseId,
    required this.userId,
    required this.acceptedPolicyVersion,
    required this.acceptedInstructorLegalNameShare,
    required this.acceptedPeerLegalNameShare,
    this.peerShareToken,
    this.acceptedAt,
    this.updatedAt,
  });

  final String? id;
  final String courseId;
  final String userId;
  final int acceptedPolicyVersion;
  final bool acceptedInstructorLegalNameShare;
  final bool acceptedPeerLegalNameShare;
  final String? peerShareToken;
  final Timestamp? acceptedAt;
  final Timestamp? updatedAt;

  bool covers(CoursePrivacyPolicy policy) {
    if (!policy.requiresAnyConsent) {
      return true;
    }
    if (acceptedPolicyVersion != policy.consentPolicyVersion) {
      return false;
    }
    if (policy.shareWithInstructorEnabled &&
        !acceptedInstructorLegalNameShare) {
      return false;
    }
    if (policy.shareAmongLearnersEnabled && !acceptedPeerLegalNameShare) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toMap() {
    return {
      'courseId': courseId,
      'userId': userId,
      'acceptedPolicyVersion': acceptedPolicyVersion,
      'acceptedInstructorLegalNameShare': acceptedInstructorLegalNameShare,
      'acceptedPeerLegalNameShare': acceptedPeerLegalNameShare,
      if ((peerShareToken ?? '').trim().isNotEmpty)
        'peerShareToken': peerShareToken!.trim(),
      'acceptedAt': acceptedAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory CoursePrivacyConsent.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return CoursePrivacyConsent(
      id: doc.id,
      courseId: data['courseId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      acceptedPolicyVersion:
          (data['acceptedPolicyVersion'] as num?)?.toInt() ?? 0,
      acceptedInstructorLegalNameShare:
          data['acceptedInstructorLegalNameShare'] == true,
      acceptedPeerLegalNameShare: data['acceptedPeerLegalNameShare'] == true,
      peerShareToken: data['peerShareToken'] as String?,
      acceptedAt: data['acceptedAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }
}

class CourseEntryRequirement {
  const CourseEntryRequirement({
    required this.policy,
    required this.consent,
    required this.legalName,
    this.isResolved = true,
  });

  final CoursePrivacyPolicy policy;
  final CoursePrivacyConsent? consent;
  final String? legalName;
  final bool isResolved;

  bool get hasLegalName => (legalName ?? '').trim().isNotEmpty;

  bool get requiresConsent => policy.requiresAnyConsent;

  bool get isConsentSatisfied =>
      !policy.requiresAnyConsent || (consent?.covers(policy) ?? false);

  bool get canEnter =>
      isResolved &&
      (!policy.requiresLegalName || hasLegalName) &&
      isConsentSatisfied;
}
