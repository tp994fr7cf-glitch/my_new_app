import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/teacher_course_list_service.dart';

void main() {
  test('live session blocks course deletion before status changes', () async {
    final steps = <String>[];

    await expectLater(
      () => runTeacherCourseDeletion(
        isAlreadyDeleting: false,
        assertRawArchivesIdle: () async {
          steps.add('assertIdle');
          throw const LiveCourseDeletionBlockedException();
        },
        markDeleting: () async => steps.add('markDeleting'),
        deleteCourseMedia: () async => steps.add('deleteCourseMedia'),
        deleteRawArchives: () async => steps.add('deleteRawArchives'),
        markDeleted: () async => steps.add('markDeleted'),
      ),
      throwsA(isA<LiveCourseDeletionBlockedException>()),
    );
    expect(steps, ['assertIdle']);
  });

  test('resume still deletes media and raw archives', () async {
    final steps = <String>[];
    final rawModes = <bool>[];

    await runTeacherCourseDeletion(
      isAlreadyDeleting: true,
      assertRawArchivesIdle: () async {
        steps.add('assertIdle');
        rawModes.add(false);
      },
      markDeleting: () async => steps.add('markDeleting'),
      deleteCourseMedia: () async => steps.add('deleteCourseMedia'),
      deleteRawArchives: () async {
        steps.add('deleteRawArchives');
        rawModes.add(true);
      },
      markDeleted: () async => steps.add('markDeleted'),
    );

    expect(steps, [
      'assertIdle',
      'deleteCourseMedia',
      'deleteRawArchives',
      'markDeleted',
    ]);
    expect(rawModes, [false, true]);
  });
}
