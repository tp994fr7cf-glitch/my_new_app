import type {Bucket, File} from "@google-cloud/storage";
import type {DocumentData, Firestore} from "firebase-admin/firestore";

import {
  LIVE_AUDIO_PROBE_RAW_PREFIX_ROOT,
  RAW_ARCHIVE_CLEANUP_TARGET_BYTES,
  evaluateCourseDeletedRawCleanupSession,
  evaluateLiveAudioProbeRetentionSession,
  expectedLinkedArchiveCopyPath,
  expectedLiveAudioProbeRawPrefix,
  LiveAudioProbeRawSession,
  LiveAudioProbeRetentionPlan,
  LiveAudioProbeRetentionProtectionReason,
  LiveAudioProbeRetentionSelectionPolicy,
  planLiveAudioProbeRetention,
} from "./live_audio_probe_retention";

const rawListPrefix = `${LIVE_AUDIO_PROBE_RAW_PREFIX_ROOT}/`;
const inventoryPageSize = 1000;
const storageConcurrency = 20;

type RawObject = {
  name: string;
  sizeBytes: number;
  generation: string;
};

type RawSessionGroup = {
  sessionId: string;
  archivePrefix: string;
  sizeBytes: number;
  objectCount: number;
  hasUnsafeObjectName: boolean;
};

export type LiveAudioProbeRawRetentionMode = "plan" | "apply";

export type LiveAudioProbeRawRetentionLogEntry = {
  event:
    | "inventory_complete"
    | "cleanup_not_triggered"
    | "cleanup_planned"
    | "session_deleted"
    | "session_skipped"
    | "session_partially_deleted"
    | "cleanup_complete"
    | "deleted_course_cleanup_complete"
    | "course_raw_cleanup_complete";
  [key: string]: unknown;
};

export type CourseRawArchiveCleanupMode = "check" | "delete";

export class CourseLiveArchiveInProgressError extends Error {
  constructor(
    readonly reason: Extract<
      LiveAudioProbeRetentionProtectionReason,
      "liveOrRecording" | "finalizing"
    >,
    readonly sessionId: string,
  ) {
    super("配信を終了してから削除してください。");
    this.name = "CourseLiveArchiveInProgressError";
  }
}

export type CourseRawArchiveCleanupResult = {
  courseId: string;
  mode: CourseRawArchiveCleanupMode;
  sessionCount: number;
  deletedSessionCount: number;
  deletedBytes: number;
  deletedObjectCount: number;
  sessionResults: LiveAudioProbeRawRetentionSessionResult[];
};

export type DeletedCourseRawArchiveCleanupResult = {
  deletedBytes: number;
  deletedObjectCount: number;
  sessionResults: LiveAudioProbeRawRetentionSessionResult[];
};

export type LiveAudioProbeRawRetentionSessionResult = {
  sessionId: string;
  archivePrefix: string;
  status: "deleted" | "skipped" | "partiallyDeleted";
  plannedBytes: number;
  deletedBytes: number;
  deletedObjectCount: number;
  remainingBytes: number;
  remainingObjectCount: number;
  reason?: LiveAudioProbeRetentionProtectionReason | "deleteFailed";
  errorName?: string;
};

export type LiveAudioProbeRawRetentionResult = {
  mode: LiveAudioProbeRawRetentionMode;
  plan: LiveAudioProbeRetentionPlan;
  inventoryObjectCount: number;
  unassignedObjectCount: number;
  unassignedBytes: number;
  protectedBytes: number;
  deletedBytes: number;
  deletedObjectCount: number;
  remainingBytes: number;
  targetReached: boolean;
  sessionResults: LiveAudioProbeRawRetentionSessionResult[];
};

export type LiveAudioProbeRawRetentionOptions = {
  db: Firestore;
  rawBucket: Bucket;
  completedCopyBucket: Bucket;
  mode: LiveAudioProbeRawRetentionMode;
  selectionPolicy?: LiveAudioProbeRetentionSelectionPolicy;
  log?: (entry: LiveAudioProbeRawRetentionLogEntry) => void;
};

