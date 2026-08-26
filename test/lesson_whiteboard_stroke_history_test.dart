import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard_stroke_history.dart';

void main() {
  test('undo history keeps only the newest 30 strokes', () {
    final history = WhiteboardStrokeHistory();
    for (var index = 0; index < 31; index++) {
      history.recordDrawn(boardId: 'board', strokeId: 's$index');
    }

    bool alwaysVisible(WhiteboardStrokeHistoryEntry entry) => true;
    expect(history.takeUndoVisible(alwaysVisible)?.strokeId, 's30');

    WhiteboardStrokeHistoryEntry? oldestKept;
    while (true) {
      final entry = history.takeUndoVisible(alwaysVisible);
      if (entry == null) {
        break;
      }
      oldestKept = entry;
    }
    expect(oldestKept?.strokeId, 's1');
  });

  test('undo skips strokes that are not currently visible', () {
    final history = WhiteboardStrokeHistory();
    history.recordDrawn(boardId: 'board', strokeId: 'future');
    history.recordDrawn(boardId: 'board', strokeId: 'visible');

    expect(
      history.takeUndoVisible((entry) => entry.strokeId == 'visible')?.strokeId,
      'visible',
    );
    expect(history.takeUndoVisible((entry) => true)?.strokeId, 'future');
  });

  test('a new stroke clears redo', () {
    final history = WhiteboardStrokeHistory();
    history.recordDrawn(boardId: 'board', strokeId: 'a');
    final undone = history.takeUndoVisible((_) => true)!;
    history.pushRedo(undone);
    expect(history.canRedo, isTrue);

    history.recordDrawn(boardId: 'board', strokeId: 'b');
    expect(history.canRedo, isFalse);
    expect(history.takeUndoVisible((_) => true)?.strokeId, 'b');
  });
}
