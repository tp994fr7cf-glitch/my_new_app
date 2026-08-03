import assert from "node:assert/strict";
import test from "node:test";

import {
  availableHlsDurationMs,
  createHlsAccessToken,
  finalizedHlsDurationMs,
  firstHlsAudioTrackStartedAtMs,
  firstHlsSegmentStartedAtMs,
  hlsMediaTimelineOffsetSec,
  isSafeHlsObjectPath,
  resolveLiveAudioPlaybackCompensation,
  rewriteHlsManifest,
  verifyHlsAccessToken,
} from "./live_hls_proxy";

test("reads exact duration from a finalized HLS media playlist", () => {
  assert.equal(
    finalizedHlsDurationMs(
      "#EXTM3U\n" +
      "#EXT-X-VERSION:3\n" +
      "#EXTINF:9.984,\npart-1.ts\n" +
      "#EXTINF:10,\npart-2.ts\n" +
      "#EXTINF:0.516,\npart-3.ts\n" +
      "#EXT-X-ENDLIST\n",
    ),
    20500,
  );
});

test("rejects partial or duration-less HLS manifests", () => {
  assert.equal(
    finalizedHlsDurationMs("#EXTM3U\n#EXTINF:10,\npart-1.ts\n"),
    null,
  );
  assert.equal(
    finalizedHlsDurationMs(
      "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000\nchild.m3u8\n" +
      "#EXT-X-ENDLIST\n",
    ),
    null,
  );
  assert.equal(finalizedHlsDurationMs("not-a-manifest"), null);
});

test("reads only completed segments from an in-progress HLS playlist", () => {
  assert.equal(
    availableHlsDurationMs(
      "#EXTM3U\n" +
      "#EXT-X-TARGETDURATION:16\n" +
      "#EXTINF:14.506,\npart-1.ts\n" +
      "#EXTINF:5.494,\npart-2.ts\n",
    ),
    20000,
  );
  assert.equal(
    availableHlsDurationMs(
      "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000\nchild.m3u8\n",
    ),
    null,
  );
});

test("reads the actual media start from Agora's first HLS segment", () => {
  const manifest =
    "#EXTM3U\n" +
    "#EXT-X-TARGETDURATION:16\n" +
    "#EXTINF:14.506,\n" +
    "prefix_probe_session_20260803132012996.ts\n" +
    "#EXTINF:5.494,\n" +
    "prefix_probe_session_20260803132027502.ts\n";
  assert.equal(
    firstHlsSegmentStartedAtMs(manifest),
    Date.UTC(2026, 7, 3, 13, 20, 12, 996),
  );
  assert.equal(
    hlsMediaTimelineOffsetSec({
      manifest,
      sessionStartedAtMs: Date.UTC(2026, 7, 3, 13, 20, 10, 75),
    }),
    2.921,
  );
  assert.equal(
    firstHlsSegmentStartedAtMs(
      "#EXTM3U\n#EXTINF:10,\nsegment-without-time.ts\n",
    ),
    null,
  );
  assert.equal(
    firstHlsSegmentStartedAtMs(
      "#EXTM3U\n#EXTINF:10,\nprefix_20260230000000000.ts\n",
    ),
    null,
  );
});

test("prefers Agora's NTP audio track start over the segment filename", () => {
  const sessionStartedAtMs = Date.UTC(2026, 7, 3, 13, 20, 10, 75);
  const audioStartedAtMs = Date.UTC(2026, 7, 3, 13, 20, 12, 855);
  const manifest =
    "#EXTM3U\n" +
    "#EXT-X-AGORA-TRACK-EVENT:" +
    "EVENT=START,TRACK_TYPE=AUDIO,TIME=20260803132012855\n" +
    "#EXTINF:14.506,\n" +
    "prefix_probe_session_20260803132012996.ts\n";
  assert.equal(firstHlsAudioTrackStartedAtMs(manifest), audioStartedAtMs);
  assert.equal(
    hlsMediaTimelineOffsetSec({manifest, sessionStartedAtMs}),
    2.78,
  );
  assert.equal(
    firstHlsAudioTrackStartedAtMs(
      "#EXTM3U\n" +
      "#EXT-X-AGORA-TRACK-EVENT:" +
      "EVENT=START,TRACK_TYPE=AUDIO,TIME=1785763212855\n",
    ),
    1785763212855,
  );
});

