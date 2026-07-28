import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/course_access_service.dart';

void main() {
  test('only published course data is learner-accessible', () {
    expect(
      isCourseLearnerAccessibleData({'status': 'published'}),
      isTrue,
    );
    expect(isCourseLearnerAccessibleData({'status': 'deleted'}), isFalse);
    expect(isCourseLearnerAccessibleData({}), isFalse);
    expect(isCourseLearnerAccessibleData(null), isFalse);
  });
}
