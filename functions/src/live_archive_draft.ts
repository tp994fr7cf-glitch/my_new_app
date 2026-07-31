export type LiveArchiveDraftFailureCode =
  | "versionConflict"
  | "invalidLesson"
  | "invalidDraft"
  | "placeholderMissing";

export type PreparedLiveArchiveDraft =
  | {
    ok: true;
    baseLessonDocumentVersion: number;
    draftRevision: number;
    mediaSegments: Record<string, unknown>[];
  }
  | {
    ok: false;
    code: LiveArchiveDraftFailureCode;
  };

export function prepareLiveArchiveDraft({
  lesson,
  existingDraft,
  segmentId,
  playbackUrl,
  durationSec,
  durationMs,
  liveSessionId,
}: {
  lesson: unknown;
  existingDraft: unknown;
  segmentId: string;
  playbackUrl: string;
  durationSec: number;
  durationMs: number;
  liveSessionId: string;
}): PreparedLiveArchiveDraft {
  if (!isRecord(lesson)) {
    return {ok: false, code: "invalidLesson"};
  }
  const documentVersion = lesson.documentVersion;
  if (!isPositiveSafeInteger(documentVersion)) {
    return {ok: false, code: "invalidLesson"};
  }

  let draftRevision = 0;
  let sourceSegments = lesson.mediaSegments;
  if (existingDraft !== null && existingDraft !== undefined) {
    if (!isRecord(existingDraft)) {
      return {ok: false, code: "invalidDraft"};
    }
    if (existingDraft.baseLessonDocumentVersion !== documentVersion) {
      return {ok: false, code: "versionConflict"};
    }
    if (
      !isPositiveSafeInteger(existingDraft.draftRevision) ||
      !isRecord(existingDraft.boardSet)
    ) {
      return {ok: false, code: "invalidDraft"};
    }
    draftRevision = existingDraft.draftRevision;
    if (Array.isArray(existingDraft.mediaSegments)) {
      sourceSegments = existingDraft.mediaSegments;
    }
  }

  if (
    !Array.isArray(sourceSegments) ||
    sourceSegments.length < 1 ||
    sourceSegments.length > 100
  ) {
    return {ok: false, code: "invalidLesson"};
  }
  const ids = new Set<string>();
  const normalized: Record<string, unknown>[] = [];
  let replaced = false;
  for (const value of sourceSegments) {
    if (
      !isRecord(value) ||
      typeof value.id !== "string" ||
      !value.id.trim() ||
      ids.has(value.id) ||
      !isNonNegativeSafeInteger(value.order)
    ) {
      return {ok: false, code: "invalidLesson"};
    }
    ids.add(value.id);
    if (value.id !== segmentId) {
      normalized.push({...value});
      continue;
    }
    const existingUrl = typeof value.url === "string" ? value.url.trim() : "";
    const existingSessionId =
      typeof value.liveSessionId === "string" ?
        value.liveSessionId.trim() :
        "";
    if (
      value.sourceKind !== "liveArchive" ||
      existingUrl ||
      (existingSessionId && existingSessionId !== liveSessionId)
    ) {
      return {ok: false, code: "placeholderMissing"};
    }
    normalized.push({
      ...value,
      url: playbackUrl,
      durationSec,
      durationMs,
      sourceKind: "liveArchive",
      liveSessionId,
    });
    replaced = true;
  }
  if (!replaced) {
    return {ok: false, code: "placeholderMissing"};
  }
  return {
    ok: true,
    baseLessonDocumentVersion: documentVersion,
    draftRevision: draftRevision + 1,
    mediaSegments: normalized,
  };
}

export function firebaseStorageDownloadUrl({
  bucketName,
  objectPath,
  downloadToken,
}: {
  bucketName: string;
  objectPath: string;
  downloadToken: string;
}): string {
  return "https://firebasestorage.googleapis.com/v0/b/" +
    `${encodeURIComponent(bucketName)}/o/${encodeURIComponent(objectPath)}` +
    `?alt=media&token=${encodeURIComponent(downloadToken)}`;
}

export function selectManifestObject(
  files: readonly string[],
  extension: ".m3u8" | ".mp4",
  requiredPrefix: string,
): string | null {
  const normalizedPrefix = requiredPrefix.endsWith("/") ?
    requiredPrefix :
    `${requiredPrefix}/`;
  return files.find(
    (file) =>
      file.startsWith(normalizedPrefix) &&
      file.toLowerCase().endsWith(extension),
  ) ?? null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isPositiveSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && typeof value === "number" && value > 0;
}

function isNonNegativeSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && typeof value === "number" && value >= 0;
}
