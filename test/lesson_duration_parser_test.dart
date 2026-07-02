import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_duration_parser.dart';

void main() {
  test('parseLessonDurationLabel parses minute and second labels', () {
    expect(parseLessonDurationLabel('1分30秒'), 90);
    expect(parseLessonDurationLabel('10分'), 600);
    expect(parseLessonDurationLabel('45秒'), 45);
    expect(parseLessonDurationLabel(''), isNull);
  });

  test('resolveLessonMediaDurationSec prefers player duration', () {
    expect(
      resolveLessonMediaDurationSec(
        playerDuration: const Duration(seconds: 95),
        mediaDurationSec: 90,
        durationLabel: '1分30秒',
      ),
      95,
    );
  });

  test('resolveLessonMediaDurationSec falls back to stored media duration', () {
    expect(
      resolveLessonMediaDurationSec(
        playerDuration: null,
        mediaDurationSec: 90,
        durationLabel: '1分30秒',
      ),
      90,
    );
  });

  test('resolveLessonMediaDurationSec falls back to duration label', () {
    expect(
      resolveLessonMediaDurationSec(
        playerDuration: null,
        mediaDurationSec: 0,
        durationLabel: '1分30秒',
      ),
      90,
    );
  });
}
