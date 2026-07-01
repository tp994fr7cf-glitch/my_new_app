import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/course_privacy_service.dart';

void main() {
  group('resolveLegalNameForConsent', () {
    test('uses profile legal name when submission is empty', () {
      expect(
        resolveLegalNameForConsent(
          submittedLegalName: '',
          profileLegalName: '山田 太郎',
          requiresLegalName: true,
        ),
        '山田 太郎',
      );
    });

    test('uses submitted legal name when profile is empty', () {
      expect(
        resolveLegalNameForConsent(
          submittedLegalName: '山田 太郎',
          profileLegalName: '',
          requiresLegalName: true,
        ),
        '山田 太郎',
      );
    });

    test('throws when legal name is required but missing', () {
      expect(
        () => resolveLegalNameForConsent(
          submittedLegalName: '',
          profileLegalName: '',
          requiresLegalName: true,
        ),
        throwsStateError,
      );
    });

    test('throws when submitted legal name differs from profile', () {
      expect(
        () => resolveLegalNameForConsent(
          submittedLegalName: '別の名前',
          profileLegalName: '山田 太郎',
          requiresLegalName: true,
        ),
        throwsStateError,
      );
    });
  });
}
