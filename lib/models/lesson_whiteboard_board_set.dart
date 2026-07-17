import 'lesson_whiteboard.dart';

const int maxLessonWhiteboardBoards = 20;

class LessonWhiteboardBoard {
  const LessonWhiteboardBoard({
    required this.id,
    required this.order,
    this.title = '',
    this.layerBundle = const LessonWhiteboardLayerBundle(),
  });

  static const String defaultBoardId = 'default';

  final String id;
  final int order;
  final String title;
  final LessonWhiteboardLayerBundle layerBundle;

  factory LessonWhiteboardBoard.fromMap(Map data) {
    return LessonWhiteboardBoard(
      id: data['id'] as String? ?? defaultBoardId,
      order: (data['order'] as num?)?.toInt() ?? 0,
      title: data['title'] as String? ?? '',
      layerBundle: LessonWhiteboardLayerBundle.fromMap(data['layers']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order': order,
      if (title.isNotEmpty) 'title': title,
      'layers': layerBundle.toMapList(),
    };
  }

  LessonWhiteboardBoard copyWith({
    String? id,
    int? order,
    String? title,
    LessonWhiteboardLayerBundle? layerBundle,
  }) {
    return LessonWhiteboardBoard(
      id: id ?? this.id,
      order: order ?? this.order,
      title: title ?? this.title,
      layerBundle: layerBundle ?? this.layerBundle,
    );
  }
}

class LessonWhiteboardBoardSwitchEvent {
  const LessonWhiteboardBoardSwitchEvent({
    required this.boardId,
    required this.globalTimestampSec,
    required this.sequence,
  });

  final String boardId;
  final double globalTimestampSec;
  final int sequence;

  factory LessonWhiteboardBoardSwitchEvent.fromMap(Map data) {
    return LessonWhiteboardBoardSwitchEvent(
      boardId: data['boardId'] as String? ?? '',
      globalTimestampSec:
          (data['globalTimestampSec'] as num?)?.toDouble() ?? 0,
      sequence: (data['sequence'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'boardId': boardId,
      'globalTimestampSec': globalTimestampSec,
      'sequence': sequence,
    };
  }
}

class BoardSet {
  const BoardSet({
    this.boards = const [],
    this.switchEvents = const [],
  }) : assert(boards.length <= maxLessonWhiteboardBoards);

  static const int maxBoards = maxLessonWhiteboardBoards;

  final List<LessonWhiteboardBoard> boards;
  final List<LessonWhiteboardBoardSwitchEvent> switchEvents;

  bool get isEmpty => boards.isEmpty;

  List<LessonWhiteboardBoard> get orderedBoards {
    final sorted = List<LessonWhiteboardBoard>.from(boards)
      ..sort((a, b) => a.order.compareTo(b.order));
    return sorted;
  }

  List<LessonWhiteboardBoardSwitchEvent> get orderedSwitchEvents {
    final sorted = List<LessonWhiteboardBoardSwitchEvent>.from(switchEvents)
      ..sort((a, b) {
        final timeComparison = a.globalTimestampSec.compareTo(
          b.globalTimestampSec,
        );
        if (timeComparison != 0) {
          return timeComparison;
        }
        return a.sequence.compareTo(b.sequence);
      });
    return sorted;
  }

  LessonWhiteboardBoard? get defaultBoard {
    final ordered = orderedBoards;
    if (ordered.isEmpty) {
      return null;
    }
    return ordered.firstWhere(
      (board) => board.id == LessonWhiteboardBoard.defaultBoardId,
      orElse: () => ordered.first,
    );
  }

  LessonWhiteboardBoard? boardById(String boardId) {
    for (final board in boards) {
      if (board.id == boardId) {
        return board;
      }
    }
    return null;
  }

  LessonWhiteboardBoard? resolveBoardAt(double globalTimestampSec) {
    var resolved = defaultBoard;
    for (final event in orderedSwitchEvents) {
      if (event.globalTimestampSec > globalTimestampSec) {
        break;
      }
      resolved = boardById(event.boardId) ?? resolved;
    }
    return resolved;
  }

  factory BoardSet.fromMap(Object? data) {
    if (data is! Map) {
      return const BoardSet();
    }
    final boardsData = data['boards'];
    final eventsData = data['switchEvents'];
    final parsedBoards = boardsData is List
        ? boardsData
              .whereType<Map>()
              .map(LessonWhiteboardBoard.fromMap)
              .take(maxLessonWhiteboardBoards)
              .toList()
        : const <LessonWhiteboardBoard>[];
    final parsedEvents = eventsData is List
        ? eventsData
              .whereType<Map>()
              .map(LessonWhiteboardBoardSwitchEvent.fromMap)
              .toList()
        : const <LessonWhiteboardBoardSwitchEvent>[];
    return BoardSet(boards: parsedBoards, switchEvents: parsedEvents);
  }

  factory BoardSet.fromLegacyLayers(List<LessonWhiteboardLayer> layers) {
    return BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
          layerBundle: LessonWhiteboardLayerBundle(layers: layers),
        ),
      ],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'boards': orderedBoards.map((board) => board.toMap()).toList(),
      'switchEvents': orderedSwitchEvents
          .map((event) => event.toMap())
          .toList(),
    };
  }

  BoardSet copyWith({
    List<LessonWhiteboardBoard>? boards,
    List<LessonWhiteboardBoardSwitchEvent>? switchEvents,
  }) {
    return BoardSet(
      boards: boards ?? this.boards,
      switchEvents: switchEvents ?? this.switchEvents,
    );
  }

  BoardSet copyWithDefaultLayerBundle(
    LessonWhiteboardLayerBundle layerBundle,
  ) {
    final currentDefault = defaultBoard;
    if (currentDefault == null) {
      return BoardSet.fromLegacyLayers(layerBundle.layers).copyWith(
        switchEvents: switchEvents,
      );
    }
    return copyWith(
      boards: [
        for (final board in boards)
          if (board.id == currentDefault.id)
            board.copyWith(layerBundle: layerBundle)
          else
            board,
      ],
    );
  }
}

typedef LessonWhiteboardBoardSet = BoardSet;
typedef WhiteboardBoard = LessonWhiteboardBoard;
typedef WhiteboardBoardSwitchEvent = LessonWhiteboardBoardSwitchEvent;
