const int maxWhiteboardStrokeHistory = 30;

class WhiteboardStrokeHistoryEntry {
  const WhiteboardStrokeHistoryEntry({
    required this.boardId,
    required this.strokeId,
  });

  final String boardId;
  final String strokeId;
}

/// In-memory undo/redo of unsaved strokes. Saved strokes are never recorded.
class WhiteboardStrokeHistory {
  final List<WhiteboardStrokeHistoryEntry> _undo = [];
  final List<WhiteboardStrokeHistoryEntry> _redo = [];

  bool get canRedo => _redo.isNotEmpty;

  bool canUndoVisible(
    bool Function(WhiteboardStrokeHistoryEntry entry) isVisible,
  ) {
    return peekUndoVisible(isVisible) != null;
  }

  WhiteboardStrokeHistoryEntry? peekUndoVisible(
    bool Function(WhiteboardStrokeHistoryEntry entry) isVisible,
  ) {
    for (var index = _undo.length - 1; index >= 0; index--) {
      final entry = _undo[index];
      if (isVisible(entry)) {
        return entry;
      }
    }
    return null;
  }

  void recordDrawn({required String boardId, required String strokeId}) {
    _redo.clear();
    _undo.add(
      WhiteboardStrokeHistoryEntry(boardId: boardId, strokeId: strokeId),
    );
    _trimUndo();
  }

  WhiteboardStrokeHistoryEntry? takeUndoVisible(
    bool Function(WhiteboardStrokeHistoryEntry entry) isVisible,
  ) {
    for (var index = _undo.length - 1; index >= 0; index--) {
      if (isVisible(_undo[index])) {
        return _undo.removeAt(index);
      }
    }
    return null;
  }

  void pushRedo(WhiteboardStrokeHistoryEntry entry) {
    _redo.add(entry);
  }

  WhiteboardStrokeHistoryEntry? takeRedo() {
    if (_redo.isEmpty) {
      return null;
    }
    return _redo.removeLast();
  }

  void pushUndo(WhiteboardStrokeHistoryEntry entry) {
    _undo.add(entry);
    _trimUndo();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  void _trimUndo() {
    while (_undo.length > maxWhiteboardStrokeHistory) {
      _undo.removeAt(0);
    }
  }
}
