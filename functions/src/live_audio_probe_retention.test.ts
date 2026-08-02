import type {Bucket} from "@google-cloud/storage";
import type {Firestore} from "firebase-admin/firestore";
import assert from "node:assert/strict";
import test from "node:test";

import {
  RAW_ARCHIVE_BYTES_PER_GB,
  RAW_ARCHIVE_CLEANUP_TARGET_BYTES,
  RAW_ARCHIVE_CLEANUP_TRIGGER_BYTES,
  RAW_ARCHIVE_HARD_LIMIT_BYTES,
  LiveAudioProbeRawSession,
  LiveAudioProbeRetentionDecision,
  evaluateLiveAudioProbeRetentionSession,
  expectedLinkedArchiveCopyPath,
  expectedLiveAudioProbeRawPrefix,
  planLiveAudioProbeRetention,
} from "./live_audio_probe_retention";
import {runLiveAudioProbeRawRetention} from
  "./live_audio_probe_retention_runtime";

const gb = RAW_ARCHIVE_BYTES_PER_GB;
const sessionIds = {
  oldest: "AAAAAAAAAAAAAAAAAAAA",
  middle: "BBBBBBBBBBBBBBBBBBBB",
  newest: "CCCCCCCCCCCCCCCCCCCC",
  fourth: "DDDDDDDDDDDDDDDDDDDD",
} as const;

function rawSession(
  sessionId: string,
  overrides: Partial<LiveAudioProbeRawSession> = {},
): LiveAudioProbeRawSession {
  return {
    sessionId,
    archivePrefix: expectedLiveAudioProbeRawPrefix(sessionId) ?? "",
    sizeBytes: gb,
    startedAtMs: 1,
    status: "draftReady",
    state: "draftReady",
    archiveStatus: "draftReady",
    ...overrides,
  };
}

function protectionReason(
  decision: LiveAudioProbeRetentionDecision,
): string {
  assert.equal(decision.eligible, false);
  if (decision.eligible) {
    assert.fail("Expected the session to be protected.");
  }
  return decision.protected.reason;
}

test("uses strict 9 GB cleanup and 10 GB hard-limit boundaries", () => {
  const atFive = planLiveAudioProbeRetention({
    totalBytes: RAW_ARCHIVE_CLEANUP_TARGET_BYTES,
    sessions: [],
  });
  assert.equal(atFive.cleanupTriggered, false);
  assert.equal(atFive.targetReached, true);
  assert.equal(atFive.projectedBytes, 5 * gb);

  const atNine = planLiveAudioProbeRetention({
    totalBytes: RAW_ARCHIVE_CLEANUP_TRIGGER_BYTES,
    sessions: [],
  });
  assert.equal(atNine.cleanupTriggered, false);
  assert.equal(atNine.hardLimitExceeded, false);
  assert.equal(atNine.targetReached, true);

  const aboveNine = planLiveAudioProbeRetention({
    totalBytes: RAW_ARCHIVE_CLEANUP_TRIGGER_BYTES + 1,
    sessions: [
      rawSession(sessionIds.oldest, {
        sizeBytes: 4 * gb + 1,
      }),
    ],
  });
  assert.equal(aboveNine.cleanupTriggered, true);
  assert.equal(aboveNine.selectedBytes, 4 * gb + 1);
  assert.equal(aboveNine.projectedBytes, RAW_ARCHIVE_CLEANUP_TARGET_BYTES);
  assert.equal(aboveNine.targetReached, true);

  const atTen = planLiveAudioProbeRetention({
    totalBytes: RAW_ARCHIVE_HARD_LIMIT_BYTES,
    sessions: [],
  });
  assert.equal(atTen.hardLimitExceeded, false);

  const aboveTen = planLiveAudioProbeRetention({
    totalBytes: RAW_ARCHIVE_HARD_LIMIT_BYTES + 1,
    sessions: [],
  });
  assert.equal(aboveTen.hardLimitExceeded, true);
});

