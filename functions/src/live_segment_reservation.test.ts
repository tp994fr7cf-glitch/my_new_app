import assert from "node:assert/strict";
import test from "node:test";

import {
  calculatedLiveStartSec,
  durationSecForLiveStart,
  nextDraftBaseDocumentVersionAfterLiveReservation,
} from "./live_segment_reservation";

test("counts unpublished duration without a URL toward live start", () => {
  assert.equal(
    durationSecForLiveStart({
      durationSec: 12,
      url: "",
    }),
    12,
  );
  assert.equal(
    calculatedLiveStartSec(
      [
        {
          id: "record",
          order: 0,
          url: "",
          durationSec: 12,
        },
        {
          id: "live",
          order: 1,
          sourceKind: "liveArchive",
        },
      ],
      1,
    ),
    12,
  );
});

test("prefers durationMs and skips retired or empty previous parts", () => {
  assert.equal(
    durationSecForLiveStart({
      durationMs: 1500,
      durationSec: 12,
    }),
    1.5,
  );
  assert.equal(
    durationSecForLiveStart({
      retired: true,
      durationSec: 40,
    }),
    0,
  );
  assert.equal(
    calculatedLiveStartSec(
      [
        {id: "hole", order: 0},
        {id: "retired", order: 1, retired: true, durationSec: 9},
        {id: "ready", order: 2, durationMs: 4500},
        {id: "live", order: 3, sourceKind: "liveArchive"},
      ],
      3,
    ),
    4.5,
  );
});

test("advances draft base version only when it already matches the lesson", () => {
  assert.equal(
    nextDraftBaseDocumentVersionAfterLiveReservation({
      draftExists: true,
      draftBaseDocumentVersion: 4,
      currentLessonDocumentVersion: 4,
      nextLessonDocumentVersion: 5,
    }),
    5,
  );
  assert.equal(
    nextDraftBaseDocumentVersionAfterLiveReservation({
      draftExists: false,
      draftBaseDocumentVersion: 4,
      currentLessonDocumentVersion: 4,
      nextLessonDocumentVersion: 5,
    }),
    null,
  );
  assert.equal(
    nextDraftBaseDocumentVersionAfterLiveReservation({
      draftExists: true,
      draftBaseDocumentVersion: 3,
      currentLessonDocumentVersion: 4,
      nextLessonDocumentVersion: 5,
    }),
    null,
  );
});
