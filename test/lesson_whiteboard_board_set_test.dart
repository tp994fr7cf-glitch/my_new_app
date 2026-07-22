import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';

void main() {
  const defaultLayer = LessonWhiteboardLayer(
    id: 'default-layer',
    order: 0,
    title: 'Default layer',
  );
  const secondLayer = LessonWhiteboardLayer(
    id: 'second-layer',
    order: 0,
    title: 'Second layer',
  );
  const boardSet = BoardSet(
    boards: [
      LessonWhiteboardBoard(
        id: 'second',
        order: 1,
        layerBundle: LessonWhiteboardLayerBundle(layers: [secondLayer]),
      ),
      LessonWhiteboardBoard(
        id: LessonWhiteboardBoard.defaultBoardId,
        order: 0,
        layerBundle: LessonWhiteboardLayerBundle(layers: [defaultLayer]),
      ),
    ],
    switchEvents: [
      LessonWhiteboardBoardSwitchEvent(
        boardId: 'second',
        globalTimestampSec: 10,
        sequence: 2,
      ),
      LessonWhiteboardBoardSwitchEvent(
        boardId: LessonWhiteboardBoard.defaultBoardId,
        globalTimestampSec: 10,
        sequence: 1,
      ),
      LessonWhiteboardBoardSwitchEvent(
        boardId: 'second',
        globalTimestampSec: 5,
        sequence: 0,
      ),
    ],
    viewportEvents: [
      LessonWhiteboardViewportEvent(
        boardId: LessonWhiteboardBoard.defaultBoardId,
        globalTimestampSec: 1,
        sequence: 0,
        interactionId: 0,
        viewport: LessonWhiteboardViewport.full,
      ),
      LessonWhiteboardViewportEvent(
        boardId: LessonWhiteboardBoard.defaultBoardId,
        globalTimestampSec: 2,
        sequence: 1,
        interactionId: 0,
        viewport: LessonWhiteboardViewport(
          centerX: 0.5,
          centerY: 0.5,
          scale: 2,
        ),
      ),
      LessonWhiteboardViewportEvent(
        boardId: LessonWhiteboardBoard.defaultBoardId,
        globalTimestampSec: 4,
        sequence: 2,
        interactionId: 1,
        viewport: LessonWhiteboardViewport(
          centerX: 0.5,
          centerY: 0.5,
          scale: 2,
        ),
      ),
      LessonWhiteboardViewportEvent(
        boardId: LessonWhiteboardBoard.defaultBoardId,
        globalTimestampSec: 5,
        sequence: 3,
        interactionId: 1,
        viewport: LessonWhiteboardViewport(
          centerX: 0.5,
          centerY: 0.5,
          scale: 4,
        ),
      ),
    ],
  );

  test('orders boards and resolves switches by global time then sequence', () {
    expect(boardSet.orderedBoards.map((board) => board.id), [
      LessonWhiteboardBoard.defaultBoardId,
      'second',
    ]);
    expect(
      boardSet.resolveBoardAt(0)?.id,
      LessonWhiteboardBoard.defaultBoardId,
    );
    expect(boardSet.resolveBoardAt(5)?.id, 'second');
    expect(boardSet.resolveBoardAt(10)?.id, 'second');
    expect(boardSet.orderedSwitchEvents.map((event) => event.sequence), [
      0,
      1,
      2,
    ]);
  });

  test(
    'round-trip retains every board switch event including same-time events',
    () {
      final restored = BoardSet.fromMap(boardSet.toMap());

      expect(restored.boards, hasLength(2));
      expect(restored.switchEvents, hasLength(3));
      expect(restored.orderedSwitchEvents.map((event) => event.sequence), [
        0,
        1,
        2,
      ]);
      expect(restored.resolveBoardAt(10)?.id, 'second');
      expect(restored.viewportEvents, hasLength(4));
      expect(restored.nextViewportSequence, 4);
      expect(restored.nextViewportInteractionId, 2);
    },
  );

  test('viewport playback interpolates only within one interaction', () {
    expect(
      boardSet
          .resolveViewportAt(
            boardId: LessonWhiteboardBoard.defaultBoardId,
            globalTimestampSec: 0.5,
          )
          .scale,
      1,
    );
    expect(
      boardSet
          .resolveViewportAt(
            boardId: LessonWhiteboardBoard.defaultBoardId,
            globalTimestampSec: 1.5,
          )
          .scale,
      1.5,
    );
    expect(
      boardSet
          .resolveViewportAt(
            boardId: LessonWhiteboardBoard.defaultBoardId,
            globalTimestampSec: 3,
          )
          .scale,
      2,
    );
    expect(
      boardSet
          .resolveViewportAt(
            boardId: LessonWhiteboardBoard.defaultBoardId,
            globalTimestampSec: 4.5,
          )
          .scale,
      3,
    );
  });

  test('same-time viewport events resolve to the final sequence', () {
    const pausedEvents = BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
      ],
      viewportEvents: [
        LessonWhiteboardViewportEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 3,
          sequence: 0,
          interactionId: 0,
          viewport: LessonWhiteboardViewport.full,
        ),
        LessonWhiteboardViewportEvent(
          boardId: LessonWhiteboardBoard.defaultBoardId,
          globalTimestampSec: 3,
          sequence: 1,
          interactionId: 0,
          viewport: LessonWhiteboardViewport(
            centerX: 0.5,
            centerY: 0.5,
            scale: 8,
          ),
        ),
      ],
    );

    expect(
      pausedEvents
          .resolveViewportAt(
            boardId: LessonWhiteboardBoard.defaultBoardId,
            globalTimestampSec: 3,
          )
          .scale,
      8,
    );
  });

  test('parsing enforces the maximum of 20 boards', () {
    final parsed = BoardSet.fromMap({
      'boards': [
        for (var index = 0; index < 21; index++)
          {'id': 'board-$index', 'order': index, 'layers': <Object>[]},
      ],
      'switchEvents': <Object>[],
    });

    expect(parsed.boards, hasLength(maxLessonWhiteboardBoards));
    expect(parsed.boards.last.id, 'board-19');
  });

  test('parsing bounds switch events and skips invalid sequences', () {
    final parsed = BoardSet.fromMap({
      'boards': [
        {
          'id': LessonWhiteboardBoard.defaultBoardId,
          'order': 0,
          'layers': <Object>[],
        },
      ],
      'switchEvents': [
        {
          'boardId': LessonWhiteboardBoard.defaultBoardId,
          'globalTimestampSec': 0,
          'sequence': -1,
        },
        for (var index = 0; index <= maxLessonBoardSwitchEvents; index++)
          {
            'boardId': LessonWhiteboardBoard.defaultBoardId,
            'globalTimestampSec': index / 10,
            'sequence': index,
          },
        {
          'boardId': LessonWhiteboardBoard.defaultBoardId,
          'globalTimestampSec': 2,
          'sequence': 2,
        },
      ],
    });

    expect(parsed.switchEvents, hasLength(maxLessonBoardSwitchEvents));
    expect(parsed.switchEvents.first.sequence, 0);
    expect(parsed.switchEvents.last.sequence, maxLessonBoardSwitchEvents - 1);
  });

  test('parsing repairs blank and duplicate board IDs', () {
    final parsed = BoardSet.fromMap({
      'boards': [
        {'id': '', 'order': 8, 'layers': <Object>[]},
        {'id': 'same', 'order': 4, 'layers': <Object>[]},
        {'id': 'same', 'order': 2, 'layers': <Object>[]},
      ],
      'switchEvents': <Object>[],
    });

    expect(parsed.boards.map((board) => board.id).toSet(), hasLength(3));
    expect(parsed.boards.map((board) => board.order), [0, 1, 2]);
    expect(
      LessonWhiteboardBoard.generateId(),
      isNot(equals(LessonWhiteboardBoard.generateId())),
    );
  });

  test(
    'malformed board-set entries are skipped without losing valid boards',
    () {
      final parsed = BoardSet.fromMap({
        'boards': [
          {
            'id': 'broken',
            'order': 0,
            'layers': [
              {'id': 99, 'strokes': <Object>[]},
            ],
          },
          {
            'id': 'valid',
            'order': 'unexpected',
            'title': 12,
            'layers': <Object>[],
            'unknownFutureField': true,
          },
        ],
        'switchEvents': [
          {'boardId': 'valid', 'globalTimestampSec': double.nan, 'sequence': 0},
          {'boardId': 7, 'globalTimestampSec': 2},
        ],
        'unknownFutureField': true,
      });

      expect(parsed.boards.map((board) => board.id), ['valid']);
      expect(parsed.boards.single.order, 0);
      expect(parsed.boards.single.title, isEmpty);
      expect(parsed.switchEvents, isEmpty);
      expect(BoardSet.fromMap(parsed.toMap()).boards.single.id, 'valid');
    },
  );

  test('legacy whiteboardLayers fall back to one default board', () {
    final lesson = CourseLesson.fromMap({
      'title': 'Legacy board',
      'duration': '10秒',
      'whiteboardLayers': [defaultLayer.toMap()],
    });

    expect(lesson.publishedBoardSet.boards, hasLength(1));
    expect(
      lesson.publishedBoardSet.defaultBoard?.id,
      LessonWhiteboardBoard.defaultBoardId,
    );
    expect(lesson.whiteboardLayers.single.id, 'default-layer');
    expect(
      (lesson.toMap()['publishedBoardSet'] as Map)['boards'],
      hasLength(1),
    );
  });

  test('CourseLesson persists published boards but omits drafts', () {
    const lesson = CourseLesson(
      title: 'Boards',
      duration: '20秒',
      publishedBoardSet: boardSet,
      draftBoardSet: BoardSet(
        boards: [
          LessonWhiteboardBoard(
            id: LessonWhiteboardBoard.defaultBoardId,
            order: 0,
            title: 'Draft',
          ),
        ],
      ),
    );

    final restored = CourseLesson.fromMap(lesson.toMap());

    expect(restored.publishedBoardSet.boards, hasLength(2));
    expect(restored.publishedBoardSet.switchEvents, hasLength(3));
    expect(restored.publishedBoardSet.viewportEvents, hasLength(4));
    expect(lesson.toMap(), isNot(contains('draftBoardSet')));
    expect(lesson.toMap(), isNot(contains('whiteboardDraftLayers')));
    expect(restored.draftBoardSet, isEmpty);
    expect(restored.whiteboardLayers.single.id, 'default-layer');
    expect(restored.whiteboardDraftLayers, isEmpty);
  });

  test('legacy mirror edits update only the default board in copyWith', () {
    const editedLayer = LessonWhiteboardLayer(
      id: 'edited',
      order: 0,
      title: 'Edited',
    );
    const lesson = CourseLesson(
      title: 'Boards',
      duration: '20秒',
      publishedBoardSet: boardSet,
    );

    final changed = lesson.copyWith(whiteboardLayers: const [editedLayer]);

    expect(changed.whiteboardLayers.single.id, 'edited');
    expect(changed.publishedBoardSet.boardById('second'), isNotNull);
    expect(changed.publishedBoardSet.switchEvents, hasLength(3));
    expect(changed.publishedBoardSet.viewportEvents, hasLength(4));
  });
}
