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

export function resolveLiveArchiveDuration({
  timingVersion,
  hlsDurationMs,
  sessionStartedAtMs,
  archiveStartedAtMs,
  archiveStopRequestedAtMs,
  archiveStoppedAtMs,
  finalizedAtMs,
}: {
  timingVersion: number;
  hlsDurationMs: number | null;
  sessionStartedAtMs: number;
  archiveStartedAtMs: number;
  archiveStopRequestedAtMs: number;
  archiveStoppedAtMs: number;
  finalizedAtMs: number;
}): {
  durationMs: number;
  durationSec: number;
  source: "hls" | "wallClock";
} {
  if (
    timingVersion >= 2 &&
    hlsDurationMs !== null &&
    Number.isSafeInteger(hlsDurationMs) &&
    hlsDurationMs > 0
  ) {
    return {
      durationMs: hlsDurationMs,
      durationSec: Math.max(1, Math.floor(hlsDurationMs / 1000)),
      source: "hls",
    };
  }
  const startAtMs = archiveStartedAtMs > 0 ?
    archiveStartedAtMs :
    sessionStartedAtMs;
  const endAtMs = timingVersion >= 2 ?
    archiveStopRequestedAtMs || archiveStoppedAtMs || finalizedAtMs :
    finalizedAtMs;
  const durationMs = Math.max(1000, endAtMs - startAtMs);
  return {
    durationMs,
    durationSec: Math.max(1, Math.floor(durationMs / 1000)),
    source: "wallClock",
  };
}

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

