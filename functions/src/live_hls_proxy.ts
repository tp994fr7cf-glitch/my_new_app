import {createHmac, timingSafeEqual} from "node:crypto";
import {posix as path} from "node:path";

export type HlsAccessClaims = {
  sessionId: string;
  uid: string;
  expiresAtSec: number;
};

export function createHlsAccessToken(
  claims: HlsAccessClaims,
  secret: string,
): string {
  const payload = Buffer.from(JSON.stringify(claims), "utf8").toString(
    "base64url",
  );
  const signature = sign(payload, secret);
  return `${payload}.${signature}`;
}

export function verifyHlsAccessToken(
  token: string,
  secret: string,
  nowSec = Math.floor(Date.now() / 1000),
): HlsAccessClaims | null {
  const [payload, signature, extra] = token.split(".");
  if (!payload || !signature || extra !== undefined || !secret) {
    return null;
  }
  const expected = sign(payload, secret);
  const actualBytes = Buffer.from(signature, "utf8");
  const expectedBytes = Buffer.from(expected, "utf8");
  if (
    actualBytes.length !== expectedBytes.length ||
    !timingSafeEqual(actualBytes, expectedBytes)
  ) {
    return null;
  }
  try {
    const decoded = JSON.parse(
      Buffer.from(payload, "base64url").toString("utf8"),
    ) as Partial<HlsAccessClaims>;
    if (
      typeof decoded.sessionId !== "string" ||
      !/^[A-Za-z0-9]{20}$/.test(decoded.sessionId) ||
      typeof decoded.uid !== "string" ||
      decoded.uid.length < 1 ||
      decoded.uid.length > 256 ||
      !Number.isSafeInteger(decoded.expiresAtSec) ||
      (decoded.expiresAtSec ?? 0) < nowSec
    ) {
      return null;
    }
    return decoded as HlsAccessClaims;
  } catch {
    return null;
  }
}

export function isSafeHlsObjectPath(
  objectPath: string,
  sessionId: string,
): boolean {
  const prefix = `liveAudioProbeSessions/${sessionId}/`;
  return (
    objectPath.startsWith(prefix) &&
    objectPath.length <= 1024 &&
    !objectPath.includes("..") &&
    /^[A-Za-z0-9._/-]+$/.test(objectPath)
  );
}

export function finalizedHlsDurationMs(manifest: string): number | null {
  if (!/^#EXT-X-ENDLIST\s*$/m.test(manifest)) {
    return null;
  }
  return availableHlsDurationMs(manifest);
}

export function availableHlsDurationMs(manifest: string): number | null {
  if (
    manifest.length === 0 ||
    manifest.length > 2 * 1024 * 1024 ||
    !manifest.split(/\r?\n/, 1)[0]?.trim().startsWith("#EXTM3U")
  ) {
    return null;
  }
  let totalSeconds = 0;
  let segmentCount = 0;
  for (const line of manifest.split(/\r?\n/)) {
    const match = /^#EXTINF:([0-9]+(?:\.[0-9]+)?)(?:,.*)?$/.exec(
      line.trim(),
    );
    if (!match) {
      continue;
    }
    const seconds = Number(match[1]);
    if (!Number.isFinite(seconds) || seconds < 0) {
      return null;
    }
    totalSeconds += seconds;
    segmentCount++;
  }
  const durationMs = Math.round(totalSeconds * 1000);
  return segmentCount > 0 && Number.isSafeInteger(durationMs) && durationMs > 0 ?
    durationMs :
    null;
}

export function firstHlsSegmentStartedAtMs(
  manifest: string,
): number | null {
  if (
    manifest.length === 0 ||
    manifest.length > 2 * 1024 * 1024 ||
    !manifest.split(/\r?\n/, 1)[0]?.trim().startsWith("#EXTM3U")
  ) {
    return null;
  }
  for (const rawLine of manifest.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }
    const match =
      /_(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{3})\.ts$/.exec(
        line,
      );
    if (!match) {
      return null;
    }
    return parseAgoraUtcTimestamp(match.slice(1).join(""));
  }
  return null;
}

export function firstHlsAudioTrackStartedAtMs(
  manifest: string,
): number | null {
  if (
    manifest.length === 0 ||
    manifest.length > 2 * 1024 * 1024 ||
    !manifest.split(/\r?\n/, 1)[0]?.trim().startsWith("#EXTM3U")
  ) {
    return null;
  }
  for (const rawLine of manifest.split(/\r?\n/)) {
    const match =
      /^#EXT-X-AGORA-TRACK-EVENT:EVENT=START,TRACK_TYPE=AUDIO,TIME=(\d+)$/.exec(
        rawLine.trim(),
      );
    if (!match) {
      continue;
    }
    return parseAgoraUtcTimestamp(match[1]);
  }
  return null;
}

