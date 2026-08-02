export const LIVE_AUDIO_PROBE_RAW_PREFIX_ROOT = "liveAudioProbeSessions";
export const RAW_ARCHIVE_BYTES_PER_GB = 1_000_000_000;
export const RAW_ARCHIVE_HARD_LIMIT_BYTES =
  10 * RAW_ARCHIVE_BYTES_PER_GB;
export const RAW_ARCHIVE_CLEANUP_TRIGGER_BYTES =
  9 * RAW_ARCHIVE_BYTES_PER_GB;
export const RAW_ARCHIVE_CLEANUP_TARGET_BYTES =
  5 * RAW_ARCHIVE_BYTES_PER_GB;

const liveAudioProbeSessionIdPattern = /^[A-Za-z0-9]{20}$/;
const lessonLinkIdPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;

export type LiveAudioProbeRawSession = {
  sessionId: string;
  archivePrefix: string;
  sizeBytes: number;
  startedAtMs: number;
  status: unknown;
  state: unknown;
  archiveStatus: unknown;
  courseId?: unknown;
  lessonId?: unknown;
  segmentId?: unknown;
  completedCopyExists?: boolean;
  completedCopyObjectPath?: string;
};

export type LiveAudioProbeRetentionProtectionReason =
  | "invalidSessionId"
  | "unsafeArchivePrefix"
  | "invalidSize"
  | "invalidStartedAt"
  | "duplicateSession"
  | "liveOrRecording"
  | "finalizing"
  | "retryableArchive"
  | "unconfirmedTerminalState"
  | "partialOrInvalidLessonLinks"
  | "completedCopyNotVerified"
  | "completedCopyPathMismatch";

export type LiveAudioProbeRetentionCandidate = {
  sessionId: string;
  archivePrefix: string;
  sizeBytes: number;
  startedAtMs: number;
};

export type LiveAudioProbeProtectedSession = {
  sessionId: string;
  archivePrefix: string;
  sizeBytes: number;
  reason: LiveAudioProbeRetentionProtectionReason;
};

export type LiveAudioProbeRetentionDecision =
  | {
    eligible: true;
    candidate: LiveAudioProbeRetentionCandidate;
  }
  | {
    eligible: false;
    protected: LiveAudioProbeProtectedSession;
  };

export type LiveAudioProbeRetentionSelectionPolicy =
  | "threshold"
  | "allEligible";

export type LiveAudioProbeRetentionPlan = {
  selectionPolicy: LiveAudioProbeRetentionSelectionPolicy;
  cleanupTriggered: boolean;
  hardLimitExceeded: boolean;
  targetReached: boolean;
  totalBytes: number;
  selectedBytes: number;
  projectedBytes: number;
  eligibleSessions: LiveAudioProbeRetentionCandidate[];
  selectedSessions: LiveAudioProbeRetentionCandidate[];
  protectedSessions: LiveAudioProbeProtectedSession[];
};

export function expectedLiveAudioProbeRawPrefix(
  sessionId: string,
): string | null {
  if (!liveAudioProbeSessionIdPattern.test(sessionId)) {
    return null;
  }
  return `${LIVE_AUDIO_PROBE_RAW_PREFIX_ROOT}/${sessionId}/`;
}

export function expectedLinkedArchiveCopyPath({
  sessionId,
  courseId,
  lessonId,
  segmentId,
}: {
  sessionId: string;
  courseId: string;
  lessonId: string;
  segmentId: string;
}): string | null {
  if (
    !liveAudioProbeSessionIdPattern.test(sessionId) ||
    !lessonLinkIdPattern.test(courseId) ||
    !lessonLinkIdPattern.test(lessonId) ||
    !lessonLinkIdPattern.test(segmentId)
  ) {
    return null;
  }
  return `courseMedia/${courseId}/lessons/${lessonId}/segments/${segmentId}/` +
    `live-${sessionId}.mp4`;
}