/**
 * Shared plan/apply API for the scheduled Function and the later admin script.
 * All deletion paths are derived from a validated session ID and are re-read
 * from Storage and Firestore immediately before generation-scoped deletion.
 * Threshold selection is the fail-safe default; one-time cleanup must opt in
 * explicitly with selectionPolicy: "allEligible".
 */
export async function runLiveAudioProbeRawRetention({
  db,
  rawBucket,
  completedCopyBucket,
  mode,
  selectionPolicy = "threshold",
  log = () => undefined,
}: LiveAudioProbeRawRetentionOptions): Promise<
  LiveAudioProbeRawRetentionResult
> {
  const inventory = await inventoryRawArchive(rawBucket);
  const sessions = await mapWithConcurrency(
    inventory.sessionGroups,
    storageConcurrency,
    (group) => retentionSessionFromStoredState({
      db,
      completedCopyBucket,
      group,
    }),
  );
  const plan = planLiveAudioProbeRetention({
    totalBytes: inventory.totalBytes,
    sessions,
    selectionPolicy,
  });
  const protectedBytes =
    inventory.unassignedBytes +
    plan.protectedSessions.reduce(
      (total, session) => total + session.sizeBytes,
      0,
    );

  log({
    event: "inventory_complete",
    mode,
    selectionPolicy,
    totalBytes: inventory.totalBytes,
    objectCount: inventory.objectCount,
    sessionCount: inventory.sessionGroups.length,
    eligibleSessionCount: plan.eligibleSessions.length,
    protectedSessionCount: plan.protectedSessions.length,
    protectedBytes,
    unassignedObjectCount: inventory.unassignedObjectCount,
    unassignedBytes: inventory.unassignedBytes,
    cleanupTriggered: plan.cleanupTriggered,
    hardLimitExceeded: plan.hardLimitExceeded,
  });

  if (selectionPolicy === "threshold" && !plan.cleanupTriggered) {
    log({
      event: "cleanup_not_triggered",
      mode,
      selectionPolicy,
      totalBytes: inventory.totalBytes,
    });
    return {
      mode,
      plan,
      inventoryObjectCount: inventory.objectCount,
      unassignedObjectCount: inventory.unassignedObjectCount,
      unassignedBytes: inventory.unassignedBytes,
      protectedBytes,
      deletedBytes: 0,
      deletedObjectCount: 0,
      remainingBytes: inventory.totalBytes,
      targetReached: true,
      sessionResults: [],
    };
  }

  log({
    event: "cleanup_planned",
    mode,
    selectionPolicy,
    totalBytes: plan.totalBytes,
    targetBytes: RAW_ARCHIVE_CLEANUP_TARGET_BYTES,
    selectedSessionCount: plan.selectedSessions.length,
    selectedBytes: plan.selectedBytes,
    projectedBytes: plan.projectedBytes,
    targetReached: plan.targetReached,
  });

  if (mode === "plan") {
    return {
      mode,
      plan,
      inventoryObjectCount: inventory.objectCount,
      unassignedObjectCount: inventory.unassignedObjectCount,
      unassignedBytes: inventory.unassignedBytes,
      protectedBytes,
      deletedBytes: 0,
      deletedObjectCount: 0,
      remainingBytes: inventory.totalBytes,
      targetReached: plan.targetReached,
      sessionResults: [],
    };
  }

  const sessionResults: LiveAudioProbeRawRetentionSessionResult[] = [];
  let estimatedRemainingBytes = inventory.totalBytes;
  let deletedBytes = 0;
  let deletedObjectCount = 0;

  // eligibleSessions is already sorted oldest-first by the pure core. Threshold
  // mode can continue past its initial selection when revalidation protects a
  // candidate. allEligible mode deliberately processes every eligible session.
  for (const candidate of plan.eligibleSessions) {
    if (
      selectionPolicy === "threshold" &&
      estimatedRemainingBytes <= RAW_ARCHIVE_CLEANUP_TARGET_BYTES
    ) {
      break;
    }
    const result = await revalidateAndDeleteSession({
      db,
      rawBucket,
      completedCopyBucket,
      sessionId: candidate.sessionId,
      plannedBytes: candidate.sizeBytes,
    });
    sessionResults.push(result);
    deletedBytes += result.deletedBytes;
    deletedObjectCount += result.deletedObjectCount;
    estimatedRemainingBytes = Math.max(
      0,
      estimatedRemainingBytes - result.deletedBytes,
    );

    log({
      event:
        result.status === "deleted" ?
          "session_deleted" :
          result.status === "partiallyDeleted" ?
            "session_partially_deleted" :
            "session_skipped",
      ...result,
    });
  }

  // A fresh listing is the source of truth after generation-scoped deletes and
  // also accounts for objects concurrently added or removed during this run.
  const finalInventory = await inventoryRawArchive(rawBucket);
  const targetReached = selectionPolicy === "allEligible" ?
    sessionResults.length === plan.eligibleSessions.length &&
      sessionResults.every((session) => session.status === "deleted") :
    finalInventory.totalBytes <= RAW_ARCHIVE_CLEANUP_TARGET_BYTES;
  const result: LiveAudioProbeRawRetentionResult = {
    mode,
    plan,
    inventoryObjectCount: inventory.objectCount,
    unassignedObjectCount: inventory.unassignedObjectCount,
    unassignedBytes: inventory.unassignedBytes,
    protectedBytes,
    deletedBytes,
    deletedObjectCount,
    remainingBytes: finalInventory.totalBytes,
    targetReached,
    sessionResults,
  };
  log({
    event: "cleanup_complete",
    mode,
    selectionPolicy,
    originalBytes: inventory.totalBytes,
    deletedBytes,
    deletedObjectCount,
    remainingBytes: finalInventory.totalBytes,
    protectedBytes,
    targetReached,
    deletedSessionCount: sessionResults.filter(
      (session) => session.status === "deleted",
    ).length,
    skippedSessionCount: sessionResults.filter(
      (session) => session.status === "skipped",
    ).length,
    partiallyDeletedSessionCount: sessionResults.filter(
      (session) => session.status === "partiallyDeleted",
    ).length,
  });
  return result;
}

