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
    },
  );

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

  test('CourseLesson round-trips published and draft board sets', () {
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
    expect(restored.draftBoardSet.defaultBoard?.title, 'Draft');
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
  });
}
