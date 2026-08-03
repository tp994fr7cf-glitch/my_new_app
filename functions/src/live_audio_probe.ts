import {createHash} from "node:crypto";

export const liveAudioProbeTokenLifetimeSec = 15 * 60;
export const liveAudioProbeMaxDurationSec = 60 * 60;
export const liveAudioProbeMaxDurationMs =
  liveAudioProbeMaxDurationSec * 1000;
export const liveAudioArchiveTokenLifetimeSec =
  liveAudioProbeMaxDurationSec;
export const maxLiveAudioProbeStrokes = 2000;
export const maxLiveAudioProbePointsPerStroke = 600;
export const maxLiveAudioBoardSetBytes = 750 * 1024;
export const maxLiveAudioBoards = 20;
export const maxLiveAudioBoardSwitchEvents = 10000;
export const maxLiveAudioViewportEvents = 2000;
export const maxLiveAudioTimelineChunkEvents = 100;
export const maxLiveAudioTimelineEvents = 15000;
export const maxLiveAudioTimelineChunkBytes = 700 * 1024;

export type LiveAudioProbePermission = "publisher" | "subscriber";
export type LiveAudioSessionState =
  | "active"
  | "live"
  | "finalizing"
  | "draftReady"
  | "archiveFailed"
  | "ended";

export type LiveAudioTimelineEvent =
  | {
    type: "boardCreate";
    boardId: string;
    globalTimestampSec: number;
    boardOrder: number;
    boardTitle: string;
  }
  | {
    type: "boardSwitch";
    boardId: string;
    globalTimestampSec: number;
  }
  | {
    type: "viewport";
    boardId: string;
    globalTimestampSec: number;
    interactionId: number;
    centerX: number;
    centerY: number;
    scale: number;
  }
  | {
    type: "strokeCompleted";
    boardId: string;
    globalTimestampSec: number;
    stroke: WhiteboardStroke;
  };

export type WhiteboardStroke = {
  id: string;
  timestampSec: number;
  endTimestampSec?: number;
  colorArgb: number;
  strokeWidth: number;
  points: Array<{x: number; y: number; timestampSec?: number}>;
};

export function remainingLiveAudioProbeDurationSec({
  startedAtMs,
  nowMs,
}: {
  startedAtMs: unknown;
  nowMs: number;
}): number {
  if (
    typeof startedAtMs !== "number" ||
    !Number.isSafeInteger(startedAtMs) ||
    startedAtMs <= 0 ||
    !Number.isSafeInteger(nowMs) ||
    nowMs < 0
  ) {
    return 0;
  }
  return Math.max(
    0,
    Math.ceil(
      (startedAtMs + liveAudioProbeMaxDurationMs - nowMs) / 1000,
    ),
  );
}

export function hasLiveAudioProbeExceededMaxDuration({
  startedAtMs,
  nowMs,
}: {
  startedAtMs: unknown;
  nowMs: number;
}): boolean {
  return (
    typeof startedAtMs === "number" &&
    Number.isSafeInteger(startedAtMs) &&
    startedAtMs > 0 &&
    Number.isSafeInteger(nowMs) &&
    nowMs >= startedAtMs + liveAudioProbeMaxDurationMs
  );
}

export function rtcUidForFirebaseUser(firebaseUid: string): number {
  const digest = createHash("sha256").update(firebaseUid).digest();
  const uid = digest.readUInt32BE(0);
  return uid === 0 ? 1 : uid;
}

export function permissionForParticipant({
  ownerUid,
  participantUid,
  activePresenterUid,
  presenterUids,
}: {
  ownerUid: string;
  participantUid: string;
  activePresenterUid?: string;
  presenterUids?: readonly string[];
}): LiveAudioProbePermission {
  const presenterUid = resolveActivePresenterUid({
    ownerUid,
    activePresenterUid,
    presenterUids,
  });
  return participantUid === presenterUid ? "publisher" : "subscriber";
}