test("allEligible explicitly selects every safe session below threshold", () => {
  const plan = planLiveAudioProbeRetention({
    totalBytes: 3 * gb,
    sessions: [
      rawSession(sessionIds.middle, {
        sizeBytes: gb,
        startedAtMs: 200,
      }),
      rawSession(sessionIds.oldest, {
        sizeBytes: 2 * gb,
        startedAtMs: 100,
      }),
    ],
    selectionPolicy: "allEligible",
  });

  assert.equal(plan.selectionPolicy, "allEligible");
  assert.equal(plan.cleanupTriggered, false);
  assert.deepEqual(
    plan.selectedSessions.map((session) => session.sessionId),
    [sessionIds.oldest, sessionIds.middle],
  );
  assert.equal(plan.selectedBytes, 3 * gb);
  assert.equal(plan.projectedBytes, 0);
  assert.equal(plan.targetReached, true);
});

test("selects oldest whole sessions until at or below 5 GB", () => {
  const plan = planLiveAudioProbeRetention({
    totalBytes: 10 * gb,
    sessions: [
      rawSession(sessionIds.newest, {
        sizeBytes: 2 * gb,
        startedAtMs: 300,
      }),
      rawSession(sessionIds.oldest, {
        sizeBytes: 3 * gb,
        startedAtMs: 100,
      }),
      rawSession(sessionIds.middle, {
        sizeBytes: 2 * gb,
        startedAtMs: 200,
      }),
    ],
  });

  assert.deepEqual(
    plan.eligibleSessions.map((session) => session.sessionId),
    [sessionIds.oldest, sessionIds.middle, sessionIds.newest],
  );
  assert.deepEqual(
    plan.selectedSessions.map((session) => session.sessionId),
    [sessionIds.oldest, sessionIds.middle],
  );
  assert.equal(plan.selectedBytes, 5 * gb);
  assert.equal(plan.projectedBytes, 5 * gb);
  assert.equal(plan.targetReached, true);
});

test("does not partially select a session when the target is overshot", () => {
  const plan = planLiveAudioProbeRetention({
    totalBytes: 9 * gb + 1,
    sessions: [
      rawSession(sessionIds.oldest, {
        sizeBytes: 3 * gb,
        startedAtMs: 100,
      }),
      rawSession(sessionIds.middle, {
        sizeBytes: 2 * gb,
        startedAtMs: 200,
      }),
    ],
  });

  assert.deepEqual(
    plan.selectedSessions.map((session) => session.sessionId),
    [sessionIds.oldest, sessionIds.middle],
  );
  assert.equal(plan.projectedBytes, 4 * gb + 1);
});

test("protects live, finalizing, retryable, and unknown lifecycle states", () => {
  const cases: Array<{
    name: string;
    overrides: Partial<LiveAudioProbeRawSession>;
    reason: string;
  }> = [
    {name: "active status", overrides: {status: "active"}, reason: "liveOrRecording"},
    {name: "live state", overrides: {state: "live"}, reason: "liveOrRecording"},
    {name: "starting archive", overrides: {archiveStatus: "starting"}, reason: "liveOrRecording"},
    {name: "recording archive", overrides: {archiveStatus: "recording"}, reason: "liveOrRecording"},
    {name: "available archive", overrides: {archiveStatus: "available"}, reason: "liveOrRecording"},
    {name: "finalizing state", overrides: {state: "finalizing"}, reason: "finalizing"},
    {name: "stopping archive", overrides: {archiveStatus: "stopping"}, reason: "finalizing"},
    {name: "archive failure", overrides: {status: "archiveFailed"}, reason: "retryableArchive"},
    {name: "generic failure", overrides: {state: "failed"}, reason: "retryableArchive"},
    {name: "ended archive", overrides: {archiveStatus: "ended"}, reason: "retryableArchive"},
    {name: "unknown terminal state", overrides: {archiveStatus: "complete"}, reason: "unconfirmedTerminalState"},
  ];

  for (const entry of cases) {
    assert.equal(
      protectionReason(
        evaluateLiveAudioProbeRetentionSession(
          rawSession(sessionIds.oldest, entry.overrides),
        ),
      ),
      entry.reason,
      entry.name,
    );
  }
});

