import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_cycle_display.dart';

void main() {
  group('displayedCycleNumber', () {
    test('renumbers after a fully deleted previous cycle', () {
      final displayed = displayedCycleNumber(
        actualCycleNumber: 5,
        records: const [
          LessonCycleDisplayRecord(cycleNumber: 3, isDeleted: true),
          LessonCycleDisplayRecord(cycleNumber: 3, isDeleted: true),
          LessonCycleDisplayRecord(cycleNumber: 4, isDeleted: false),
        ],
      );

      expect(displayed, 4);
    });

    test('keeps numbering when a previous cycle is partially visible', () {
      final displayed = displayedCycleNumber(
        actualCycleNumber: 4,
        records: const [
          LessonCycleDisplayRecord(cycleNumber: 3, isDeleted: true),
          LessonCycleDisplayRecord(cycleNumber: 3, isDeleted: false),
        ],
      );

      expect(displayed, 4);
    });

    test('does not count deleted future cycles', () {
      final displayed = displayedCycleNumber(
        actualCycleNumber: 2,
        records: const [
          LessonCycleDisplayRecord(cycleNumber: 3, isDeleted: true),
        ],
      );

      expect(displayed, 2);
    });
  });
}
