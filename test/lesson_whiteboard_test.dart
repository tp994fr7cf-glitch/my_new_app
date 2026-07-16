import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_media_timeline.dart';
import 'package:my_new_app/models/lesson_timed_anchor.dart';
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

  test(
    'WhiteboardStroke round-trips segment anchors and global recovery times',
    () {
      const stroke = WhiteboardStroke(
        id: 'anchored',
        timestampSec: 100,
        endTimestampSec: 101,
        segmentId: 'audio-part',
        segmentTimestampSec: 10,
        segmentEndTimestampSec: 11,
        points: [
          WhiteboardPoint(
            x: 0.1,
            y: 0.2,
            timestampSec: 100,
            segmentId: 'audio-part',
            segmentTimestampSec: 10,
          ),
          WhiteboardPoint(
            x: 0.4,
            y: 0.6,
            timestampSec: 101,
            segmentId: 'audio-part',
            segmentTimestampSec: 11,
          ),
        ],
      );

      final restored = WhiteboardStroke.fromMap(stroke.toMap());

      expect(restored.timestampSec, 100);
      expect(restored.segmentId, 'audio-part');
      expect(restored.segmentTimestampSec, 10);
      expect(restored.segmentEndTimestampSec, 11);
      expect(restored.points.last.timestampSec, 101);
      expect(restored.points.last.segmentId, 'audio-part');
      expect(restored.points.last.segmentTimestampSec, 11);
    },
  );

  test(
    'visibleWhiteboardStrokes filters legacy strokes by stroke start time',
    () {
      const strokes = [
        WhiteboardStroke(
          id: 'a',
          timestampSec: 5,
          points: [WhiteboardPoint(x: 0, y: 0), WhiteboardPoint(x: 1, y: 1)],
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
    },
  );

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
    const points = [WhiteboardPoint(x: 0.1, y: 0.1, timestampSec: 1.0)];

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

  test(
    'visibleWhiteboardStrokes uses exact seconds for fractional stroke starts',
    () {
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
    },
  );

  test(
    'resolveWhiteboardForLessonPublish prefers saved draft over working copy',
    () {
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
    },
  );

  test('segment-anchored stroke follows its media part after reorder', () {
    final timeline = LessonMediaTimeline(
      segments: [
        _segment(id: 'video-part', order: 0, mediaType: 'video'),
        _segment(id: 'audio-part', order: 1, mediaType: 'audio'),
      ],
    );
    const stroke = WhiteboardStroke(
      id: 'audio-writing',
      timestampSec: 10,
      endTimestampSec: 20,
      segmentId: 'audio-part',
      segmentTimestampSec: 10,
      segmentEndTimestampSec: 20,
      points: [
        WhiteboardPoint(
          x: 0.1,
          y: 0.5,
          timestampSec: 10,
          segmentId: 'audio-part',
          segmentTimestampSec: 10,
        ),
        WhiteboardPoint(
          x: 0.9,
          y: 0.5,
          timestampSec: 20,
          segmentId: 'audio-part',
          segmentTimestampSec: 20,
        ),
      ],
    );
    const bundle = LessonWhiteboardLayerBundle(
      layers: [
        LessonWhiteboardLayer(id: 'primary', order: 0, strokes: [stroke]),
      ],
    );

    final duringVideo = visibleWhiteboardBundleStrokes(
      bundle: bundle,
      timeline: timeline,
      globalPositionSec: 20,
      segmentLocalPositionSec: 20,
      activeSegmentId: 'video-part',
    );
    final duringAudio = visibleWhiteboardBundleStrokes(
      bundle: bundle,
      timeline: timeline,
      globalPositionSec: 110,
      segmentLocalPositionSec: 20,
      activeSegmentId: 'audio-part',
    );

    expect(duringVideo, isEmpty);
    expect(duringAudio, hasLength(1));
    expect(duringAudio.single.id, 'audio-writing');
  });

  test(
    'deleted segment strokes are hidden for learners but retain global recovery',
    () {
      final timeline = LessonMediaTimeline(
        segments: [_segment(id: 'video-part', order: 0, mediaType: 'video')],
      );
      const stroke = WhiteboardStroke(
        id: 'deleted-audio-writing',
        timestampSec: 10,
        segmentId: 'deleted-audio-part',
        segmentTimestampSec: 10,
        points: [
          WhiteboardPoint(
            x: 0.1,
            y: 0.5,
            timestampSec: 10,
            segmentId: 'deleted-audio-part',
            segmentTimestampSec: 10,
          ),
          WhiteboardPoint(
            x: 0.9,
            y: 0.5,
            timestampSec: 20,
            segmentId: 'deleted-audio-part',
            segmentTimestampSec: 20,
          ),
        ],
      );

      expect(
        visiblePortionOfWhiteboardStrokeAtPlayback(
          stroke: stroke,
          timeline: timeline,
          globalPositionSec: 20,
          segmentLocalPositionSec: 20,
          activeSegmentId: 'video-part',
        ),
        isNull,
      );
      expect(
        visiblePortionOfWhiteboardStrokeAtPlayback(
          stroke: stroke,
          timeline: timeline,
          globalPositionSec: 20,
          segmentLocalPositionSec: 20,
          activeSegmentId: 'video-part',
          hideOrphanedSegmentAnchors: false,
        ),
        isNotNull,
      );
      expect(
        findOrphanedWhiteboardStrokes(strokes: [stroke], timeline: timeline),
        hasLength(1),
      );
    },
  );

  test('orphan recovery can reassign or return a stroke to global timing', () {
    const stroke = WhiteboardStroke(
      id: 'orphan',
      timestampSec: 12,
      segmentId: 'deleted',
      segmentTimestampSec: 2,
      points: [
        WhiteboardPoint(
          x: 0,
          y: 0,
          timestampSec: 12,
          segmentId: 'deleted',
          segmentTimestampSec: 2,
        ),
        WhiteboardPoint(
          x: 1,
          y: 1,
          timestampSec: 13,
          segmentId: 'deleted',
          segmentTimestampSec: 3,
        ),
      ],
    );

    final reassigned = stroke.reassignToSegment(
      'replacement',
      maxLocalSec: 2.5,
    );
    final global = stroke.withoutSegmentAnchor();

    expect(reassigned.segmentId, 'replacement');
    expect(
      reassigned.points.every((point) => point.segmentId == 'replacement'),
      isTrue,
    );
    expect(reassigned.points.last.segmentTimestampSec, 2.5);
    expect(reassigned.timestampSec, 12);
    expect(global.segmentId, isNull);
    expect(global.points.every((point) => point.segmentId == null), isTrue);
    expect(global.timestampSec, 12);
  });

  test('bundle playback still honors layer visibility windows', () {
    final timeline = LessonMediaTimeline(
      segments: [_segment(id: 'audio', order: 0, mediaType: 'audio')],
    );
    const bundle = LessonWhiteboardLayerBundle(
      layers: [
        LessonWhiteboardLayer(
          id: 'timed-layer',
          order: 0,
          visibleFromSec: 20,
          visibleUntilSec: 40,
          strokes: [
            WhiteboardStroke(
              id: 'legacy',
              timestampSec: 0,
              points: [
                WhiteboardPoint(x: 0, y: 0),
                WhiteboardPoint(x: 1, y: 1),
              ],
            ),
          ],
        ),
      ],
    );

    expect(
      visibleWhiteboardBundleStrokes(
        bundle: bundle,
        timeline: timeline,
        globalPositionSec: 10,
        segmentLocalPositionSec: 10,
        activeSegmentId: 'audio',
      ),
      isEmpty,
    );
    expect(
      visibleWhiteboardBundleStrokes(
        bundle: bundle,
        timeline: timeline,
        globalPositionSec: 30,
        segmentLocalPositionSec: 30,
        activeSegmentId: 'audio',
      ),
      hasLength(1),
    );
  });

  test('bundle playback hides a layer linked to a deleted segment', () {
    final timeline = LessonMediaTimeline(
      segments: [_segment(id: 'audio', order: 0, mediaType: 'audio')],
    );
    const bundle = LessonWhiteboardLayerBundle(
      layers: [
        LessonWhiteboardLayer(
          id: 'deleted-layer',
          order: 0,
          anchorType: LessonTimedAnchorType.segment,
          segmentId: 'deleted',
          strokes: [
            WhiteboardStroke(
              id: 'legacy-local',
              timestampSec: 0,
              points: [
                WhiteboardPoint(x: 0, y: 0),
                WhiteboardPoint(x: 1, y: 1),
              ],
            ),
          ],
        ),
      ],
    );

    expect(
      visibleWhiteboardBundleStrokes(
        bundle: bundle,
        timeline: timeline,
        globalPositionSec: 10,
        segmentLocalPositionSec: 10,
        activeSegmentId: 'audio',
      ),
      isEmpty,
    );
  });

  test('updating primary strokes preserves other whiteboard layers', () {
    const secondary = LessonWhiteboardLayer(
      id: 'secondary',
      order: 1,
      title: '補助',
      strokes: [
        WhiteboardStroke(
          id: 'secondary-stroke',
          timestampSec: 1,
          points: [WhiteboardPoint(x: 0, y: 0), WhiteboardPoint(x: 1, y: 1)],
        ),
      ],
    );
    const bundle = LessonWhiteboardLayerBundle(
      layers: [
        LessonWhiteboardLayer(
          id: LessonWhiteboardLayer.primaryLayerId,
          order: 0,
          strokes: [],
        ),
        secondary,
      ],
    );

    final updated = bundle.copyWithPrimaryStrokes(
      strokes: const [
        WhiteboardStroke(
          id: 'new-primary',
          timestampSec: 2,
          points: [
            WhiteboardPoint(x: 0.1, y: 0.1),
            WhiteboardPoint(x: 0.9, y: 0.9),
          ],
        ),
      ],
    );

    expect(updated.orderedLayers, hasLength(2));
    expect(updated.orderedLayers.first.strokes.single.id, 'new-primary');
    expect(updated.orderedLayers.last, same(secondary));
  });

  test('empty primary draft marker survives storage until lesson publish', () {
    const marker = LessonWhiteboardLayer(
      id: LessonWhiteboardLayer.primaryLayerId,
      order: 0,
      updatedAtMs: 123,
    );
    const bundle = LessonWhiteboardLayerBundle(layers: [marker]);

    final restored = LessonWhiteboardLayerBundle.fromMap(bundle.toMapList());
    final selected = resolveWhiteboardLayersForLessonPublish(
      publishedLayers: const [
        LessonWhiteboardLayer(
          id: LessonWhiteboardLayer.primaryLayerId,
          order: 0,
          strokes: [
            WhiteboardStroke(
              id: 'old',
              timestampSec: 0,
              points: [
                WhiteboardPoint(x: 0, y: 0),
                WhiteboardPoint(x: 1, y: 1),
              ],
            ),
          ],
        ),
      ],
      draftLayers: restored.layers,
      workingLayers: const LessonWhiteboardLayerBundle(),
    );

    expect(restored.layers, hasLength(1));
    expect(restored.layers.single.updatedAtMs, 123);
    expect(restored.isEmpty, isTrue);
    expect(selected, hasLength(1));
    expect(selected.single.isEmpty, isTrue);
  });
}

LessonMediaSegment _segment({
  required String id,
  required int order,
  required String mediaType,
}) {
  return LessonMediaSegment(
    id: id,
    order: order,
    mediaType: mediaType,
    url: 'https://example.com/$id',
    durationSec: 90,
  );
}
