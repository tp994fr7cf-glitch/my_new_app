import 'package:cloud_firestore/cloud_firestore.dart';

const String coursePrivacyPolicyField = 'privacyPolicy';
const String coursePrivacyShareWithInstructorField =
    'shareLegalNameWithInstructor';
const String coursePrivacyShareAmongLearnersField =
    'shareLegalNameAmongLearners';
const String coursePrivacyConsentPolicyVersionField = 'consentPolicyVersion';

class CoursePrivacyPolicy {
  const CoursePrivacyPolicy({
    required this.shareWithInstructorEnabled,
    required this.shareAmongLearnersEnabled,
    required this.consentPolicyVersion,
    this.updatedAt,
  });

  final bool shareWithInstructorEnabled;
  final bool shareAmongLearnersEnabled;
  final int consentPolicyVersion;
  final Timestamp? updatedAt;

  bool get requiresAnyConsent =>
      shareWithInstructorEnabled || shareAmongLearnersEnabled;

  bool get requiresLegalName =>
      shareWithInstructorEnabled || shareAmongLearnersEnabled;

  CoursePrivacyPolicy normalized() {
    if (shareAmongLearnersEnabled && !shareWithInstructorEnabled) {
      return CoursePrivacyPolicy(
        shareWithInstructorEnabled: true,
        shareAmongLearnersEnabled: true,
        consentPolicyVersion: consentPolicyVersion,
        updatedAt: updatedAt,
      );
    }
    return this;
  }

  CoursePrivacyPolicy copyWith({
    bool? shareWithInstructorEnabled,
    bool? shareAmongLearnersEnabled,
    int? consentPolicyVersion,
    Timestamp? updatedAt,
  }) {
    return CoursePrivacyPolicy(
      shareWithInstructorEnabled:
          shareWithInstructorEnabled ?? this.shareWithInstructorEnabled,
      shareAmongLearnersEnabled:
          shareAmongLearnersEnabled ?? this.shareAmongLearnersEnabled,
      consentPolicyVersion: consentPolicyVersion ?? this.consentPolicyVersion,
      updatedAt: updatedAt ?? this.updatedAt,
    ).normalized();
  }

  Map<String, dynamic> toMap() {
    final normalizedPolicy = normalized();
    return {
      coursePrivacyShareWithInstructorField:
          normalizedPolicy.shareWithInstructorEnabled,
      coursePrivacyShareAmongLearnersField:
          normalizedPolicy.shareAmongLearnersEnabled,
      coursePrivacyConsentPolicyVersionField:
          normalizedPolicy.consentPolicyVersion,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static const empty = CoursePrivacyPolicy(
    shareWithInstructorEnabled: false,
    shareAmongLearnersEnabled: false,
    consentPolicyVersion: 1,
  );

  factory CoursePrivacyPolicy.fromCourseMap(Map<String, dynamic> data) {
    final policyData = data[coursePrivacyPolicyField];
    if (policyData is! Map) {
      return empty;
    }
    final map = Map<String, dynamic>.from(policyData);
    final version = (map[coursePrivacyConsentPolicyVersionField] as num?)
        ?.toInt();
    return CoursePrivacyPolicy(
      shareWithInstructorEnabled:
          map[coursePrivacyShareWithInstructorField] == true,
      shareAmongLearnersEnabled:
          map[coursePrivacyShareAmongLearnersField] == true,
      consentPolicyVersion: version == null || version < 1 ? 1 : version,
      updatedAt: map['updatedAt'] as Timestamp?,
    ).normalized();
  }
}
