import 'dart:convert';

import 'course.dart';
import 'lesson_whiteboard_board_set.dart';

const int maxLessonPayloadUtf8Bytes = 850 * 1024;
const int lessonPayloadWarningUtf8Bytes = 700 * 1024;
const int maxLessonBoardSwitchEvents = 10000;
const String lessonPayloadTooLargeMessage =
    '書き物のデータ量が大きすぎるため保存できません。内容を減らしてください。';
const String lessonBoardLimitMessage = '書き物は20枚まで保存できます。';
const String lessonBoardSwitchEventLimitMessage = '書き物の切替履歴は10000件まで保存できます。';
const String lessonBoardDataInvalidMessage = '書き物のIDまたは順序が不正なため保存できません。';
const String lessonBoardSwitchDataInvalidMessage =
    '書き物の切替履歴に、存在しないボードが含まれているため保存できません。';

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
  if (boardSet.switchEvents.length > maxLessonBoardSwitchEvents) {
    throw const LessonPayloadValidationException(
      lessonBoardSwitchEventLimitMessage,
    );
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
  if (boardSet.switchEvents.any((event) => !ids.contains(event.boardId))) {
    throw const LessonPayloadValidationException(
      lessonBoardSwitchDataInvalidMessage,
    );
  }
  _validateEncodedPayload(boardSet.toMap());
}

void validateLessonsForPersistence(List<CourseLesson> lessons) {
  validateLessonBoardSetsForPersistence(lessons);
  _validateEncodedPayload(lessons.map((lesson) => lesson.toMap()).toList());
}

void validateLessonBoardSetsForPersistence(List<CourseLesson> lessons) {
  for (final lesson in lessons) {
    validateBoardSetForPersistence(lesson.publishedBoardSet);
    validateBoardSetForPersistence(lesson.draftBoardSet);
  }
}

void validateRawLessonsPayloadForPersistence(List<Object?> lessons) {
  _validateEncodedPayload(lessons);
}

void validateCourseDocumentForPersistence(Map<String, dynamic> courseData) {
  _validateEncodedPayload(_jsonSafeFirestoreValue(courseData));
}

Object? _jsonSafeFirestoreValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _jsonSafeFirestoreValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_jsonSafeFirestoreValue).toList();
  }
  // Firestore Timestamp, FieldValue, GeoPoint, and reference-like values are
  // small compared with user-authored lesson data and are not JSON encodable.
  return '<firestore-value>';
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
