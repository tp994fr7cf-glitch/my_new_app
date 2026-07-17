import 'dart:convert';

import 'course.dart';
import 'lesson_whiteboard_board_set.dart';

const int maxLessonPayloadUtf8Bytes = 850 * 1024;
const String lessonPayloadTooLargeMessage =
    '書き物のデータ量が大きすぎるため保存できません。内容を減らしてください。';
const String lessonBoardLimitMessage = '書き物は20枚まで保存できます。';
const String lessonBoardDataInvalidMessage = '書き物のIDまたは順序が不正なため保存できません。';

class LessonPayloadValidationException implements Exception {
  const LessonPayloadValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

int estimateSerializedUtf8JsonBytes(Object? value) {
  return utf8.encode(jsonEncode(value)).length;
}

void validateBoardSetForPersistence(BoardSet boardSet) {
  if (boardSet.boards.length > maxLessonWhiteboardBoards) {
    throw const LessonPayloadValidationException(lessonBoardLimitMessage);
  }
  final ids = <String>{};
  final orders = <int>{};
  if (boardSet.boards.any(
    (board) =>
        board.id.trim().isEmpty ||
        !ids.add(board.id) ||
        !orders.add(board.order),
  )) {
    throw const LessonPayloadValidationException(lessonBoardDataInvalidMessage);
  }
  _validateEncodedPayload(boardSet.toMap());
}

void validateLessonsForPersistence(List<CourseLesson> lessons) {
  for (final lesson in lessons) {
    validateBoardSetForPersistence(lesson.publishedBoardSet);
    validateBoardSetForPersistence(lesson.draftBoardSet);
  }
  _validateEncodedPayload(lessons.map((lesson) => lesson.toMap()).toList());
}

void validateRawLessonsPayloadForPersistence(List<Object?> lessons) {
  _validateEncodedPayload(lessons);
}

void _validateEncodedPayload(Object? payload) {
  try {
    if (estimateSerializedUtf8JsonBytes(payload) > maxLessonPayloadUtf8Bytes) {
      throw const LessonPayloadValidationException(
        lessonPayloadTooLargeMessage,
      );
    }
  } on LessonPayloadValidationException {
    rethrow;
  } on Object {
    throw const LessonPayloadValidationException(lessonPayloadTooLargeMessage);
  }
}