export async function cleanupRawArchivesForCourse({
  db,
  rawBucket,
  courseId,
  mode,
  refuseIfLive = true,
  log = () => undefined,
}: {
  db: Firestore;
  rawBucket: Bucket;
  courseId: string;
  mode: CourseRawArchiveCleanupMode;
  refuseIfLive?: boolean;
  log?: (entry: LiveAudioProbeRawRetentionLogEntry) => void;
}): Promise<CourseRawArchiveCleanupResult> {
  const snapshot = await db
    .collection(LIVE_AUDIO_PROBE_RAW_PREFIX_ROOT)
    .where("courseId", "==", courseId)
    .get();
  const sessions = snapshot.docs.map((doc) => {
    const data = doc.data() ?? {};
    const expectedPrefix = expectedLiveAudioProbeRawPrefix(doc.id);
    return {
      sessionId: doc.id,
      archivePrefix: stringField(data.archivePrefix) || expectedPrefix || "",
      sizeBytes: 0,
      startedAtMs: numberField(data.startedAtMs),
      status: data.status,
      state: data.state,
      archiveStatus: data.archiveStatus,
      courseId: data.courseId,
      lessonId: data.lessonId,
      segmentId: data.segmentId,
    } satisfies LiveAudioProbeRawSession;
  });

  for (const session of sessions) {
    const decision = evaluateCourseDeletedRawCleanupSession(session);
    if (
      !decision.eligible &&
      (decision.protected.reason === "liveOrRecording" ||
        decision.protected.reason === "finalizing")
    ) {
      if (refuseIfLive) {
        throw new CourseLiveArchiveInProgressError(
          decision.protected.reason,
          session.sessionId,
        );
      }
    }
  }

  if (mode === "check") {
    return {
      courseId,
      mode,
      sessionCount: sessions.length,
      deletedSessionCount: 0,
      deletedBytes: 0,
      deletedObjectCount: 0,
      sessionResults: [],
    };
  }

  const sessionResults: LiveAudioProbeRawRetentionSessionResult[] = [];
  for (const session of sessions) {
    const decision = evaluateCourseDeletedRawCleanupSession(session);
    if (!decision.eligible) {
      sessionResults.push(skippedSessionResult({
        sessionId: session.sessionId,
        archivePrefix: session.archivePrefix,
        plannedBytes: 0,
        reason: decision.protected.reason,
      }));
      continue;
    }
    sessionResults.push(
      await deleteRawSessionPrefixIfSafe({
        rawBucket,
        sessionId: session.sessionId,
        plannedBytes: 0,
      }),
    );
  }

  const deletedSessions = sessionResults.filter(
    (session) => session.status === "deleted",
  );
  const result: CourseRawArchiveCleanupResult = {
    courseId,
    mode,
    sessionCount: sessions.length,
    deletedSessionCount: deletedSessions.length,
    deletedBytes: sessionResults.reduce(
      (total, session) => total + session.deletedBytes,
      0,
    ),
    deletedObjectCount: sessionResults.reduce(
      (total, session) => total + session.deletedObjectCount,
      0,
    ),
    sessionResults,
  };
  log({
    event: "course_raw_cleanup_complete",
    ...result,
  });
  return result;
}

