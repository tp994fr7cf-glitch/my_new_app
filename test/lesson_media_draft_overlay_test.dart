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
    expect(isPersistableMediaDraftSegment(livePlaceholder), isTrue);
    expect(isPersistableMediaDraftSegment(recorded), isTrue);
    expect(isPersistableMediaDraftSegment(recordingHole), isTrue);
    expect(
      isPersistableMediaDraftSegment(const LessonMediaSegment(id: 'empty', order: 0)),
      isFalse,
    );
  });
}
