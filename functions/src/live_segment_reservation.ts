export function durationSecForLiveStart(
  segment: Record<string, unknown>,
): number {
  if (segment.retired === true) {
    return 0;
  }
  const durationMs =
    typeof segment.durationMs === "number" &&
    Number.isFinite(segment.durationMs) &&
    segment.durationMs > 0 ?
      segment.durationMs :
      0;
  const durationSec =
    typeof segment.durationSec === "number" &&
    Number.isFinite(segment.durationSec) &&
    segment.durationSec > 0 ?
      segment.durationSec :
      0;
  return durationMs > 0 ? durationMs / 1000 : durationSec;
}

export function calculatedLiveStartSec(
  segments: Record<string, unknown>[],
  targetOrder: number,
): number {
  return segments.reduce((total, segment, index) => {
    const order =
      typeof segment.order === "number" && Number.isFinite(segment.order) ?
        segment.order :
        index;
    if (order >= targetOrder) {
      return total;
    }
    return total + durationSecForLiveStart(segment);
  }, 0);
}

export function nextDraftBaseDocumentVersionAfterLiveReservation({
  draftExists,
  draftBaseDocumentVersion,
  currentLessonDocumentVersion,
  nextLessonDocumentVersion,
}: {
  draftExists: boolean;
  draftBaseDocumentVersion: unknown;
  currentLessonDocumentVersion: unknown;
  nextLessonDocumentVersion: number;
}): number | null {
  if (!draftExists) {
    return null;
  }
  if (draftBaseDocumentVersion !== currentLessonDocumentVersion) {
    return null;
  }
  if (
    typeof currentLessonDocumentVersion !== "number" ||
    !Number.isSafeInteger(currentLessonDocumentVersion)
  ) {
    return null;
  }
  return nextLessonDocumentVersion;
}