test("rejects invalid IDs, unsafe prefixes, sizes, and timestamps", () => {
  assert.equal(
    protectionReason(
      evaluateLiveAudioProbeRetentionSession(
        rawSession("short", {archivePrefix: "liveAudioProbeSessions/short/"}),
      ),
    ),
    "invalidSessionId",
  );
  assert.equal(
    protectionReason(
      evaluateLiveAudioProbeRetentionSession(
        rawSession(sessionIds.oldest, {
          archivePrefix: "liveAudioProbeSessions/../../courseMedia/",
        }),
      ),
    ),
    "unsafeArchivePrefix",
  );
  assert.equal(
    protectionReason(
      evaluateLiveAudioProbeRetentionSession(
        rawSession(sessionIds.oldest, {sizeBytes: 0}),
      ),
    ),
    "invalidSize",
  );
  assert.equal(
    protectionReason(
      evaluateLiveAudioProbeRetentionSession(
        rawSession(sessionIds.oldest, {startedAtMs: 0}),
      ),
    ),
    "invalidStartedAt",
  );
});

test("protects every occurrence of duplicate IDs or prefixes", () => {
  const duplicateIdPlan = planLiveAudioProbeRetention({
    totalBytes: 10 * gb,
    sessions: [
      rawSession(sessionIds.oldest),
      rawSession(sessionIds.oldest, {startedAtMs: 2}),
    ],
  });
  assert.deepEqual(
    duplicateIdPlan.protectedSessions.map((session) => session.reason),
    ["duplicateSession", "duplicateSession"],
  );
  assert.equal(duplicateIdPlan.eligibleSessions.length, 0);

  const duplicatePrefix = expectedLiveAudioProbeRawPrefix(sessionIds.oldest);
  assert.ok(duplicatePrefix);
  const duplicatePrefixPlan = planLiveAudioProbeRetention({
    totalBytes: 10 * gb,
    sessions: [
      rawSession(sessionIds.oldest),
      rawSession(sessionIds.middle, {archivePrefix: duplicatePrefix}),
    ],
  });
  assert.deepEqual(
    duplicatePrefixPlan.protectedSessions.map((session) => session.reason),
    ["duplicateSession", "duplicateSession"],
  );
});

test("requires a verified exact MP4 copy for linked sessions", () => {
  const links = {
    courseId: "course-1",
    lessonId: "lesson-1",
    segmentId: "segment-1",
  };
  const expectedCopyPath = expectedLinkedArchiveCopyPath({
    sessionId: sessionIds.oldest,
    ...links,
  });
  assert.ok(expectedCopyPath);

  assert.equal(
    evaluateLiveAudioProbeRetentionSession(
      rawSession(sessionIds.oldest),
    ).eligible,
    true,
    "unlinked terminal sessions do not require a completed copy",
  );
  assert.equal(
    protectionReason(
      evaluateLiveAudioProbeRetentionSession(
        rawSession(sessionIds.oldest, {courseId: links.courseId}),
      ),
    ),
    "partialOrInvalidLessonLinks",
  );
  assert.equal(
    protectionReason(
      evaluateLiveAudioProbeRetentionSession(
        rawSession(sessionIds.oldest, {
          ...links,
          completedCopyExists: false,
          completedCopyObjectPath: expectedCopyPath,
        }),
      ),
    ),
    "completedCopyNotVerified",
  );
  assert.equal(
    protectionReason(
      evaluateLiveAudioProbeRetentionSession(
        rawSession(sessionIds.oldest, {
          ...links,
          completedCopyExists: true,
          completedCopyObjectPath: `${expectedCopyPath}.wrong`,
        }),
      ),
    ),
    "completedCopyPathMismatch",
  );
  assert.equal(
    evaluateLiveAudioProbeRetentionSession(
      rawSession(sessionIds.oldest, {
        ...links,
        completedCopyExists: true,
        completedCopyObjectPath: expectedCopyPath,
      }),
    ).eligible,
    true,
  );
});