export function resolveActivePresenterUid({
  ownerUid,
  activePresenterUid,
  presenterUids = [],
}: {
  ownerUid: string;
  activePresenterUid?: string;
  presenterUids?: readonly string[];
}): string {
  const explicit = activePresenterUid?.trim();
  if (explicit) {
    return explicit;
  }
  const legacyPresenter = presenterUids.find((uid) => uid.trim().length > 0);
  return legacyPresenter ?? ownerUid;
}

export function isLiveSessionState(value: unknown): boolean {
  return value === "active" || value === "live";
}

export function isSupportedSessionState(
  value: unknown,
): value is LiveAudioSessionState {
  return (
    isLiveSessionState(value) ||
    value === "finalizing" ||
    value === "draftReady" ||
    value === "archiveFailed" ||
    value === "ended"
  );
}

export function canTransitionSessionState(
  from: LiveAudioSessionState,
  to: LiveAudioSessionState,
): boolean {
  if (from === to) {
    return true;
  }
  if (isLiveSessionState(from)) {
    return to === "finalizing";
  }
  if (from === "finalizing") {
    return to === "draftReady" || to === "archiveFailed";
  }
  if (from === "archiveFailed" || from === "ended") {
    return to === "finalizing" || to === "draftReady";
  }
  return false;
}

export function isValidProbeSessionId(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9]{20}$/.test(value);
}

export function isValidLiveAudioJoinCode(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}$/.test(value);
}

export function isValidOptionalLinkId(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(value)
  );
}

export function isValidSegmentStartSec(value: unknown): value is number {
  return isFiniteNumberInRange(value, 0, 7 * 24 * 60 * 60);
}

export function maximumAllowedGlobalTimestampSec({
  segmentStartSec,
  startedAtMs,
  nowMs,
  graceSec = 60,
}: {
  segmentStartSec: number;
  startedAtMs: number;
  nowMs: number;
  graceSec?: number;
}): number {
  return segmentStartSec +
    Math.max(0, (nowMs - startedAtMs) / 1000) +
    graceSec;
}

export function isValidWhiteboardStroke(
  value: unknown,
): value is WhiteboardStroke {
  if (!isRecord(value)) {
    return false;
  }
  if (
    !hasOnlyKeys(value, [
      "id",
      "timestampSec",
      "endTimestampSec",
      "colorArgb",
      "strokeWidth",
      "points",
    ])
  ) {
    return false;
  }
  if (
    !isSafeId(value.id) ||
    !isFiniteNonNegative(value.timestampSec) ||
    !isFiniteInteger(value.colorArgb) ||
    !isFiniteNumberInRange(value.strokeWidth, 0.5, 20) ||
    !Array.isArray(value.points) ||
    value.points.length < 1 ||
    value.points.length > maxLiveAudioProbePointsPerStroke
  ) {
    return false;
  }
  if (
    value.endTimestampSec !== undefined &&
    (
      !isFiniteNonNegative(value.endTimestampSec) ||
      value.endTimestampSec < value.timestampSec
    )
  ) {
    return false;
  }
  const endTimestampSec =
    typeof value.endTimestampSec === "number" ?
      value.endTimestampSec :
      undefined;
  let previousPointTimestampSec = value.timestampSec;
  return value.points.every((point) => {
    if (
      !isRecord(point) ||
      !hasOnlyKeys(point, ["x", "y", "timestampSec"])
    ) {
      return false;
    }
    const pointTimestampSec = point.timestampSec;
    const timestampIsValid =
      pointTimestampSec === undefined ||
      (
        isFiniteNonNegative(pointTimestampSec) &&
        pointTimestampSec >= previousPointTimestampSec &&
        (
          endTimestampSec === undefined ||
          pointTimestampSec <= endTimestampSec
        )
      );
    if (typeof pointTimestampSec === "number" && timestampIsValid) {
      previousPointTimestampSec = pointTimestampSec;
    }
    return (
      isFiniteNumberInRange(point.x, 0, 1) &&
      isFiniteNumberInRange(point.y, 0, 1) &&
      timestampIsValid
    );
  });
}