export async function runDeletedCourseRawArchiveCleanup({
  db,
  rawBucket,
  log = () => undefined,
}: {
  db: Firestore;
  rawBucket: Bucket;
  log?: (entry: LiveAudioProbeRawRetentionLogEntry) => void;
}): Promise<DeletedCourseRawArchiveCleanupResult> {
  const inventory = await inventoryRawArchive(rawBucket);
  const sessionResults: LiveAudioProbeRawRetentionSessionResult[] = [];

  for (const group of inventory.sessionGroups) {
    const snapshot = await db
      .collection(LIVE_AUDIO_PROBE_RAW_PREFIX_ROOT)
      .doc(group.sessionId)
      .get();
    const data = snapshot.exists ? snapshot.data() ?? {} : {};
    const courseId = stringField(data.courseId);
    if (courseId === "") {
      continue;
    }
    const courseSnapshot = await db.collection("courses").doc(courseId).get();
    const courseStatus = courseSnapshot.exists ?
      stringField(courseSnapshot.data()?.status) :
      "deleted";
    if (
      courseSnapshot.exists &&
      courseStatus !== "deleting" &&
      courseStatus !== "deleted"
    ) {
      continue;
    }
    if (group.hasUnsafeObjectName) {
      sessionResults.push(skippedSessionResult({
        sessionId: group.sessionId,
        archivePrefix: group.archivePrefix,
        plannedBytes: group.sizeBytes,
        remainingBytes: group.sizeBytes,
        remainingObjectCount: group.objectCount,
        reason: "unsafeArchivePrefix",
      }));
      continue;
    }
    const session: LiveAudioProbeRawSession = {
      sessionId: group.sessionId,
      archivePrefix: stringField(data.archivePrefix) || group.archivePrefix,
      sizeBytes: group.sizeBytes,
      startedAtMs: numberField(data.startedAtMs),
      status: data.status,
      state: data.state,
      archiveStatus: data.archiveStatus,
      courseId,
    };
    const decision = evaluateCourseDeletedRawCleanupSession(session);
    if (!decision.eligible) {
      sessionResults.push(skippedSessionResult({
        sessionId: group.sessionId,
        archivePrefix: group.archivePrefix,
        plannedBytes: group.sizeBytes,
        remainingBytes: group.sizeBytes,
        remainingObjectCount: group.objectCount,
        reason: decision.protected.reason,
      }));
      continue;
    }
    sessionResults.push(
      await deleteRawSessionPrefixIfSafe({
        rawBucket,
        sessionId: group.sessionId,
        plannedBytes: group.sizeBytes,
      }),
    );
  }

  const result: DeletedCourseRawArchiveCleanupResult = {
    deletedBytes: sessionResults.reduce(
      (total, session) => total + session.deletedBytes,
      0,
    ),
    deletedObjectCount: sessionResults.reduce(
      (total, session) => total + session.deletedObjectCount,
      0,
    ),
    sessionResults,
  };
  log({
    event: "deleted_course_cleanup_complete",
    inspectedSessionCount: inventory.sessionGroups.length,
    cleanedSessionCount: sessionResults.length,
    deletedBytes: result.deletedBytes,
    deletedObjectCount: result.deletedObjectCount,
    skippedSessionCount: sessionResults.filter(
      (session) => session.status === "skipped",
    ).length,
  });
  return result;
}

