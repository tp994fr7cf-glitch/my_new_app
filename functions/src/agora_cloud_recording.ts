const agoraCloudRecordingBaseUrl = "https://api.sd-rtn.com/v1/apps";

export type AgoraCloudRecordingConfig = {
  appId: string;
  customerId: string;
  customerSecret: string;
  gcsAccessKey: string;
  gcsSecretKey: string;
  gcsBucket: string;
};

export type StartCloudRecordingInput = {
  channelName: string;
  recorderUid: number;
  recordingToken: string;
  fileNamePrefix: readonly string[];
};

export type CloudRecordingHandle = {
  resourceId: string;
  sid: string;
  recorderUid: string;
};

export type AgoraCloudRecordingOperation =
  | "acquire"
  | "start"
  | "stop"
  | "query";

export type ArchiveManifest = {
  fileListMode: "string" | "json" | "unknown";
  files: string[];
  manifestFile: string;
};

type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

export class AgoraCloudRecordingError extends Error {
  constructor(
    message: string,
    readonly httpStatus?: number,
    readonly operation?: AgoraCloudRecordingOperation,
    readonly providerCode?: number,
  ) {
    super(message);
    this.name = "AgoraCloudRecordingError";
  }
}

export function basicAuthorizationHeader(
  customerId: string,
  customerSecret: string,
): string {
  return `Basic ${Buffer.from(
    `${customerId}:${customerSecret}`,
    "utf8",
  ).toString("base64")}`;
}

export function buildAcquireRequest(
  channelName: string,
  recorderUid: number,
): Record<string, unknown> {
  return {
    cname: channelName,
    uid: String(recorderUid),
    clientRequest: {
      scene: 0,
      resourceExpiredHour: 24,
    },
  };
}

export function buildStartRequest({
  channelName,
  recorderUid,
  recordingToken,
  fileNamePrefix,
  config,
}: StartCloudRecordingInput & {
  config: Pick<
    AgoraCloudRecordingConfig,
    "gcsAccessKey" | "gcsSecretKey" | "gcsBucket"
  >;
}): Record<string, unknown> {
  assertSafePrefix(fileNamePrefix);
  return {
    cname: channelName,
    uid: String(recorderUid),
    clientRequest: {
      token: recordingToken,
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
        bucket: config.gcsBucket,
        accessKey: config.gcsAccessKey,
        secretKey: config.gcsSecretKey,
        fileNamePrefix: [...fileNamePrefix],
      },
    },
  };
}

export function buildStopRequest(
  channelName: string,
  recorderUid: string | number,
): Record<string, unknown> {
  return {
    cname: channelName,
    uid: String(recorderUid),
    clientRequest: {
      async_stop: false,
    },
  };
}

export function isCompleteCloudRecordingConfig(
  config: AgoraCloudRecordingConfig,
): boolean {
  return Object.values(config).every((value) => value.trim().length > 0);
}

export function extractArchiveManifest(value: unknown): ArchiveManifest | null {
  const candidates: unknown[] = [];
  collectFileLists(value, candidates, 0);
  const files: string[] = [];
  let fileListMode: ArchiveManifest["fileListMode"] = "unknown";
  for (const candidate of candidates) {
    if (typeof candidate === "string") {
      fileListMode = "string";
      addSafeFile(files, candidate);
      continue;
    }
    if (!Array.isArray(candidate)) {
      continue;
    }
    fileListMode = "json";
    for (const entry of candidate) {
      if (typeof entry === "string") {
        addSafeFile(files, entry);
      } else if (isRecord(entry)) {
        const name =
          typeof entry.fileName === "string" ?
            entry.fileName :
            entry.filename;
        if (typeof name === "string") {
          addSafeFile(files, name);
        }
      }
    }
  }
  if (files.length === 0) {
    return null;
  }
  const manifestFile =
    files.find((file) => file.toLowerCase().endsWith(".m3u8")) ?? files[0];
  return {
    fileListMode,
    files: files.slice(0, 100),
    manifestFile,
  };
}

export function archiveManifestFromStored(
  value: unknown,
): ArchiveManifest | null {
  if (
    !isRecord(value) ||
    (
      value.fileListMode !== "string" &&
      value.fileListMode !== "json" &&
      value.fileListMode !== "unknown"
    ) ||
    !Array.isArray(value.files) ||
    typeof value.manifestFile !== "string"
  ) {
    return null;
  }
  const files: string[] = [];
  for (const file of value.files) {
    if (typeof file !== "string") {
      return null;
    }
    addSafeFile(files, file);
  }
  if (
    files.length !== value.files.length ||
    !files.includes(value.manifestFile)
  ) {
    return null;
  }
  return {
    fileListMode: value.fileListMode,
    files,
    manifestFile: value.manifestFile,
  };
}