export function isValidBoardSet(
  value: unknown,
): value is Record<string, unknown> {
  if (
    !isRecord(value) ||
    !hasOnlyKeys(value, ["boards", "switchEvents", "viewportEvents"]) ||
    !Array.isArray(value.boards) ||
    value.boards.length < 1 ||
    value.boards.length > maxLiveAudioBoards ||
    !Array.isArray(value.switchEvents) ||
    value.switchEvents.length > maxLiveAudioBoardSwitchEvents ||
    !Array.isArray(value.viewportEvents) ||
    value.viewportEvents.length > maxLiveAudioViewportEvents ||
    serializedJsonBytes(value) > maxLiveAudioBoardSetBytes
  ) {
    return false;
  }

  const boardIds = new Set<string>();
  const boardOrders = new Set<number>();
  let totalStrokes = 0;
  let totalPoints = 0;
  for (const board of value.boards) {
    if (
      !isRecord(board) ||
      !hasOnlyKeys(board, ["id", "order", "title", "layers"]) ||
      !isSafeId(board.id) ||
      !isFiniteIntegerInRange(board.order, 0, maxLiveAudioBoards - 1) ||
      (board.title !== undefined && !isBoundedString(board.title, 100)) ||
      !Array.isArray(board.layers) ||
      board.layers.length > 20 ||
      boardIds.has(board.id) ||
      boardOrders.has(board.order)
    ) {
      return false;
    }
    boardIds.add(board.id);
    boardOrders.add(board.order);
    const layerIds = new Set<string>();
    const layerOrders = new Set<number>();
    for (const layer of board.layers) {
      if (
        !isRecord(layer) ||
        !hasOnlyKeys(layer, [
          "id",
          "order",
          "title",
          "anchorType",
          "segmentId",
          "visibleFromSec",
          "visibleUntilSec",
          "strokes",
          "updatedAtMs",
        ]) ||
        !isSafeId(layer.id) ||
        !isFiniteIntegerInRange(layer.order, 0, 99) ||
        (layer.title !== undefined && !isBoundedString(layer.title, 100)) ||
        (layer.anchorType !== "global" && layer.anchorType !== "segment") ||
        (layer.segmentId !== undefined &&
          !isValidOptionalLinkId(layer.segmentId)) ||
        (layer.visibleFromSec !== undefined &&
          !isFiniteNonNegative(layer.visibleFromSec)) ||
        (layer.visibleUntilSec !== undefined &&
          !isFiniteNonNegative(layer.visibleUntilSec)) ||
        (
          typeof layer.visibleFromSec === "number" &&
          typeof layer.visibleUntilSec === "number" &&
          layer.visibleUntilSec < layer.visibleFromSec
        ) ||
        (layer.updatedAtMs !== undefined &&
          !isFiniteIntegerInRange(layer.updatedAtMs, 0, Number.MAX_SAFE_INTEGER)) ||
        (layer.strokes !== undefined && !Array.isArray(layer.strokes)) ||
        layerIds.has(layer.id) ||
        layerOrders.has(layer.order)
      ) {
        return false;
      }
      layerIds.add(layer.id);
      layerOrders.add(layer.order);
      const strokes = layer.strokes ?? [];
      if (!Array.isArray(strokes)) {
        return false;
      }
      for (const stroke of strokes) {
        if (!isValidWhiteboardStroke(stroke)) {
          return false;
        }
        totalStrokes += 1;
        totalPoints += stroke.points.length;
        if (totalStrokes > 2000 || totalPoints > 100000) {
          return false;
        }
      }
    }
  }

  const switchSequences = new Set<number>();
  for (const event of value.switchEvents) {
    if (
      !isRecord(event) ||
      !hasOnlyKeys(event, ["boardId", "globalTimestampSec", "sequence"]) ||
      typeof event.boardId !== "string" ||
      !boardIds.has(event.boardId) ||
      !isFiniteNonNegative(event.globalTimestampSec) ||
      !isFiniteIntegerInRange(event.sequence, 0, Number.MAX_SAFE_INTEGER) ||
      switchSequences.has(event.sequence)
    ) {
      return false;
    }
    switchSequences.add(event.sequence);
  }

  const viewportSequences = new Set<number>();
  for (const event of value.viewportEvents) {
    if (
      !isRecord(event) ||
      !hasOnlyKeys(event, [
        "boardId",
        "globalTimestampSec",
        "sequence",
        "interactionId",
        "centerX",
        "centerY",
        "scale",
      ]) ||
      typeof event.boardId !== "string" ||
      !boardIds.has(event.boardId) ||
      !isFiniteNonNegative(event.globalTimestampSec) ||
      !isFiniteIntegerInRange(event.sequence, 0, Number.MAX_SAFE_INTEGER) ||
      viewportSequences.has(event.sequence) ||
      !isFiniteIntegerInRange(event.interactionId, 0, Number.MAX_SAFE_INTEGER) ||
      !isValidViewport(event.centerX, event.centerY, event.scale)
    ) {
      return false;
    }
    viewportSequences.add(event.sequence);
  }
  return true;
}

