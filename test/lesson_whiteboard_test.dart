import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';

void main() {
  test('LessonWhiteboard round-trips through map', () {
    const whiteboard = LessonWhiteboard(
      version: 1,
      updatedAtMs: 123,
      strokes: [
        WhiteboardStroke(
          id: 'stroke-1',
          timestampSec: 10.5,
          endTimestampSec: 11.2,
          points: [
            WhiteboardPoint(x: 0.1, y: 0.2),
            WhiteboardPoint(x: 0.4, y: 0.6),
          ],
        ),
      ],
    );

    final restored = LessonWhiteboard.fromMap(whiteboard.toMap());
    expect(restored.version, 1);
    expect(restored.updatedAtMs, 123);
    expect(restored.strokes, hasLength(1));
    expect(restored.strokes.first.timestampSec, 10.5);
    expect(restored.strokes.first.points, hasLength(2));
  });

  test('visibleWhiteboardStrokes filters by playback position', () {
    const strokes = [
      WhiteboardStroke(
        id: 'a',
        timestampSec: 5,
        points: [
          WhiteboardPoint(x: 0, y: 0),
          WhiteboardPoint(x: 1, y: 1),
        ],
      ),
      WhiteboardStroke(
        id: 'b',
        timestampSec: 20,
        points: [
          WhiteboardPoint(x: 0.2, y: 0.2),
          WhiteboardPoint(x: 0.8, y: 0.8),
        ],
      ),
    ];

    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 4.9),
      isEmpty,
    );
    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 5),
      hasLength(1),
    );
    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 30),
      hasLength(2),
    );
  });

  test('mergeWhiteboardDraft prefers draft over published', () {
    const published = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'published',
          timestampSec: 1,
          points: [
            WhiteboardPoint(x: 0, y: 0),
            WhiteboardPoint(x: 1, y: 1),
          ],
        ),
      ],
    );
    const draft = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'draft',
          timestampSec: 2,
          points: [
            WhiteboardPoint(x: 0.1, y: 0.1),
            WhiteboardPoint(x: 0.9, y: 0.9),
          ],
        ),
      ],
    );

    final merged = mergeWhiteboardDraft(published: published, draft: draft);
    expect(merged.strokes.single.id, 'draft');
  });

  test('visibleWhiteboardStrokes uses exact seconds for fractional timestamps', () {
    const strokes = [
      WhiteboardStroke(
        id: 'a',
        timestampSec: 1.3,
        points: [
          WhiteboardPoint(x: 0, y: 0),
          WhiteboardPoint(x: 1, y: 1),
        ],
      ),
      WhiteboardStroke(
        id: 'b',
        timestampSec: 2.1,
        points: [
          WhiteboardPoint(x: 0.2, y: 0.2),
          WhiteboardPoint(x: 0.8, y: 0.8),
        ],
      ),
    ];

    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 1),
      isEmpty,
    );
    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 1.3),
      hasLength(1),
    );
    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 2.09),
      hasLength(1),
    );
    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 2.1),
      hasLength(2),
    );
  });
}