type StoredDocument = Record<string, unknown>;

function storedSession(
  sessionId: string,
  startedAtMs: number,
  overrides: StoredDocument = {},
): StoredDocument {
  return {
    archivePrefix: expectedLiveAudioProbeRawPrefix(sessionId),
    startedAtMs,
    status: "draftReady",
    state: "draftReady",
    archiveStatus: "draftReady",
    ...overrides,
  };
}

class FakeFirestore {
  readonly readCounts = new Map<string, number>();

  constructor(
    private readonly documents: Record<
      string,
      StoredDocument | readonly StoredDocument[]
    >,
  ) {}

  collection(name: string) {
    assert.equal(name, "liveAudioProbeSessions");
    return {
      doc: (sessionId: string) => ({
        get: async () => {
          const configured = this.documents[sessionId];
          const sequence = Array.isArray(configured) ? configured : [configured];
          const readCount = this.readCounts.get(sessionId) ?? 0;
          this.readCounts.set(sessionId, readCount + 1);
          const data = sequence[
            Math.min(readCount, Math.max(0, sequence.length - 1))
          ];
          return {
            exists: data !== undefined,
            data: () => data,
          };
        },
      }),
    };
  }

  asFirestore(): Firestore {
    return this as unknown as Firestore;
  }
}

type FakeRawObject = {
  name: string;
  sizeBytes: number;
  generation: string;
  deleteError?: Error;
};

class FakeRawBucket {
  readonly deleteCalls: Array<{
    name: string;
    generation: string | undefined;
    ignoreNotFound: boolean | undefined;
  }> = [];

  constructor(readonly objects: FakeRawObject[]) {}

  async getFiles(options: {
    prefix?: string;
    pageToken?: string;
  }) {
    assert.equal(options.pageToken, undefined);
    const prefix = options.prefix ?? "";
    const files = this.objects
      .filter((object) => object.name.startsWith(prefix))
      .map((object) => ({
        name: object.name,
        generation: object.generation,
        metadata: {
          size: String(object.sizeBytes),
          generation: object.generation,
        },
      }));
    return [files, null] as const;
  }

  file(name: string, options?: {generation?: string}) {
    return {
      delete: async ({ignoreNotFound}: {ignoreNotFound?: boolean}) => {
        this.deleteCalls.push({
          name,
          generation: options?.generation,
          ignoreNotFound,
        });
        const index = this.objects.findIndex(
          (object) =>
            object.name === name &&
            object.generation === options?.generation,
        );
        if (index < 0) {
          if (ignoreNotFound) {
            return;
          }
          throw new Error("Object not found");
        }
        const object = this.objects[index];
        if (object.deleteError !== undefined) {
          throw object.deleteError;
        }
        this.objects.splice(index, 1);
      },
    };
  }

  asBucket(): Bucket {
    return this as unknown as Bucket;
  }
}

type CompletedCopyMetadata = {
  contentType?: string;
  metadata?: Record<string, string>;
};

class FakeCompletedCopyBucket {
  readonly metadataCalls: string[] = [];

  constructor(
    private readonly metadataByPath:
      Record<string, CompletedCopyMetadata | undefined> = {},
  ) {}

  file(path: string) {
    return {
      getMetadata: async () => {
        this.metadataCalls.push(path);
        const metadata = this.metadataByPath[path];
        if (metadata === undefined) {
          throw Object.assign(new Error("Not found"), {code: 404});
        }
        return [metadata];
      },
    };
  }

  asBucket(): Bucket {
    return this as unknown as Bucket;
  }
}

function rawObject(
  sessionId: string,
  sizeBytes: number,
  suffix = "archive.m3u8",
  generation = "1",
): FakeRawObject {
  const prefix = expectedLiveAudioProbeRawPrefix(sessionId);
  assert.ok(prefix);
  return {
    name: `${prefix}${suffix}`,
    sizeBytes,
    generation,
  };
}