async function retentionSessionFromStoredState({
  db,
  completedCopyBucket,
  group,
}: {
  db: Firestore;
  completedCopyBucket: Bucket;
  group: RawSessionGroup;
}): Promise<LiveAudioProbeRawSession> {
  const snapshot = await db
    .collection(LIVE_AUDIO_PROBE_RAW_PREFIX_ROOT)
    .doc(group.sessionId)
    .get();
  const data = snapshot.exists ? snapshot.data() ?? {} : {};
  const completedCopy = await completedCopyVerification({
    completedCopyBucket,
    sessionId: group.sessionId,
    data,
  });
  return {
    sessionId: group.sessionId,
    archivePrefix: group.hasUnsafeObjectName ?
      "" :
      stringField(data.archivePrefix),
    sizeBytes: group.sizeBytes,
    startedAtMs: numberField(data.startedAtMs),
    status: data.status,
    state: data.state,
    archiveStatus: data.archiveStatus,
    courseId: data.courseId,
    lessonId: data.lessonId,
    segmentId: data.segmentId,
    completedCopyExists: completedCopy.exists,
    completedCopyObjectPath: completedCopy.objectPath,
  };
}

async function completedCopyVerification({
  completedCopyBucket,
  sessionId,
  data,
}: {
  completedCopyBucket: Bucket;
  sessionId: string;
  data: DocumentData;
}): Promise<{exists: boolean; objectPath?: string}> {
  const objectPath = stringField(data.archivePlaybackObjectPath) || undefined;
  const expectedPath = expectedLinkedArchiveCopyPath({
    sessionId,
    courseId: stringField(data.courseId),
    lessonId: stringField(data.lessonId),
    segmentId: stringField(data.segmentId),
  });
  if (expectedPath === null) {
    return {exists: false, objectPath};
  }
  const draftReady =
    isRecord(data.draftReady) ? data.draftReady : {};
  if (draftReady.storageObjectPath !== expectedPath) {
    return {exists: false, objectPath};
  }
  try {
    const [metadata] = await completedCopyBucket
      .file(expectedPath)
      .getMetadata();
    const customMetadata = metadata.metadata;
    return {
      exists:
        metadata.contentType === "video/mp4" &&
        customMetadata?.liveSessionId === sessionId,
      objectPath,
    };
  } catch (error) {
    if (isNotFoundError(error)) {
      return {exists: false, objectPath};
    }
    throw error;
  }
}