export class AgoraCloudRecordingClient {
  constructor(
    private readonly config: AgoraCloudRecordingConfig,
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async start(
    input: StartCloudRecordingInput,
  ): Promise<CloudRecordingHandle> {
    const recorderUid = String(input.recorderUid);
    const acquired = await this.post(
      "/cloud_recording/acquire",
      buildAcquireRequest(input.channelName, input.recorderUid),
      "acquire",
    );
    const resourceId = requiredResponseId(acquired, "resourceId");
    const started = await this.post(
      `/cloud_recording/resourceid/${encodeURIComponent(resourceId)}` +
        "/mode/mix/start",
      buildStartRequest({...input, config: this.config}),
      "start",
    );
    return {
      resourceId,
      sid: requiredResponseId(started, "sid"),
      recorderUid,
    };
  }

  async stop({
    channelName,
    resourceId,
    sid,
    recorderUid,
  }: {
    channelName: string;
    resourceId: string;
    sid: string;
    recorderUid: string | number;
  }): Promise<{response: unknown; manifest: ArchiveManifest | null}> {
    const response = await this.post(
      `/cloud_recording/resourceid/${encodeURIComponent(resourceId)}` +
        `/sid/${encodeURIComponent(sid)}/mode/mix/stop`,
      buildStopRequest(channelName, recorderUid),
      "stop",
    );
    return {
      response,
      manifest: extractArchiveManifest(response),
    };
  }

  async query({
    resourceId,
    sid,
  }: {
    resourceId: string;
    sid: string;
  }): Promise<{response: unknown; manifest: ArchiveManifest | null}> {
    const response = await this.request(
      `/cloud_recording/resourceid/${encodeURIComponent(resourceId)}` +
        `/sid/${encodeURIComponent(sid)}/mode/mix/query`,
      "GET",
      undefined,
      "query",
    );
    return {
      response,
      manifest: extractArchiveManifest(response),
    };
  }

  private post(
    path: string,
    body: Record<string, unknown>,
    operation: AgoraCloudRecordingOperation,
  ): Promise<unknown> {
    return this.request(path, "POST", body, operation);
  }

  private async request(
    path: string,
    method: "GET" | "POST",
    body?: Record<string, unknown>,
    operation?: AgoraCloudRecordingOperation,
  ): Promise<unknown> {
    const appId = encodeURIComponent(this.config.appId);
    let response: Response;
    try {
      response = await this.fetchImpl(
        `${agoraCloudRecordingBaseUrl}/${appId}${path}`,
        {
          method,
          headers: {
            Authorization: basicAuthorizationHeader(
              this.config.customerId,
              this.config.customerSecret,
            ),
            "Content-Type": "application/json",
          },
          ...(body === undefined ? {} : {body: JSON.stringify(body)}),
        },
      );
    } catch {
      throw new AgoraCloudRecordingError(
        "Agora Cloud Recordingへ接続できませんでした。",
        undefined,
        operation,
      );
    }
    const text = await response.text();
    let payload: unknown = {};
    if (text) {
      try {
        payload = JSON.parse(text) as unknown;
      } catch {
        throw new AgoraCloudRecordingError(
          "Agora Cloud Recordingの応答が不正です。",
          response.status,
          operation,
        );
      }
    }
    if (!response.ok) {
      throw new AgoraCloudRecordingError(
        "Agora Cloud Recordingのリクエストが失敗しました。",
        response.status,
        operation,
        providerErrorCode(payload),
      );
    }
    return payload;
  }
}

function requiredResponseId(value: unknown, field: string): string {
  if (!isRecord(value)) {
    throw new AgoraCloudRecordingError(
      "Agora Cloud Recordingの応答が不完全です。",
    );
  }
  const id = value[field];
  if (typeof id !== "string" || !/^[A-Za-z0-9_-]{1,256}$/.test(id)) {
    throw new AgoraCloudRecordingError(
      "Agora Cloud Recordingの応答が不完全です。",
    );
  }
  return id;
}

function providerErrorCode(value: unknown): number | undefined {
  if (!isRecord(value)) {
    return undefined;
  }
  const code = value.code;
  return typeof code === "number" && Number.isSafeInteger(code) ?
    code :
    undefined;
}

function assertSafePrefix(prefix: readonly string[]): void {
  const totalLength = prefix.reduce((sum, part) => sum + part.length + 1, 0);
  if (
    prefix.length === 0 ||
    totalLength > 128 ||
    prefix.some((part) => !/^[A-Za-z0-9]+$/.test(part))
  ) {
    throw new AgoraCloudRecordingError("録音ファイルの保存先が不正です。");
  }
}

function collectFileLists(
  value: unknown,
  output: unknown[],
  depth: number,
): void {
  if (depth > 5 || value === null || typeof value !== "object") {
    return;
  }
  if (Array.isArray(value)) {
    for (const entry of value.slice(0, 100)) {
      collectFileLists(entry, output, depth + 1);
    }
    return;
  }
  for (const [key, entry] of Object.entries(value)) {
    if (key === "fileList") {
      output.push(entry);
    } else {
      collectFileLists(entry, output, depth + 1);
    }
  }
}

function addSafeFile(files: string[], value: string): void {
  const file = value.trim();
  if (
    files.length < 100 &&
    file.length > 0 &&
    file.length <= 512 &&
    !file.includes("..") &&
    /^[A-Za-z0-9._/-]+$/.test(file) &&
    !files.includes(file)
  ) {
    files.push(file);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