test("runtime plan verifies completed-copy metadata and never deletes", async () => {
  const goodLinks = {
    courseId: "course-good",
    lessonId: "lesson-good",
    segmentId: "segment-good",
  };
  const badLinks = {
    courseId: "course-bad",
    lessonId: "lesson-bad",
    segmentId: "segment-bad",
  };
  const goodPath = expectedLinkedArchiveCopyPath({
    sessionId: sessionIds.oldest,
    ...goodLinks,
  });
  const badPath = expectedLinkedArchiveCopyPath({
    sessionId: sessionIds.middle,
    ...badLinks,
  });
  assert.ok(goodPath);
  assert.ok(badPath);

  const rawBucket = new FakeRawBucket([
    rawObject(sessionIds.oldest, 5 * gb, "good.mp4", "11"),
    rawObject(sessionIds.middle, 5 * gb, "bad.mp4", "12"),
  ]);
  const db = new FakeFirestore({
    [sessionIds.oldest]: storedSession(sessionIds.oldest, 100, {
      ...goodLinks,
      archivePlaybackObjectPath: goodPath,
      draftReady: {storageObjectPath: goodPath},
    }),
    [sessionIds.middle]: storedSession(sessionIds.middle, 200, {
      ...badLinks,
      archivePlaybackObjectPath: badPath,
      draftReady: {storageObjectPath: badPath},
    }),
  });
  const completedCopyBucket = new FakeCompletedCopyBucket({
    [goodPath]: {
      contentType: "video/mp4",
      metadata: {liveSessionId: sessionIds.oldest},
    },
    [badPath]: {
      contentType: "video/mp4",
      metadata: {liveSessionId: sessionIds.oldest},
    },
  });

  const result = await runLiveAudioProbeRawRetention({
    db: db.asFirestore(),
    rawBucket: rawBucket.asBucket(),
    completedCopyBucket: completedCopyBucket.asBucket(),
    mode: "plan",
  });

  assert.equal(result.plan.cleanupTriggered, true);
  assert.deepEqual(
    result.plan.eligibleSessions.map((session) => session.sessionId),
    [sessionIds.oldest],
  );
  assert.deepEqual(
    result.plan.protectedSessions.map((session) => ({
      sessionId: session.sessionId,
      reason: session.reason,
    })),
    [{
      sessionId: sessionIds.middle,
      reason: "completedCopyNotVerified",
    }],
  );
  assert.deepEqual(completedCopyBucket.metadataCalls.sort(), [badPath, goodPath]);
  assert.equal(rawBucket.deleteCalls.length, 0);
  assert.equal(result.deletedBytes, 0);
  assert.equal(result.remainingBytes, 10 * gb);
  assert.equal(result.targetReached, true);
});

test("runtime protects unsafe object names without deleting them", async () => {
  const prefix = expectedLiveAudioProbeRawPrefix(sessionIds.oldest);
  assert.ok(prefix);
  const rawBucket = new FakeRawBucket([
    {
      name: `${prefix}../courseMedia/escape.mp4`,
      sizeBytes: 6 * gb,
      generation: "21",
    },
    rawObject(sessionIds.middle, 4 * gb, "safe.m3u8", "22"),
  ]);
  const db = new FakeFirestore({
    [sessionIds.oldest]: storedSession(sessionIds.oldest, 100),
    [sessionIds.middle]: storedSession(sessionIds.middle, 200),
  });

  const result = await runLiveAudioProbeRawRetention({
    db: db.asFirestore(),
    rawBucket: rawBucket.asBucket(),
    completedCopyBucket: new FakeCompletedCopyBucket().asBucket(),
    mode: "plan",
  });

  assert.deepEqual(
    result.plan.protectedSessions.map((session) => ({
      sessionId: session.sessionId,
      reason: session.reason,
    })),
    [{
      sessionId: sessionIds.oldest,
      reason: "unsafeArchivePrefix",
    }],
  );
  assert.deepEqual(
    result.plan.selectedSessions.map((session) => session.sessionId),
    [sessionIds.middle],
  );
  assert.equal(result.plan.targetReached, false);
  assert.equal(rawBucket.deleteCalls.length, 0);
});