async function revalidateAndDeleteSession({
  db,
  rawBucket,
  completedCopyBucket,
  sessionId,
  plannedBytes,
}: {
  db: Firestore;
  rawBucket: Bucket;
  completedCopyBucket: Bucket;
  sessionId: string;
  plannedBytes: number;
}): Promise<LiveAudioProbeRawRetentionSessionResult> {
  const expectedPrefix = expectedLiveAudioProbeRawPrefix(sessionId);
  if (expectedPrefix === null) {
    return skippedSessionResult({
      sessionId,
      archivePrefix: "",
      plannedBytes,
      reason: "invalidSessionId",
    });
  }

  const objects = await listRawObjects(rawBucket, expectedPrefix);
  const unsafeObject = objects.find(
    (object) => !isStrictSessionObjectName(object.name, expectedPrefix),
  );
  if (unsafeObject !== undefined) {
    return skippedSessionResult({
      sessionId,
      archivePrefix: expectedPrefix,
      plannedBytes,
      remainingBytes: sumObjectBytes(objects),
      remainingObjectCount: objects.length,
      reason: "unsafeArchivePrefix",
    });
  }
  if (objects.length === 0) {
    return {
      sessionId,
      archivePrefix: expectedPrefix,
      status: "deleted",
      plannedBytes,
      deletedBytes: 0,
      deletedObjectCount: 0,
      remainingBytes: 0,
      remainingObjectCount: 0,
    };
  }

  const currentGroup: RawSessionGroup = {
    sessionId,
    archivePrefix: expectedPrefix,
    sizeBytes: sumObjectBytes(objects),
    objectCount: objects.length,
    hasUnsafeObjectName: false,
  };
  const currentSession = await retentionSessionFromStoredState({
    db,
    completedCopyBucket,
    group: currentGroup,
  });
  const decision = evaluateLiveAudioProbeRetentionSession(currentSession);
  if (!decision.eligible) {
    return skippedSessionResult({
      sessionId,
      archivePrefix: expectedPrefix,
      plannedBytes,
      remainingBytes: currentGroup.sizeBytes,
      remainingObjectCount: currentGroup.objectCount,
      reason: decision.protected.reason,
    });
  }

  return deleteListedRawSessionObjects({
    rawBucket,
    sessionId,
    expectedPrefix,
    objects,
    plannedBytes,
  });
}

async function deleteRawSessionPrefixIfSafe({
  rawBucket,
  sessionId,
  plannedBytes,
}: {
  rawBucket: Bucket;
  sessionId: string;
  plannedBytes: number;
}): Promise<LiveAudioProbeRawRetentionSessionResult> {
  const expectedPrefix = expectedLiveAudioProbeRawPrefix(sessionId);
  if (expectedPrefix === null) {
    return skippedSessionResult({
      sessionId,
      archivePrefix: "",
      plannedBytes,
      reason: "invalidSessionId",
    });
  }

  const objects = await listRawObjects(rawBucket, expectedPrefix);
  const unsafeObject = objects.find(
    (object) => !isStrictSessionObjectName(object.name, expectedPrefix),
  );
  if (unsafeObject !== undefined) {
    return skippedSessionResult({
      sessionId,
      archivePrefix: expectedPrefix,
      plannedBytes,
      remainingBytes: sumObjectBytes(objects),
      remainingObjectCount: objects.length,
      reason: "unsafeArchivePrefix",
    });
  }
  if (objects.length === 0) {
    return {
      sessionId,
      archivePrefix: expectedPrefix,
      status: "deleted",
      plannedBytes,
      deletedBytes: 0,
      deletedObjectCount: 0,
      remainingBytes: 0,
      remainingObjectCount: 0,
    };
  }
  return deleteListedRawSessionObjects({
    rawBucket,
    sessionId,
    expectedPrefix,
    objects,
    plannedBytes,
  });
}

