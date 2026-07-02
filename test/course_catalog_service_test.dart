import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/services/course_catalog_service.dart';

void main() {
  const service = CourseCatalogService();

  test('watchCourse returns null without Firebase initialized', () {
    final course = sampleCourses.first;
    expect(service.watchCourse(course), isNull);
  });

  test('fetchCourse returns fallback without Firebase initialized', () async {
    const fallback = Course(
      id: 'offline-course',
      title: 'Offline',
      instructorName: 'Teacher',
      category: 'Test',
      level: 'Test',
      duration: '1時間',
      lessonCount: 1,
      rating: 0,
      priceLabel: '無料',
      description: 'Test',
      lessons: [CourseLesson(title: 'Lesson 1', duration: '10分')],
    );

    final resolved = await service.fetchCourse('offline-course', fallback: fallback);
    expect(resolved, same(fallback));
  });
}
