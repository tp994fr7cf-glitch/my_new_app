import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/utils/firestore_parsing.dart';

void main() {
  test('parseIntField accepts numeric strings', () {
    expect(parseIntField('12'), 12);
    expect(parseIntField(3.0), 3);
    expect(parseIntField(null), 0);
  });

  test('Course.fromMap accepts string numeric fields in nested data', () {
    final course = Course.fromMap({
      'title': 'Test Course',
      'instructorName': 'Teacher',
      'category': 'Test',
      'level': 'Beginner',
      'duration': '1時間',
      'lessonCount': '2',
      'rating': '4.5',
      'priceLabel': '無料',
      'description': 'Description',
      'lessons': [
        {
          'title': 'Lesson 1',
          'duration': '10分',
          'mediaSegments': [
            {
              'id': 'seg-1',
              'order': '0',
              'mediaType': 'audio',
              'url': 'https://example.com/audio.mp3',
              'durationSec': '90',
            },
          ],
        },
      ],
    });

    expect(course.lessonCount, 2);
    expect(course.rating, 4.5);
    expect(course.lessons, hasLength(1));
    expect(course.lessons.first.mediaSegments.first.order, 0);
    expect(course.lessons.first.mediaSegments.first.durationSec, 90);
  });
}