async function deleteListedRawSessionObjects({
  rawBucket,
  sessionId,
  expectedPrefix,
  objects,
  plannedBytes,
}: {
  rawBucket: Bucket;
  sessionId: string;
  expectedPrefix: string;
  objects: readonly RawObject[];
  plannedBytes: number;
}): Promise<LiveAudioProbeRawRetentionSessionResult> {
  const deletions = await mapWithConcurrency(
    objects,
    storageConcurrency,
    async (object) => {
      // Keep the final guard adjacent to the destructive operation.
      if (!isStrictSessionObjectName(object.name, expectedPrefix)) {
        return {object, deleted: false, errorName: "UnsafeArchivePrefix"};
      }
      try {
        await rawBucket
          .file(object.name, {generation: object.generation})
          .delete({ignoreNotFound: true});
        return {object, deleted: true};
      } catch (error) {
        return {object, deleted: false, errorName: errorName(error)};
      }
    },
  );
  const deleted = deletions.filter((entry) => entry.deleted);
  const failed = deletions.filter((entry) => !entry.deleted);
  const remainingObjects = await listRawObjects(rawBucket, expectedPrefix);
  const remainingBytes = sumObjectBytes(remainingObjects);
  const deletedBytes = deleted.reduce(
    (total, entry) => total + entry.object.sizeBytes,
    0,
  );

  if (remainingObjects.length === 0 && failed.length === 0) {
    return {
      sessionId,
      archivePrefix: expectedPrefix,
      status: "deleted",
      plannedBytes,
      deletedBytes,
      deletedObjectCount: deleted.length,
      remainingBytes: 0,
      remainingObjectCount: 0,
    };
  }
  return {
    sessionId,
    archivePrefix: expectedPrefix,
    status: deleted.length > 0 ? "partiallyDeleted" : "skipped",
    plannedBytes,
    deletedBytes,
    deletedObjectCount: deleted.length,
    remainingBytes,
    remainingObjectCount: remainingObjects.length,
    reason: "deleteFailed",
    errorName: failed[0]?.errorName ??
      (remainingObjects.length > 0 ? "ObjectsRemainAfterDelete" : undefined),
  };
}

function skippedSessionResult({
  sessionId,
  archivePrefix,
  plannedBytes,
  remainingBytes = 0,
  remainingObjectCount = 0,
  reason,
}: {
  sessionId: string;
  archivePrefix: string;
  plannedBytes: number;
  remainingBytes?: number;
  remainingObjectCount?: number;
  reason: LiveAudioProbeRetentionProtectionReason;
}): LiveAudioProbeRawRetentionSessionResult {
  return {
    sessionId,
    archivePrefix,
    status: "skipped",
    plannedBytes,
    deletedBytes: 0,
    deletedObjectCount: 0,
    remainingBytes,
    remainingObjectCount,
    reason,
  };
}

async function inventoryRawArchive(rawBucket: Bucket): Promise<{
  totalBytes: number;
  objectCount: number;
  sessionGroups: RawSessionGroup[];
  unassignedObjectCount: number;
  unassignedBytes: number;
}> {
  const objects = await listRawObjects(rawBucket, rawListPrefix);
  const groups = new Map<string, RawSessionGroup>();
  let unassignedObjectCount = 0;
  let unassignedBytes = 0;

  for (const object of objects) {
    const remainder = object.name.slice(rawListPrefix.length);
    const separatorIndex = remainder.indexOf("/");
    const sessionId =
      separatorIndex > 0 ? remainder.slice(0, separatorIndex) : "";
    const archivePrefix = expectedLiveAudioProbeRawPrefix(sessionId);
    if (archivePrefix === null) {
      unassignedObjectCount++;
      unassignedBytes += object.sizeBytes;
      continue;
    }
    const group = groups.get(sessionId) ?? {
      sessionId,
      archivePrefix,
      sizeBytes: 0,
      objectCount: 0,
      hasUnsafeObjectName: false,
    };
    group.sizeBytes += object.sizeBytes;
    group.objectCount++;
    if (!isStrictSessionObjectName(object.name, archivePrefix)) {
      group.hasUnsafeObjectName = true;
    }
    groups.set(sessionId, group);
  }

  return {
    totalBytes: sumObjectBytes(objects),
    objectCount: objects.length,
    sessionGroups: [...groups.values()].filter(
      (group) => group.sizeBytes > 0,
    ),
    unassignedObjectCount,
    unassignedBytes,
  };
}

