import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_whiteboard.dart';

void main() {
  test('LessonWhiteboard round-trips through map with point timestamps', () {
    const whiteboard = LessonWhiteboard(
      version: 1,
      updatedAtMs: 123,
      strokes: [
        WhiteboardStroke(
          id: 'stroke-1',
          timestampSec: 10.5,
          endTimestampSec: 11.2,
          points: [
            WhiteboardPoint(x: 0.1, y: 0.2, timestampSec: 10.5),
            WhiteboardPoint(x: 0.4, y: 0.6, timestampSec: 11.0),
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
    expect(restored.strokes.first.points.last.timestampSec, 11.0);
  });

  test('visibleWhiteboardStrokes filters legacy strokes by stroke start time', () {
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

  test('visibleWhiteboardStrokes reveals timed points progressively', () {
    const stroke = WhiteboardStroke(
      id: 'long',
      timestampSec: 5,
      endTimestampSec: 8,
      points: [
        WhiteboardPoint(x: 0.0, y: 0.5, timestampSec: 5.0),
        WhiteboardPoint(x: 0.3, y: 0.5, timestampSec: 6.0),
        WhiteboardPoint(x: 0.6, y: 0.5, timestampSec: 7.0),
        WhiteboardPoint(x: 1.0, y: 0.5, timestampSec: 8.0),
      ],
    );

    expect(
      visibleWhiteboardStrokes(strokes: [stroke], positionSec: 5.5),
      isEmpty,
    );

    final atSix = visibleWhiteboardStrokes(strokes: [stroke], positionSec: 6.0);
    expect(atSix, hasLength(1));
    expect(atSix.first.points, hasLength(2));

    final atSeven = visibleWhiteboardStrokes(
      strokes: [stroke],
      positionSec: 7.2,
    );
    expect(atSeven.first.points, hasLength(3));

    final atEnd = visibleWhiteboardStrokes(strokes: [stroke], positionSec: 8);
    expect(atEnd.first.points, hasLength(4));
  });

  test('shouldSampleWhiteboardPoint thins dense points', () {
    const points = [
      WhiteboardPoint(x: 0.1, y: 0.1, timestampSec: 1.0),
    ];

    expect(
      shouldSampleWhiteboardPoint(
        existingPoints: points,
        nextPoint: const WhiteboardPoint(x: 0.11, y: 0.11),
        nextTimestampSec: 1.01,
        force: false,
      ),
      isTrue,
    );
    expect(
      shouldSampleWhiteboardPoint(
        existingPoints: points,
        nextPoint: const WhiteboardPoint(x: 0.2, y: 0.2),
        nextTimestampSec: 1.06,
        force: false,
      ),
      isTrue,
    );
    expect(
      shouldSampleWhiteboardPoint(
        existingPoints: points,
        nextPoint: const WhiteboardPoint(x: 0.11, y: 0.11),
        nextTimestampSec: 1.01,
        force: true,
      ),
      isTrue,
    );
  });

  test('mergeWhiteboardDraft prefers draft over published', () {
    const published = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'published',
          timestampSec: 1,
          points: [
            WhiteboardPoint(x: 0, y: 0, timestampSec: 1),
            WhiteboardPoint(x: 1, y: 1, timestampSec: 1.5),
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
            WhiteboardPoint(x: 0.1, y: 0.1, timestampSec: 2),
            WhiteboardPoint(x: 0.9, y: 0.9, timestampSec: 2.5),
          ],
        ),
      ],
    );

    final merged = mergeWhiteboardDraft(published: published, draft: draft);
    expect(merged.strokes.single.id, 'draft');
  });

  test('visibleWhiteboardStrokes uses exact seconds for fractional stroke starts', () {
    const strokes = [
      WhiteboardStroke(
        id: 'a',
        timestampSec: 1.3,
        points: [
          WhiteboardPoint(x: 0, y: 0, timestampSec: 1.3),
          WhiteboardPoint(x: 1, y: 1, timestampSec: 1.8),
        ],
      ),
      WhiteboardStroke(
        id: 'b',
        timestampSec: 2.1,
        points: [
          WhiteboardPoint(x: 0.2, y: 0.2, timestampSec: 2.1),
          WhiteboardPoint(x: 0.8, y: 0.8, timestampSec: 2.4),
        ],
      ),
    ];

    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 1),
      isEmpty,
    );
    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 1.3),
      isEmpty,
    );
    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 1.8),
      hasLength(1),
    );
    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 2.09),
      hasLength(1),
    );
    expect(
      visibleWhiteboardStrokes(strokes: strokes, positionSec: 2.4),
      hasLength(2),
    );
  });

  test('resolveWhiteboardForLessonPublish prefers saved draft over working copy', () {
    const published = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'published',
          timestampSec: 0,
          points: [
            WhiteboardPoint(x: 0.1, y: 0.5, timestampSec: 0),
            WhiteboardPoint(x: 0.9, y: 0.5, timestampSec: 10),
          ],
        ),
      ],
    );
    const draft = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'draft',
          timestampSec: 0,
          points: [
            WhiteboardPoint(x: 0.2, y: 0.2, timestampSec: 0),
            WhiteboardPoint(x: 0.8, y: 0.8, timestampSec: 10),
          ],
        ),
      ],
    );
    const unsavedWorking = LessonWhiteboard(
      strokes: [
        WhiteboardStroke(
          id: 'unsaved',
          timestampSec: 0,
          points: [
            WhiteboardPoint(x: 0.0, y: 0.0, timestampSec: 0),
            WhiteboardPoint(x: 1.0, y: 1.0, timestampSec: 10),
          ],
        ),
      ],
    );

    expect(
      resolveWhiteboardForLessonPublish(
        publishedWhiteboard: published,
        draftWhiteboard: draft,
        workingWhiteboard: unsavedWorking,
      ),
      draft,
    );
    expect(
      resolveWhiteboardForLessonPublish(
        publishedWhiteboard: published,
        draftWhiteboard: null,
        workingWhiteboard: unsavedWorking,
      ),
      published,
    );
  });
}