export function hlsMediaTimelineOffsetSec({
  manifest,
  sessionStartedAtMs,
  maximumOffsetSec = 5 * 60,
}: {
  manifest: string;
  sessionStartedAtMs: number;
  maximumOffsetSec?: number;
}): number | null {
  // The audio-track event shares Agora's NTP clock with publisher timestamps.
  // A segment filename is only a fallback because the container may begin
  // before audible audio. Preserve this priority unless manifest evidence from
  // a reproduced issue shows that Agora changed the event semantics.
  const mediaStartedAtMs =
    firstHlsAudioTrackStartedAtMs(manifest) ??
    firstHlsSegmentStartedAtMs(manifest);
  if (
    mediaStartedAtMs === null ||
    !Number.isSafeInteger(sessionStartedAtMs) ||
    sessionStartedAtMs <= 0 ||
    !Number.isFinite(maximumOffsetSec) ||
    maximumOffsetSec < 0
  ) {
    return null;
  }
  const offsetSec = (mediaStartedAtMs - sessionStartedAtMs) / 1000;
  return offsetSec >= 0 && offsetSec <= maximumOffsetSec ?
    offsetSec :
    null;
}

export type LiveAudioPlaybackCompensationSource =
  | "legacy"
  | "agoraAudioFrame"
  | "fallback";

/**
 * Measures one constant capture-to-HLS delay for a session.
 *
 * Timing v5 intentionally leaves older sessions unchanged. The measured value
 * is preferred; 1.2 seconds is only a fallback. A short startup transient can
 * still remain because one scalar cannot model a delay that settles during the
 * first several seconds. This is the current verified baseline, but it may be
 * revised when a reproducible issue provides evidence for a better model.
 */
export function resolveLiveAudioPlaybackCompensation({
  timingVersion,
  hlsMediaStartedAtMs,
  audioCaptureStartedAtMs,
  fallbackSec = 1.2,
  maximumCompensationSec = 3,
}: {
  timingVersion: number;
  hlsMediaStartedAtMs: number | null;
  audioCaptureStartedAtMs: number;
  fallbackSec?: number;
  maximumCompensationSec?: number;
}): {
  compensationSec: number;
  source: LiveAudioPlaybackCompensationSource;
} {
  if (timingVersion < 5) {
    return {compensationSec: 0, source: "legacy"};
  }
  if (
    hlsMediaStartedAtMs !== null &&
    Number.isSafeInteger(hlsMediaStartedAtMs) &&
    hlsMediaStartedAtMs > 0 &&
    Number.isSafeInteger(audioCaptureStartedAtMs) &&
    audioCaptureStartedAtMs > 0 &&
    Number.isFinite(maximumCompensationSec) &&
    maximumCompensationSec >= 0
  ) {
    const measuredSec =
      (hlsMediaStartedAtMs - audioCaptureStartedAtMs) / 1000;
    if (measuredSec >= 0 && measuredSec <= maximumCompensationSec) {
      return {
        compensationSec: Number(measuredSec.toFixed(6)),
        source: "agoraAudioFrame",
      };
    }
  }
  const safeFallbackSec =
    Number.isFinite(fallbackSec) && fallbackSec >= 0 ?
      Math.min(fallbackSec, maximumCompensationSec) :
      0;
  return {
    compensationSec: Number(safeFallbackSec.toFixed(6)),
    source: "fallback",
  };
}

function parseAgoraUtcTimestamp(value: string): number | null {
  if (/^\d{13}$/.test(value)) {
    const unixTimestampMs = Number(value);
    return Number.isSafeInteger(unixTimestampMs) && unixTimestampMs > 0 ?
      unixTimestampMs :
      null;
  }
  const match =
    /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{3})$/.exec(value);
  if (!match) {
    return null;
  }
  const parts = match.slice(1).map(Number);
  const [year, month, day, hour, minute, second, millisecond] = parts;
  const startedAtMs = Date.UTC(
    year,
    month - 1,
    day,
    hour,
    minute,
    second,
    millisecond,
  );
  const date = new Date(startedAtMs);
  return date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day &&
    date.getUTCHours() === hour &&
    date.getUTCMinutes() === minute &&
    date.getUTCSeconds() === second &&
    date.getUTCMilliseconds() === millisecond ?
    startedAtMs :
    null;
}

export function rewriteHlsManifest({
  manifest,
  manifestObjectPath,
  proxyUrl,
  token,
}: {
  manifest: string;
  manifestObjectPath: string;
  proxyUrl: string;
  token: string;
}): string {
  const directory = path.dirname(manifestObjectPath);
  const rewrite = (reference: string): string => {
    const trimmed = reference.trim();
    if (
      !trimmed ||
      /^[a-z][a-z0-9+.-]*:/i.test(trimmed) ||
      trimmed.startsWith("/") ||
      trimmed.startsWith("//")
    ) {
      throw new Error("External HLS references are not allowed.");
    }
    const objectPath = path.normalize(path.join(directory, trimmed));
    const url = new URL(proxyUrl);
    url.searchParams.set("token", token);
    url.searchParams.set("file", objectPath);
    return url.toString();
  };

  return manifest
    .split(/\r?\n/)
    .map((line) => {
      if (!line || (!line.startsWith("#") && !line.trim())) {
        return line;
      }
      if (!line.startsWith("#")) {
        return rewrite(line);
      }
      return line.replace(/URI="([^"]+)"/g, (_match, reference: string) => {
        return `URI="${rewrite(reference)}"`;
      });
    })
    .join("\n");
}

function sign(payload: string, secret: string): string {
  return createHmac("sha256", secret).update(payload).digest("base64url");
}