async function listRawObjects(
  rawBucket: Bucket,
  prefix: string,
): Promise<RawObject[]> {
  if (
    prefix !== rawListPrefix &&
    !isStrictSessionPrefix(prefix)
  ) {
    throw new Error("Refusing to list an unsafe raw archive prefix.");
  }
  const objects: RawObject[] = [];
  let pageToken: string | undefined;
  do {
    const [files, nextQuery] = await rawBucket.getFiles({
      autoPaginate: false,
      maxResults: inventoryPageSize,
      pageToken,
      prefix,
    });
    for (const file of files) {
      if (!file.name.startsWith(prefix)) {
        throw new Error("Storage returned an object outside the requested prefix.");
      }
      objects.push(rawObjectFromFile(file));
    }
    pageToken =
      nextQuery !== null &&
      "pageToken" in nextQuery &&
      typeof nextQuery.pageToken === "string" ?
        nextQuery.pageToken :
        undefined;
  } while (pageToken !== undefined);
  return objects;
}

function rawObjectFromFile(file: File): RawObject {
  const sizeBytes = integerFromStorageMetadata(file.metadata.size);
  const generationValue = file.metadata.generation ?? file.generation;
  const generation =
    typeof generationValue === "string" ?
      generationValue :
      typeof generationValue === "number" ?
        String(generationValue) :
        "";
  if (!/^[1-9][0-9]*$/.test(generation)) {
    throw new Error("Raw archive object has no safe generation.");
  }
  return {name: file.name, sizeBytes, generation};
}

function integerFromStorageMetadata(value: unknown): number {
  const parsed =
    typeof value === "number" ?
      value :
      typeof value === "string" && /^[0-9]+$/.test(value) ?
        Number(value) :
        Number.NaN;
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error("Raw archive object has an invalid size.");
  }
  return parsed;
}

function isStrictSessionPrefix(prefix: string): boolean {
  const sessionId = prefix.slice(rawListPrefix.length, -1);
  return (
    prefix.startsWith(rawListPrefix) &&
    prefix.endsWith("/") &&
    expectedLiveAudioProbeRawPrefix(sessionId) === prefix
  );
}

function isStrictSessionObjectName(name: string, prefix: string): boolean {
  if (!isStrictSessionPrefix(prefix) || !name.startsWith(prefix)) {
    return false;
  }
  if (name.includes("\\") || /[\u0000-\u001f\u007f]/.test(name)) {
    return false;
  }
  const suffix = name.slice(prefix.length);
  return !suffix.split("/").some((part) => part === "." || part === "..");
}

function sumObjectBytes(objects: readonly RawObject[]): number {
  return objects.reduce((total, object) => {
    const next = total + object.sizeBytes;
    if (!Number.isSafeInteger(next)) {
      throw new Error("Raw archive inventory exceeds safe integer range.");
    }
    return next;
  }, 0);
}

async function mapWithConcurrency<T, R>(
  values: readonly T[],
  concurrency: number,
  mapper: (value: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(values.length);
  let nextIndex = 0;
  const workers = Array.from(
    {length: Math.min(concurrency, values.length)},
    async () => {
      while (nextIndex < values.length) {
        const index = nextIndex++;
        results[index] = await mapper(values[index]);
      }
    },
  );
  await Promise.all(workers);
  return results;
}

function stringField(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function numberField(value: unknown): number {
  return typeof value === "number" ? value : 0;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNotFoundError(error: unknown): boolean {
  if (!isRecord(error)) {
    return false;
  }
  return error.code === 404 || error.code === "404";
}

function errorName(error: unknown): string {
  return error instanceof Error ? error.name : "UnknownError";
}
