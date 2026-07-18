/// Limits for lesson media segments. [maxSegmentsPerLesson] null means unlimited.
const int maxLessonMediaSegments = 100;

class LessonMediaConfig {
  const LessonMediaConfig({this.maxSegmentsPerLesson});

  static const LessonMediaConfig current = LessonMediaConfig(
    maxSegmentsPerLesson: maxLessonMediaSegments,
  );

  final int? maxSegmentsPerLesson;

  bool canAddSegment({required int currentSegmentCount}) {
    final max = maxSegmentsPerLesson;
    if (max == null) {
      return true;
    }
    return currentSegmentCount < max;
  }
}
