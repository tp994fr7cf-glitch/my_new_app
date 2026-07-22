import 'lesson_whiteboard.dart';

const int maxLessonWhiteboardBoards = 20;
const int maxLessonBoardSwitchEvents = 10000;
const int maxLessonViewportEvents = 2000;
const double minLessonWhiteboardViewportScale = 1;
const double maxLessonWhiteboardViewportScale = 8;

class LessonWhiteboardBoard {
  const LessonWhiteboardBoard({
    required this.id,
    required this.order,
    this.title = '',
    this.layerBundle = const LessonWhiteboardLayerBundle(),
  });

  static const String defaultBoardId = 'default';
  static int _generatedIdSequence = 0;

  /// Generates a process-unique ID suitable for a newly-created board.
  static String generateId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    return 'board-$micros-${_generatedIdSequence++}';
  }

  final String id;
  final int order;
  final String title;
  final LessonWhiteboardLayerBundle layerBundle;

  factory LessonWhiteboardBoard.fromMap(Map data) {
    return LessonWhiteboardBoard(
      id: data['id'] is String ? data['id'] as String : defaultBoardId,
      order: data['order'] is num ? (data['order'] as num).toInt() : 0,
      title: data['title'] is String ? data['title'] as String : '',
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
      boardId: data['boardId'] is String ? data['boardId'] as String : '',
      globalTimestampSec: data['globalTimestampSec'] is num
          ? (data['globalTimestampSec'] as num).toDouble()
          : 0,
      sequence: data['sequence'] is num ? (data['sequence'] as num).toInt() : 0,
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

class LessonWhiteboardViewport {
  const LessonWhiteboardViewport({
    required this.centerX,
    required this.centerY,
    required this.scale,
  });

  static const full = LessonWhiteboardViewport(
    centerX: 0.5,
    centerY: 0.5,
    scale: minLessonWhiteboardViewportScale,
  );

  final double centerX;
  final double centerY;
  final double scale;

  factory LessonWhiteboardViewport.normalized({
    required double centerX,
    required double centerY,
    required double scale,
  }) {
    final safeScale = scale.isFinite
        ? scale
              .clamp(
                minLessonWhiteboardViewportScale,
                maxLessonWhiteboardViewportScale,
              )
              .toDouble()
        : minLessonWhiteboardViewportScale;
    final halfExtent = 0.5 / safeScale;
    return LessonWhiteboardViewport(
      centerX: (centerX.isFinite ? centerX : 0.5)
          .clamp(halfExtent, 1 - halfExtent)
          .toDouble(),
      centerY: (centerY.isFinite ? centerY : 0.5)
          .clamp(halfExtent, 1 - halfExtent)
          .toDouble(),
      scale: safeScale,
    );
  }

  double get left => centerX - (0.5 / scale);
  double get top => centerY - (0.5 / scale);
  double get width => 1 / scale;
  double get height => 1 / scale;
  bool get isFull => scale == minLessonWhiteboardViewportScale;

  static LessonWhiteboardViewport lerp(
    LessonWhiteboardViewport start,
    LessonWhiteboardViewport end,
    double t,
  ) {
    final progress = t.clamp(0.0, 1.0);
    return LessonWhiteboardViewport.normalized(
      centerX: start.centerX + ((end.centerX - start.centerX) * progress),
      centerY: start.centerY + ((end.centerY - start.centerY) * progress),
      scale: start.scale + ((end.scale - start.scale) * progress),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LessonWhiteboardViewport &&
        other.centerX == centerX &&
        other.centerY == centerY &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(centerX, centerY, scale);
}

class LessonWhiteboardViewportEvent {
  const LessonWhiteboardViewportEvent({
    required this.boardId,
    required this.globalTimestampSec,
    required this.sequence,
    required this.interactionId,
    required this.viewport,
  });

  final String boardId;
  final double globalTimestampSec;
  final int sequence;
  final int interactionId;
  final LessonWhiteboardViewport viewport;

  factory LessonWhiteboardViewportEvent.fromMap(Map data) {
    return LessonWhiteboardViewportEvent(
      boardId: data['boardId'] is String ? data['boardId'] as String : '',
      globalTimestampSec: data['globalTimestampSec'] is num
          ? (data['globalTimestampSec'] as num).toDouble()
          : 0,
      sequence: data['sequence'] is num ? (data['sequence'] as num).toInt() : 0,
      interactionId: data['interactionId'] is num
          ? (data['interactionId'] as num).toInt()
          : 0,
      viewport: LessonWhiteboardViewport.normalized(
        centerX: data['centerX'] is num
            ? (data['centerX'] as num).toDouble()
            : 0.5,
        centerY: data['centerY'] is num
            ? (data['centerY'] as num).toDouble()
            : 0.5,
        scale: data['scale'] is num
            ? (data['scale'] as num).toDouble()
            : minLessonWhiteboardViewportScale,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'boardId': boardId,
      'globalTimestampSec': globalTimestampSec,
      'sequence': sequence,
      'interactionId': interactionId,
      'centerX': viewport.centerX,
      'centerY': viewport.centerY,
      'scale': viewport.scale,
    };
  }
}

class BoardSet {
  const BoardSet({
    this.boards = const [],
    this.switchEvents = const [],
    this.viewportEvents = const [],
  });

  static const int maxBoards = maxLessonWhiteboardBoards;

  final List<LessonWhiteboardBoard> boards;
  final List<LessonWhiteboardBoardSwitchEvent> switchEvents;
  final List<LessonWhiteboardViewportEvent> viewportEvents;

  bool get isEmpty => boards.isEmpty;
  bool get isNotEmpty => boards.isNotEmpty;
  bool get canAddBoard => boards.length < maxLessonWhiteboardBoards;

  int get nextSwitchSequence {
    var next = 0;
    for (final event in switchEvents) {
      if (event.sequence >= next) {
        next = event.sequence + 1;
      }
    }
    return next;
  }

  int get nextViewportSequence {
    var next = 0;
    for (final event in viewportEvents) {
      if (event.sequence >= next) {
        next = event.sequence + 1;
      }
    }
    return next;
  }

  int get nextViewportInteractionId {
    var next = 0;
    for (final event in viewportEvents) {
      if (event.interactionId >= next) {
        next = event.interactionId + 1;
      }
    }
    return next;
  }

  List<LessonWhiteboardBoard> get orderedBoards {
    final sorted = List<LessonWhiteboardBoard>.from(boards)
      ..sort((a, b) => a.order.compareTo(b.order));
    return sorted.length <= maxLessonWhiteboardBoards
        ? sorted
        : sorted.take(maxLessonWhiteboardBoards).toList();
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

  List<LessonWhiteboardViewportEvent> get orderedViewportEvents {
    final sorted = List<LessonWhiteboardViewportEvent>.from(viewportEvents)
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
    for (final board in orderedBoards) {
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

  LessonWhiteboardViewport resolveViewportAt({
    required String boardId,
    required double globalTimestampSec,
  }) {
    LessonWhiteboardViewportEvent? previous;
    LessonWhiteboardViewportEvent? next;
    for (final event in orderedViewportEvents) {
      if (event.boardId != boardId) {
        continue;
      }
      if (event.globalTimestampSec <= globalTimestampSec) {
        previous = event;
        continue;
      }
      next = event;
      break;
    }
    if (previous == null) {
      return LessonWhiteboardViewport.full;
    }
    if (next == null ||
        next.interactionId != previous.interactionId ||
        next.globalTimestampSec <= previous.globalTimestampSec) {
      return previous.viewport;
    }
    final progress =
        (globalTimestampSec - previous.globalTimestampSec) /
        (next.globalTimestampSec - previous.globalTimestampSec);
    return LessonWhiteboardViewport.lerp(
      previous.viewport,
      next.viewport,
      progress,
    );
  }

  factory BoardSet.fromMap(Object? data) {
    if (data is! Map) {
      return const BoardSet();
    }
    final boardsData = data['boards'];
    final eventsData = data['switchEvents'];
    final viewportEventsData = data['viewportEvents'];
    final rawBoards = <LessonWhiteboardBoard>[];
    if (boardsData is List) {
      for (final boardData in boardsData.whereType<Map>()) {
        if (rawBoards.length >= maxLessonWhiteboardBoards) {
          break;
        }
        final board = _tryParseBoard(boardData);
        if (board != null) {
          rawBoards.add(board);
        }
      }
    }
    final usedIds = <String>{};
    final parsedBoards = <LessonWhiteboardBoard>[];
    for (var index = 0; index < rawBoards.length; index++) {
      final board = rawBoards[index];
      var id = board.id.trim();
      if (id.isEmpty || usedIds.contains(id)) {
        var suffix = index + 1;
        do {
          id = 'board-$suffix';
          suffix++;
        } while (usedIds.contains(id));
      }
      usedIds.add(id);
      parsedBoards.add(board.copyWith(id: id, order: index));
    }
    final parsedEvents = <LessonWhiteboardBoardSwitchEvent>[];
    final usedSwitchSequences = <int>{};
    if (eventsData is List) {
      for (final eventData in eventsData.whereType<Map>()) {
        if (parsedEvents.length >= maxLessonBoardSwitchEvents) {
          break;
        }
        final event = _tryParseSwitchEvent(eventData);
        if (event != null &&
            usedIds.contains(event.boardId) &&
            event.globalTimestampSec.isFinite &&
            event.globalTimestampSec >= 0 &&
            event.sequence >= 0 &&
            usedSwitchSequences.add(event.sequence)) {
          parsedEvents.add(event);
        }
      }
    }
    final parsedViewportEvents = <LessonWhiteboardViewportEvent>[];
    final usedViewportSequences = <int>{};
    if (viewportEventsData is List) {
      for (final eventData in viewportEventsData.whereType<Map>()) {
        if (parsedViewportEvents.length >= maxLessonViewportEvents) {
          break;
        }
        final event = _tryParseViewportEvent(eventData);
        if (event != null &&
            usedIds.contains(event.boardId) &&
            event.globalTimestampSec.isFinite &&
            event.globalTimestampSec >= 0 &&
            event.sequence >= 0 &&
            event.interactionId >= 0 &&
            usedViewportSequences.add(event.sequence)) {
          parsedViewportEvents.add(event);
        }
      }
    }
    return BoardSet(
      boards: parsedBoards,
      switchEvents: parsedEvents,
      viewportEvents: parsedViewportEvents,
    );
  }

  static LessonWhiteboardBoard? _tryParseBoard(Map data) {
    try {
      return LessonWhiteboardBoard.fromMap(data);
    } on Object {
      return null;
    }
  }

  static LessonWhiteboardBoardSwitchEvent? _tryParseSwitchEvent(Map data) {
    try {
      return LessonWhiteboardBoardSwitchEvent.fromMap(data);
    } on Object {
      return null;
    }
  }

  static LessonWhiteboardViewportEvent? _tryParseViewportEvent(Map data) {
    try {
      return LessonWhiteboardViewportEvent.fromMap(data);
    } on Object {
      return null;
    }
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
      'viewportEvents': orderedViewportEvents
          .map((event) => event.toMap())
          .toList(),
    };
  }

  BoardSet copyWith({
    List<LessonWhiteboardBoard>? boards,
    List<LessonWhiteboardBoardSwitchEvent>? switchEvents,
    List<LessonWhiteboardViewportEvent>? viewportEvents,
  }) {
    return BoardSet(
      boards: boards ?? this.boards,
      switchEvents: switchEvents ?? this.switchEvents,
      viewportEvents: viewportEvents ?? this.viewportEvents,
    );
  }

  BoardSet copyWithDefaultLayerBundle(LessonWhiteboardLayerBundle layerBundle) {
    final currentDefault = defaultBoard;
    if (currentDefault == null) {
      return BoardSet.fromLegacyLayers(
        layerBundle.layers,
      ).copyWith(switchEvents: switchEvents);
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

  /// Returns a valid set for an editor, which must always have one board.
  BoardSet ensureEditable() {
    if (boards.isNotEmpty) {
      return copyWith(
        boards: [
          for (final entry in orderedBoards.indexed)
            entry.$2.copyWith(order: entry.$1),
        ],
      );
    }
    return const BoardSet(
      boards: [
        LessonWhiteboardBoard(
          id: LessonWhiteboardBoard.defaultBoardId,
          order: 0,
        ),
      ],
    );
  }

  BoardSet replaceBoard(LessonWhiteboardBoard replacement) {
    if (boardById(replacement.id) == null) {
      return this;
    }
    return copyWith(
      boards: [
        for (final board in boards)
          if (board.id == replacement.id) replacement else board,
      ],
    );
  }
}

typedef LessonWhiteboardBoardSet = BoardSet;
typedef WhiteboardBoard = LessonWhiteboardBoard;
typedef WhiteboardBoardSwitchEvent = LessonWhiteboardBoardSwitchEvent;
