import assert from "node:assert/strict";
import test from "node:test";

import {
  AgoraCloudRecordingClient,
  archiveManifestFromStored,
  basicAuthorizationHeader,
  buildAcquireRequest,
  buildStartRequest,
  buildStopRequest,
  extractArchiveManifest,
} from "./agora_cloud_recording";

test("builds Basic authentication without exposing credentials in payload", () => {
  assert.equal(
    basicAuthorizationHeader("customer", "secret"),
    `Basic ${Buffer.from("customer:secret").toString("base64")}`,
  );
  const payload = buildAcquireRequest("probe_channel", 123);
  assert.equal(JSON.stringify(payload).includes("customer"), false);
  assert.equal(JSON.stringify(payload).includes("secret"), false);
});

test("builds live-broadcast audio HLS and MP4 payload for Google Cloud", () => {
  const payload = buildStartRequest({
    channelName: "probe_channel",
    recorderUid: 123,
    recordingToken: "recording-token",
    fileNamePrefix: ["liveAudioProbeSessions", "AbCdEfGhIjKlMnOpQrSt"],
    config: {
      gcsAccessKey: "access",
      gcsSecretKey: "storage-secret",
      gcsBucket: "recordings",
    },
  });
  assert.deepEqual(payload, {
    cname: "probe_channel",
    uid: "123",
    clientRequest: {
      token: "recording-token",
      recordingConfig: {
        channelType: 1,
        streamTypes: 0,
        maxIdleTime: 120,
        audioProfile: 1,
      },
      recordingFileConfig: {
        avFileType: ["hls", "mp4"],
      },
      storageConfig: {
        vendor: 6,
        region: 0,
        bucket: "recordings",
        accessKey: "access",
        secretKey: "storage-secret",
        fileNamePrefix: [
          "liveAudioProbeSessions",
          "AbCdEfGhIjKlMnOpQrSt",
        ],
      },
    },
  });
  assert.deepEqual(buildStopRequest("probe_channel", 123), {
    cname: "probe_channel",
    uid: "123",
    clientRequest: {async_stop: false},
  });
});

test("uses acquire then mix start with Basic auth without network", async () => {
  const calls: Array<{url: string; init?: RequestInit}> = [];
  const responses = [
    {resourceId: "resource-1"},
    {sid: "sid-1"},
  ];
  const fakeFetch = async (
    input: string | URL | Request,
    init?: RequestInit,
  ): Promise<Response> => {
    calls.push({url: String(input), init});
    return new Response(JSON.stringify(responses.shift()), {
      status: 200,
      headers: {"Content-Type": "application/json"},
    });
  };
  const client = new AgoraCloudRecordingClient(
    {
      appId: "app-id",
      customerId: "customer",
      customerSecret: "secret",
      gcsAccessKey: "access",
      gcsSecretKey: "storage-secret",
      gcsBucket: "recordings",
    },
    fakeFetch,
  );
  const handle = await client.start({
    channelName: "probe_channel",
    recorderUid: 123,
    recordingToken: "recording-token",
    fileNamePrefix: ["liveAudioProbeSessions", "AbCdEfGhIjKlMnOpQrSt"],
  });

  assert.deepEqual(handle, {
    resourceId: "resource-1",
    sid: "sid-1",
    recorderUid: "123",
  });
  assert.equal(calls.length, 2);
  assert.match(calls[0].url, /cloud_recording\/acquire$/);
  assert.match(
    calls[1].url,
    /resourceid\/resource-1\/mode\/mix\/start$/,
  );
  assert.equal(
    (calls[0].init?.headers as Record<string, string>).Authorization,
    basicAuthorizationHeader("customer", "secret"),
  );
});

test("queries active mix recording without network", async () => {
  const calls: Array<{url: string; init?: RequestInit}> = [];
  const fakeFetch = async (
    input: string | URL | Request,
    init?: RequestInit,
  ): Promise<Response> => {
    calls.push({url: String(input), init});
    return new Response(JSON.stringify({
      serverResponse: {
        fileList: [
          {
            fileName:
              "liveAudioProbeSessions/AbCdEfGhIjKlMnOpQrSt/live.m3u8",
          },
        ],
      },
    }));
  };
  const client = new AgoraCloudRecordingClient(
    {
      appId: "app-id",
      customerId: "customer",
      customerSecret: "secret",
      gcsAccessKey: "access",
      gcsSecretKey: "storage-secret",
      gcsBucket: "recordings",
    },
    fakeFetch,
  );
  const queried = await client.query({
    resourceId: "resource-1",
    sid: "sid-1",
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].init?.method, "GET");
  assert.equal(calls[0].init?.body, undefined);
  assert.match(
    calls[0].url,
    /resourceid\/resource-1\/sid\/sid-1\/mode\/mix\/query$/,
  );
  assert.equal(
    queried.manifest?.manifestFile,
    "liveAudioProbeSessions/AbCdEfGhIjKlMnOpQrSt/live.m3u8",
  );
});

test("extracts safe HLS manifest metadata from stop response", () => {
  const manifest = extractArchiveManifest({
      serverResponse: {
        fileListMode: "json",
        fileList: [
          {
            fileName:
              "liveAudioProbeSessions/AbCdEfGhIjKlMnOpQrSt/archive.m3u8",
          },
          {
            fileName:
              "liveAudioProbeSessions/AbCdEfGhIjKlMnOpQrSt/archive.mp4",
          },
        ],
      },
    });
  assert.deepEqual(
    manifest,
    {
      fileListMode: "json",
      files: [
        "liveAudioProbeSessions/AbCdEfGhIjKlMnOpQrSt/archive.m3u8",
        "liveAudioProbeSessions/AbCdEfGhIjKlMnOpQrSt/archive.mp4",
      ],
      manifestFile:
        "liveAudioProbeSessions/AbCdEfGhIjKlMnOpQrSt/archive.m3u8",
    },
  );
  assert.deepEqual(archiveManifestFromStored(manifest), manifest);
  assert.equal(
    archiveManifestFromStored({
      fileListMode: "json",
      files: ["../secret.mp4"],
      manifestFile: "../secret.mp4",
    }),
    null,
  );
});
