import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/course.dart';
import 'package:my_new_app/models/lesson_media_segment.dart';
import 'package:my_new_app/models/lesson_playback_mode.dart';
import 'package:my_new_app/models/lesson_publication_validator.dart';
import 'package:my_new_app/models/lesson_whiteboard_board_set.dart';

void main() {
  const locked = LessonMediaSegment(
    id: 'locked',
    order: 0,
    title: 'Original title',
    mediaType: 'video',
    url: 'https://example.com/locked.mp4',
    durationSec: 30,
  );
  const tail = LessonMediaSegment(
    id: 'tail',
    order: 1,
    title: 'Tail',
    mediaType: 'audio',
    url: 'https://example.com/tail.mp3',
    durationSec: 20,
  );

  CourseLesson previousLesson() {
    return const CourseLesson(
      title: 'Lesson',
      duration: '30秒',
      mediaSegments: [locked],
      publishedSegmentIds: ['locked'],
      playbackMode: LessonPlaybackMode.independentSingle,
    );
  }

  String? validate(CourseLesson next) {
    return validateAppendOnlyLessonPublication(
      previous: previousLesson(),
      next: next,
    );
  }

  test('allows a title edit and append-only tail additions', () {
    final next = previousLesson().copyWith(
      mediaSegments: [
        locked.copyWith(title: 'Edited title'),
        tail,
      ],
      publishedSegmentIds: const ['locked', 'tail'],
      contentRevision: 2,
    );

    expect(validate(next), isNull);
  });

  test(
    'locks published material backgrounds but allows new material boards',
    () {
      const background = LessonWhiteboardBoardBackground(
        assetId: 'material-1',
        storagePath:
            'courseMedia/course/lessons/lesson/materials/'
            'material-1/shared/selected.pdf',
        mediaType: lessonWhiteboardBackgroundPdf,
        pageNumber: 1,
        aspectRatio: 0.707,
      );
      final previous = previousLesson().copyWith(
        publishedBoardSet: const BoardSet(
          boards: [
            LessonWhiteboardBoard(
              id: 'material-board',
              order: 0,
              background: background,
            ),
          ],
        ),
      );
      final appended = previous.copyWith(
        publishedBoardSet: const BoardSet(
          boards: [
            LessonWhiteboardBoard(
              id: 'material-board',
              order: 0,
              background: background,
            ),
            LessonWhiteboardBoard(
              id: 'new-board',
              order: 1,
              background: LessonWhiteboardBoardBackground(
                assetId: 'material-2',
                storagePath:
                    'courseMedia/course/lessons/lesson/materials/'
                    'material-2/shared/image.png',
                mediaType: lessonWhiteboardBackgroundImage,
                aspectRatio: 1.5,
              ),
            ),
          ],
        ),
      );
      final removed = previous.copyWith(
        publishedBoardSet: const BoardSet(
          boards: [LessonWhiteboardBoard(id: 'replacement', order: 0)],
        ),
      );

      expect(
        validateAppendOnlyLessonPublication(previous: previous, next: appended),
        isNull,
      );
      expect(
        validateAppendOnlyLessonPublication(previous: previous, next: removed),
        lessonPublishedMaterialBoardsLockedError,
      );
    },
  );

  test('publishes every URL-bearing tail and increments the revision once', () {
    final next = previousLesson().copyWith(
      mediaSegments: const [
        locked,
        tail,
        LessonMediaSegment(id: 'empty-draft', order: 2),
      ],
      contentRevision: 7,
    );

    final published = LessonPublicationValidator.prepareForPublication(
      previous: previousLesson().copyWith(contentRevision: 7),
      next: next,
    );

    expect(published.mediaSegments.map((segment) => segment.id), [
      'locked',
      'tail',
      'empty-draft',
    ]);
    expect(published.publishedSegmentIds, ['locked', 'tail']);
    expect(published.contentRevision, 8);
  });

  test('preserves the revision when no new segment ID is published', () {
    final previous = previousLesson().copyWith(contentRevision: 7);
    final published = LessonPublicationValidator.prepareForPublication(
      previous: previous,
      next: previous.copyWith(
        mediaSegments: [locked.copyWith(title: 'Renamed')],
      ),
    );

    expect(published.publishedSegmentIds, ['locked']);
    expect(published.contentRevision, 7);
  });

  test('allows timing correction changes on a published part', () {
    final next = previousLesson().copyWith(
      mediaSegments: [
        locked.copyWith(
          whiteboardStartCorrectionMs: 500,
          whiteboardEndCorrectionMs: 1500,
        ),
      ],
    );

    expect(validate(next), isNull);
  });

  test('rejects out-of-range or reversing timing corrections', () {
    final outOfRange = previousLesson().copyWith(
      mediaSegments: [locked.copyWith(whiteboardStartCorrectionMs: 5100)],
    );
    final reversing = previousLesson().copyWith(
      mediaSegments: [
        locked
            .copyWith(durationSec: 5)
            .copyWith(
              whiteboardStartCorrectionMs: 5000,
              whiteboardEndCorrectionMs: -5000,
            ),
      ],
    );

    expect(validate(outOfRange), lessonWhiteboardTimingCorrectionInvalidError);
    expect(validate(reversing), lessonWhiteboardTimingCorrectionInvalidError);
  });

  test('allows changing mode before any part has been published', () {
    final previous = previousLesson().copyWith(
      publishedSegmentIds: const [],
      playbackMode: LessonPlaybackMode.continuous,
    );
    final next = previous.copyWith(
      playbackMode: LessonPlaybackMode.independentPanels,
    );

    expect(
      validateAppendOnlyLessonPublication(previous: previous, next: next),
      isNull,
    );
  });

  test('rejects changing mode after a part has been published', () {
    final next = previousLesson().copyWith(
      playbackMode: LessonPlaybackMode.independentPanels,
    );

    expect(validate(next), lessonPlaybackModeLockedError);
  });

  test('rejects removal and replacement of a locked part', () {
    final removed = previousLesson().copyWith(
      mediaSegments: const [],
      publishedSegmentIds: const [],
    );
    final replaced = previousLesson().copyWith(
      mediaSegments: [locked.copyWith(id: 'replacement')],
      publishedSegmentIds: const ['replacement'],
    );

    expect(validate(removed), lessonPublishedSegmentsLockedError);
    expect(validate(replaced), lessonPublishedSegmentsLockedError);
  });

  test('rejects locked media type, URL, duration, and order changes', () {
    final changes = [
      locked.copyWith(mediaType: 'audio'),
      locked.copyWith(url: 'https://example.com/other.mp4'),
      locked.copyWith(durationSec: 31),
      locked.copyWith(durationMs: 30001),
      locked.copyWith(order: 1),
    ];

    for (final changedSegment in changes) {
      final next = previousLesson().copyWith(mediaSegments: [changedSegment]);
      expect(
        validate(next),
        lessonPublishedSegmentsLockedError,
        reason: 'change to ${changedSegment.toMap()} must be rejected',
      );
    }
  });

  test('rejects reordering a locked prefix', () {
    final previous = previousLesson().copyWith(
      mediaSegments: const [locked, tail],
      publishedSegmentIds: const ['locked', 'tail'],
    );
    final next = previous.copyWith(
      mediaSegments: [tail.copyWith(order: 0), locked.copyWith(order: 1)],
    );

    expect(
      LessonPublicationValidator.validate(previous: previous, next: next),
      lessonPublishedSegmentsLockedError,
    );
  });

  test('rejects unpublishing a locked part or publishing a non-prefix gap', () {
    final unpublished = previousLesson().copyWith(
      publishedSegmentIds: const [],
    );
    final invalidGap = previousLesson().copyWith(
      mediaSegments: const [
        locked,
        LessonMediaSegment(id: 'draft', order: 1),
        LessonMediaSegment(id: 'published-after-gap', order: 2),
      ],
      publishedSegmentIds: const ['locked', 'published-after-gap'],
    );

    expect(validate(unpublished), lessonPublishedSegmentsLockedError);
    expect(validate(invalidGap), lessonPublishedSegmentsLockedError);
  });

  test('reserves a live archive slot between published parts', () {
    const livePlaceholder = LessonMediaSegment(
      id: 'live',
      order: 1,
      title: 'Live class',
      mediaType: 'audio',
      sourceKind: lessonMediaSourceLiveArchive,
      liveSessionId: 'session-1',
    );
    const laterPublished = LessonMediaSegment(
      id: 'later',
      order: 2,
      mediaType: 'audio',
      url: 'https://example.com/later.m4a',
      durationSec: 10,
    );
    final previous = previousLesson().copyWith(
      mediaSegments: const [locked, livePlaceholder, laterPublished],
      publishedSegmentIds: const ['locked', 'later'],
    );

    expect(
      LessonPublicationValidator.validate(previous: previous, next: previous),
      isNull,
    );

    final archived = livePlaceholder.copyWith(
      url: 'https://example.com/live.m4a',
      durationSec: 45,
      durationMs: 45250,
    );
    final published = LessonPublicationValidator.prepareForPublication(
      previous: previous,
      next: previous.copyWith(
        mediaSegments: [locked, archived, laterPublished],
      ),
    );

    expect(published.publishedSegmentIds, ['locked', 'live', 'later']);
    expect(published.effectivePublishedMediaSegments[1].isLiveArchive, isTrue);
  });

  test('rejects moving or replacing a reserved live archive slot', () {
    const livePlaceholder = LessonMediaSegment(
      id: 'live',
      order: 1,
      mediaType: 'audio',
      sourceKind: lessonMediaSourceLiveArchive,
    );
    final previous = previousLesson().copyWith(
      mediaSegments: const [locked, livePlaceholder],
    );

    expect(
      LessonPublicationValidator.validate(
        previous: previous,
        next: previous.copyWith(
          mediaSegments: [
            locked,
            livePlaceholder.copyWith(id: 'replacement'),
          ],
        ),
      ),
      lessonPublishedSegmentsLockedError,
    );
  });

  test('rejects blank and duplicate segment IDs', () {
    final blank = previousLesson().copyWith(
      mediaSegments: [locked.copyWith(id: ' ')],
      publishedSegmentIds: const [],
    );
    final duplicate = previousLesson().copyWith(
      mediaSegments: const [locked, locked],
      publishedSegmentIds: const ['locked'],
    );

    expect(validate(blank), lessonInvalidSegmentIdError);
    expect(validate(duplicate), lessonInvalidSegmentIdError);
  });

  test('rejects stale and duplicate published IDs', () {
    final stale = previousLesson().copyWith(
      publishedSegmentIds: const ['locked', 'missing'],
    );
    final duplicate = previousLesson().copyWith(
      publishedSegmentIds: const ['locked', 'locked'],
    );

    expect(validate(stale), lessonInvalidPublishedSegmentIdsError);
    expect(validate(duplicate), lessonInvalidPublishedSegmentIdsError);
  });

  test(
    'rejects duplicate order ambiguity and insertion before locked prefix',
    () {
      final duplicateOrder = previousLesson().copyWith(
        mediaSegments: [locked, tail.copyWith(order: 0)],
      );
      final insertedBeforePrefix = previousLesson().copyWith(
        mediaSegments: [tail.copyWith(order: 0), locked.copyWith(order: 1)],
      );

      expect(validate(duplicateOrder), lessonDuplicateSegmentOrderError);
      expect(
        validate(insertedBeforePrefix),
        lessonPublishedSegmentsLockedError,
      );
    },
  );

  test(
    'rejects malformed persisted publication metadata without unlocking',
    () {
      final malformed = CourseLesson.fromMap({
        'title': 'Malformed',
        'duration': '30秒',
        'mediaSegments': [locked.toMap()],
        'publishedSegmentIds': ['missing'],
      });

      expect(malformed.effectivePublishedMediaSegments, isEmpty);
      expect(malformed.lockedSegmentIds, {'locked'});
      expect(
        LessonPublicationValidator.validate(
          previous: malformed,
          next: malformed,
        ),
        lessonMalformedPublicationMetadataError,
      );
    },
  );

  test('rejects a new 101st part', () {
    final existingSegments = [
      for (var index = 0; index < 100; index++)
        LessonMediaSegment(
          id: 'segment-$index',
          order: index,
          url: 'https://example.com/$index.mp4',
        ),
    ];
    final previous = CourseLesson(
      title: 'At cap',
      duration: '30秒',
      mediaSegments: existingSegments,
      publishedSegmentIds: [for (final segment in existingSegments) segment.id],
    );
    final next = previous.copyWith(
      mediaSegments: [
        ...existingSegments,
        const LessonMediaSegment(
          id: 'segment-100',
          order: 100,
          url: 'https://example.com/100.mp4',
        ),
      ],
    );

    expect(
      LessonPublicationValidator.validate(previous: previous, next: next),
      lessonMediaSegmentLimitError,
    );
  });

  test('legacy lessons already over the cap still allow title-only saves', () {
    final segments = [
      for (var index = 0; index < 101; index++)
        LessonMediaSegment(
          id: 'legacy-$index',
          order: index,
          url: 'https://example.com/$index.mp4',
        ),
    ];
    final previous = CourseLesson(
      title: 'Legacy',
      duration: '30秒',
      mediaSegments: segments,
    );

    expect(
      () => LessonPublicationValidator.prepareForPublication(
        previous: previous,
        next: previous.copyWith(title: 'Renamed'),
      ),
      returnsNormally,
    );
  });

  test('rejects content revision overflow before publishing', () {
    final previous = previousLesson().copyWith(
      contentRevision: maxLessonContentRevision,
    );
    final next = previous.copyWith(mediaSegments: const [locked, tail]);

    expect(
      () => LessonPublicationValidator.prepareForPublication(
        previous: previous,
        next: next,
      ),
      throwsA(
        isA<LessonPublicationValidationException>().having(
          (error) => error.message,
          'message',
          lessonContentRevisionLimitError,
        ),
      ),
    );
  });

  test(
    'asks for a choice when a live slot is unfinished and a later part is ready',
    () {
      const livePlaceholder = LessonMediaSegment(
        id: 'live',
        order: 0,
        mediaType: 'audio',
        sourceKind: lessonMediaSourceLiveArchive,
      );
      final next = const CourseLesson(
        title: 'Lesson',
        duration: '30秒',
        mediaSegments: [livePlaceholder, tail],
      );

      expect(
        lessonNeedsPendingPartPublishChoice(
          previous: const CourseLesson(title: 'Lesson', duration: '30秒'),
          next: next,
        ),
        isTrue,
      );
    },
  );

  test(
    'publishing a later part keeps the earlier live slot in the lesson document',
    () {
      const livePlaceholder = LessonMediaSegment(
        id: 'live',
        order: 0,
        mediaType: 'audio',
        sourceKind: lessonMediaSourceLiveArchive,
      );
      final published = LessonPublicationValidator.prepareForPublication(
        previous: const CourseLesson(title: 'Lesson', duration: '30秒'),
        next: const CourseLesson(
          title: 'Lesson',
          duration: '30秒',
          mediaSegments: [livePlaceholder, tail],
        ),
      );

      expect(published.publishedSegmentIds, ['tail']);
      expect(published.mediaSegments.map((segment) => segment.id), [
        'live',
        'tail',
      ]);
      expect(
        published.visibleLessonPartSegments.map((segment) => segment.id),
        ['live', 'tail'],
      );
      expect(
        published.effectivePublishedMediaSegments.map((segment) => segment.id),
        ['tail'],
      );
      expect(published.visibleLessonPartSegments.first.isLivePlaceholder, isTrue);
      expect(published.visibleLessonPartSegments[1].order, 1);
    },
  );

  test('reservation persist keeps later recorded parts unpublished', () {
    const livePlaceholder = LessonMediaSegment(
      id: 'live',
      order: 0,
      mediaType: 'audio',
      sourceKind: lessonMediaSourceLiveArchive,
    );
    final reserved = LessonPublicationValidator.prepareForPersist(
      previous: const CourseLesson(title: 'Lesson', duration: '30秒'),
      next: const CourseLesson(
        title: 'Lesson',
        duration: '30秒',
        mediaSegments: [livePlaceholder, tail],
      ),
      intent: LessonMediaPersistIntent.keepUnpublishedTails,
    );

    expect(reserved.publishedSegmentIds, isEmpty);
    expect(reserved.mediaSegments.map((segment) => segment.id), ['live']);
    expect(reserved.visibleLessonPartSegments, isEmpty);
  });
}
