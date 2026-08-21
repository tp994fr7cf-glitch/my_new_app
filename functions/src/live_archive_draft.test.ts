import assert from "node:assert/strict";
import test from "node:test";

import {
  adjustLiveArchiveBoardSet,
  firebaseStorageDownloadUrl,
  prepareLiveArchiveDraft,
  resolveLiveArchiveDuration,
  selectManifestObject,
} from "./live_archive_draft";
import {isValidBoardSet} from "./live_audio_probe";

const publishedSegments = [
  {
    id: "intro",
    order: 0,
    title: "導入",
    mediaType: "audio",
    url: "https://example.com/intro.m4a",
    durationSec: 10,
  },
  {
    id: "live-slot",
    order: 1,
    title: "ライブ",
    mediaType: "audio",
    url: "",
    sourceKind: "liveArchive",
    liveSessionId: "",
  },
];

test("uses HLS duration and excludes finalization time from fallback", () => {
  assert.deepEqual(
    resolveLiveArchiveDuration({
      timingVersion: 2,
      hlsDurationMs: 20500,
      sessionStartedAtMs: 1000,
      archiveStartedAtMs: 5000,
      archiveStopRequestedAtMs: 25000,
      archiveStoppedAtMs: 28000,
      finalizedAtMs: 45000,
    }),
    {durationMs: 20500, durationSec: 20, source: "hls"},
  );
  assert.deepEqual(
    resolveLiveArchiveDuration({
      timingVersion: 2,
      hlsDurationMs: null,
      sessionStartedAtMs: 1000,
      archiveStartedAtMs: 5000,
      archiveStopRequestedAtMs: 25000,
      archiveStoppedAtMs: 28000,
      finalizedAtMs: 45000,
    }),
    {durationMs: 20000, durationSec: 20, source: "wallClock"},
  );
  assert.deepEqual(
    resolveLiveArchiveDuration({
      timingVersion: 1,
      hlsDurationMs: 20500,
      sessionStartedAtMs: 1000,
      archiveStartedAtMs: 5000,
      archiveStopRequestedAtMs: 25000,
      archiveStoppedAtMs: 28000,
      finalizedAtMs: 45000,
    }),
    {durationMs: 40000, durationSec: 40, source: "wallClock"},
  );
});

test("adjusts only board data added during the live archive", () => {
  const baselineBoardSet = {
    boards: [
      {
        id: "default",
        order: 0,
        layers: [
          {
            id: "primary",
            order: 0,
            anchorType: "global",
            strokes: [
              {
                id: "existing",
                timestampSec: 36,
                endTimestampSec: 50,
                colorArgb: 4278190080,
                strokeWidth: 3,
                points: [
                  {x: 0.1, y: 0.1, timestampSec: 36},
                  {x: 0.2, y: 0.2, timestampSec: 50},
                ],
              },
            ],
          },
        ],
      },
    ],
    switchEvents: [
      {boardId: "default", globalTimestampSec: 50, sequence: 0},
    ],
    viewportEvents: [
      {
        boardId: "default",
        globalTimestampSec: 50,
        sequence: 0,
        interactionId: 0,
        centerX: 0.5,
        centerY: 0.5,
        scale: 1,
      },
    ],
  };
  const boardSet = structuredClone(baselineBoardSet);
  boardSet.boards[0].layers[0].strokes.push({
    id: "live",
    timestampSec: 45,
    endTimestampSec: 55,
    colorArgb: 4278190080,
    strokeWidth: 3,
    points: [
      {x: 0.3, y: 0.3, timestampSec: 45},
      {x: 0.4, y: 0.4, timestampSec: 55},
    ],
  });
  boardSet.switchEvents.push({
    boardId: "default",
    globalTimestampSec: 45,
    sequence: 1,
  });
  boardSet.viewportEvents.push({
    boardId: "default",
    globalTimestampSec: 55,
    sequence: 1,
    interactionId: 1,
    centerX: 0.6,
    centerY: 0.6,
    scale: 2,
  });

  const adjusted = adjustLiveArchiveBoardSet({
    boardSet,
    baselineBoardSet,
    segmentStartSec: 30,
    archiveTimelineOffsetSec: 5,
    recordingWallDurationSec: 20,
    mediaDurationSec: 10,
    segmentId: "live-slot",
  });

  assert.ok(adjusted);
  assert.equal(isValidBoardSet(adjusted), true);
  const boards = adjusted.boards as typeof boardSet.boards;
  assert.deepEqual(
    boards[0].layers[0].strokes[0],
    baselineBoardSet.boards[0].layers[0].strokes[0],
  );
  assert.equal(boards[0].layers[0].strokes.length, 1);
  assert.deepEqual(boards[0].layers[1], {
    id: "segment-live-slot",
    order: 1,
    anchorType: "segment",
    segmentId: "live-slot",
    strokes: [
      {
        id: "live",
        timestampSec: 5,
        endTimestampSec: 10,
        colorArgb: 4278190080,
        strokeWidth: 3,
        points: [
          {x: 0.3, y: 0.3, timestampSec: 5},
          {x: 0.4, y: 0.4, timestampSec: 10},
        ],
      },
    ],
  });
  assert.deepEqual(adjusted.switchEvents, [
    {boardId: "default", globalTimestampSec: 50, sequence: 0},
    {
      boardId: "default",
      globalTimestampSec: 5,
      sequence: 1,
      segmentId: "live-slot",
    },
  ]);
  assert.deepEqual(adjusted.viewportEvents, [
    baselineBoardSet.viewportEvents[0],
    {
      boardId: "default",
      globalTimestampSec: 10,
      sequence: 1,
      interactionId: 1,
      centerX: 0.6,
      centerY: 0.6,
      scale: 2,
      segmentId: "live-slot",
    },
  ]);

  const preservedElapsedTime = adjustLiveArchiveBoardSet({
    boardSet,
    baselineBoardSet,
    segmentStartSec: 30,
    archiveTimelineOffsetSec: 5,
    recordingWallDurationSec: 20,
    mediaDurationSec: 10,
    preserveElapsedTime: true,
    segmentId: "live-slot",
  });
  assert.ok(preservedElapsedTime);
  const preservedBoards =
    preservedElapsedTime.boards as typeof boardSet.boards;
  assert.equal(preservedBoards[0].layers[1].strokes[0].timestampSec, 10);
  assert.equal(preservedBoards[0].layers[1].strokes[0].endTimestampSec, 10);
});

