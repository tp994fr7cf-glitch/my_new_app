import assert from "node:assert/strict";
import test from "node:test";

import {
  canTransitionSessionState,
  hasLiveAudioProbeExceededMaxDuration,
  isValidBoardSet,
  isValidLiveAudioJoinCode,
  isValidOptionalLinkId,
  isValidProbeSessionId,
  isValidSegmentStartSec,
  isValidTimelineChunk,
  isValidWhiteboardStroke,
  maximumAllowedGlobalTimestampSec,
  canDrawBoard,
  canPublishAudio,
  permissionForParticipant,
  resolveActivePresenterUid,
  resolveCoSpeakerUid,
  remainingLiveAudioProbeDurationSec,
  rtcUidForFirebaseUser,
  validateTimelineBoardReferences,
  maxLiveAudioProbeStrokes,
} from "./live_audio_probe";

test("assigns stable non-zero Agora IDs", () => {
  const first = rtcUidForFirebaseUser("firebase-user-a");
  const second = rtcUidForFirebaseUser("firebase-user-a");
  assert.equal(first, second);
  assert.ok(first > 0);
  assert.ok(first <= 0xffffffff);
});

test("teacher always publishes audio and drawing stays with one person", () => {
  assert.equal(
    permissionForParticipant({
      ownerUid: "teacher",
      participantUid: "teacher",
      activePresenterUid: "student-a",
      presenterUids: ["student-a"],
    }),
    "publisher",
  );
  assert.equal(
    canPublishAudio({
      ownerUid: "teacher",
      participantUid: "student-a",
      activePresenterUid: "teacher",
      presenterUids: ["student-a"],
    }),
    true,
  );
  assert.equal(
    canDrawBoard({
      ownerUid: "teacher",
      participantUid: "teacher",
      activePresenterUid: "teacher",
      presenterUids: ["student-a"],
    }),
    true,
  );
  assert.equal(
    canDrawBoard({
      ownerUid: "teacher",
      participantUid: "student-a",
      activePresenterUid: "teacher",
      presenterUids: ["student-a"],
    }),
    false,
  );
  assert.equal(
    canDrawBoard({
      ownerUid: "teacher",
      participantUid: "student-a",
      activePresenterUid: "student-a",
      presenterUids: ["student-a"],
    }),
    true,
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
    resolveCoSpeakerUid({
      ownerUid: "teacher",
      activePresenterUid: "teacher",
      presenterUids: ["student-a"],
    }),
    "student-a",
  );
  assert.equal(
    resolveActivePresenterUid({
      ownerUid: "teacher",
      activePresenterUid: "student-a",
      presenterUids: [],
    }),
    "student-a",
  );
  assert.equal(
    resolveActivePresenterUid({
      ownerUid: "teacher",
      activePresenterUid: "student-a",
      presenterUids: ["student-b"],
    }),
    "teacher",
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
  assert.equal(isValidLiveAudioJoinCode("0000"), true);
  assert.equal(isValidLiveAudioJoinCode("1234"), true);
  assert.equal(isValidLiveAudioJoinCode("123"), false);
  assert.equal(isValidLiveAudioJoinCode("12a4"), false);
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
  assert.equal(
    isValidWhiteboardStroke({
      id: "stroke_hidden",
      timestampSec: 1.2,
      endTimestampSec: 1.5,
      hiddenAtSec: 2.0,
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
      id: "stroke_hidden_too_early",
      timestampSec: 1.2,
      hiddenAtSec: 1.0,
      colorArgb: 0xff000000,
      strokeWidth: 3,
      points: [{x: 0.1, y: 0.2, timestampSec: 1.2}],
    }),
    false,
  );
});

function boardSetWithStrokeCount(count: number) {
  return {
    boards: [
      {
        id: "default",
        order: 0,
        layers: [
          {
            id: "primary",
            order: 0,
            anchorType: "global",
            strokes: Array.from({length: count}, (_, index) => ({
              id: `s${index}`,
              timestampSec: 0,
              colorArgb: 0xff000000,
              strokeWidth: 3,
              points: [{x: 0.1, y: 0.2, timestampSec: 0}],
            })),
          },
        ],
      },
    ],
    switchEvents: [],
    viewportEvents: [],
  };
}

test("accepts 4000 live strokes and rejects more", () => {
  assert.equal(maxLiveAudioProbeStrokes, 4000);
  assert.equal(isValidBoardSet(boardSetWithStrokeCount(4000)), true);
  assert.equal(isValidBoardSet(boardSetWithStrokeCount(4001)), false);
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
  const hiddenStrokeBoardSet = {
    ...boardSet,
    boards: [
      {
        ...boardSet.boards[0],
        layers: [
          {
            ...boardSet.boards[0].layers[0],
            strokes: [
              {
                id: "stroke_hidden",
                timestampSec: 1.2,
                endTimestampSec: 1.5,
                hiddenAtSec: 2.0,
                colorArgb: 0xff000000,
                strokeWidth: 3,
                points: [
                  {x: 0.1, y: 0.2, timestampSec: 1.2},
                  {x: 0.3, y: 0.4, timestampSec: 1.4},
                ],
              },
            ],
          },
        ],
      },
    ],
  };
  assert.equal(isValidBoardSet(hiddenStrokeBoardSet), true);
  const materialBackground = {
    assetId: "material-1",
    storagePath:
      "courseMedia/course-1/lessons/lesson-1/materials/material-1/shared.pdf",
    mediaType: "pdf",
    pageNumber: 1,
    aspectRatio: 0.707,
  };
  const materialBoardSet = {
    ...boardSet,
    boards: [{...boardSet.boards[0], background: materialBackground}],
  };
  assert.equal(isValidBoardSet(materialBoardSet), true);
  assert.equal(
    isValidBoardSet({
      ...materialBoardSet,
      boards: [
        {
          ...materialBoardSet.boards[0],
          background: {...materialBackground, storagePath: "other/private.pdf"},
        },
      ],
    }),
    false,
  );
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

test("limits every live session to one hour from its server start", () => {
  const startedAtMs = 1000;
  assert.equal(
    remainingLiveAudioProbeDurationSec({
      startedAtMs,
      nowMs: startedAtMs,
    }),
    3600,
  );
  assert.equal(
    remainingLiveAudioProbeDurationSec({
      startedAtMs,
      nowMs: startedAtMs + 3599500,
    }),
    1,
  );
  assert.equal(
    hasLiveAudioProbeExceededMaxDuration({
      startedAtMs,
      nowMs: startedAtMs + 3599999,
    }),
    false,
  );
  assert.equal(
    hasLiveAudioProbeExceededMaxDuration({
      startedAtMs,
      nowMs: startedAtMs + 3600000,
    }),
    true,
  );
});

test("rejects invalid session start times for duration tokens", () => {
  assert.equal(
    remainingLiveAudioProbeDurationSec({
      startedAtMs: 0,
      nowMs: Date.now(),
    }),
    0,
  );
  assert.equal(
    hasLiveAudioProbeExceededMaxDuration({
      startedAtMs: "invalid",
      nowMs: Date.now(),
    }),
    false,
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