export function isValidTimelineEvent(
  value: unknown,
): value is LiveAudioTimelineEvent {
  if (!isRecord(value) || typeof value.type !== "string") {
    return false;
  }
  if (
    value.type === "boardCreate" &&
    hasOnlyKeys(value, [
      "type",
      "boardId",
      "globalTimestampSec",
      "boardOrder",
      "boardTitle",
    ])
  ) {
    return (
      isSafeId(value.boardId) &&
      isFiniteNonNegative(value.globalTimestampSec) &&
      isFiniteIntegerInRange(value.boardOrder, 0, maxLiveAudioBoards - 1) &&
      isBoundedString(value.boardTitle, 100)
    );
  }
  if (
    value.type === "boardSwitch" &&
    hasOnlyKeys(value, ["type", "boardId", "globalTimestampSec"])
  ) {
    return isSafeId(value.boardId) &&
      isFiniteNonNegative(value.globalTimestampSec);
  }
  if (
    value.type === "viewport" &&
    hasOnlyKeys(value, [
      "type",
      "boardId",
      "globalTimestampSec",
      "interactionId",
      "centerX",
      "centerY",
      "scale",
    ])
  ) {
    return (
      isSafeId(value.boardId) &&
      isFiniteNonNegative(value.globalTimestampSec) &&
      isFiniteIntegerInRange(value.interactionId, 0, Number.MAX_SAFE_INTEGER) &&
      isValidViewport(value.centerX, value.centerY, value.scale)
    );
  }
  if (
    value.type === "strokeCompleted" &&
    hasOnlyKeys(value, [
      "type",
      "boardId",
      "globalTimestampSec",
      "stroke",
    ])
  ) {
    return (
      isSafeId(value.boardId) &&
      isFiniteNonNegative(value.globalTimestampSec) &&
      isValidWhiteboardStroke(value.stroke)
    );
  }
  return false;
}

export function isValidTimelineChunk(value: unknown): value is {
  expectedNextSequence: number;
  chunkId: string;
  events: LiveAudioTimelineEvent[];
} {
  return (
    isRecord(value) &&
    hasOnlyKeys(value, ["expectedNextSequence", "chunkId", "events"]) &&
    isFiniteIntegerInRange(
      value.expectedNextSequence,
      0,
      maxLiveAudioTimelineEvents,
    ) &&
    isSafeId(value.chunkId) &&
    Array.isArray(value.events) &&
    value.events.length >= 1 &&
    value.events.length <= maxLiveAudioTimelineChunkEvents &&
    value.events.every(isValidTimelineEvent) &&
    hasNonDecreasingTimelineTimestamps(value.events) &&
    serializedJsonBytes(value.events) <= maxLiveAudioTimelineChunkBytes
  );
}

