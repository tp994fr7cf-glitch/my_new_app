import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course_participant_identity.dart';
import 'package:my_new_app/models/course_profile_display.dart';
import 'package:my_new_app/models/public_user_profile.dart';

void main() {
  test('shouldUseCourseSharedStudentProfile is false for alias authors', () {
    expect(
      shouldUseCourseSharedStudentProfile(
        authorId: 'user-a',
        authorRole: 'student',
        authorProfileVisible: false,
        courseId: 'course-1',
      ),
      isFalse,
    );
  });

  test('shouldUseCourseSharedStudentProfile is false without courseId', () {
    expect(
      shouldUseCourseSharedStudentProfile(
        authorId: 'user-a',
        authorRole: 'student',
        authorProfileVisible: true,
        courseId: null,
      ),
      isFalse,
    );
  });

  test('shouldUseCourseSharedStudentProfile is false for teachers', () {
    expect(
      shouldUseCourseSharedStudentProfile(
        authorId: 'teacher-a',
        authorRole: 'teacher',
        authorProfileVisible: true,
        courseId: 'course-1',
      ),
      isFalse,
    );
  });

  test('CourseParticipantIdentity exposes shared profile mirror', () {
    const identity = CourseParticipantIdentity(
      courseId: 'course-1',
      userId: 'user-a',
      identityMode: courseIdentityModeProfile,
      aliasConfiguredAtEnrollment: false,
      aliasRetired: true,
      sharedDisplayName: '表示名A',
      sharedAvatarColorName: 'green',
      sharedBio: '自己紹介A',
    );

    expect(identity.hasSharedProfileMirror, isTrue);
    final profile = identity.toSharedPublicUserProfile();
    expect(profile.displayName, '表示名A');
    expect(profile.avatarColorName, 'green');
    expect(profile.bio, '自己紹介A');
  });

  test('sharedProfileMirrorFieldsFrom maps PublicUserProfile fields', () {
    const profile = PublicUserProfile(
      userId: 'user-a',
      role: publicUserProfileRoleStudent,
      displayName: ' 表示名 ',
      avatarColorName: 'purple',
      bio: ' bio ',
    );

    final fields = sharedProfileMirrorFieldsFrom(profile);
    expect(fields['sharedDisplayName'], '表示名');
    expect(fields['sharedAvatarColorName'], 'purple');
    expect(fields['sharedBio'], 'bio');
  });
}
