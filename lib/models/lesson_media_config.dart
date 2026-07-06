/// Limits for lesson media segments. [maxSegmentsPerLesson] null means unlimited.
class LessonMediaConfig {
  const LessonMediaConfig({this.maxSegmentsPerLesson});

  static const LessonMediaConfig current = LessonMediaConfig();

  final int? maxSegmentsPerLesson;

  bool canAddSegment({required int currentSegmentCount}) {
    final max = maxSegmentsPerLesson;
    if (max == null) {
      return true;
    }
    return currentSegmentCount < max;
  }
}
