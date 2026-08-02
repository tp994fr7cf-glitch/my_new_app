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
  if (
    manifest.length === 0 ||
    manifest.length > 2 * 1024 * 1024 ||
    !manifest.split(/\r?\n/, 1)[0]?.trim().startsWith("#EXTM3U") ||
    !/^#EXT-X-ENDLIST\s*$/m.test(manifest)
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