export function evaluateLiveAudioProbeRetentionSession(
  session: LiveAudioProbeRawSession,
): LiveAudioProbeRetentionDecision {
  const protect = (
    reason: LiveAudioProbeRetentionProtectionReason,
  ): LiveAudioProbeRetentionDecision => ({
    eligible: false,
    protected: {
      sessionId: session.sessionId,
      archivePrefix: session.archivePrefix,
      sizeBytes: safeReportableBytes(session.sizeBytes),
      reason,
    },
  });

  const expectedPrefix = expectedLiveAudioProbeRawPrefix(session.sessionId);
  if (expectedPrefix === null) {
    return protect("invalidSessionId");
  }
  if (session.archivePrefix !== expectedPrefix) {
    return protect("unsafeArchivePrefix");
  }
  if (!isPositiveSafeInteger(session.sizeBytes)) {
    return protect("invalidSize");
  }
  if (!isPositiveSafeInteger(session.startedAtMs)) {
    return protect("invalidStartedAt");
  }

  const lifecycleValues = [session.status, session.state, session.archiveStatus];
  if (
    lifecycleValues.some((value) => value === "active" || value === "live") ||
    session.archiveStatus === "starting" ||
    session.archiveStatus === "recording" ||
    session.archiveStatus === "available"
  ) {
    return protect("liveOrRecording");
  }
  if (
    lifecycleValues.includes("finalizing") ||
    session.archiveStatus === "stopping"
  ) {
    return protect("finalizing");
  }
  if (
    lifecycleValues.some(
      (value) =>
        value === "archiveFailed" ||
        value === "failed" ||
        value === "ended",
    )
  ) {
    return protect("retryableArchive");
  }
  if (!lifecycleValues.every((value) => value === "draftReady")) {
    return protect("unconfirmedTerminalState");
  }

  const rawLinks = [session.courseId, session.lessonId, session.segmentId];
  const presentLinks = rawLinks.filter(isNonEmptyString);
  if (presentLinks.length !== 0 && presentLinks.length !== rawLinks.length) {
    return protect("partialOrInvalidLessonLinks");
  }
  if (presentLinks.length === rawLinks.length) {
    const [courseId, lessonId, segmentId] = presentLinks;
    const expectedCopyPath = expectedLinkedArchiveCopyPath({
      sessionId: session.sessionId,
      courseId,
      lessonId,
      segmentId,
    });
    if (expectedCopyPath === null) {
      return protect("partialOrInvalidLessonLinks");
    }
    if (session.completedCopyExists !== true) {
      return protect("completedCopyNotVerified");
    }
    if (session.completedCopyObjectPath !== expectedCopyPath) {
      return protect("completedCopyPathMismatch");
    }
  }

  return {
    eligible: true,
    candidate: {
      sessionId: session.sessionId,
      archivePrefix: expectedPrefix,
      sizeBytes: session.sizeBytes,
      startedAtMs: session.startedAtMs,
    },
  };
}

export function planLiveAudioProbeRetention({
  totalBytes,
  sessions,
  selectionPolicy = "threshold",
}: {
  totalBytes: number;
  sessions: readonly LiveAudioProbeRawSession[];
  selectionPolicy?: LiveAudioProbeRetentionSelectionPolicy;
}): LiveAudioProbeRetentionPlan {
  if (!isNonNegativeSafeInteger(totalBytes)) {
    throw new RangeError("totalBytes must be a non-negative safe integer.");
  }
  if (selectionPolicy !== "threshold" && selectionPolicy !== "allEligible") {
    throw new RangeError("selectionPolicy must be threshold or allEligible.");
  }

  const duplicateSessionIds = duplicateValues(
    sessions.map((session) => session.sessionId),
  );
  const duplicatePrefixes = duplicateValues(
    sessions.map((session) => session.archivePrefix),
  );
  const eligibleSessions: LiveAudioProbeRetentionCandidate[] = [];
  const protectedSessions: LiveAudioProbeProtectedSession[] = [];

  for (const session of sessions) {
    if (
      duplicateSessionIds.has(session.sessionId) ||
      duplicatePrefixes.has(session.archivePrefix)
    ) {
      protectedSessions.push({
        sessionId: session.sessionId,
        archivePrefix: session.archivePrefix,
        sizeBytes: safeReportableBytes(session.sizeBytes),
        reason: "duplicateSession",
      });
      continue;
    }
    const decision = evaluateLiveAudioProbeRetentionSession(session);
    if (decision.eligible) {
      eligibleSessions.push(decision.candidate);
    } else {
      protectedSessions.push(decision.protected);
    }
  }

  eligibleSessions.sort(
    (left, right) =>
      left.startedAtMs - right.startedAtMs ||
      left.sessionId.localeCompare(right.sessionId),
  );

  const cleanupTriggered = totalBytes > RAW_ARCHIVE_CLEANUP_TRIGGER_BYTES;
  const selectedSessions: LiveAudioProbeRetentionCandidate[] = [];
  let selectedBytes = 0;
  if (selectionPolicy === "allEligible") {
    selectedSessions.push(...eligibleSessions);
    selectedBytes = eligibleSessions.reduce(
      (total, session) => total + session.sizeBytes,
      0,
    );
  } else if (cleanupTriggered) {
    for (const session of eligibleSessions) {
      if (totalBytes - selectedBytes <= RAW_ARCHIVE_CLEANUP_TARGET_BYTES) {
        break;
      }
      selectedSessions.push(session);
      selectedBytes += session.sizeBytes;
    }
  }
  const projectedBytes = Math.max(0, totalBytes - selectedBytes);

  return {
    selectionPolicy,
    cleanupTriggered,
    hardLimitExceeded: totalBytes > RAW_ARCHIVE_HARD_LIMIT_BYTES,
    targetReached:
      selectionPolicy === "allEligible" ||
      !cleanupTriggered ||
      projectedBytes <= RAW_ARCHIVE_CLEANUP_TARGET_BYTES,
    totalBytes,
    selectedBytes,
    projectedBytes,
    eligibleSessions,
    selectedSessions,
    protectedSessions,
  };
}

function duplicateValues(values: readonly string[]): ReadonlySet<string> {
  const seen = new Set<string>();
  const duplicates = new Set<string>();
  for (const value of values) {
    if (seen.has(value)) {
      duplicates.add(value);
    } else {
      seen.add(value);
    }
  }
  return duplicates;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

function isPositiveSafeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

function isNonNegativeSafeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

function safeReportableBytes(value: unknown): number {
  return isNonNegativeSafeInteger(value) ? value : 0;
}