test("measures future archive compensation from Agora audio frame time", () => {
  assert.deepEqual(
    resolveLiveAudioPlaybackCompensation({
      timingVersion: 5,
      hlsMediaStartedAtMs: 1785781298967,
      audioCaptureStartedAtMs: 1785781297627,
    }),
    {compensationSec: 1.34, source: "agoraAudioFrame"},
  );
  assert.deepEqual(
    resolveLiveAudioPlaybackCompensation({
      timingVersion: 4,
      hlsMediaStartedAtMs: 1785781298967,
      audioCaptureStartedAtMs: 1785781297627,
    }),
    {compensationSec: 0, source: "legacy"},
  );
});

test("falls back when an audio frame anchor cannot be trusted", () => {
  assert.deepEqual(
    resolveLiveAudioPlaybackCompensation({
      timingVersion: 5,
      hlsMediaStartedAtMs: 1785781305000,
      audioCaptureStartedAtMs: 1785781297000,
    }),
    {compensationSec: 1.2, source: "fallback"},
  );
  assert.deepEqual(
    resolveLiveAudioPlaybackCompensation({
      timingVersion: 5,
      hlsMediaStartedAtMs: null,
      audioCaptureStartedAtMs: 0,
    }),
    {compensationSec: 1.2, source: "fallback"},
  );
});

test("signs expiring HLS access without exposing credentials", () => {
  const token = createHlsAccessToken(
    {
      sessionId: "12345678901234567890",
      uid: "teacher-1",
      expiresAtSec: 200,
    },
    "server-secret",
  );

  assert.deepEqual(verifyHlsAccessToken(token, "server-secret", 100), {
    sessionId: "12345678901234567890",
    uid: "teacher-1",
    expiresAtSec: 200,
  });
  assert.equal(verifyHlsAccessToken(token, "wrong-secret", 100), null);
  assert.equal(verifyHlsAccessToken(token, "server-secret", 201), null);
  assert.equal(token.includes("server-secret"), false);
});

test("rewrites relative HLS segment and map references through proxy", () => {
  const rewritten = rewriteHlsManifest({
    manifest:
      "#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:10,\npart-1.ts\n",
    manifestObjectPath:
      "liveAudioProbeSessions/12345678901234567890/audio/index.m3u8",
    proxyUrl:
      "https://example.test/liveAudioProbeHls",
    token: "signed-token",
  });

  assert.match(
    rewritten,
    /file=liveAudioProbeSessions%2F12345678901234567890%2Faudio%2Fpart-1.ts/,
  );
  assert.match(rewritten, /token=signed-token/);
  assert.match(rewritten, /init.mp4/);
  assert.equal(
    isSafeHlsObjectPath(
      "liveAudioProbeSessions/12345678901234567890/audio/part-1.ts",
      "12345678901234567890",
    ),
    true,
  );
  assert.equal(
    isSafeHlsObjectPath(
      "liveAudioProbeSessions/12345678901234567890/../secret",
      "12345678901234567890",
    ),
    false,
  );
});

test("rejects external manifest references", () => {
  assert.throws(() =>
    rewriteHlsManifest({
      manifest: "#EXTM3U\nhttps://evil.example/segment.ts\n",
      manifestObjectPath:
        "liveAudioProbeSessions/12345678901234567890/index.m3u8",
      proxyUrl: "https://example.test/liveAudioProbeHls",
      token: "signed-token",
    }),
  );
});