test("replaces only a reserved live placeholder", () => {
  const prepared = prepareLiveArchiveDraft({
    lesson: {
      documentVersion: 7,
      mediaSegments: publishedSegments,
    },
    existingDraft: null,
    segmentId: "live-slot",
    playbackUrl: "https://firebasestorage.example/live.mp4",
    durationSec: 45,
    durationMs: 45250,
    liveSessionId: "session-1",
  });
  assert.equal(prepared.ok, true);
  if (!prepared.ok) {
    return;
  }
  assert.equal(prepared.baseLessonDocumentVersion, 7);
  assert.equal(prepared.draftRevision, 1);
  assert.deepEqual(prepared.mediaSegments[1], {
    ...publishedSegments[1],
    url: "https://firebasestorage.example/live.mp4",
    durationSec: 45,
    durationMs: 45250,
    sourceKind: "liveArchive",
    liveSessionId: "session-1",
  });
});

test("prefers a same-version draft and increments its revision", () => {
  const draftSegments = publishedSegments.map((segment) => ({...segment}));
  draftSegments[0].title = "下書きの導入";
  const prepared = prepareLiveArchiveDraft({
    lesson: {
      documentVersion: 7,
      mediaSegments: publishedSegments,
    },
    existingDraft: {
      baseLessonDocumentVersion: 7,
      draftRevision: 3,
      boardSet: {boards: []},
      mediaSegments: draftSegments,
    },
    segmentId: "live-slot",
    playbackUrl: "https://firebasestorage.example/live.mp4",
    durationSec: 45,
    durationMs: 45250,
    liveSessionId: "session-1",
  });
  assert.equal(prepared.ok, true);
  if (prepared.ok) {
    assert.equal(prepared.draftRevision, 4);
    assert.equal(prepared.mediaSegments[0].title, "下書きの導入");
  }
});

test("rejects version conflicts and missing placeholders", () => {
  assert.deepEqual(
    prepareLiveArchiveDraft({
      lesson: {documentVersion: 7, mediaSegments: publishedSegments},
      existingDraft: {
        baseLessonDocumentVersion: 6,
        draftRevision: 2,
        boardSet: {boards: []},
      },
      segmentId: "live-slot",
      playbackUrl: "https://example.com/live.mp4",
      durationSec: 45,
      durationMs: 45000,
      liveSessionId: "session-1",
    }),
    {ok: false, code: "versionConflict"},
  );
  assert.deepEqual(
    prepareLiveArchiveDraft({
      lesson: {documentVersion: 7, mediaSegments: publishedSegments},
      existingDraft: null,
      segmentId: "missing",
      playbackUrl: "https://example.com/live.mp4",
      durationSec: 45,
      durationMs: 45000,
      liveSessionId: "session-1",
    }),
    {ok: false, code: "placeholderMissing"},
  );
});

test("builds persistent Firebase URL and selects safe manifest files", () => {
  assert.equal(
    firebaseStorageDownloadUrl({
      bucketName: "project.appspot.com",
      objectPath: "courseMedia/course 1/live.mp4",
      downloadToken: "token-value",
    }),
    "https://firebasestorage.googleapis.com/v0/b/project.appspot.com/o/" +
      "courseMedia%2Fcourse%201%2Flive.mp4?alt=media&token=token-value",
  );
  const files = [
    "liveAudioProbeSessions/session1/archive.m3u8",
    "liveAudioProbeSessions/session1/archive.mp4",
  ];
  assert.equal(
    selectManifestObject(
      files,
      ".mp4",
      "liveAudioProbeSessions/session1/",
    ),
    files[1],
  );
  assert.equal(
    selectManifestObject(files, ".mp4", "other/session/"),
    null,
  );
});
