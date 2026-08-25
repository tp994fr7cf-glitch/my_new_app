import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/lesson_media_draft_overlay.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';

void main() {
  const livePlaceholder = LessonMediaSegment(
    id: 'live',
    order: 0,
    mediaType: 'audio',
    sourceKind: lessonMediaSourceLiveArchive,
  );
  const recorded = LessonMediaSegment(
    id: 'record',
    order: 1,
    mediaType: 'audio',
    url: 'https://example.com/record.mp3',
    durationSec: 12,
  );

  test('keeps a live reservation when overlaying a recorded draft part', () {
    final merged = overlayDraftMediaSegments(
      publishedSegments: const [livePlaceholder],
      draftSegments: const [recorded],
    );

    expect(merged.map((segment) => segment.id), ['live', 'record']);
    expect(merged.first.isLivePlaceholder, isTrue);
    expect(merged[1].url, recorded.url);
  });

  test('keeps draft order when a recording slot sits before a live part', () {
    const recordingDraft = LessonMediaSegment(
      id: 'record',
      order: 0,
      mediaType: 'audio',
      url: 'https://example.com/record.mp3',
      durationSec: 12,
      sourceKind: lessonMediaSourceAudioRecording,
    );
    const liveInDraft = LessonMediaSegment(
      id: 'live',
      order: 1,
      mediaType: 'audio',
      sourceKind: lessonMediaSourceLiveArchive,
    );
    const publishedLiveOnly = LessonMediaSegment(
      id: 'live',
      order: 0,
      mediaType: 'audio',
      sourceKind: lessonMediaSourceLiveArchive,
    );

    final merged = overlayDraftMediaSegments(
      publishedSegments: const [publishedLiveOnly],
      draftSegments: const [recordingDraft, liveInDraft],
    );

    expect(merged.map((segment) => segment.id), ['record', 'live']);
    expect(merged.first.url, recordingDraft.url);
    expect(merged[1].isLivePlaceholder, isTrue);
  });

  test('keeps live placeholders inside a media draft list', () {
    const recordingHole = LessonMediaSegment(
      id: 'record',
      order: 0,
      mediaType: 'audio',
      sourceKind: lessonMediaSourceAudioRecording,
    );
    expect(isPersistableMediaDraftSegment(livePlaceholder), isFalse);
    expect(isPersistableMediaDraftSegment(recorded), isTrue);
    expect(isPersistableMediaDraftSegment(recordingHole), isFalse);
    expect(
      isPersistableMediaDraftSegment(
        const LessonMediaSegment(id: 'empty-video', order: 0, mediaType: 'video'),
      ),
      isFalse,
    );
    expect(isPersistableMediaDraftSegment(const LessonMediaSegment(id: ' ', order: 0)),
      isFalse,
    );
    expect(
      isPersistableMediaDraftSegment(
        livePlaceholder.copyWith(isRetired: true),
      ),
      isFalse,
    );
  });

  test(
    'keeps published numbering when a later live archive is the only draft',
    () {
      const recordingHole = LessonMediaSegment(
        id: 'record-1',
        order: 0,
        mediaType: 'audio',
        sourceKind: lessonMediaSourceAudioRecording,
      );
      const unusedLive = LessonMediaSegment(
        id: 'live-2',
        order: 1,
        mediaType: 'audio',
        sourceKind: lessonMediaSourceLiveArchive,
      );
      const laterRecordingHole = LessonMediaSegment(
        id: 'record-3',
        order: 2,
        mediaType: 'audio',
        sourceKind: lessonMediaSourceAudioRecording,
      );
      const reservedLive = LessonMediaSegment(
        id: 'live-4',
        order: 3,
        mediaType: 'audio',
        sourceKind: lessonMediaSourceLiveArchive,
        liveSessionId: 'session-4',
      );
      const archivedLive = LessonMediaSegment(
        id: 'live-4',
        order: 0,
        mediaType: 'audio',
        url: 'https://example.com/live-4.m4a',
        durationSec: 40,
        sourceKind: lessonMediaSourceLiveArchive,
        liveSessionId: 'session-4',
      );

      final merged = overlayDraftMediaSegments(
        publishedSegments: const [
          recordingHole,
          unusedLive,
          laterRecordingHole,
          reservedLive,
        ],
        draftSegments: const [archivedLive],
      );

      expect(merged.map((segment) => segment.id), [
        'record-1',
        'live-2',
        'record-3',
        'live-4',
      ]);
      expect(merged[3].url, archivedLive.url);
      expect(merged[3].order, 3);
      expect(merged[3].liveSessionId, 'session-4');
      expect(merged[1].isLivePlaceholder, isTrue);
    },
  );

  test(
    'keeps published order even after a persistable draft was renumbered',
    () {
      const firstHole = LessonMediaSegment(
        id: 'one',
        order: 0,
        mediaType: 'audio',
      );
      const reservedLive = LessonMediaSegment(
        id: 'live',
        order: 1,
        mediaType: 'audio',
        sourceKind: lessonMediaSourceLiveArchive,
        liveSessionId: 'session-1',
      );
      const archivedLive = LessonMediaSegment(
        id: 'live',
        order: 0,
        mediaType: 'audio',
        url: 'https://example.com/live.m4a',
        durationSec: 20,
        sourceKind: lessonMediaSourceLiveArchive,
        liveSessionId: 'session-1',
      );

      final merged = overlayDraftMediaSegments(
        publishedSegments: const [firstHole, reservedLive],
        draftSegments: LessonMediaSegment.normalizeOrders(const [archivedLive]),
      );

      expect(merged.map((segment) => segment.id), ['one', 'live']);
      expect(merged.first.hasUrl, isFalse);
      expect(merged[1].url, archivedLive.url);
      expect(merged[1].order, 1);
    },
  );

  test('does not revive a retired numbering slot from a media draft', () {
    final merged = overlayDraftMediaSegments(
      publishedSegments: [livePlaceholder.copyWith(isRetired: true), recorded],
      draftSegments: const [livePlaceholder, recorded],
    );

    expect(merged.map((segment) => segment.id), ['live', 'record']);
    expect(merged.first.isRetired, isTrue);
    expect(merged.first.hasUrl, isFalse);
    expect(merged[1].url, recorded.url);
  });
}
