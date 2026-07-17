import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_payload_size_validator.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';

void main() {
  test('UTF-8 estimate counts multibyte Japanese text', () {
    expect(estimateSerializedUtf8JsonBytes('あ'), 5);
  });

  test('accepts a normal board set and lessons payload', () {
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          title: '板書',
        ),
      ],
    );
    const lessons = [
      CourseLesson(title: 'レッスン', duration: '10秒', draftBoardSet: boardSet),
    ];

    expect(() => validateBoardSetForPersistence(boardSet), returnsNormally);
    expect(() => validateLessonsForPersistence(lessons), returnsNormally);
  });

  test(
    'rejects a twenty-first embedded board before serialization truncates it',
    () {
      final boardSet = BoardSet(
        boards: [
          for (var index = 0; index <= maxLessonWhiteboardBoards; index++)
            LessonWhiteboardBoard(id: 'board-$index', order: index),
        ],
      );

      expect(
        () => validateBoardSetForPersistence(boardSet),
        throwsA(
          isA<LessonPayloadValidationException>().having(
            (error) => error.message,
            'message',
            lessonBoardLimitMessage,
          ),
        ),
      );
    },
  );

  test('rejects ambiguous board IDs and orders before save', () {
    const duplicateIds = BoardSet(
      boards: [
        LessonWhiteboardBoard(id: 'same', order: 0),
        LessonWhiteboardBoard(id: 'same', order: 1),
      ],
    );
    const duplicateOrders = BoardSet(
      boards: [
        LessonWhiteboardBoard(id: 'a', order: 0),
        LessonWhiteboardBoard(id: 'b', order: 0),
      ],
    );

    for (final boardSet in [duplicateIds, duplicateOrders]) {
      expect(
        () => validateBoardSetForPersistence(boardSet),
        throwsA(
          isA<LessonPayloadValidationException>().having(
            (error) => error.message,
            'message',
            lessonBoardDataInvalidMessage,
          ),
        ),
      );
    }
  });

  test('rejects switch events that reference a missing board', () {
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: 'deleted-board',
          globalTimestampSec: 3,
          sequence: 0,
        ),
      ],
    );

    expect(
      () => validateBoardSetForPersistence(boardSet),
      throwsA(
        isA<LessonPayloadValidationException>().having(
          (error) => error.message,
          'message',
          lessonBoardSwitchDataInvalidMessage,
        ),
      ),
    );
  });

  test('rejects a board payload near the Firestore document limit', () {
    final largeJapaneseTitle = List.filled(300000, 'あ').join();
    final boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          title: largeJapaneseTitle,
        ),
      ],
    );
    final lessons = [
      CourseLesson(title: '大きな板書', duration: '10秒', draftBoardSet: boardSet),
    ];

    expect(
      () => validateLessonsForPersistence(lessons),
      throwsA(
        isA<LessonPayloadValidationException>().having(
          (error) => error.message,
          'message',
          lessonPayloadTooLargeMessage,
        ),
      ),
    );
  });
}
