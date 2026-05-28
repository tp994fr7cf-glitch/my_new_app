String buildCycleQuizKey({
  required String courseId,
  required int lessonNumber,
  required int cycleNumber,
  required String eventId,
  String? sessionId,
  int? quizVersion,
}) {
  final eventKey = quizVersion == null ? eventId : '$eventId:v$quizVersion';
  if (sessionId != null) {
    return '${sessionId}_$eventKey';
  }

  return '${courseId}_${lessonNumber}_${cycleNumber}_$eventKey';
}