test("runtime allEligible plan and apply work below threshold", async () => {
  const rawBucket = new FakeRawBucket([
    rawObject(sessionIds.oldest, gb, "old.m3u8", "25"),
    rawObject(sessionIds.middle, gb, "middle.m3u8", "26"),
  ]);
  const db = new FakeFirestore({
    [sessionIds.oldest]: storedSession(sessionIds.oldest, 100),
    [sessionIds.middle]: storedSession(sessionIds.middle, 200),
  });
  const commonOptions = {
    db: db.asFirestore(),
    rawBucket: rawBucket.asBucket(),
    completedCopyBucket: new FakeCompletedCopyBucket().asBucket(),
    selectionPolicy: "allEligible" as const,
  };

  const planned = await runLiveAudioProbeRawRetention({
    ...commonOptions,
    mode: "plan",
  });
  assert.equal(planned.plan.cleanupTriggered, false);
  assert.deepEqual(
    planned.plan.selectedSessions.map((session) => session.sessionId),
    [sessionIds.oldest, sessionIds.middle],
  );
  assert.equal(rawBucket.deleteCalls.length, 0);

  const applied = await runLiveAudioProbeRawRetention({
    ...commonOptions,
    mode: "apply",
  });
  assert.deepEqual(
    applied.sessionResults.map((session) => session.status),
    ["deleted", "deleted"],
  );
  assert.equal(applied.deletedBytes, 2 * gb);
  assert.equal(applied.remainingBytes, 0);
  assert.equal(applied.targetReached, true);
});

test("runtime apply revalidates state and uses generation-scoped deletion", async () => {
  const rawBucket = new FakeRawBucket([
    rawObject(sessionIds.oldest, 4 * gb, "old.m3u8", "31"),
    rawObject(sessionIds.middle, 3 * gb, "middle.m3u8", "32"),
    rawObject(sessionIds.newest, 3 * gb, "new.m3u8", "33"),
  ]);
  const db = new FakeFirestore({
    [sessionIds.oldest]: [
      storedSession(sessionIds.oldest, 100),
      storedSession(sessionIds.oldest, 100, {status: "active"}),
    ],
    [sessionIds.middle]: storedSession(sessionIds.middle, 200),
    [sessionIds.newest]: storedSession(sessionIds.newest, 300),
  });

  const result = await runLiveAudioProbeRawRetention({
    db: db.asFirestore(),
    rawBucket: rawBucket.asBucket(),
    completedCopyBucket: new FakeCompletedCopyBucket().asBucket(),
    mode: "apply",
  });

  assert.deepEqual(
    result.plan.selectedSessions.map((session) => session.sessionId),
    [sessionIds.oldest, sessionIds.middle],
    "the original plan stops after its first two oldest sessions",
  );
  assert.deepEqual(
    result.sessionResults.map((session) => ({
      sessionId: session.sessionId,
      status: session.status,
      reason: session.reason,
    })),
    [
      {
        sessionId: sessionIds.oldest,
        status: "skipped",
        reason: "liveOrRecording",
      },
      {
        sessionId: sessionIds.middle,
        status: "deleted",
        reason: undefined,
      },
      {
        sessionId: sessionIds.newest,
        status: "deleted",
        reason: undefined,
      },
    ],
    "apply continues to a later safe session after re-protecting the oldest",
  );
  assert.deepEqual(rawBucket.deleteCalls, [
    {
      name: `${expectedLiveAudioProbeRawPrefix(sessionIds.middle)}middle.m3u8`,
      generation: "32",
      ignoreNotFound: true,
    },
    {
      name: `${expectedLiveAudioProbeRawPrefix(sessionIds.newest)}new.m3u8`,
      generation: "33",
      ignoreNotFound: true,
    },
  ]);
  assert.deepEqual(
    rawBucket.objects.map((object) => object.name),
    [`${expectedLiveAudioProbeRawPrefix(sessionIds.oldest)}old.m3u8`],
  );
  assert.equal(result.deletedBytes, 6 * gb);
  assert.equal(result.remainingBytes, 4 * gb);
  assert.equal(result.targetReached, true);
});
