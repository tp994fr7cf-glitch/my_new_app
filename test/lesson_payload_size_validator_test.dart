import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_payload_size_validator.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';

void main() {
  test('UTF-8 estimate counts multibyte Japanese text', () {
    expect(estimateSerializedUtf8JsonBytes('あ'), 5);
  });

  test('formats lesson payload usage as kilobytes over 850', () {
    expect(formatLessonPayloadUsageFraction(0), '0/850');
    expect(formatLessonPayloadUsageFraction(1023), '0/850');
    expect(formatLessonPayloadUsageFraction(1024), '1/850');
    expect(formatLessonPayloadUsageFraction(850 * 1024), '850/850');
    expect(formatLessonPayloadUsageFraction(851 * 1024), '851/850');
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

  test('validates material board background metadata', () {
    const valid = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: 'page-1',
          order: 0,
          background: LessonWhiteboardBoardBackground(
            assetId: 'material-1',
            storagePath:
                'courseMedia/course/lessons/lesson/materials/shared.pdf',
            mediaType: lessonWhiteboardBackgroundPdf,
            pageNumber: 1,
            aspectRatio: 0.707,
          ),
        ),
      ],
    );
    const invalid = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: 'page-1',
          order: 0,
          background: LessonWhiteboardBoardBackground(
            assetId: 'material-1',
            storagePath: '',
            mediaType: lessonWhiteboardBackgroundPdf,
            pageNumber: 1,
            aspectRatio: 0.707,
          ),
        ),
      ],
    );

    expect(() => validateBoardSetForPersistence(valid), returnsNormally);
    expect(
      () => validateBoardSetForPersistence(invalid),
      throwsA(
        isA<LessonPayloadValidationException>().having(
          (error) => error.message,
          'message',
          lessonBoardBackgroundInvalidMessage,
        ),
      ),
    );
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

  test('rejects duplicate switch sequences', () {
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
      ],
      switchEvents: [
        LessonWhiteboardBoardSwitchEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 1,
          sequence: 0,
        ),
        LessonWhiteboardBoardSwitchEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 2,
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

  test('rejects more than 10000 board switch events before Firestore', () {
    final boardSet = BoardSet(
      boards: const [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
      ],
      switchEvents: [
        for (var index = 0; index <= maxLessonBoardSwitchEvents; index++)
          LessonWhiteboardBoardSwitchEvent(
            boardId: LessonWhiteboardBoard.defaultBoardId,
            globalTimestampSec: index.toDouble(),
            sequence: index,
          ),
      ],
    );

    expect(
      () => validateBoardSetForPersistence(boardSet),
      throwsA(
        isA<LessonPayloadValidationException>().having(
          (error) => error.message,
          'message',
          lessonBoardSwitchEventLimitMessage,
        ),
      ),
    );
  });

  test('rejects invalid viewport events before save', () {
    const boardSet = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
      ],
      viewportEvents: [
        LessonWhiteboardViewportEvent(
          boardId: 'deleted-board',
          globalTimestampSec: 3,
          sequence: 0,
          interactionId: 0,
          viewport: LessonWhiteboardViewport.full,
        ),
      ],
    );

    expect(
      () => validateBoardSetForPersistence(boardSet),
      throwsA(
        isA<LessonPayloadValidationException>().having(
          (error) => error.message,
          'message',
          lessonViewportDataInvalidMessage,
        ),
      ),
    );
  });

  test('rejects more than 2000 viewport events before Firestore', () {
    final boardSet = BoardSet(
      boards: const [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
      ],
      viewportEvents: [
        for (var index = 0; index <= maxLessonViewportEvents; index++)
          LessonWhiteboardViewportEvent(
            boardId: LessonWhiteboardBoard.defaultBoardId,
            globalTimestampSec: index / 10,
            sequence: index,
            interactionId: index ~/ 10,
            viewport: LessonWhiteboardViewport.full,
          ),
      ],
    );

    expect(
      () => validateBoardSetForPersistence(boardSet),
      throwsA(
        isA<LessonPayloadValidationException>().having(
          (error) => error.message,
          'message',
          lessonViewportEventLimitMessage,
        ),
      ),
    );
  });

  test(
    'complete course validation includes metadata and normalizes sentinels',
    () {
      expect(
        () => validateCourseDocumentForPersistence({
          'lessons': const <Object>[],
          'updatedAt': Timestamp.now(),
          'serverUpdatedAt': FieldValue.serverTimestamp(),
        }),
        returnsNormally,
      );

      expect(
        () => validateCourseDocumentForPersistence({
          'lessons': const <Object>[],
          'description': List.filled(300000, 'あ').join(),
        }),
        throwsA(
          isA<LessonPayloadValidationException>().having(
            (error) => error.message,
            'message',
            lessonPayloadTooLargeMessage,
          ),
        ),
      );
    },
  );

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
