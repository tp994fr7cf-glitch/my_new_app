import assert from "node:assert/strict";
import test from "node:test";

import {
  createHlsAccessToken,
  finalizedHlsDurationMs,
  isSafeHlsObjectPath,
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
