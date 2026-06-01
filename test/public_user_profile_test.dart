import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/public_user_profile.dart';

void main() {
  group('PublicUserProfile', () {
    test('uses defaults when profile fields are missing', () {
      final profile = PublicUserProfile.fromMap({
        'userId': 'user-a',
      }, fallbackId: 'user-a_student');

      expect(profile.userId, 'user-a');
      expect(profile.role, publicUserProfileRoleStudent);
      expect(profile.displayName, '学習者');
      expect(profile.avatarColorName, defaultProfileColorName);
    });

    test('keeps teacher and student profile ids separate', () {
      expect(
        publicUserProfileDocumentId('user-a', publicUserProfileRoleStudent),
        'user-a_student',
      );
      expect(
        publicUserProfileDocumentId('user-a', publicUserProfileRoleTeacher),
        'user-a_teacher',
      );
    });

    test('fallback profile uses provided display name', () {
      final profile = fallbackPublicUserProfile(
        userId: 'user-a',
        role: publicUserProfileRoleStudent,
        displayName: 'なお',
      );

      expect(profile.displayName, 'なお');
      expect(profile.initial, 'な');
    });
  });
}
