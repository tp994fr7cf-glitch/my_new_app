import assert from "node:assert/strict";
import test from "node:test";

import {
  firebaseStorageDownloadUrl,
  prepareLiveArchiveDraft,
  selectManifestObject,
} from "./live_archive_draft";

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
