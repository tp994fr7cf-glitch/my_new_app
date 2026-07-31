import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';
import 'package:my_new_app/services/live_audio_probe_message.dart';

void main() {
  test('round trips a compact synchronized point message', () {
    const original = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.strokePoint,
      strokeId: 'stroke_1',
      timestampSec: 1.234567,
      point: WhiteboardPoint(x: 0.25, y: 0.75),
    );

    final encoded = original.encode();
    final decoded = LiveAudioProbeMessage.tryDecode(encoded);

    expect(encoded.length, lessThan(1024));
    expect(decoded, isNotNull);
    expect(decoded!.kind, LiveAudioProbeMessageKind.strokePoint);
    expect(decoded.strokeId, 'stroke_1');
    expect(decoded.timestampSec, closeTo(1.23457, 0.000001));
    expect(decoded.point!.x, 0.25);
    expect(decoded.point!.y, 0.75);
  });

  test('rejects malformed or out-of-bounds messages', () {
    expect(
      LiveAudioProbeMessage.tryDecode(
        Uint8List.fromList(
          '{"v":1,"t":"p","i":"stroke","q":1,"x":2,"y":0.5}'.codeUnits,
        ),
      ),
      isNull,
    );
    expect(
      LiveAudioProbeMessage.tryDecode(Uint8List.fromList([0xff, 0xfe])),
      isNull,
    );
  });

  test('allows a stroke start without a point', () {
    const start = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.strokeStart,
      strokeId: 'stroke_2',
      timestampSec: 2,
    );

    final decoded = LiveAudioProbeMessage.tryDecode(start.encode());

    expect(decoded, isNotNull);
    expect(decoded!.kind, LiveAudioProbeMessageKind.strokeStart);
    expect(decoded.point, isNull);
  });

  test('saved complete strokes reject delayed live fragments', () {
    expect(
      shouldApplyLiveAudioProbeMessage(
        messageStrokeId: 'saved-stroke',
        localStrokeId: null,
        savedStrokeIds: {'saved-stroke'},
      ),
      isFalse,
    );
    expect(
      shouldApplyLiveAudioProbeMessage(
        messageStrokeId: 'new-stroke',
        localStrokeId: null,
        savedStrokeIds: {'saved-stroke'},
      ),
      isTrue,
    );
  });

  test('round trips board switches and viewport changes', () {
    const boardSwitch = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.boardSwitch,
      boardId: 'board-2',
      timestampSec: 12.5,
    );
    const viewport = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.viewport,
      boardId: 'board-2',
      timestampSec: 13,
      interactionId: 4,
      viewport: LessonWhiteboardViewport(centerX: 0.4, centerY: 0.6, scale: 3),
    );

    final decodedSwitch = LiveAudioProbeMessage.tryDecode(boardSwitch.encode());
    final decodedViewport = LiveAudioProbeMessage.tryDecode(viewport.encode());

    expect(decodedSwitch?.kind, LiveAudioProbeMessageKind.boardSwitch);
    expect(decodedSwitch?.boardId, 'board-2');
    expect(decodedViewport?.kind, LiveAudioProbeMessageKind.viewport);
    expect(decodedViewport?.interactionId, 4);
    expect(decodedViewport?.viewport?.scale, 3);
    expect(decodedViewport?.viewport?.centerY, 0.6);
  });

  test('round trips a bounded board creation message', () {
    const message = LiveAudioProbeMessage(
      kind: LiveAudioProbeMessageKind.boardCreate,
      boardId: 'board-3',
      boardOrder: 2,
      boardTitle: '問題2',
      timestampSec: 8,
    );

    final decoded = LiveAudioProbeMessage.tryDecode(message.encode());

    expect(decoded?.kind, LiveAudioProbeMessageKind.boardCreate);
    expect(decoded?.boardId, 'board-3');
    expect(decoded?.boardOrder, 2);
    expect(decoded?.boardTitle, '問題2');
    expect(message.toTimelineStorageMap(), {
      'type': 'boardCreate',
      'boardId': 'board-3',
      'globalTimestampSec': 8,
      'boardOrder': 2,
      'boardTitle': '問題2',
    });
  });
}