export function adjustLiveArchiveBoardSet({
  boardSet,
  baselineBoardSet,
  segmentStartSec,
  archiveTimelineOffsetSec,
  recordingWallDurationSec,
  mediaDurationSec,
}: {
  boardSet: unknown;
  baselineBoardSet: unknown;
  segmentStartSec: number;
  archiveTimelineOffsetSec: number;
  recordingWallDurationSec: number;
  mediaDurationSec: number;
}): Record<string, unknown> | null {
  if (
    !isRecord(boardSet) ||
    !isRecord(baselineBoardSet) ||
    !Array.isArray(boardSet.boards) ||
    !Array.isArray(boardSet.switchEvents) ||
    !Array.isArray(boardSet.viewportEvents) ||
    !Number.isFinite(segmentStartSec) ||
    segmentStartSec < 0 ||
    !Number.isFinite(archiveTimelineOffsetSec) ||
    archiveTimelineOffsetSec < 0 ||
    !Number.isFinite(recordingWallDurationSec) ||
    recordingWallDurationSec <= 0 ||
    !Number.isFinite(mediaDurationSec) ||
    mediaDurationSec <= 0
  ) {
    return null;
  }
  const baselineStrokeIds = collectStrokeIds(baselineBoardSet);
  const baselineSwitchSequences = collectEventSequences(
    baselineBoardSet.switchEvents,
  );
  const baselineViewportSequences = collectEventSequences(
    baselineBoardSet.viewportEvents,
  );
  if (
    baselineStrokeIds === null ||
    baselineSwitchSequences === null ||
    baselineViewportSequences === null
  ) {
    return null;
  }
  const scale = mediaDurationSec / recordingWallDurationSec;
  const liveStartSec = segmentStartSec + archiveTimelineOffsetSec;
  const adjustedTimestamp = (value: unknown): number | null => {
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
      return null;
    }
    const recordingLocalSec = Math.min(
      recordingWallDurationSec,
      Math.max(0, value - liveStartSec),
    );
    return Number(
      (segmentStartSec + recordingLocalSec * scale).toFixed(6),
    );
  };

  const boards: Record<string, unknown>[] = [];
  for (const board of boardSet.boards) {
    if (!isRecord(board) || !Array.isArray(board.layers)) {
      return null;
    }
    const layers: Record<string, unknown>[] = [];
    for (const layer of board.layers) {
      if (!isRecord(layer)) {
        return null;
      }
      const rawStrokes = layer.strokes ?? [];
      if (!Array.isArray(rawStrokes)) {
        return null;
      }
      const strokes: Record<string, unknown>[] = [];
      for (const stroke of rawStrokes) {
        if (!isRecord(stroke) || typeof stroke.id !== "string") {
          return null;
        }
        if (baselineStrokeIds.has(stroke.id)) {
          strokes.push({...stroke});
          continue;
        }
        const timestampSec = adjustedTimestamp(stroke.timestampSec);
        if (timestampSec === null || !Array.isArray(stroke.points)) {
          return null;
        }
        const points: Record<string, unknown>[] = [];
        for (const point of stroke.points) {
          if (!isRecord(point)) {
            return null;
          }
          if (point.timestampSec === undefined) {
            points.push({...point});
            continue;
          }
          const pointTimestampSec = adjustedTimestamp(point.timestampSec);
          if (pointTimestampSec === null) {
            return null;
          }
          points.push({...point, timestampSec: pointTimestampSec});
        }
        let endTimestampSec: number | undefined;
        if (stroke.endTimestampSec !== undefined) {
          const adjustedEnd = adjustedTimestamp(stroke.endTimestampSec);
          if (adjustedEnd === null) {
            return null;
          }
          endTimestampSec = adjustedEnd;
        }
        strokes.push({
          ...stroke,
          timestampSec,
          ...(endTimestampSec === undefined ? {} : {endTimestampSec}),
          points,
        });
      }
      layers.push({...layer, ...(layer.strokes === undefined ? {} : {strokes})});
    }
    boards.push({...board, layers});
  }

  const adjustEvents = (
    values: unknown[],
    baselineSequences: ReadonlySet<number>,
  ): Record<string, unknown>[] | null => {
    const adjusted: Record<string, unknown>[] = [];
    for (const value of values) {
      if (
        !isRecord(value) ||
        typeof value.sequence !== "number" ||
        !Number.isSafeInteger(value.sequence)
      ) {
        return null;
      }
      if (baselineSequences.has(value.sequence)) {
        adjusted.push({...value});
        continue;
      }
      const globalTimestampSec = adjustedTimestamp(value.globalTimestampSec);
      if (globalTimestampSec === null) {
        return null;
      }
      adjusted.push({...value, globalTimestampSec});
    }
    return adjusted;
  };
  const switchEvents = adjustEvents(
    boardSet.switchEvents,
    baselineSwitchSequences,
  );
  const viewportEvents = adjustEvents(
    boardSet.viewportEvents,
    baselineViewportSequences,
  );
  if (switchEvents === null || viewportEvents === null) {
    return null;
  }
  return {...boardSet, boards, switchEvents, viewportEvents};
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

function collectStrokeIds(boardSet: Record<string, unknown>): Set<string> | null {
  if (!Array.isArray(boardSet.boards)) {
    return null;
  }
  const ids = new Set<string>();
  for (const board of boardSet.boards) {
    if (!isRecord(board) || !Array.isArray(board.layers)) {
      return null;
    }
    for (const layer of board.layers) {
      if (!isRecord(layer)) {
        return null;
      }
      const strokes = layer.strokes ?? [];
      if (!Array.isArray(strokes)) {
        return null;
      }
      for (const stroke of strokes) {
        if (!isRecord(stroke) || typeof stroke.id !== "string") {
          return null;
        }
        ids.add(stroke.id);
      }
    }
  }
  return ids;
}

function collectEventSequences(value: unknown): Set<number> | null {
  if (!Array.isArray(value)) {
    return null;
  }
  const sequences = new Set<number>();
  for (const event of value) {
    if (
      !isRecord(event) ||
      typeof event.sequence !== "number" ||
      !Number.isSafeInteger(event.sequence)
    ) {
      return null;
    }
    sequences.add(event.sequence);
  }
  return sequences;
}

function isPositiveSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && typeof value === "number" && value > 0;
}

function isNonNegativeSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && typeof value === "number" && value >= 0;
}