export function serializedJsonBytes(value: unknown): number {
  try {
    return Buffer.byteLength(JSON.stringify(value), "utf8");
  } catch {
    return Number.POSITIVE_INFINITY;
  }
}

export function validateTimelineBoardReferences({
  events,
  knownBoards,
  createdBoardIds,
}: {
  events: readonly LiveAudioTimelineEvent[];
  knownBoards: ReadonlyMap<string, number>;
  createdBoardIds: ReadonlySet<string>;
}): {
  valid: boolean;
  resultingBoards: Map<string, number>;
  resultingCreatedBoardIds: Set<string>;
} {
  const boards = new Map(knownBoards);
  const createdIds = new Set(createdBoardIds);
  for (const event of events) {
    if (event.type === "boardCreate") {
      const existingOrder = boards.get(event.boardId);
      const orderUsedByAnotherBoard = [...boards].some(
        ([boardId, order]) =>
          boardId !== event.boardId && order === event.boardOrder,
      );
      if (
        createdIds.has(event.boardId) ||
        (existingOrder !== undefined && existingOrder !== event.boardOrder) ||
        orderUsedByAnotherBoard ||
        (existingOrder === undefined && boards.size >= maxLiveAudioBoards)
      ) {
        return {
          valid: false,
          resultingBoards: boards,
          resultingCreatedBoardIds: createdIds,
        };
      }
      boards.set(event.boardId, event.boardOrder);
      createdIds.add(event.boardId);
      continue;
    }
    if (!boards.has(event.boardId)) {
      return {
        valid: false,
        resultingBoards: boards,
        resultingCreatedBoardIds: createdIds,
      };
    }
  }
  return {
    valid: true,
    resultingBoards: boards,
    resultingCreatedBoardIds: createdIds,
  };
}

function isValidViewport(
  centerX: unknown,
  centerY: unknown,
  scale: unknown,
): boolean {
  if (
    !isFiniteNumberInRange(scale, 1, 8) ||
    typeof centerX !== "number" ||
    !Number.isFinite(centerX) ||
    typeof centerY !== "number" ||
    !Number.isFinite(centerY)
  ) {
    return false;
  }
  const halfExtent = 0.5 / scale;
  return (
    centerX >= halfExtent &&
    centerX <= 1 - halfExtent &&
    centerY >= halfExtent &&
    centerY <= 1 - halfExtent
  );
}

function hasNonDecreasingTimelineTimestamps(
  events: readonly LiveAudioTimelineEvent[],
): boolean {
  let previousTimestampSec = -1;
  for (const event of events) {
    if (event.globalTimestampSec < previousTimestampSec) {
      return false;
    }
    if (
      event.type === "strokeCompleted" &&
      event.globalTimestampSec < event.stroke.timestampSec
    ) {
      return false;
    }
    previousTimestampSec = event.globalTimestampSec;
  }
  return true;
}

function isSafeId(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$/.test(value)
  );
}

function isBoundedString(value: unknown, maximumLength: number): boolean {
  return typeof value === "string" && value.length <= maximumLength;
}

function hasOnlyKeys(
  value: Record<string, unknown>,
  allowedKeys: readonly string[],
): boolean {
  const allowed = new Set(allowedKeys);
  return Object.keys(value).every((key) => allowed.has(key));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isFiniteNonNegative(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function isFiniteInteger(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    Number.isInteger(value)
  );
}

function isFiniteIntegerInRange(
  value: unknown,
  minimum: number,
  maximum: number,
): value is number {
  return (
    isFiniteInteger(value) &&
    value >= minimum &&
    value <= maximum
  );
}

function isFiniteNumberInRange(
  value: unknown,
  minimum: number,
  maximum: number,
): value is number {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    value >= minimum &&
    value <= maximum
  );
}
