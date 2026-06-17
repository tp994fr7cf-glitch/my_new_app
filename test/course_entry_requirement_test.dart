import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course_privacy_consent.dart';
import 'package:my_new_app/models/course_privacy_policy.dart';

void main() {
  group('CourseEntryRequirement.canEnter', () {
    const consentPolicy = CoursePrivacyPolicy(
      shareWithInstructorEnabled: true,
      shareAmongLearnersEnabled: false,
      consentPolicyVersion: 3,
    );

    const consent = CoursePrivacyConsent(
      courseId: 'course-a',
      userId: 'user-a',
      acceptedPolicyVersion: 3,
      acceptedInstructorLegalNameShare: true,
      acceptedPeerLegalNameShare: false,
    );

    test('returns false while requirement is unresolved', () {
      const requirement = CourseEntryRequirement(
        policy: consentPolicy,
        consent: consent,
        legalName: '山田 太郎',
        isResolved: false,
      );

      expect(requirement.isConsentSatisfied, isTrue);
      expect(requirement.canEnter, isFalse);
    });

    test('returns true after requirement is resolved', () {
      const requirement = CourseEntryRequirement(
        policy: consentPolicy,
        consent: consent,
        legalName: '山田 太郎',
        isResolved: true,
      );

      expect(requirement.isConsentSatisfied, isTrue);
      expect(requirement.canEnter, isTrue);
    });

    test('stays blocked while unresolved even when policy does not require consent', () {
      const requirement = CourseEntryRequirement(
        policy: CoursePrivacyPolicy.empty,
        consent: null,
        legalName: null,
        isResolved: false,
      );

      expect(requirement.requiresConsent, isFalse);
      expect(requirement.isConsentSatisfied, isTrue);
      expect(requirement.canEnter, isFalse);
    });

    test('can enter after resolved when policy does not require consent', () {
      const requirement = CourseEntryRequirement(
        policy: CoursePrivacyPolicy.empty,
        consent: null,
        legalName: null,
        isResolved: true,
      );

      expect(requirement.requiresConsent, isFalse);
      expect(requirement.isConsentSatisfied, isTrue);
      expect(requirement.canEnter, isTrue);
    });
  });
}
