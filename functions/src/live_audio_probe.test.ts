import assert from "node:assert/strict";
import test from "node:test";

import {
  canTransitionSessionState,
  isValidBoardSet,
  isValidOptionalLinkId,
  isValidProbeSessionId,
  isValidSegmentStartSec,
  isValidTimelineChunk,
  isValidWhiteboardStroke,
  maximumAllowedGlobalTimestampSec,
  permissionForParticipant,
  resolveActivePresenterUid,
  rtcUidForFirebaseUser,
  validateTimelineBoardReferences,
} from "./live_audio_probe";

test("assigns stable non-zero Agora IDs", () => {
  const first = rtcUidForFirebaseUser("firebase-user-a");
  const second = rtcUidForFirebaseUser("firebase-user-a");
  assert.equal(first, second);
  assert.ok(first > 0);
  assert.ok(first <= 0xffffffff);
});

test("exactly one active presenter can publish", () => {
  assert.equal(
    permissionForParticipant({
      ownerUid: "teacher",
      participantUid: "teacher",
      activePresenterUid: "student-a",
      presenterUids: [],
    }),
    "subscriber",
  );
  assert.equal(
    permissionForParticipant({
      ownerUid: "teacher",
      participantUid: "student-a",
      activePresenterUid: "student-a",
      presenterUids: ["student-a", "student-b"],
    }),
    "publisher",
  );
  assert.equal(
    permissionForParticipant({
      ownerUid: "teacher",
      participantUid: "student-b",
      activePresenterUid: "student-a",
      presenterUids: ["student-a", "student-b"],
    }),
    "subscriber",
  );
  assert.equal(
    resolveActivePresenterUid({
      ownerUid: "teacher",
      presenterUids: [],
    }),
    "teacher",
  );
  assert.equal(
    permissionForParticipant({
      ownerUid: "teacher",
      participantUid: "teacher",
      activePresenterUid: "teacher",
    }),
    "publisher",
  );
});

test("validates probe session identifiers", () => {
  assert.equal(isValidProbeSessionId("AbCdEfGhIjKlMnOpQrSt"), true);
  assert.equal(isValidProbeSessionId("../secret"), false);
  assert.equal(isValidProbeSessionId("short"), false);
  assert.equal(isValidOptionalLinkId("course_123"), true);
  assert.equal(isValidOptionalLinkId("../course"), false);
  assert.equal(isValidSegmentStartSec(90.5), true);
  assert.equal(isValidSegmentStartSec(-1), false);
});

test("validates bounded whiteboard strokes", () => {
  assert.equal(
    isValidWhiteboardStroke({
      id: "stroke_1",
      timestampSec: 1.2,
      endTimestampSec: 1.5,
      colorArgb: 0xff000000,
      strokeWidth: 3,
      points: [
        {x: 0.1, y: 0.2, timestampSec: 1.2},
        {x: 0.3, y: 0.4, timestampSec: 1.4},
      ],
    }),
    true,
  );
  assert.equal(
    isValidWhiteboardStroke({
      id: "stroke_2",
      timestampSec: 1.2,
      colorArgb: 0xff000000,
      strokeWidth: 3,
      points: [{x: 1.1, y: 0.2}],
    }),
    false,
  );
});

test("validates BoardSet snapshots and bounded timeline chunks", () => {
  const boardSet = {
    boards: [
      {
        id: "default",
        order: 0,
        layers: [
          {
            id: "primary",
            order: 0,
            anchorType: "global",
            strokes: [],
          },
        ],
      },
    ],
    switchEvents: [
      {boardId: "default", globalTimestampSec: 1, sequence: 0},
    ],
    viewportEvents: [
      {
        boardId: "default",
        globalTimestampSec: 1,
        sequence: 0,
        interactionId: 0,
        centerX: 0.5,
        centerY: 0.5,
        scale: 1,
      },
    ],
  };
  assert.equal(isValidBoardSet(boardSet), true);
  assert.equal(
    isValidBoardSet({...boardSet, extraServerField: "not allowed"}),
    false,
  );
  assert.equal(
    isValidTimelineChunk({
      expectedNextSequence: 0,
      chunkId: "chunk-1",
      events: [
        {
          type: "boardSwitch",
          boardId: "default",
          globalTimestampSec: 1,
        },
        {
          type: "viewport",
          boardId: "default",
          globalTimestampSec: 1.1,
          interactionId: 1,
          centerX: 0.5,
          centerY: 0.5,
          scale: 2,
        },
      ],
    }),
    true,
  );
  assert.equal(
    isValidTimelineChunk({
      expectedNextSequence: 0,
      chunkId: "chunk-1",
      events: [{type: "boardSwitch", boardId: "../bad", globalTimestampSec: 1}],
    }),
    false,
  );
  const boardCreateChunk = [
    {
      type: "boardCreate" as const,
      boardId: "board-2",
      globalTimestampSec: 90,
      boardOrder: 1,
      boardTitle: "追加ボード",
    },
    {
      type: "boardSwitch" as const,
      boardId: "board-2",
      globalTimestampSec: 90.1,
    },
    {
      type: "viewport" as const,
      boardId: "board-2",
      globalTimestampSec: 90.2,
      interactionId: 1,
      centerX: 0.5,
      centerY: 0.5,
      scale: 1,
    },
  ];
  assert.equal(
    isValidTimelineChunk({
      expectedNextSequence: 0,
      chunkId: "chunk-board-create",
      events: boardCreateChunk,
    }),
    true,
  );
  assert.equal(
    validateTimelineBoardReferences({
      events: boardCreateChunk,
      knownBoards: new Map([["default", 0]]),
      createdBoardIds: new Set(),
    }).valid,
    true,
  );
  assert.equal(
    validateTimelineBoardReferences({
      events: boardCreateChunk.slice(1),
      knownBoards: new Map([["default", 0]]),
      createdBoardIds: new Set(),
    }).valid,
    false,
  );
  assert.equal(
    validateTimelineBoardReferences({
      events: boardCreateChunk,
      knownBoards: new Map([
        ["default", 0],
        ["board-2", 1],
      ]),
      createdBoardIds: new Set(),
    }).valid,
    true,
  );
});

test("checks global timestamps from the segment start", () => {
  assert.equal(
    maximumAllowedGlobalTimestampSec({
      segmentStartSec: 90,
      startedAtMs: 1000,
      nowMs: 11000,
      graceSec: 60,
    }),
    160,
  );
});

test("allows only safe live session state transitions", () => {
  assert.equal(canTransitionSessionState("active", "finalizing"), true);
  assert.equal(canTransitionSessionState("live", "finalizing"), true);
  assert.equal(canTransitionSessionState("finalizing", "draftReady"), true);
  assert.equal(canTransitionSessionState("finalizing", "archiveFailed"), true);
  assert.equal(canTransitionSessionState("archiveFailed", "finalizing"), true);
  assert.equal(canTransitionSessionState("draftReady", "live"), false);
  assert.equal(canTransitionSessionState("active", "draftReady"), false);
});
