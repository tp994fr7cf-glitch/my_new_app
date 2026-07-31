import 'dart:convert';
import 'dart:typed_data';

import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';

enum LiveAudioProbeMessageKind {
  strokeStart,
  strokePoint,
  strokeEnd,
  boardCreate,
  boardSwitch,
  viewport,
}

class LiveAudioProbeMessage {
  const LiveAudioProbeMessage({
    required this.kind,
    required this.timestampSec,
    this.strokeId = '',
    this.boardId = LessonWhiteboardBoard.defaultBoardId,
    this.point,
    this.boardOrder,
    this.boardTitle,
    this.viewport,
    this.interactionId,
  });

  final LiveAudioProbeMessageKind kind;
  final String strokeId;
  final String boardId;
  final double timestampSec;
  final WhiteboardPoint? point;
  final int? boardOrder;
  final String? boardTitle;
  final LessonWhiteboardViewport? viewport;
  final int? interactionId;

  Uint8List encode() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toStorageMap())));
  }

  Map<String, Object> toStorageMap() {
    final point = this.point;
    final viewport = this.viewport;
    return <String, Object>{
      'v': 2,
      't': switch (kind) {
        LiveAudioProbeMessageKind.strokeStart => 's',
        LiveAudioProbeMessageKind.strokePoint => 'p',
        LiveAudioProbeMessageKind.strokeEnd => 'e',
        LiveAudioProbeMessageKind.boardCreate => 'c',
        LiveAudioProbeMessageKind.boardSwitch => 'b',
        LiveAudioProbeMessageKind.viewport => 'w',
      },
      'q': _compact(timestampSec),
      'b': boardId,
      if (strokeId.isNotEmpty) 'i': strokeId,
      if (point != null) 'x': _compact(point.x),
      if (point != null) 'y': _compact(point.y),
      'o': ?boardOrder,
      if (boardTitle?.isNotEmpty == true) 'n': boardTitle!,
      if (viewport != null) 'x': _compact(viewport.centerX),
      if (viewport != null) 'y': _compact(viewport.centerY),
      if (viewport != null) 'z': _compact(viewport.scale),
      'r': ?interactionId,
    };
  }

  Map<String, Object> toTimelineStorageMap() {
    return switch (kind) {
      LiveAudioProbeMessageKind.boardCreate => {
        'type': 'boardCreate',
        'boardId': boardId,
        'globalTimestampSec': timestampSec,
        'boardOrder': boardOrder ?? 0,
        'boardTitle': boardTitle ?? '',
      },
      LiveAudioProbeMessageKind.boardSwitch => {
        'type': 'boardSwitch',
        'boardId': boardId,
        'globalTimestampSec': timestampSec,
      },
      LiveAudioProbeMessageKind.viewport => {
        'type': 'viewport',
        'boardId': boardId,
        'globalTimestampSec': timestampSec,
        'interactionId': interactionId ?? 0,
        'centerX': viewport?.centerX ?? 0.5,
        'centerY': viewport?.centerY ?? 0.5,
        'scale': viewport?.scale ?? 1,
      },
      LiveAudioProbeMessageKind.strokeStart ||
      LiveAudioProbeMessageKind.strokePoint ||
      LiveAudioProbeMessageKind.strokeEnd => throw StateError(
        '未完了の板書はタイムラインへ保存できません。',
      ),
    };
  }

  static LiveAudioProbeMessage? tryDecode(Uint8List data) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map) {
        return null;
      }
      final version = decoded['v'];
      final type = decoded['t'];
      final timestamp = decoded['q'];
      if ((version != 1 && version != 2) ||
          timestamp is! num ||
          !timestamp.isFinite ||
          timestamp < 0) {
        return null;
      }
      final kind = switch (type) {
        's' => LiveAudioProbeMessageKind.strokeStart,
        'p' => LiveAudioProbeMessageKind.strokePoint,
        'e' => LiveAudioProbeMessageKind.strokeEnd,
        'c' when version == 2 => LiveAudioProbeMessageKind.boardCreate,
        'b' when version == 2 => LiveAudioProbeMessageKind.boardSwitch,
        'w' when version == 2 => LiveAudioProbeMessageKind.viewport,
        _ => null,
      };
      if (kind == null) {
        return null;
      }
      final rawStrokeId = decoded['i'];
      final isStrokeMessage =
          kind == LiveAudioProbeMessageKind.strokeStart ||
          kind == LiveAudioProbeMessageKind.strokePoint ||
          kind == LiveAudioProbeMessageKind.strokeEnd;
      if (isStrokeMessage &&
          (rawStrokeId is! String ||
              rawStrokeId.isEmpty ||
              rawStrokeId.length > 100)) {
        return null;
      }
      final rawBoardId = version == 1
          ? LessonWhiteboardBoard.defaultBoardId
          : decoded['b'];
      if (rawBoardId is! String ||
          rawBoardId.isEmpty ||
          rawBoardId.length > 100) {
        return null;
      }
      final x = decoded['x'];
      final y = decoded['y'];
      WhiteboardPoint? point;
      if (isStrokeMessage && (x != null || y != null)) {
        if (x is! num ||
            y is! num ||
            !x.isFinite ||
            !y.isFinite ||
            x < 0 ||
            x > 1 ||
            y < 0 ||
            y > 1) {
          return null;
        }
        point = WhiteboardPoint(
          x: x.toDouble(),
          y: y.toDouble(),
          timestampSec: timestamp.toDouble(),
        );
      }
      if ((kind == LiveAudioProbeMessageKind.strokePoint ||
              kind == LiveAudioProbeMessageKind.strokeEnd) &&
          point == null) {
        return null;
      }
      LessonWhiteboardViewport? viewport;
      int? interactionId;
      if (kind == LiveAudioProbeMessageKind.viewport) {
        final scale = decoded['z'];
        final rawInteractionId = decoded['r'];
        if (x is! num ||
            y is! num ||
            scale is! num ||
            !x.isFinite ||
            !y.isFinite ||
            !scale.isFinite ||
            rawInteractionId is! num ||
            !rawInteractionId.isFinite ||
            rawInteractionId < 0) {
          return null;
        }
        viewport = LessonWhiteboardViewport.normalized(
          centerX: x.toDouble(),
          centerY: y.toDouble(),
          scale: scale.toDouble(),
        );
        interactionId = rawInteractionId.toInt();
      }
      int? boardOrder;
      String? boardTitle;
      if (kind == LiveAudioProbeMessageKind.boardCreate) {
        final rawOrder = decoded['o'];
        final rawTitle = decoded['n'];
        if (rawOrder is! num ||
            !rawOrder.isFinite ||
            rawOrder < 0 ||
            rawOrder >= maxLessonWhiteboardBoards ||
            (rawTitle != null &&
                (rawTitle is! String || rawTitle.length > 80))) {
          return null;
        }
        boardOrder = rawOrder.toInt();
        boardTitle = rawTitle is String ? rawTitle : '';
      }
      return LiveAudioProbeMessage(
        kind: kind,
        strokeId: rawStrokeId is String ? rawStrokeId : '',
        boardId: rawBoardId,
        timestampSec: timestamp.toDouble(),
        point: point,
        boardOrder: boardOrder,
        boardTitle: boardTitle,
        viewport: viewport,
        interactionId: interactionId,
      );
    } catch (_) {
      return null;
    }
  }
}

bool shouldApplyLiveAudioProbeMessage({
  required String messageStrokeId,
  required String? localStrokeId,
  required Set<String> savedStrokeIds,
}) {
  return messageStrokeId != localStrokeId &&
      !savedStrokeIds.contains(messageStrokeId);
}

double _compact(double value) => double.parse(value.toStringAsFixed(5));
