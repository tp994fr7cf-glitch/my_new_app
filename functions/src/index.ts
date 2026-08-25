import {createHash, randomInt, randomUUID} from "node:crypto";

import {initializeApp} from "firebase-admin/app";
import {
  DocumentData,
  DocumentReference,
  FieldValue,
  getFirestore,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {logger} from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";
import {setGlobalOptions} from "firebase-functions/v2";
import {
  CallableRequest,
  HttpsError,
  onCall,
  onRequest,
} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {RtcTokenBuilder} from "agora-token";

import {
  AgoraCloudRecordingClient,
  AgoraCloudRecordingConfig,
  AgoraCloudRecordingError,
  ArchiveManifest,
  archiveManifestFromStored,
  isCompleteCloudRecordingConfig,
} from "./agora_cloud_recording";
import {
  adjustLiveArchiveBoardSet,
  firebaseStorageDownloadUrl,
  prepareLiveArchiveDraft,
  resolveLiveArchiveDuration,
  selectManifestObject,
} from "./live_archive_draft";
import {
  calculatedLiveStartSec,
  nextDraftBaseDocumentVersionAfterLiveReservation,
} from "./live_segment_reservation";
import {
  availableHlsDurationMs,
  createHlsAccessToken,
  finalizedHlsDurationMs,
  hlsMediaTimelineOffsetSec,
  isSafeHlsObjectPath,
  resolveLiveAudioPlaybackCompensation,
  rewriteHlsManifest,
  verifyHlsAccessToken,
} from "./live_hls_proxy";
import {
  isLiveSessionState,
  isSupportedSessionState,
  isValidBoardSet,
  isValidLiveAudioJoinCode,
  isValidOptionalLinkId,
  isValidProbeSessionId,
  isValidSegmentStartSec,
  isValidTimelineChunk,
  isValidWhiteboardStroke,
  hasLiveAudioProbeExceededMaxDuration,
  liveAudioArchiveTokenLifetimeSec,
  liveAudioProbeMaxDurationMs,
  liveAudioProbeMaxDurationSec,
  liveAudioProbeTokenLifetimeSec,
  maxLiveAudioProbeStrokes,
  maxLiveAudioTimelineEvents,
  maximumAllowedGlobalTimestampSec,
  canDrawBoard,
  canPublishAudio,
  permissionForParticipant,
  resolveActivePresenterUid,
  resolveCoSpeakerUid,
  remainingLiveAudioProbeDurationSec,
  rtcUidForFirebaseUser,
  validateTimelineBoardReferences,
} from "./live_audio_probe";
import {
  cleanupRawArchivesForCourse,
  CourseLiveArchiveInProgressError,
  runDeletedCourseRawArchiveCleanup,
  runLiveAudioProbeRawRetention,
} from
  "./live_audio_probe_retention_runtime";

initializeApp();
setGlobalOptions({region: "asia-northeast1", maxInstances: 10});

const agoraAppId = defineSecret("AGORA_APP_ID");
const agoraAppCertificate = defineSecret("AGORA_APP_CERTIFICATE");
const agoraCustomerId = defineSecret("AGORA_CUSTOMER_ID");
const agoraCustomerSecret = defineSecret("AGORA_CUSTOMER_SECRET");
const agoraGcsAccessKey = defineSecret("AGORA_GCS_ACCESS_KEY");
const agoraGcsSecretKey = defineSecret("AGORA_GCS_SECRET_KEY");
const agoraGcsBucket = defineSecret("AGORA_GCS_BUCKET");
const archiveSecrets = [
  agoraAppId,
  agoraAppCertificate,
  agoraCustomerId,
  agoraCustomerSecret,
  agoraGcsAccessKey,
  agoraGcsSecretKey,
  agoraGcsBucket,
];

const db = getFirestore();
const sessionCollection = "liveAudioProbeSessions";
const joinCodeCollection = "liveAudioProbeJoinCodes";
const archivePrefixRoot = "liveAudioProbeSessions";
// Timing v5 is the current device-verified baseline for live audio/board sync.
// It ties together Agora NTP board timestamps, the HLS audio-track origin, and
// per-session capture compensation. This is not an immutable design: change it
// when a reproduced bug justifies doing so, but use a new timing version rather
// than silently changing how already-created sessions are interpreted.
const liveArchiveTimingVersion = 5;
// Used only when the per-session Android audio-frame measurement is unavailable.
const liveAudioPlaybackFallbackCompensationSec = 1.2;
const archiveConfigWarning =
  "録音の保存設定が未完了です。配信は続けられますが、録音は保存されません。";
const archiveStartWarning =
  "録音の自動保存を開始できませんでした。配信は続けられます。先生はあとで再試行できます。";
const archiveStopWarning =
  "配信は終了しましたが、録音ファイルを確認できませんでした。先生はあとで再試行できます。";
const archiveMp4Warning =
  "配信は終了しましたが、レッスン用のMP4録音ファイルを確認できませんでした。";
const archiveStorageWarning =
  "配信は終了しましたが、録音をレッスン用保存先へコピーできませんでした。保存元バケットの読み取り権限を確認してください。";
const archiveDraftWarning =
  "配信は終了しましたが、レッスン下書きを安全に作成できませんでした。講座・レッスン・予約枠・版を確認してください。";

export const cleanupLiveAudioProbeRawArchives = onSchedule(
  {
    schedule: "15 4 * * *",
    timeZone: "Asia/Tokyo",
    secrets: [agoraGcsBucket],
    timeoutSeconds: 540,
    maxInstances: 1,
    retryCount: 0,
  },
  async (event) => {
    logger.info("live_audio_probe_raw_cleanup_started", {
      event: "cleanup_started",
      scheduleTime: event.scheduleTime,
    });
    try {
      const storage = getStorage();
      const rawBucketName = agoraGcsBucket.value().trim();
      if (!rawBucketName) {
        throw new Error("AGORA_GCS_BUCKET is empty.");
      }
      const rawBucket = storage.bucket(rawBucketName);
      await runDeletedCourseRawArchiveCleanup({
        db,
        rawBucket,
        log: (entry) => {
          logger.info(`live_audio_probe_raw_${entry.event}`, entry);
        },
      });
      await runLiveAudioProbeRawRetention({
        db,
        rawBucket,
        completedCopyBucket: storage.bucket(),
        mode: "apply",
        selectionPolicy: "threshold",
        log: (entry) => {
          const message = `live_audio_probe_raw_${entry.event}`;
          if (
            entry.event === "session_skipped" ||
            entry.event === "session_partially_deleted" ||
            (entry.event === "cleanup_complete" &&
              entry.targetReached !== true)
          ) {
            logger.warn(message, entry);
          } else {
            logger.info(message, entry);
          }
        },
      });
    } catch (error) {
      logger.error("live_audio_probe_raw_cleanup_failed", {
        event: "cleanup_failed",
        errorName: error instanceof Error ? error.name : "UnknownError",
      });
      throw error;
    }
  },
);

export const deleteLiveAudioProbeRawArchivesForCourse = onCall(
  {
    secrets: [agoraGcsBucket],
    timeoutSeconds: 540,
  },
  async (request) => {
    const uid = requireAuthenticatedUid(request);
    await requireActiveTeacher(
      uid,
      "先生として利用中のユーザーだけが講座の生録画を削除できます。",
    );
    const data =
      request.data !== null &&
        typeof request.data === "object" &&
        !Array.isArray(request.data) ?
        request.data as Record<string, unknown> :
        {};
    const courseId = data.courseId;
    if (!isValidOptionalLinkId(courseId)) {
      throw new HttpsError("invalid-argument", "講座IDが不正です。");
    }
    const mode = data.mode === "check" ? "check" : "delete";
    const courseSnapshot = await db.collection("courses").doc(courseId).get();
    if (!courseSnapshot.exists) {
      throw new HttpsError("not-found", "講座が見つかりません。");
    }
    const course = courseSnapshot.data() ?? {};
    if (course.instructorId !== uid) {
      throw new HttpsError(
        "permission-denied",
        "この講座の生録画を削除する権限がありません。",
      );
    }
    const status = course.status;
    if (
      status !== "published" &&
      status !== "deleting" &&
      status !== "deleted"
    ) {
      throw new HttpsError(
        "failed-precondition",
        "この講座の状態では生録画を削除できません。",
      );
    }
    const rawBucketName = agoraGcsBucket.value().trim();
    if (!rawBucketName) {
      throw new HttpsError(
        "failed-precondition",
        "生録画の保存先が設定されていないため削除できません。",
      );
    }
    try {
      const result = await cleanupRawArchivesForCourse({
        db,
        rawBucket: getStorage().bucket(rawBucketName),
        courseId,
        mode,
        refuseIfLive: true,
        log: (entry) => {
          logger.info(`live_audio_probe_raw_${entry.event}`, entry);
        },
      });
      return {
        courseId: result.courseId,
        mode: result.mode,
        sessionCount: result.sessionCount,
        deletedSessionCount: result.deletedSessionCount,
        deletedBytes: result.deletedBytes,
        deletedObjectCount: result.deletedObjectCount,
      };
    } catch (error) {
      if (error instanceof CourseLiveArchiveInProgressError) {
        throw new HttpsError("failed-precondition", error.message);
      }
      throw error;
    }
  },
);

export const enforceLiveAudioProbeDurationLimit = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "Asia/Tokyo",
    secrets: archiveSecrets,
    timeoutSeconds: 540,
    maxInstances: 1,
    retryCount: 1,
  },
  async (event) => {
    const collection = db.collection(sessionCollection);
    const [activeByStatus, liveByState, finalizingByState] = await Promise.all([
      collection.where("status", "==", "active").get(),
      collection.where("state", "==", "live").get(),
      collection.where("state", "==", "finalizing").get(),
    ]);
    const activeSessions = new Map<
      string,
      QueryDocumentSnapshot<DocumentData>
    >();
    for (const snapshot of [...activeByStatus.docs, ...liveByState.docs]) {
      activeSessions.set(snapshot.id, snapshot);
    }
    const nowMs = Date.now();
    const expiredSessions = [...activeSessions.values()].filter((snapshot) => {
      return hasLiveAudioProbeExceededMaxDuration({
        startedAtMs: snapshot.data().startedAtMs,
        nowMs,
      });
    });
    const pendingForcedFinalizations = finalizingByState.docs.filter(
      (snapshot) => snapshot.data().closeReason === "maxDuration",
    );
    logger.info("live_audio_probe_duration_limit_checked", {
      event: "duration_limit_checked",
      scheduleTime: event.scheduleTime,
      activeCount: activeSessions.size,
      expiredCount: expiredSessions.length,
      pendingFinalizationCount: pendingForcedFinalizations.length,
    });

    for (const snapshot of expiredSessions) {
      const session = snapshot.data();
      const ownerUid = stringField(session.ownerUid);
      if (!ownerUid) {
        logger.error("live_audio_probe_duration_limit_invalid_owner", {
          event: "duration_limit_invalid_owner",
          sessionId: snapshot.id,
        });
        continue;
      }
      try {
        const closing = await moveSessionToFinalizing(
          snapshot.ref,
          ownerUid,
          false,
          "maxDuration",
        );
        if (!closing.alreadyClosed) {
          await stopArchiveAndFinalize(snapshot.ref, closing.session);
        }
        logger.warn("live_audio_probe_duration_limit_enforced", {
          event: "duration_limit_enforced",
          sessionId: snapshot.id,
          startedAtMs: safeNonNegativeInteger(session.startedAtMs),
          enforcedAtMs: nowMs,
        });
      } catch (error) {
        logArchiveError("duration-limit", error);
      }
    }

    for (const snapshot of pendingForcedFinalizations) {
      try {
        await stopArchiveAndFinalize(snapshot.ref, snapshot.data());
        logger.warn("live_audio_probe_duration_limit_finalization_retried", {
          event: "duration_limit_finalization_retried",
          sessionId: snapshot.id,
        });
      } catch (error) {
        logArchiveError("duration-limit-finalization-retry", error);
      }
    }
  },
);

export const createLiveAudioProbeSession = onCall(
  {secrets: archiveSecrets, timeoutSeconds: 120},
  async (request) => {
    const uid = requireAuthenticatedUid(request);
    await requireActiveTeacher(uid);
    const input = validatedCreateInput(request.data);

    const sessionReference = db.collection(sessionCollection).doc();
    const joinCode = await reserveLiveAudioJoinCode({
      sessionId: sessionReference.id,
      ownerUid: uid,
    });
    const participantReference = sessionReference
      .collection("participants")
      .doc(uid);
    const archiveBaselineReference = sessionReference
      .collection("archiveInternal")
      .doc("baseline");
    const displayName = authenticatedDisplayName(request);
    const rtcUid = rtcUidForFirebaseUser(uid);
    const channelName = `probe_${sessionReference.id}`;
    const startedAtMs = Date.now();
    const maximumEndsAtMs = startedAtMs + liveAudioProbeMaxDurationMs;
    const now = FieldValue.serverTimestamp();
    const sessionData = {
      ownerUid: uid,
      activePresenterUid: uid,
      channelName,
      joinCode,
      status: "active",
      state: "live",
      presenterUids: [],
      startedAtMs,
      maximumEndsAtMs,
      maximumDurationSec: liveAudioProbeMaxDurationSec,
      archiveTimingVersion: liveArchiveTimingVersion,
      timelineClockSource: "agoraNtp",
      audioPlaybackCompensationSec:
        liveAudioPlaybackFallbackCompensationSec,
      audioPlaybackCompensationSource: "fallback",
      archiveStatus: "starting",
      archiveError: null,
      archiveErrorCode: null,
      archivePrefix: `${archivePrefixRoot}/${sessionReference.id}/`,
      boardSetRevision: input.initialBoardSet === undefined ? 0 : 1,
      segmentStartSec: input.segmentStartSec,
      timelineCreatedBoardIds: [],
      timelineCreatedBoardOrders: [],
      ...(input.initialBoardSet === undefined ?
        {} :
        {boardSetSnapshot: input.initialBoardSet}),
      timelineNextSequence: 0,
      ...input.links,
      createdAt: now,
      updatedAt: now,
    };
    const participantData = {
      uid,
      rtcUid,
      displayName,
      permission: "publisher",
      joinedAt: now,
      updatedAt: now,
    };
    await db.runTransaction(async (transaction) => {
      const links = input.links;
      const linkedIds = [links.courseId, links.lessonId, links.segmentId];
      const hasAnyLink = linkedIds.some((value) => typeof value === "string");
      if (hasAnyLink && linkedIds.some((value) => typeof value !== "string")) {
        throw new HttpsError(
          "invalid-argument",
          "講座・レッスン・配信パートは3項目すべて指定してください。",
        );
      }
      if (hasAnyLink) {
        const courseReference = db.collection("courses").doc(links.courseId);
        const lessonReference = courseReference
          .collection("lessons")
          .doc(links.lessonId);
        const draftReference = courseReference
          .collection("lessonDrafts")
          .doc(links.lessonId);
        const [courseSnapshot, lessonSnapshot, draftSnapshot] =
          await Promise.all([
            transaction.get(courseReference),
            transaction.get(lessonReference),
            transaction.get(draftReference),
          ]);
        if (!courseSnapshot.exists || !lessonSnapshot.exists) {
          throw new HttpsError(
            "not-found",
            "配信を結び付けるレッスンが見つかりません。",
          );
        }
        const course = courseSnapshot.data() ?? {};
        const lesson = lessonSnapshot.data() ?? {};
        if (
          course.instructorId !== uid ||
          course.status === "deleting" ||
          course.status === "deleted"
        ) {
          throw new HttpsError(
            "permission-denied",
            "このレッスンで配信を開始する権限がありません。",
          );
        }
        const reserved = reserveLiveSegmentForSession({
          lesson,
          segmentId: links.segmentId,
          sessionId: sessionReference.id,
          requestedStartSec: input.segmentStartSec,
        });
        if (!reserved.ok) {
          throw new HttpsError("failed-precondition", reserved.message);
        }
        transaction.update(lessonReference, {
          mediaSegments: reserved.mediaSegments,
          documentVersion: reserved.documentVersion,
          updatedAt: now,
        });
        transaction.update(courseReference, {updatedAt: now});
        const nextDraftBase =
          nextDraftBaseDocumentVersionAfterLiveReservation({
            draftExists: draftSnapshot.exists,
            draftBaseDocumentVersion:
              draftSnapshot.data()?.baseLessonDocumentVersion,
            currentLessonDocumentVersion: lesson.documentVersion,
            nextLessonDocumentVersion: reserved.documentVersion,
          });
        if (nextDraftBase !== null) {
          transaction.update(draftReference, {
            baseLessonDocumentVersion: nextDraftBase,
            updatedAt: now,
          });
        }
      }
      transaction.create(sessionReference, sessionData);
      transaction.create(participantReference, participantData);
      transaction.create(archiveBaselineReference, {
        timingVersion: liveArchiveTimingVersion,
        boardSet: input.initialBoardSet ?? null,
        createdAt: now,
      });
    }).catch(async (error: unknown) => {
      await releaseLiveAudioJoinCode({
        joinCode,
        sessionId: sessionReference.id,
      });
      throw error;
    });

    const archive = await startArchiveWithoutFailingLive({
      sessionReference,
      sessionId: sessionReference.id,
      channelName,
    });
    return {
      sessionId: sessionReference.id,
      joinCode,
      archiveStatus: archive.archiveStatus,
      warning: archive.warning,
    };
  },
);

export const resolveLiveAudioProbeJoinCode = onCall(async (request) => {
  requireAuthenticatedUid(request);
  const joinCode = requireLiveAudioJoinCode(request.data?.joinCode);
  const mapping = await db.collection(joinCodeCollection).doc(joinCode).get();
  if (!mapping.exists) {
    throw new HttpsError("not-found", "配信コードに一致する配信が見つかりません。");
  }
  const sessionId = stringField(mapping.data()?.sessionId);
  if (!isValidProbeSessionId(sessionId)) {
    throw new HttpsError("not-found", "配信コードに一致する配信が見つかりません。");
  }
  const session = await db.collection(sessionCollection).doc(sessionId).get();
  if (
    !session.exists ||
    !isLiveSessionState(storedSessionState(session.data() ?? {}))
  ) {
    throw new HttpsError("not-found", "配信コードに一致する配信が見つかりません。");
  }
  return {sessionId};
});

export const issueLiveAudioProbeToken = onCall(
  {secrets: [agoraAppId, agoraAppCertificate]},
  async (request) => {
    const uid = requireAuthenticatedUid(request);
    const sessionId = requireSessionId(request.data?.sessionId);
    const sessionReference = db.collection(sessionCollection).doc(sessionId);
    const participantReference = sessionReference
      .collection("participants")
      .doc(uid);
    // Session read and participant.permission write stay in one transaction so
    // a concurrent presenter change cannot stamp a stale role onto the doc.
    const issued = await db.runTransaction(async (transaction) => {
      const sessionSnapshot = await transaction.get(sessionReference);
      if (!sessionSnapshot.exists) {
        throw new HttpsError("not-found", "検証配信が見つかりません。");
      }
      const session = sessionSnapshot.data() ?? {};
      requireLiveSession(session);
      const remainingDurationSec = remainingLiveAudioProbeDurationSec({
        startedAtMs: session.startedAtMs,
        nowMs: Date.now(),
      });
      if (remainingDurationSec <= 0) {
        throw new HttpsError(
          "failed-precondition",
          "この配信は1時間の上限に達したため終了しました。",
        );
      }
      const ownerUid = stringField(session.ownerUid);
      const presenterUids = stringListField(session.presenterUids);
      const activePresenterUid = resolveActivePresenterUid({
        ownerUid,
        activePresenterUid: stringField(session.activePresenterUid),
        presenterUids,
      });
      const permission = permissionForParticipant({
        ownerUid,
        participantUid: uid,
        activePresenterUid,
        presenterUids,
      });
      const canDraw = canDrawBoard({
        ownerUid,
        participantUid: uid,
        activePresenterUid,
        presenterUids,
      });
      const rtcUid = rtcUidForFirebaseUser(uid);
      const displayName = authenticatedDisplayName(request);
      const now = FieldValue.serverTimestamp();
      const participantSnapshot = await transaction.get(participantReference);
      const participantUpdate: Record<string, unknown> = {
        uid,
        rtcUid,
        displayName,
        permission,
        updatedAt: now,
      };
      if (!participantSnapshot.exists) {
        participantUpdate.joinedAt = now;
      }
      transaction.set(participantReference, participantUpdate, {merge: true});
      return {
        permission,
        canDraw,
        rtcUid,
        channelName: stringField(session.channelName),
        remainingDurationSec,
        maximumEndsAtMs:
          safeNonNegativeInteger(session.maximumEndsAtMs) ||
          safeNonNegativeInteger(session.startedAtMs) +
            liveAudioProbeMaxDurationMs,
      };
    });

    const appId = agoraAppId.value().trim();
    const appCertificate = agoraAppCertificate.value().trim();
    if (!appId || !appCertificate) {
      throw new HttpsError(
        "failed-precondition",
        "Agoraの安全なサーバー設定が完了していません。",
      );
    }
    const canPublish = issued.permission === "publisher";
    const tokenLifetimeSec = Math.min(
      liveAudioProbeTokenLifetimeSec,
      issued.remainingDurationSec,
    );
    const token = RtcTokenBuilder.buildTokenWithUidAndPrivilege(
      appId,
      appCertificate,
      issued.channelName,
      issued.rtcUid,
      tokenLifetimeSec,
      tokenLifetimeSec,
      canPublish ? tokenLifetimeSec : 0,
      0,
      canPublish ? tokenLifetimeSec : 0,
    );
    return {
      appId,
      channelName: issued.channelName,
      rtcUid: issued.rtcUid,
      token,
      permission: issued.permission,
      canDraw: issued.canDraw,
      expiresInSec: tokenLifetimeSec,
      serverNowMs: Date.now(),
      maximumEndsAtMs: issued.maximumEndsAtMs,
    };
  },
);

export const setLiveAudioProbePresenter = onCall(async (request) => {
  const uid = requireAuthenticatedUid(request);
  const sessionId = requireSessionId(request.data?.sessionId);
  const participantUid = requireNonEmptyString(
    request.data?.participantUid,
    "対象の参加者を特定できません。",
  );
  const enabled = request.data?.enabled;
  if (typeof enabled !== "boolean") {
    throw new HttpsError("invalid-argument", "許可の値が不正です。");
  }
  const control = request.data?.control;
  if (control !== "coSpeaker" && control !== "drawer") {
    throw new HttpsError("invalid-argument", "操作の種類が不正です。");
  }
  const sessionReference = db.collection(sessionCollection).doc(sessionId);
  return db.runTransaction(async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionReference);
    if (!sessionSnapshot.exists) {
      throw new HttpsError("not-found", "検証配信が見つかりません。");
    }
    const session = sessionSnapshot.data() ?? {};
    const ownerUid = stringField(session.ownerUid);
    if (ownerUid !== uid) {
      throw new HttpsError(
        "permission-denied",
        "配信を開始した先生だけが許可を変更できます。",
      );
    }
    requireLiveSession(session);
    const presenterUids = stringListField(session.presenterUids);
    const currentCoSpeakerUid = resolveCoSpeakerUid({
      ownerUid,
      activePresenterUid: stringField(session.activePresenterUid),
      presenterUids,
    });
    const currentDrawerUid = resolveActivePresenterUid({
      ownerUid,
      activePresenterUid: stringField(session.activePresenterUid),
      presenterUids,
    });
    const requestedParticipantReference = sessionReference
      .collection("participants")
      .doc(participantUid);
    const ownerParticipantReference = sessionReference
      .collection("participants")
      .doc(ownerUid);
    const currentCoSpeakerReference = currentCoSpeakerUid ?
      sessionReference.collection("participants").doc(currentCoSpeakerUid) :
      null;
    const references = new Map<string, DocumentReference<DocumentData>>([
      [participantUid, requestedParticipantReference],
      [ownerUid, ownerParticipantReference],
    ]);
    if (currentCoSpeakerReference && currentCoSpeakerUid) {
      references.set(currentCoSpeakerUid, currentCoSpeakerReference);
    }
    const snapshots = new Map<string, boolean>();
    for (const [participantId, reference] of references) {
      snapshots.set(participantId, (await transaction.get(reference)).exists);
    }
    if (!snapshots.get(participantUid)) {
      throw new HttpsError(
        "not-found",
        "対象の参加者はまだこの配信へ参加していません。",
      );
    }

    const now = FieldValue.serverTimestamp();
    let nextCoSpeakerUid = currentCoSpeakerUid;
    let nextDrawerUid = currentDrawerUid;

    if (control === "coSpeaker") {
      if (participantUid === ownerUid) {
        throw new HttpsError(
          "failed-precondition",
          "先生のマイクは配信中ずっと使えます。",
        );
      }
      if (enabled) {
        nextCoSpeakerUid = participantUid;
        if (currentDrawerUid !== ownerUid && currentDrawerUid !== participantUid) {
          nextDrawerUid = ownerUid;
        }
      } else if (currentCoSpeakerUid === participantUid) {
        nextCoSpeakerUid = undefined;
        if (currentDrawerUid === participantUid) {
          nextDrawerUid = ownerUid;
        }
      }
    } else if (enabled) {
      if (participantUid !== ownerUid && participantUid !== currentCoSpeakerUid) {
        throw new HttpsError(
          "failed-precondition",
          "書き物を渡せるのは、一緒に話している受講者だけです。",
        );
      }
      nextDrawerUid = participantUid;
    } else if (participantUid !== ownerUid && currentDrawerUid === participantUid) {
      nextDrawerUid = ownerUid;
    }

    const nextPresenterUids = nextCoSpeakerUid ? [nextCoSpeakerUid] : [];
    transaction.update(sessionReference, {
      activePresenterUid: nextDrawerUid,
      presenterUids: nextPresenterUids,
      updatedAt: now,
    });
    if (snapshots.get(ownerUid)) {
      transaction.update(ownerParticipantReference, {
        permission: "publisher",
        updatedAt: now,
      });
    }
    if (
      currentCoSpeakerUid &&
      currentCoSpeakerUid !== nextCoSpeakerUid &&
      snapshots.get(currentCoSpeakerUid)
    ) {
      transaction.update(
        sessionReference.collection("participants").doc(currentCoSpeakerUid),
        {
          permission: "subscriber",
          updatedAt: now,
        },
      );
    }
    if (nextCoSpeakerUid && snapshots.get(nextCoSpeakerUid)) {
      transaction.update(
        sessionReference.collection("participants").doc(nextCoSpeakerUid),
        {
          permission: "publisher",
          updatedAt: now,
        },
      );
    } else if (
      participantUid !== ownerUid &&
      participantUid !== nextCoSpeakerUid &&
      snapshots.get(participantUid)
    ) {
      transaction.update(requestedParticipantReference, {
        permission: "subscriber",
        updatedAt: now,
      });
    }
    return {
      activePresenterUid: nextDrawerUid,
      coSpeakerUid: nextCoSpeakerUid ?? null,
      enabled:
        control === "coSpeaker" ?
          nextCoSpeakerUid === participantUid :
          nextDrawerUid === participantUid,
    };
  });
});

export const leaveLiveAudioProbeSession = onCall(async (request) => {
  const uid = requireAuthenticatedUid(request);
  const sessionId = requireSessionId(request.data?.sessionId);
  const sessionReference = db.collection(sessionCollection).doc(sessionId);
  return db.runTransaction(async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionReference);
    if (!sessionSnapshot.exists) {
      throw new HttpsError("not-found", "検証配信が見つかりません。");
    }
    const session = sessionSnapshot.data() ?? {};
    if (!isLiveSessionState(storedSessionState(session))) {
      return {released: false};
    }
    const ownerUid = stringField(session.ownerUid);
    if (uid === ownerUid) {
      return {released: false};
    }
    const presenterUids = stringListField(session.presenterUids);
    const currentCoSpeakerUid = resolveCoSpeakerUid({
      ownerUid,
      activePresenterUid: stringField(session.activePresenterUid),
      presenterUids,
    });
    const currentDrawerUid = resolveActivePresenterUid({
      ownerUid,
      activePresenterUid: stringField(session.activePresenterUid),
      presenterUids,
    });
    if (uid !== currentCoSpeakerUid && uid !== currentDrawerUid) {
      return {released: false};
    }
    const participantReference = sessionReference
      .collection("participants")
      .doc(uid);
    const participantExists = (await transaction.get(participantReference))
      .exists;
    const now = FieldValue.serverTimestamp();
    transaction.update(sessionReference, {
      activePresenterUid: ownerUid,
      presenterUids: [],
      updatedAt: now,
    });
    if (participantExists) {
      transaction.update(participantReference, {
        permission: "subscriber",
        updatedAt: now,
      });
    }
    return {released: true};
  });
});

export const reportLiveAudioProbeAudioCaptureStart = onCall(
  async (request) => {
    const uid = requireAuthenticatedUid(request);
    const sessionId = requireSessionId(request.data?.sessionId);
    const audioCaptureStartedAtMs = request.data?.audioCaptureStartedAtMs;
    if (
      typeof audioCaptureStartedAtMs !== "number" ||
      !Number.isSafeInteger(audioCaptureStartedAtMs) ||
      audioCaptureStartedAtMs <= 0
    ) {
      throw new HttpsError(
        "invalid-argument",
        "音声時刻の値が不正です。",
      );
    }
    const sessionReference = db.collection(sessionCollection).doc(sessionId);
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(sessionReference);
      if (!snapshot.exists) {
        throw new HttpsError("not-found", "検証配信が見つかりません。");
      }
      const session = snapshot.data() ?? {};
      requireAudioPublisher(session, uid);
      if (safeNonNegativeInteger(session.archiveTimingVersion) < 5) {
        return {stored: false};
      }
      const existing = safeNonNegativeInteger(
        session.audioCaptureStartedAtMs,
      );
      if (existing > 0) {
        return {stored: false, audioCaptureStartedAtMs: existing};
      }
      const startedAtMs = safeNonNegativeInteger(session.startedAtMs);
      const nowMs = Date.now();
      if (
        startedAtMs <= 0 ||
        audioCaptureStartedAtMs < startedAtMs - 5000 ||
        audioCaptureStartedAtMs > nowMs + 5000
      ) {
        throw new HttpsError(
          "invalid-argument",
          "音声時刻が配信時間の範囲外です。",
        );
      }
      transaction.update(sessionReference, {
        audioCaptureStartedAtMs,
        audioCaptureClockSource: "agoraAudioFrame",
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {stored: true, audioCaptureStartedAtMs};
    });
  },
);

export const saveLiveAudioProbeStroke = onCall(async (request) => {
  const uid = requireAuthenticatedUid(request);
  const sessionId = requireSessionId(request.data?.sessionId);
  const boardId = request.data?.boardId;
  if (!isValidOptionalLinkId(boardId)) {
    throw new HttpsError("invalid-argument", "ホワイトボードIDが不正です。");
  }
  const stroke = request.data?.stroke;
  if (!isValidWhiteboardStroke(stroke)) {
    throw new HttpsError("invalid-argument", "板書データが不正です。");
  }
  const sessionReference = db.collection(sessionCollection).doc(sessionId);
  const sessionSnapshot = await sessionReference.get();
  if (!sessionSnapshot.exists) {
    throw new HttpsError("not-found", "検証配信が見つかりません。");
  }
  const session = sessionSnapshot.data() ?? {};
  requirePublisher(session, uid);
  const boards = boardsFromSnapshot(session.boardSetSnapshot);
  if (boards.size > 0 && !boards.has(boardId)) {
    throw new HttpsError(
      "invalid-argument",
      "存在しないホワイトボードへ板書を保存できません。",
    );
  }

  const strokeReference = sessionReference
    .collection("whiteboardStrokes")
    .doc(stroke.id);
  const existingStroke = await strokeReference.get();
  if (!existingStroke.exists) {
    const countSnapshot = await sessionReference
      .collection("whiteboardStrokes")
      .count()
      .get();
    if (countSnapshot.data().count >= maxLiveAudioProbeStrokes) {
      throw new HttpsError(
        "resource-exhausted",
        `検証用ホワイトボードは${maxLiveAudioProbeStrokes}本までです。`,
      );
    }
  }
  await strokeReference.set({
    ...stroke,
    boardId,
    authorUid: uid,
    savedAtMs: Date.now(),
    savedAt: FieldValue.serverTimestamp(),
  });
  return {saved: true};
});

export const saveLiveAudioProbeBoardSet = onCall(async (request) => {
  const uid = requireAuthenticatedUid(request);
  const sessionId = requireSessionId(request.data?.sessionId);
  const boardSet = request.data?.boardSet;
  if (!isValidBoardSet(boardSet)) {
    throw new HttpsError(
      "invalid-argument",
      "ホワイトボード全体のデータが不正、または大きすぎます。",
    );
  }
  const expectedRevision = request.data?.expectedRevision;
  if (
    expectedRevision !== undefined &&
    (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0)
  ) {
    throw new HttpsError("invalid-argument", "保存番号が不正です。");
  }
  const sessionReference = db.collection(sessionCollection).doc(sessionId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(sessionReference);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "検証配信が見つかりません。");
    }
    const session = snapshot.data() ?? {};
    requirePublisher(session, uid);
    const currentRevision = safeNonNegativeInteger(session.boardSetRevision);
    if (
      expectedRevision !== undefined &&
      expectedRevision !== currentRevision
    ) {
      throw new HttpsError(
        "aborted",
        "別の端末で板書が更新されました。最新データを読み直してください。",
      );
    }
    const nextRevision = currentRevision + 1;
    const savedAtMs = Date.now();
    transaction.update(sessionReference, {
      boardSetSnapshot: boardSet,
      boardSetRevision: nextRevision,
      boardSetSavedByUid: uid,
      boardSetSavedAtMs: savedAtMs,
      boardSetSavedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {saved: true, revision: nextRevision, savedAtMs};
  });
});

export const appendLiveAudioProbeTimelineChunk = onCall(async (request) => {
  const uid = requireAuthenticatedUid(request);
  const sessionId = requireSessionId(request.data?.sessionId);
  const chunk = {
    expectedNextSequence: request.data?.expectedNextSequence,
    chunkId: request.data?.chunkId,
    events: request.data?.events,
  };
  if (!isValidTimelineChunk(chunk)) {
    throw new HttpsError(
      "invalid-argument",
      "配信タイムラインのデータが不正、または大きすぎます。",
    );
  }
  const sessionReference = db.collection(sessionCollection).doc(sessionId);
  const chunkReference = sessionReference
    .collection("timelineChunks")
    .doc(chunk.chunkId);
  const payloadHash = createHash("sha256")
    .update(JSON.stringify(chunk.events))
    .digest("hex");
  return db.runTransaction(async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionReference);
    const existingChunk = await transaction.get(chunkReference);
    if (!sessionSnapshot.exists) {
      throw new HttpsError("not-found", "検証配信が見つかりません。");
    }
    if (existingChunk.exists) {
      const existing = existingChunk.data() ?? {};
      if (
        existing.authorUid !== uid ||
        existing.eventCount !== chunk.events.length ||
        existing.payloadHash !== payloadHash
      ) {
        throw new HttpsError(
          "already-exists",
          "同じ送信IDが別のデータに使われています。",
        );
      }
      return {
        saved: true,
        duplicate: true,
        sequenceStart: safeNonNegativeInteger(existing.sequenceStart),
        sequenceEnd: safeNonNegativeInteger(existing.sequenceEnd),
        nextSequence: safeNonNegativeInteger(existing.sequenceEnd) + 1,
      };
    }
    const session = sessionSnapshot.data() ?? {};
    requirePublisher(session, uid);
    const nextSequence = safeNonNegativeInteger(session.timelineNextSequence);
    if (chunk.expectedNextSequence !== nextSequence) {
      throw new HttpsError(
        "aborted",
        "配信タイムラインの順番がずれました。最新データを読み直してください。",
      );
    }
    if (nextSequence + chunk.events.length > maxLiveAudioTimelineEvents) {
      throw new HttpsError(
        "resource-exhausted",
        "配信タイムラインの保存上限に達しました。",
      );
    }
    const startedAtMs = safeNonNegativeInteger(session.startedAtMs);
    const segmentStartSec =
      typeof session.segmentStartSec === "number" &&
      isValidSegmentStartSec(session.segmentStartSec) ?
        session.segmentStartSec :
        0;
    const maximumTimestampSec = maximumAllowedGlobalTimestampSec({
      segmentStartSec,
      startedAtMs,
      nowMs: Date.now(),
    });
    if (
      startedAtMs <= 0 ||
      chunk.events.some(
        (event) => event.globalTimestampSec > maximumTimestampSec,
      )
    ) {
      throw new HttpsError(
        "invalid-argument",
        "配信開始時刻より大きく先のイベントは保存できません。",
      );
    }
    const knownBoards = boardsFromSnapshot(session.boardSetSnapshot);
    const createdBoardIds = stringListField(
      session.timelineCreatedBoardIds,
    );
    const createdBoardOrders = numberListField(
      session.timelineCreatedBoardOrders,
    );
    for (let index = 0; index < createdBoardIds.length; index++) {
      const order = createdBoardOrders[index];
      if (order !== undefined) {
        knownBoards.set(createdBoardIds[index], order);
      }
    }
    const boardValidation = validateTimelineBoardReferences({
      events: chunk.events,
      knownBoards,
      createdBoardIds: new Set(createdBoardIds),
    });
    if (!boardValidation.valid) {
      throw new HttpsError(
        "invalid-argument",
        "ホワイトボード作成前のイベント、または重複した作成イベントが含まれています。",
      );
    }
    const sequenceStart = nextSequence;
    const sequenceEnd = nextSequence + chunk.events.length - 1;
    const receivedAtMs = Date.now();
    const events = chunk.events.map((event, index) => ({
      ...event,
      sequence: sequenceStart + index,
    }));
    transaction.create(chunkReference, {
      chunkId: chunk.chunkId,
      authorUid: uid,
      sequenceStart,
      sequenceEnd,
      eventCount: events.length,
      payloadHash,
      events,
      receivedAtMs,
      receivedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(sessionReference, {
      timelineNextSequence: sequenceEnd + 1,
      timelineCreatedBoardIds: [
        ...boardValidation.resultingCreatedBoardIds,
      ],
      timelineCreatedBoardOrders: [
        ...boardValidation.resultingCreatedBoardIds,
      ].map((boardId) => boardValidation.resultingBoards.get(boardId)),
      timelineUpdatedAtMs: receivedAtMs,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      saved: true,
      duplicate: false,
      sequenceStart,
      sequenceEnd,
      nextSequence: sequenceEnd + 1,
      receivedAtMs,
    };
  });
});

export const getLiveAudioProbeSnapshot = onCall(async (request) => {
  const uid = requireAuthenticatedUid(request);
  const sessionId = requireSessionId(request.data?.sessionId);
  const afterSequence = request.data?.afterSequence ?? -1;
  if (
    !Number.isSafeInteger(afterSequence) ||
    afterSequence < -1 ||
    afterSequence > maxLiveAudioTimelineEvents
  ) {
    throw new HttpsError("invalid-argument", "取得開始番号が不正です。");
  }
  const sessionReference = db.collection(sessionCollection).doc(sessionId);
  const [sessionSnapshot, participantSnapshot] = await Promise.all([
    sessionReference.get(),
    sessionReference.collection("participants").doc(uid).get(),
  ]);
  if (!sessionSnapshot.exists) {
    throw new HttpsError("not-found", "検証配信が見つかりません。");
  }
  if (!participantSnapshot.exists) {
    throw new HttpsError(
      "permission-denied",
      "この配信へ参加した人だけが復元データを取得できます。",
    );
  }
  const chunksSnapshot = await sessionReference
    .collection("timelineChunks")
    .where("sequenceEnd", ">", afterSequence)
    .orderBy("sequenceEnd")
    .limit(5)
    .get();
  const session = sessionSnapshot.data() ?? {};
  return {
    sessionId,
    state: storedSessionState(session),
    status: stringField(session.status),
    ownerUid: stringField(session.ownerUid),
    activePresenterUid: resolveActivePresenterUid({
      ownerUid: stringField(session.ownerUid),
      activePresenterUid: stringField(session.activePresenterUid),
      presenterUids: stringListField(session.presenterUids),
    }),
    startedAtMs: safeNonNegativeInteger(session.startedAtMs),
    segmentStartSec:
      typeof session.segmentStartSec === "number" ?
        session.segmentStartSec :
        0,
    boardSet: session.boardSetSnapshot ?? null,
    boardSetRevision: safeNonNegativeInteger(session.boardSetRevision),
    timelineNextSequence: safeNonNegativeInteger(
      session.timelineNextSequence,
    ),
    timelineChunks: chunksSnapshot.docs.map((doc) => doc.data()),
    hasMore:
      chunksSnapshot.size === 5 &&
      safeNonNegativeInteger(
        chunksSnapshot.docs[chunksSnapshot.size - 1]?.data().sequenceEnd,
      ) + 1 <
        safeNonNegativeInteger(session.timelineNextSequence),
  };
});

export const getLiveAudioProbeArchiveStatus = onCall(
  {secrets: archiveSecrets},
  async (request) => {
    const uid = requireAuthenticatedUid(request);
    const sessionId = requireSessionId(request.data?.sessionId);
    const sessionReference = db.collection(sessionCollection).doc(sessionId);
    const [snapshot, participant] = await Promise.all([
      sessionReference.get(),
      sessionReference.collection("participants").doc(uid).get(),
    ]);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "検証配信が見つかりません。");
    }
    const session = snapshot.data() ?? {};
    if (session.ownerUid !== uid && !participant.exists) {
      throw new HttpsError(
        "permission-denied",
        "この配信の参加者だけが録音状態を確認できます。",
      );
    }
    const status = session.archiveStatus === "recording" ?
      await queryAndUpdateArchiveStatus(sessionReference, session) :
      safeArchiveStatus(session);
    return archiveStatusWithHlsAccess({
      status,
      sessionId,
      uid,
      request,
    });
  },
);

export const liveAudioProbeHls = onRequest(
  {secrets: [agoraAppCertificate, agoraGcsBucket], timeoutSeconds: 120},
  async (request, response) => {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Methods", "GET, OPTIONS");
    response.set("Access-Control-Allow-Headers", "Range");
    if (request.method === "OPTIONS") {
      response.status(204).send("");
      return;
    }
    if (request.method !== "GET") {
      response.status(405).send("Method not allowed");
      return;
    }
    const token =
      typeof request.query.token === "string" ? request.query.token : "";
    const claims = verifyHlsAccessToken(
      token,
      agoraAppCertificate.value().trim(),
    );
    if (!claims) {
      response.status(403).send("Invalid or expired playback access");
      return;
    }
    const sessionSnapshot = await db
      .collection(sessionCollection)
      .doc(claims.sessionId)
      .get();
    if (!sessionSnapshot.exists) {
      response.status(404).send("Live session not found");
      return;
    }
    const session = sessionSnapshot.data() ?? {};
    const requestedPath =
      typeof request.query.file === "string" ?
        request.query.file :
        stringField(session.hlsManifestObjectPath);
    if (
      !requestedPath ||
      !isSafeHlsObjectPath(requestedPath, claims.sessionId)
    ) {
      response.status(400).send("Invalid playback object");
      return;
    }
    const bucket = getStorage().bucket(agoraGcsBucket.value().trim());
    const file = bucket.file(requestedPath);
    try {
      if (requestedPath.toLowerCase().endsWith(".m3u8")) {
        const [contents] = await file.download();
        if (contents.byteLength > 2 * 1024 * 1024) {
          response.status(413).send("Manifest is too large");
          return;
        }
        const rewritten = rewriteHlsManifest({
          manifest: contents.toString("utf8"),
          manifestObjectPath: requestedPath,
          proxyUrl: hlsProxyUrl(request),
          token,
        });
        response.set("Content-Type", "application/vnd.apple.mpegurl");
        response.set("Cache-Control", "private, no-store");
        response.status(200).send(rewritten);
        return;
      }
      const [metadata] = await file.getMetadata();
      response.set(
        "Content-Type",
        typeof metadata.contentType === "string" ?
          metadata.contentType :
          "application/octet-stream",
      );
      response.set("Cache-Control", "private, max-age=3600");
      await new Promise<void>((resolve, reject) => {
        const stream = file.createReadStream();
        stream.on("error", reject);
        stream.on("end", resolve);
        stream.pipe(response);
      });
    } catch (error) {
      logArchiveError("hls-proxy", error);
      if (!response.headersSent) {
        response.status(404).send("Playback object not ready");
      } else {
        response.end();
      }
    }
  },
);

export const closeLiveAudioProbeSession = onCall(
  {secrets: archiveSecrets, timeoutSeconds: 120},
  async (request) => {
    const uid = requireAuthenticatedUid(request);
    const sessionId = requireSessionId(request.data?.sessionId);
    const sessionReference = db.collection(sessionCollection).doc(sessionId);
    const closing = await moveSessionToFinalizing(
      sessionReference,
      uid,
      false,
    );
    if (closing.alreadyClosed) {
      return {
        closed: true,
        ...safeArchiveStatus(closing.session),
      };
    }
    const result = await stopArchiveAndFinalize(
      sessionReference,
      closing.session,
    );
    return {closed: true, ...result};
  },
);

export const closeOwnedLiveAudioProbeSessions = onCall(
  {secrets: archiveSecrets, timeoutSeconds: 540},
  async (request) => {
    const uid = requireAuthenticatedUid(request);
    const snapshots = await db
      .collection(sessionCollection)
      .where("ownerUid", "==", uid)
      .get();
    const activeReferences = snapshots.docs
      .filter((snapshot) => {
        return isLiveSessionState(storedSessionState(snapshot.data()));
      })
      .map((snapshot) => snapshot.ref);
    const closedSessionIds: string[] = [];
    const failedSessionIds: string[] = [];
    for (const sessionReference of activeReferences) {
      try {
        const closing = await moveSessionToFinalizing(
          sessionReference,
          uid,
          false,
        );
        if (!closing.alreadyClosed) {
          await stopArchiveAndFinalize(sessionReference, closing.session);
        }
        closedSessionIds.push(sessionReference.id);
      } catch (error) {
        logArchiveError("close-owned-session", error);
        failedSessionIds.push(sessionReference.id);
      }
    }
    return {
      closedCount: closedSessionIds.length,
      failedCount: failedSessionIds.length,
      closedSessionIds,
      failedSessionIds,
    };
  },
);

export const retryLiveAudioProbeArchive = onCall(
  {secrets: archiveSecrets, timeoutSeconds: 120},
  async (request) => {
    const uid = requireAuthenticatedUid(request);
    const sessionId = requireSessionId(request.data?.sessionId);
    const sessionReference = db.collection(sessionCollection).doc(sessionId);
    const snapshot = await sessionReference.get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "検証配信が見つかりません。");
    }
    const session = snapshot.data() ?? {};
    if (session.ownerUid !== uid) {
      throw new HttpsError(
        "permission-denied",
        "配信を開始した先生だけが録音を再試行できます。",
      );
    }
    if (isLiveSessionState(storedSessionState(session))) {
      if (session.archiveStatus === "recording") {
        return safeArchiveStatus(session);
      }
      return startArchiveWithoutFailingLive({
        sessionReference,
        sessionId,
        channelName: stringField(session.channelName),
      });
    }
    if (storedSessionState(session) === "draftReady") {
      return reattachLinkedLessonDraftFromReadySession(
        sessionReference,
        session,
      );
    }
    const closing = await moveSessionToFinalizing(
      sessionReference,
      uid,
      true,
    );
    return stopArchiveAndFinalize(sessionReference, closing.session);
  },
);

async function requireActiveTeacher(
  uid: string,
  message = "先生として利用中のユーザーだけが検証配信を開始できます。",
): Promise<void> {
  const userSnapshot = await db.collection("users").doc(uid).get();
  const userData = userSnapshot.data();
  const roles = Array.isArray(userData?.roles) ? userData.roles : [];
  if (userData?.activeRole !== "teacher" || !roles.includes("teacher")) {
    throw new HttpsError(
      "permission-denied",
      message,
    );
  }
}

async function startArchiveWithoutFailingLive({
  sessionReference,
  sessionId,
  channelName,
}: {
  sessionReference: DocumentReference<DocumentData>;
  sessionId: string;
  channelName: string;
}): Promise<Record<string, unknown>> {
  const config = cloudRecordingConfig();
  const appCertificate = agoraAppCertificate.value().trim();
  if (!isCompleteCloudRecordingConfig(config) || !appCertificate) {
    await recordArchiveFailure(
      sessionReference,
      archiveConfigWarning,
      "missingConfig",
    );
    return {
      archiveStatus: "archiveFailed",
      warning: archiveConfigWarning,
    };
  }
  const recorderUid = rtcUidForFirebaseUser(`cloud-recording:${sessionId}`);
  const recordingToken = RtcTokenBuilder.buildTokenWithUidAndPrivilege(
    config.appId,
    appCertificate,
    channelName,
    recorderUid,
    liveAudioArchiveTokenLifetimeSec,
    liveAudioArchiveTokenLifetimeSec,
    0,
    0,
    0,
  );
  try {
    const handle = await new AgoraCloudRecordingClient(config).start({
      channelName,
      recorderUid,
      recordingToken,
      fileNamePrefix: [archivePrefixRoot, sessionId],
    });
    const archiveStartedAtMs = Date.now();
    const sessionSnapshot = await sessionReference.get();
    const sessionStartedAtMs = safeNonNegativeInteger(
      sessionSnapshot.data()?.startedAtMs,
    );
    const archiveTimelineOffsetSec = sessionStartedAtMs > 0 ?
      Math.max(0, (archiveStartedAtMs - sessionStartedAtMs) / 1000) :
      0;
    await sessionReference.update({
      archiveStatus: "recording",
      archiveError: null,
      archiveErrorCode: null,
      archiveResourceId: handle.resourceId,
      archiveSid: handle.sid,
      archiveRecorderUid: handle.recorderUid,
      archiveStartedAtMs,
      archiveTimelineOffsetSec,
      archiveStartedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      archiveStatus: "recording",
      warning: null,
      archiveStartedAtMs,
      archiveTimelineOffsetSec,
    };
  } catch (error) {
    logArchiveError("start", error);
    await recordArchiveFailure(
      sessionReference,
      archiveStartWarning,
      "startFailed",
    );
    return {
      archiveStatus: "archiveFailed",
      warning: archiveStartWarning,
    };
  }
}

async function moveSessionToFinalizing(
  sessionReference: DocumentReference<DocumentData>,
  ownerUid: string,
  allowRetry: boolean,
  closeReason?: "maxDuration",
): Promise<{session: DocumentData; alreadyClosed: boolean}> {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(sessionReference);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "検証配信が見つかりません。");
    }
    const session = snapshot.data() ?? {};
    if (session.ownerUid !== ownerUid) {
      throw new HttpsError(
        "permission-denied",
        "配信を開始した先生だけが終了できます。",
      );
    }
    const state = storedSessionState(session);
    if (state === "draftReady") {
      return {session, alreadyClosed: true};
    }
    if (state === "finalizing" && !allowRetry) {
      return {session, alreadyClosed: true};
    }
    if (
      !isLiveSessionState(state) &&
      state !== "finalizing" &&
      state !== "archiveFailed" &&
      state !== "ended"
    ) {
      throw new HttpsError(
        "failed-precondition",
        "この配信は終了処理を開始できません。",
      );
    }
    if (!allowRetry && (state === "archiveFailed" || state === "ended")) {
      return {session, alreadyClosed: true};
    }
    const presenterUids = stringListField(session.presenterUids);
    const drawerUid = resolveActivePresenterUid({
      ownerUid,
      activePresenterUid: stringField(session.activePresenterUid),
      presenterUids,
    });
    const coSpeakerUid = resolveCoSpeakerUid({
      ownerUid,
      activePresenterUid: stringField(session.activePresenterUid),
      presenterUids,
    });
    const participantUidsToUpdate = new Set<string>([drawerUid]);
    if (coSpeakerUid) {
      participantUidsToUpdate.add(coSpeakerUid);
    }
    const participantSnapshots = new Map<string, boolean>();
    for (const participantId of participantUidsToUpdate) {
      const reference = sessionReference
        .collection("participants")
        .doc(participantId);
      participantSnapshots.set(
        participantId,
        (await transaction.get(reference)).exists,
      );
    }
    const joinCode = stringField(session.joinCode);
    const joinCodeReference = isValidLiveAudioJoinCode(joinCode) ?
      db.collection(joinCodeCollection).doc(joinCode) :
      null;
    const joinCodeSnapshot = joinCodeReference === null ?
      null :
      await transaction.get(joinCodeReference);
    const now = FieldValue.serverTimestamp();
    const archiveStopRequestedAtMs =
      safeNonNegativeInteger(session.archiveStopRequestedAtMs) || Date.now();
    const closeMetadata = closeReason === undefined ?
      {} :
      {
        closeReason,
        maximumDurationSec: liveAudioProbeMaxDurationSec,
        durationLimitEnforcedAtMs: archiveStopRequestedAtMs,
      };
    if (
      joinCodeReference !== null &&
      joinCodeSnapshot?.data()?.sessionId === sessionReference.id
    ) {
      transaction.delete(joinCodeReference);
    }
    transaction.update(sessionReference, {
      status: "finalizing",
      state: "finalizing",
      archiveStatus: "finalizing",
      archiveStopRequestedAtMs,
      activePresenterUid: ownerUid,
      presenterUids: [],
      ...closeMetadata,
      updatedAt: now,
    });
    for (const [participantId, exists] of participantSnapshots) {
      if (!exists) {
        continue;
      }
      transaction.update(
        sessionReference.collection("participants").doc(participantId),
        {
          permission: "subscriber",
          updatedAt: now,
        },
      );
    }
    return {
      session: {
        ...session,
        status: "finalizing",
        state: "finalizing",
        archiveStatus: "finalizing",
        archiveStopRequestedAtMs,
        ...closeMetadata,
      },
      alreadyClosed: false,
    };
  });
}

async function stopArchiveAndFinalize(
  sessionReference: DocumentReference<DocumentData>,
  session: DocumentData,
): Promise<Record<string, unknown>> {
  const config = cloudRecordingConfig();
  if (!isCompleteCloudRecordingConfig(config)) {
    return finalizeArchiveFailure(
      sessionReference,
      archiveConfigWarning,
      "missingConfig",
    );
  }
  const storedManifest = archiveManifestFromStored(
    session.archiveStopManifest,
  );
  if (storedManifest) {
    try {
      return await finalizeStoppedManifest({
        sessionReference,
        session,
        manifest: storedManifest,
        config,
      });
    } catch (error) {
      logArchiveError("retry-finalize", error);
      if (error instanceof ArchiveFinalizationError) {
        return finalizeArchiveFailure(
          sessionReference,
          error.publicWarning,
          error.errorCode,
        );
      }
      return finalizeArchiveFailure(
        sessionReference,
        archiveDraftWarning,
        "retryFinalizeFailed",
      );
    }
  }
  const resourceId = stringField(session.archiveResourceId);
  const sid = stringField(session.archiveSid);
  const recorderUid = stringField(session.archiveRecorderUid);
  const channelName = stringField(session.channelName);
  if (!resourceId || !sid || !recorderUid || !channelName) {
    return finalizeArchiveFailure(
      sessionReference,
      archiveStopWarning,
      "missingStopMetadata",
    );
  }
  try {
    const stopped = await new AgoraCloudRecordingClient(config).stop({
      channelName,
      resourceId,
      sid,
      recorderUid,
    });
    if (!stopped.manifest) {
      return finalizeArchiveFailure(
        sessionReference,
        archiveStopWarning,
        "filesMissing",
      );
    }
    const stoppedAtMs = Date.now();
    const storedArchiveManifest = {
      fileListMode: stopped.manifest.fileListMode,
      files: stopped.manifest.files,
      manifestFile: stopped.manifest.manifestFile,
    };
    await sessionReference.update({
      archiveManifest: storedArchiveManifest,
      archiveStopManifest: storedArchiveManifest,
      archiveStoppedAtMs: stoppedAtMs,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return await finalizeStoppedManifest({
      sessionReference,
      session: {
        ...session,
        archiveManifest: storedArchiveManifest,
        archiveStopManifest: storedArchiveManifest,
        archiveStoppedAtMs: stoppedAtMs,
      },
      manifest: stopped.manifest,
      config,
    });
  } catch (error) {
    logArchiveError("stop", error);
    if (error instanceof ArchiveFinalizationError) {
      return finalizeArchiveFailure(
        sessionReference,
        error.publicWarning,
        error.errorCode,
      );
    }
    return finalizeArchiveFailure(
      sessionReference,
      archiveStopWarning,
      "stopFailed",
    );
  }
}

function finalizeStoppedManifest({
  sessionReference,
  session,
  manifest,
  config,
}: {
  sessionReference: DocumentReference<DocumentData>;
  session: DocumentData;
  manifest: ArchiveManifest;
  config: AgoraCloudRecordingConfig;
}): Promise<Record<string, unknown>> {
  const hasCompleteLessonLinks =
    isValidOptionalLinkId(session.courseId) &&
    isValidOptionalLinkId(session.lessonId) &&
    isValidOptionalLinkId(session.segmentId);
  if (hasCompleteLessonLinks) {
    return finalizeLinkedArchive({
      sessionReference,
      session,
      manifest,
      config,
    });
  }
  return finalizeArchiveSuccess(sessionReference, session, manifest, config);
}

async function finalizeArchiveSuccess(
  sessionReference: DocumentReference<DocumentData>,
  session: DocumentData,
  manifest: ArchiveManifest,
  config: AgoraCloudRecordingConfig,
): Promise<Record<string, unknown>> {
  const finalizedAtMs = Date.now();
  const duration = await finalizedArchiveDuration(session, manifest, config);
  const hlsManifestObjectPath = selectManifestObject(
    manifest.files,
    ".m3u8",
    stringField(session.archivePrefix),
  );
  await sessionReference.update({
    status: "draftReady",
    state: "draftReady",
    archiveStatus: "draftReady",
    archiveError: null,
    archiveErrorCode: null,
    archiveManifest: {
      fileListMode: manifest.fileListMode,
      files: manifest.files,
      manifestFile: manifest.manifestFile,
    },
    archiveFinalizedAtMs: finalizedAtMs,
    archiveDurationSource: duration.source,
    hlsManifestObjectPath,
    hlsAvailableDurationSec: duration.durationSec,
    ...(duration.hlsMediaStartedAtMs === null ?
      {} :
      {
        hlsMediaStartedAtMs: duration.hlsMediaStartedAtMs,
        hlsMediaTimelineOffsetSec: duration.hlsMediaTimelineOffsetSec,
      }),
    audioPlaybackCompensationSec: duration.audioPlaybackCompensationSec,
    audioPlaybackCompensationSource: duration.audioPlaybackCompensationSource,
    draftReady: {
      linkedToLesson: false,
      finalizedAtMs,
      durationMs: duration.durationMs,
      durationSource: duration.source,
    },
    endedAtMs: finalizedAtMs,
    endedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {
    state: "draftReady",
    archiveStatus: "draftReady",
    archiveError: null,
    archiveManifest: manifest,
    hlsManifestObjectPath,
    hlsAvailableDurationSec: duration.durationSec,
    hlsMediaTimelineOffsetSec: duration.hlsMediaTimelineOffsetSec,
    audioPlaybackCompensationSec: duration.audioPlaybackCompensationSec,
    audioPlaybackCompensationSource: duration.audioPlaybackCompensationSource,
  };
}

async function finalizeLinkedArchive({
  sessionReference,
  session,
  manifest,
  config,
}: {
  sessionReference: DocumentReference<DocumentData>;
  session: DocumentData;
  manifest: ArchiveManifest;
  config: AgoraCloudRecordingConfig;
}): Promise<Record<string, unknown>> {
  const sessionId = sessionReference.id;
  const prefix = stringField(session.archivePrefix);
  const mp4ObjectPath = selectManifestObject(
    manifest.files,
    ".mp4",
    prefix,
  );
  if (!mp4ObjectPath) {
    throw new ArchiveFinalizationError(archiveMp4Warning, "mp4Missing");
  }
  const courseId = stringField(session.courseId);
  const lessonId = stringField(session.lessonId);
  const segmentId = stringField(session.segmentId);
  const destinationObjectPath =
    `courseMedia/${courseId}/lessons/${lessonId}/segments/${segmentId}/` +
    `live-${sessionId}.mp4`;
  const storage = getStorage();
  const sourceFile = storage.bucket(config.gcsBucket).file(mp4ObjectPath);
  const destinationBucket = storage.bucket();
  const destinationFile = destinationBucket.file(destinationObjectPath);
  const downloadToken = randomUUID();
  try {
    await copyArchiveFileWithRetry(sourceFile, destinationFile);
    await destinationFile.setMetadata({
      contentType: "video/mp4",
      cacheControl: "private, max-age=0",
      metadata: {
        firebaseStorageDownloadTokens: downloadToken,
        liveSessionId: sessionId,
      },
    });
  } catch {
    try {
      await destinationFile.delete({ignoreNotFound: true});
    } catch (cleanupError) {
      logArchiveError("cleanup-storage-copy", cleanupError);
    }
    throw new ArchiveFinalizationError(
      archiveStorageWarning,
      "storageCopyFailed",
    );
  }
  const playbackUrl = firebaseStorageDownloadUrl({
    bucketName: destinationBucket.name,
    objectPath: destinationObjectPath,
    downloadToken,
  });
  const finalizedAtMs = Date.now();
  const duration = await finalizedArchiveDuration(session, manifest, config);
  const hlsManifestObjectPath = selectManifestObject(
    manifest.files,
    ".m3u8",
    prefix,
  );
  try {
    const draftResult = await persistLinkedLessonDraft({
      sessionReference,
      ownerUid: stringField(session.ownerUid),
      courseId,
      lessonId,
      segmentId,
      playbackUrl,
      destinationObjectPath,
      durationSec: duration.durationSec,
      durationMs: duration.durationMs,
      durationSource: duration.source,
      finalizedAtMs,
      hlsManifestObjectPath,
      hlsMediaStartedAtMs: duration.hlsMediaStartedAtMs,
      hlsMediaTimelineOffsetSec: duration.hlsMediaTimelineOffsetSec,
      audioPlaybackCompensationSec: duration.audioPlaybackCompensationSec,
      audioPlaybackCompensationSource: duration.audioPlaybackCompensationSource,
      manifest,
    });
    return {
      state: "draftReady",
      archiveStatus: "draftReady",
      archiveError: null,
      archivePlaybackUrl: playbackUrl,
      hlsManifestObjectPath,
      hlsAvailableDurationSec: duration.durationSec,
      hlsMediaTimelineOffsetSec: duration.hlsMediaTimelineOffsetSec,
      audioPlaybackCompensationSec: duration.audioPlaybackCompensationSec,
      audioPlaybackCompensationSource: duration.audioPlaybackCompensationSource,
      draftReady: draftResult,
    };
  } catch (error) {
    try {
      const latest = await sessionReference.get();
      const latestSession = latest.data() ?? {};
      if (
        storedSessionState(latestSession) === "draftReady" &&
        latestSession.archivePlaybackObjectPath === destinationObjectPath
      ) {
        return safeArchiveStatus(latestSession);
      }
    } catch (verificationError) {
      logArchiveError("verify-draft-commit", verificationError);
    }
    try {
      await destinationFile.delete({ignoreNotFound: true});
    } catch (cleanupError) {
      logArchiveError("cleanup-destination", cleanupError);
    }
    if (error instanceof ArchiveFinalizationError) {
      throw error;
    }
    throw new ArchiveFinalizationError(
      archiveDraftWarning,
      "draftWriteFailed",
    );
  }
}

async function copyArchiveFileWithRetry(
  sourceFile: ReturnType<ReturnType<typeof getStorage>["bucket"]>["file"] extends
    (...args: never[]) => infer T ? T : never,
  destinationFile: ReturnType<
    ReturnType<typeof getStorage>["bucket"]
  >["file"] extends (...args: never[]) => infer T ? T : never,
): Promise<void> {
  let lastError: unknown;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      await sourceFile.copy(destinationFile);
      return;
    } catch (error) {
      lastError = error;
      if (attempt < 3) {
        await new Promise((resolve) =>
          setTimeout(resolve, 2000 * 2 ** attempt),
        );
      }
    }
  }
  throw lastError;
}

async function reattachLinkedLessonDraftFromReadySession(
  sessionReference: DocumentReference<DocumentData>,
  session: DocumentData,
): Promise<Record<string, unknown>> {
  const playbackUrl = stringField(session.archivePlaybackUrl);
  const destinationObjectPath = stringField(session.archivePlaybackObjectPath);
  const courseId = stringField(session.courseId);
  const lessonId = stringField(session.lessonId);
  const segmentId = stringField(session.segmentId);
  const ownerUid = stringField(session.ownerUid);
  const draftReady = isObjectRecord(session.draftReady) ?
    session.draftReady :
    {};
  const durationSec =
    safeNonNegativeInteger(draftReady.durationSec) ||
    safeNonNegativeInteger(session.hlsAvailableDurationSec);
  const durationMs =
    safeNonNegativeInteger(draftReady.durationMs) ||
    durationSec * 1000;
  const durationSource =
    draftReady.durationSource === "hls" ||
    session.archiveDurationSource === "hls" ?
      "hls" :
      "wallClock";
  const finalizedAtMs =
    safeNonNegativeInteger(draftReady.finalizedAtMs) ||
    safeNonNegativeInteger(session.archiveFinalizedAtMs) ||
    Date.now();
  const manifest = archiveManifestFromStored(session.archiveManifest);
  if (
    !playbackUrl ||
    !destinationObjectPath ||
    !isValidOptionalLinkId(courseId) ||
    !isValidOptionalLinkId(lessonId) ||
    !isValidOptionalLinkId(segmentId) ||
    !ownerUid ||
    durationSec < 1 ||
    manifest === null
  ) {
    throw new HttpsError(
      "failed-precondition",
      "録音は残っていますが、レッスンへ反映する情報が足りません。時間をおいて再試行してください。",
    );
  }
  const hlsManifestObjectPath =
    stringField(session.hlsManifestObjectPath) || null;
  const rawHlsMediaStartedAtMs = session.hlsMediaStartedAtMs;
  const hlsMediaStartedAtMs =
    typeof rawHlsMediaStartedAtMs === "number" &&
    Number.isSafeInteger(rawHlsMediaStartedAtMs) &&
    rawHlsMediaStartedAtMs > 0 ?
      rawHlsMediaStartedAtMs :
      null;
  const hlsMediaTimelineOffsetSec =
    typeof session.hlsMediaTimelineOffsetSec === "number" &&
    Number.isFinite(session.hlsMediaTimelineOffsetSec) ?
      Math.max(0, session.hlsMediaTimelineOffsetSec) :
      null;
  try {
    await persistLinkedLessonDraft({
      sessionReference,
      ownerUid,
      courseId,
      lessonId,
      segmentId,
      playbackUrl,
      destinationObjectPath,
      durationSec,
      durationMs,
      durationSource,
      finalizedAtMs,
      hlsManifestObjectPath,
      hlsMediaStartedAtMs,
      hlsMediaTimelineOffsetSec,
      audioPlaybackCompensationSec: safeNonNegativeInteger(
        session.audioPlaybackCompensationSec,
      ),
      audioPlaybackCompensationSource:
        stringField(session.audioPlaybackCompensationSource) || "none",
      manifest,
    });
    const latest = await sessionReference.get();
    return safeArchiveStatus(latest.data() ?? session);
  } catch (error) {
    logArchiveError("reattach-draft", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    if (error instanceof ArchiveFinalizationError) {
      throw new HttpsError("failed-precondition", error.publicWarning);
    }
    throw new HttpsError(
      "internal",
      "録音は残っていますが、レッスンへの反映に失敗しました。もう一度お試しください。",
    );
  }
}

async function persistLinkedLessonDraft({
  sessionReference,
  ownerUid,
  courseId,
  lessonId,
  segmentId,
  playbackUrl,
  destinationObjectPath,
  durationSec,
  durationMs,
  durationSource,
  finalizedAtMs,
  hlsManifestObjectPath,
  hlsMediaStartedAtMs,
  hlsMediaTimelineOffsetSec,
  audioPlaybackCompensationSec,
  audioPlaybackCompensationSource,
  manifest,
}: {
  sessionReference: DocumentReference<DocumentData>;
  ownerUid: string;
  courseId: string;
  lessonId: string;
  segmentId: string;
  playbackUrl: string;
  destinationObjectPath: string;
  durationSec: number;
  durationMs: number;
  durationSource: "hls" | "wallClock";
  finalizedAtMs: number;
  hlsManifestObjectPath: string | null;
  hlsMediaStartedAtMs: number | null;
  hlsMediaTimelineOffsetSec: number | null;
  audioPlaybackCompensationSec: number;
  audioPlaybackCompensationSource: string;
  manifest: ArchiveManifest;
}): Promise<Record<string, unknown>> {
  const courseReference = db.collection("courses").doc(courseId);
  const lessonReference = courseReference.collection("lessons").doc(lessonId);
  const draftReference = courseReference
    .collection("lessonDrafts")
    .doc(lessonId);
  const archiveBaselineReference = sessionReference
    .collection("archiveInternal")
    .doc("baseline");
  return db.runTransaction(async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionReference);
    const courseSnapshot = await transaction.get(courseReference);
    const lessonSnapshot = await transaction.get(lessonReference);
    const draftSnapshot = await transaction.get(draftReference);
    const archiveBaselineSnapshot = await transaction.get(
      archiveBaselineReference,
    );
    if (
      !sessionSnapshot.exists ||
      !courseSnapshot.exists ||
      !lessonSnapshot.exists
    ) {
      throw new ArchiveFinalizationError(
        archiveDraftWarning,
        "linkedDocumentMissing",
      );
    }
    const currentSession = sessionSnapshot.data() ?? {};
    const course = courseSnapshot.data() ?? {};
    const lesson = lessonSnapshot.data() ?? {};
    if (
      currentSession.ownerUid !== ownerUid ||
      currentSession.courseId !== courseId ||
      currentSession.lessonId !== lessonId ||
      currentSession.segmentId !== segmentId ||
      (
        storedSessionState(currentSession) !== "finalizing" &&
        storedSessionState(currentSession) !== "draftReady"
      ) ||
      course.instructorId !== ownerUid ||
      course.status === "deleting" ||
      course.status === "deleted" ||
      (typeof lesson.id === "string" && lesson.id !== lessonId)
    ) {
      throw new ArchiveFinalizationError(
        archiveDraftWarning,
        "linkedDocumentMismatch",
      );
    }
    const boardSet = currentSession.boardSetSnapshot;
    const boardIds = new Set(boardsFromSnapshot(boardSet).keys());
    const createdBoardIds = stringListField(
      currentSession.timelineCreatedBoardIds,
    );
    if (
      !isValidBoardSet(boardSet) ||
      createdBoardIds.some((boardId) => !boardIds.has(boardId))
    ) {
      throw new ArchiveFinalizationError(
        archiveDraftWarning,
        "boardSetMissing",
      );
    }
    let draftBoardSet = boardSet;
    if (safeNonNegativeInteger(currentSession.archiveTimingVersion) >= 2) {
      const baselineBoardSet = archiveBaselineSnapshot.data()?.boardSet;
      const archiveStartedAtMs = safeNonNegativeInteger(
        currentSession.archiveStartedAtMs,
      );
      const archiveStopRequestedAtMs = safeNonNegativeInteger(
        currentSession.archiveStopRequestedAtMs,
      );
      const segmentStartSec =
        typeof currentSession.segmentStartSec === "number" &&
        isValidSegmentStartSec(currentSession.segmentStartSec) ?
          currentSession.segmentStartSec :
          -1;
      const archiveTimelineOffsetSec =
        typeof currentSession.archiveTimelineOffsetSec === "number" &&
        Number.isFinite(currentSession.archiveTimelineOffsetSec) ?
          Math.max(0, currentSession.archiveTimelineOffsetSec) :
          -1;
      const useHlsMediaOrigin =
        safeNonNegativeInteger(currentSession.archiveTimingVersion) >= 3 &&
        hlsMediaTimelineOffsetSec !== null &&
        Number.isFinite(hlsMediaTimelineOffsetSec) &&
        hlsMediaTimelineOffsetSec >= 0;
      // Keep this sign consistent with resolveLiveAudioCatchupTimelineSec.
      // Subtracting the measured audio-pipeline delay from the media origin
      // delays board visibility relative to playback in both catch-up and the
      // finalized lesson. If evidence requires changing this relationship,
      // verify both paths and introduce a new timing version for new sessions.
      const timelineOffsetSec =
        useHlsMediaOrigin && hlsMediaTimelineOffsetSec !== null ?
          Math.max(
            0,
            hlsMediaTimelineOffsetSec -
              (
                safeNonNegativeInteger(currentSession.archiveTimingVersion) >=
                  5 ?
                  audioPlaybackCompensationSec :
                  0
              ),
          ) :
          archiveTimelineOffsetSec;
      const recordingWallDurationSec =
        (archiveStopRequestedAtMs - archiveStartedAtMs) / 1000;
      const adjustedBoardSet = adjustLiveArchiveBoardSet({
        boardSet,
        baselineBoardSet,
        segmentStartSec,
        archiveTimelineOffsetSec: timelineOffsetSec,
        recordingWallDurationSec,
        mediaDurationSec: durationMs / 1000,
        preserveElapsedTime: useHlsMediaOrigin,
        segmentId,
      });
      if (
        !isValidBoardSet(baselineBoardSet) ||
        adjustedBoardSet === null ||
        !isValidBoardSet(adjustedBoardSet)
      ) {
        throw new ArchiveFinalizationError(
          archiveDraftWarning,
          "archiveTimingInvalid",
        );
      }
      draftBoardSet = adjustedBoardSet;
    }
    const prepared = prepareLiveArchiveDraft({
      lesson,
      existingDraft: draftSnapshot.exists ? draftSnapshot.data() : null,
      segmentId,
      playbackUrl,
      durationSec,
      durationMs,
      liveSessionId: sessionReference.id,
    });
    if (!prepared.ok) {
      throw new ArchiveFinalizationError(
        archiveDraftWarning,
        prepared.code,
      );
    }
    const draftReady = {
      courseId,
      lessonId,
      segmentId,
      draftRevision: prepared.draftRevision,
      baseLessonDocumentVersion: prepared.baseLessonDocumentVersion,
      storageObjectPath: destinationObjectPath,
      durationSec,
      durationMs,
      durationSource,
      finalizedAtMs,
    };
    transaction.set(draftReference, {
      lessonId,
      boardSet: draftBoardSet,
      mediaSegments: prepared.mediaSegments,
      baseLessonDocumentVersion: prepared.baseLessonDocumentVersion,
      draftRevision: prepared.draftRevision,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(sessionReference, {
      status: "draftReady",
      state: "draftReady",
      archiveStatus: "draftReady",
      archiveError: null,
      archiveErrorCode: null,
      archivePlaybackUrl: playbackUrl,
      archivePlaybackObjectPath: destinationObjectPath,
      archiveManifest: {
        fileListMode: manifest.fileListMode,
        files: manifest.files,
        manifestFile: manifest.manifestFile,
      },
      archiveFinalizedAtMs: finalizedAtMs,
      archiveDurationSource: durationSource,
      hlsManifestObjectPath,
      hlsAvailableDurationSec: durationSec,
      ...(hlsMediaStartedAtMs === null ?
        {} :
        {
          hlsMediaStartedAtMs,
          hlsMediaTimelineOffsetSec,
        }),
      audioPlaybackCompensationSec,
      audioPlaybackCompensationSource,
      draftReady,
      endedAtMs: finalizedAtMs,
      endedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return draftReady;
  });
}

async function queryAndUpdateArchiveStatus(
  sessionReference: DocumentReference<DocumentData>,
  session: DocumentData,
): Promise<Record<string, unknown>> {
  const config = cloudRecordingConfig();
  const resourceId = stringField(session.archiveResourceId);
  const sid = stringField(session.archiveSid);
  if (!isCompleteCloudRecordingConfig(config) || !resourceId || !sid) {
    return safeArchiveStatus(session);
  }
  try {
    const queried = await new AgoraCloudRecordingClient(config).query({
      resourceId,
      sid,
    });
    if (!queried.manifest) {
      return safeArchiveStatus(session);
    }
    const nowMs = Date.now();
    const hlsManifestObjectPath = selectManifestObject(
      queried.manifest.files,
      ".m3u8",
      stringField(session.archivePrefix),
    );
    const updates: Record<string, unknown> = {
      archiveManifest: {
        fileListMode: queried.manifest.fileListMode,
        files: queried.manifest.files,
        manifestFile: queried.manifest.manifestFile,
      },
      archiveQueriedAtMs: nowMs,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (hlsManifestObjectPath) {
      updates.hlsManifestObjectPath = hlsManifestObjectPath;
      try {
        const [contents] = await getStorage()
          .bucket(config.gcsBucket)
          .file(hlsManifestObjectPath)
          .download();
        const manifestText = contents.toString("utf8");
        const availableDurationMs = availableHlsDurationMs(
          manifestText,
        );
        if (availableDurationMs !== null) {
          updates.hlsAvailableDurationSec = Math.floor(
            availableDurationMs / 1000,
          );
        }
        if (safeNonNegativeInteger(session.archiveTimingVersion) >= 3) {
          const sessionStartedAtMs = safeNonNegativeInteger(
            session.startedAtMs,
          );
          const mediaTimelineOffsetSec = hlsMediaTimelineOffsetSec({
            manifest: manifestText,
            sessionStartedAtMs,
          });
          if (mediaTimelineOffsetSec !== null) {
            const mediaStartedAtMs =
              sessionStartedAtMs + Math.round(mediaTimelineOffsetSec * 1000);
            const compensation = resolveLiveAudioPlaybackCompensation({
              timingVersion: safeNonNegativeInteger(
                session.archiveTimingVersion,
              ),
              hlsMediaStartedAtMs: mediaStartedAtMs,
              audioCaptureStartedAtMs: safeNonNegativeInteger(
                session.audioCaptureStartedAtMs,
              ),
              fallbackSec: liveAudioPlaybackFallbackCompensationSec,
            });
            updates.hlsMediaTimelineOffsetSec = mediaTimelineOffsetSec;
            updates.hlsMediaStartedAtMs = mediaStartedAtMs;
            updates.audioPlaybackCompensationSec =
              compensation.compensationSec;
            updates.audioPlaybackCompensationSource = compensation.source;
          }
        }
      } catch (error) {
        logArchiveError("read-live-hls-duration", error);
      }
    }
    await sessionReference.update(updates);
    return safeArchiveStatus({
      ...session,
      ...updates,
      hlsManifestObjectPath:
        hlsManifestObjectPath ?? session.hlsManifestObjectPath,
    });
  } catch (error) {
    logArchiveError("query", error);
    return safeArchiveStatus(session);
  }
}

async function finalizedArchiveDuration(
  session: DocumentData,
  manifest: ArchiveManifest,
  config: AgoraCloudRecordingConfig,
): Promise<{
  durationMs: number;
  durationSec: number;
  source: "hls" | "wallClock";
  hlsMediaStartedAtMs: number | null;
  hlsMediaTimelineOffsetSec: number | null;
  audioPlaybackCompensationSec: number;
  audioPlaybackCompensationSource: string;
}> {
  const timingVersion = safeNonNegativeInteger(session.archiveTimingVersion);
  let hlsDurationMs: number | null = null;
  let mediaTimelineOffsetSec: number | null = null;
  const sessionStartedAtMs = safeNonNegativeInteger(session.startedAtMs);
  const hlsManifestObjectPath = selectManifestObject(
    manifest.files,
    ".m3u8",
    stringField(session.archivePrefix),
  );
  if (
    timingVersion >= 2 &&
    hlsManifestObjectPath
  ) {
    try {
      const [contents] = await getStorage()
        .bucket(config.gcsBucket)
        .file(hlsManifestObjectPath)
        .download();
      const manifestText = contents.toString("utf8");
      hlsDurationMs = finalizedHlsDurationMs(manifestText);
      if (timingVersion >= 3) {
        mediaTimelineOffsetSec = hlsMediaTimelineOffsetSec({
          manifest: manifestText,
          sessionStartedAtMs,
        });
      }
    } catch (error) {
      logArchiveError("read-hls-duration", error);
    }
  }
  const duration = resolveLiveArchiveDuration({
    timingVersion,
    hlsDurationMs,
    sessionStartedAtMs,
    archiveStartedAtMs: safeNonNegativeInteger(session.archiveStartedAtMs),
    archiveStopRequestedAtMs: safeNonNegativeInteger(
      session.archiveStopRequestedAtMs,
    ),
    archiveStoppedAtMs: safeNonNegativeInteger(session.archiveStoppedAtMs),
    finalizedAtMs: Date.now(),
  });
  const hlsMediaStartedAtMs = mediaTimelineOffsetSec === null ?
    null :
    sessionStartedAtMs + Math.round(mediaTimelineOffsetSec * 1000);
  const compensation = resolveLiveAudioPlaybackCompensation({
    timingVersion,
    hlsMediaStartedAtMs,
    audioCaptureStartedAtMs: safeNonNegativeInteger(
      session.audioCaptureStartedAtMs,
    ),
    fallbackSec: liveAudioPlaybackFallbackCompensationSec,
  });
  return {
    ...duration,
    hlsMediaStartedAtMs,
    hlsMediaTimelineOffsetSec: mediaTimelineOffsetSec,
    audioPlaybackCompensationSec: compensation.compensationSec,
    audioPlaybackCompensationSource: compensation.source,
  };
}

function archiveDuration(
  session: DocumentData,
  endAtMs: number,
): {durationMs: number; durationSec: number} {
  const archiveStartedAtMs = safeNonNegativeInteger(
    session.archiveStartedAtMs,
  );
  const startedAtMs = safeNonNegativeInteger(session.startedAtMs);
  const startAtMs = archiveStartedAtMs > 0 ? archiveStartedAtMs : startedAtMs;
  const durationMs = Math.max(1000, endAtMs - startAtMs);
  return {
    durationMs,
    durationSec: Math.max(1, Math.floor(durationMs / 1000)),
  };
}

class ArchiveFinalizationError extends Error {
  constructor(
    readonly publicWarning: string,
    readonly errorCode: string,
  ) {
    super(publicWarning);
    this.name = "ArchiveFinalizationError";
  }
}

async function finalizeArchiveFailure(
  sessionReference: DocumentReference<DocumentData>,
  warning: string,
  errorCode: string,
): Promise<Record<string, unknown>> {
  const endedAtMs = Date.now();
  await sessionReference.update({
    status: "archiveFailed",
    state: "archiveFailed",
    archiveStatus: "archiveFailed",
    archiveError: warning,
    archiveErrorCode: errorCode,
    endedAtMs,
    endedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {
    state: "archiveFailed",
    archiveStatus: "archiveFailed",
    archiveError: warning,
    archiveErrorCode: errorCode,
  };
}

async function recordArchiveFailure(
  sessionReference: DocumentReference<DocumentData>,
  warning: string,
  errorCode: string,
): Promise<void> {
  try {
    await sessionReference.update({
      archiveStatus: "archiveFailed",
      archiveError: warning,
      archiveErrorCode: errorCode,
      updatedAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    logArchiveError("record-failure", error);
  }
}

function cloudRecordingConfig(): AgoraCloudRecordingConfig {
  return {
    appId: agoraAppId.value().trim(),
    customerId: agoraCustomerId.value().trim(),
    customerSecret: agoraCustomerSecret.value().trim(),
    gcsAccessKey: agoraGcsAccessKey.value().trim(),
    gcsSecretKey: agoraGcsSecretKey.value().trim(),
    gcsBucket: agoraGcsBucket.value().trim(),
  };
}

function requireAudioPublisher(session: DocumentData, uid: string): void {
  requireLiveSession(session);
  const ownerUid = stringField(session.ownerUid);
  const presenterUids = stringListField(session.presenterUids);
  if (
    !canPublishAudio({
      ownerUid,
      participantUid: uid,
      activePresenterUid: stringField(session.activePresenterUid),
      presenterUids,
    })
  ) {
    throw new HttpsError(
      "permission-denied",
      "いまマイクを使える人だけが音声時刻を保存できます。",
    );
  }
}

function requirePublisher(session: DocumentData, uid: string): void {
  requireLiveSession(session);
  const ownerUid = stringField(session.ownerUid);
  const presenterUids = stringListField(session.presenterUids);
  if (
    !canDrawBoard({
      ownerUid,
      participantUid: uid,
      activePresenterUid: stringField(session.activePresenterUid),
      presenterUids,
    })
  ) {
    throw new HttpsError(
      "permission-denied",
      "いま書き物を担当している人だけが板書を保存できます。",
    );
  }
}

function requireLiveSession(session: DocumentData): void {
  if (!isLiveSessionState(storedSessionState(session))) {
    throw new HttpsError(
      "failed-precondition",
      "この検証配信は終了しています。",
    );
  }
}

function storedSessionState(session: DocumentData): string {
  const state = session.state;
  if (isSupportedSessionState(state)) {
    return state;
  }
  const status = session.status;
  return isSupportedSessionState(status) ? status : "ended";
}

function safeArchiveStatus(session: DocumentData): Record<string, unknown> {
  return {
    state: storedSessionState(session),
    status: stringField(session.status),
    archiveStatus: stringField(session.archiveStatus) || "archiveFailed",
    archiveError:
      typeof session.archiveError === "string" ? session.archiveError : null,
    archiveErrorCode:
      typeof session.archiveErrorCode === "string" ?
        session.archiveErrorCode :
        null,
    archivePrefix:
      typeof session.archivePrefix === "string" ? session.archivePrefix : null,
    archiveManifest: session.archiveManifest ?? null,
    archivePlaybackUrl:
      typeof session.archivePlaybackUrl === "string" ?
        session.archivePlaybackUrl :
        null,
    hlsManifestObjectPath:
      typeof session.hlsManifestObjectPath === "string" ?
        session.hlsManifestObjectPath :
        null,
    hlsAvailableDurationSec: safeNonNegativeInteger(
      session.hlsAvailableDurationSec,
    ),
    draftReady: session.draftReady ?? null,
    startedAtMs: safeNonNegativeInteger(session.startedAtMs),
    archiveStartedAtMs: safeNonNegativeInteger(session.archiveStartedAtMs),
    archiveTimelineOffsetSec:
      typeof session.archiveTimelineOffsetSec === "number" &&
      Number.isFinite(session.archiveTimelineOffsetSec) ?
        Math.max(0, session.archiveTimelineOffsetSec) :
        0,
    hlsMediaTimelineOffsetSec:
      typeof session.hlsMediaTimelineOffsetSec === "number" &&
      Number.isFinite(session.hlsMediaTimelineOffsetSec) ?
        Math.max(0, session.hlsMediaTimelineOffsetSec) :
        null,
    audioPlaybackCompensationSec:
      typeof session.audioPlaybackCompensationSec === "number" &&
      Number.isFinite(session.audioPlaybackCompensationSec) ?
        Math.max(0, session.audioPlaybackCompensationSec) :
        0,
    audioPlaybackCompensationSource:
      typeof session.audioPlaybackCompensationSource === "string" ?
        session.audioPlaybackCompensationSource :
        null,
    archiveFinalizedAtMs: safeNonNegativeInteger(
      session.archiveFinalizedAtMs,
    ),
  };
}

function archiveStatusWithHlsAccess({
  status,
  sessionId,
  uid,
  request,
}: {
  status: Record<string, unknown>;
  sessionId: string;
  uid: string;
  request: CallableRequest;
}): Record<string, unknown> {
  if (typeof status.hlsManifestObjectPath !== "string") {
    return status;
  }
  const token = createHlsAccessToken(
    {
      sessionId,
      uid,
      expiresAtSec: Math.floor(Date.now() / 1000) + 2 * 60 * 60,
    },
    agoraAppCertificate.value().trim(),
  );
  const url = new URL(hlsProxyUrl(request.rawRequest));
  url.searchParams.set("token", token);
  return {...status, hlsManifestUrl: url.toString()};
}

function hlsProxyUrl(request: {
  get(name: string): string | undefined;
  protocol: string;
}): string {
  const host =
    request.get("x-forwarded-host") ??
    request.get("host") ??
    "";
  const forwardedProtocol = request.get("x-forwarded-proto");
  const protocol = forwardedProtocol?.split(",")[0]?.trim() ||
    request.protocol ||
    "https";
  if (host) {
    return `${protocol}://${host}/liveAudioProbeHls`;
  }
  const projectId =
    process.env.GCLOUD_PROJECT ?? process.env.GCP_PROJECT ?? "";
  return `https://asia-northeast1-${projectId}.cloudfunctions.net/` +
    "liveAudioProbeHls";
}

function validatedCreateInput(value: unknown): {
  links: Record<string, string>;
  initialBoardSet?: Record<string, unknown>;
  segmentStartSec: number;
} {
  if (value === undefined || value === null) {
    return {links: {}, segmentStartSec: 0};
  }
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "配信の関連情報が不正です。");
  }
  const data = value as Record<string, unknown>;
  const allowedKeys = new Set([
    "courseId",
    "lessonId",
    "segmentId",
    "initialBoardSet",
    "segmentStartSec",
  ]);
  if (Object.keys(data).some((key) => !allowedKeys.has(key))) {
    throw new HttpsError(
      "invalid-argument",
      "配信作成データに未対応の項目が含まれています。",
    );
  }
  const result: Record<string, string> = {};
  for (const key of ["courseId", "lessonId", "segmentId"] as const) {
    const entry = data[key];
    if (entry === undefined) {
      continue;
    }
    if (!isValidOptionalLinkId(entry)) {
      throw new HttpsError(
        "invalid-argument",
        `${key}の値が不正です。`,
      );
    }
    result[key] = entry;
  }
  const initialBoardSet = data.initialBoardSet;
  if (initialBoardSet !== undefined && !isValidBoardSet(initialBoardSet)) {
    throw new HttpsError(
      "invalid-argument",
      "初期ホワイトボード全体のデータが不正、または大きすぎます。",
    );
  }
  const segmentStartSec = data.segmentStartSec ?? 0;
  if (!isValidSegmentStartSec(segmentStartSec)) {
    throw new HttpsError(
      "invalid-argument",
      "配信パートの開始時刻が不正です。",
    );
  }
  return {
    links: result,
    ...(initialBoardSet === undefined ? {} : {initialBoardSet}),
    segmentStartSec,
  };
}

function reserveLiveSegmentForSession({
  lesson,
  segmentId,
  sessionId,
  requestedStartSec,
}: {
  lesson: DocumentData;
  segmentId: string;
  sessionId: string;
  requestedStartSec: number;
}):
  | {
    ok: true;
    mediaSegments: Record<string, unknown>[];
    documentVersion: number;
  }
  | {ok: false; message: string} {
  if (!Array.isArray(lesson.mediaSegments)) {
    return {ok: false, message: "レッスンの配信パートを確認できません。"};
  }
  const mediaSegments = lesson.mediaSegments.map((entry: unknown) => {
    return typeof entry === "object" && entry !== null && !Array.isArray(entry) ?
      {...entry as Record<string, unknown>} :
      null;
  });
  if (mediaSegments.some((entry: unknown) => entry === null)) {
    return {ok: false, message: "レッスンのパート情報が不正です。"};
  }
  const typedSegments = mediaSegments as Record<string, unknown>[];
  const targetIndex = typedSegments.findIndex(
    (segment) => segment.id === segmentId,
  );
  if (targetIndex < 0) {
    return {ok: false, message: "予約した配信パートが見つかりません。"};
  }
  const target = typedSegments[targetIndex];
  if (
    target.sourceKind !== "liveArchive" ||
    (typeof target.url === "string" && target.url.trim().length > 0) ||
    (typeof target.liveSessionId === "string" &&
      target.liveSessionId.trim().length > 0)
  ) {
    return {
      ok: false,
      message: "この配信パートは開始済み、または予約状態ではありません。",
    };
  }
  const targetOrder =
    typeof target.order === "number" && Number.isFinite(target.order) ?
      target.order :
      targetIndex;
  const calculatedStartSec = calculatedLiveStartSec(
    typedSegments,
    targetOrder,
  );
  if (Math.abs(calculatedStartSec - requestedStartSec) > 0.1) {
    return {
      ok: false,
      message: "配信パートの開始位置が最新のレッスン情報と一致しません。",
    };
  }
  const documentVersion =
    typeof lesson.documentVersion === "number" &&
    Number.isSafeInteger(lesson.documentVersion) &&
    lesson.documentVersion >= 0 ?
      lesson.documentVersion + 1 :
      1;
  if (!Number.isSafeInteger(documentVersion)) {
    return {ok: false, message: "レッスンの版番号を更新できません。"};
  }
  typedSegments[targetIndex] = {...target, liveSessionId: sessionId};
  return {ok: true, mediaSegments: typedSegments, documentVersion};
}

function boardsFromSnapshot(value: unknown): Map<string, number> {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    return new Map();
  }
  const boards = (value as Record<string, unknown>).boards;
  if (!Array.isArray(boards)) {
    return new Map();
  }
  return new Map(
    boards.flatMap((board): Array<[string, number]> => {
      if (
        typeof board === "object" &&
        board !== null &&
        !Array.isArray(board) &&
        typeof (board as Record<string, unknown>).id === "string" &&
        typeof (board as Record<string, unknown>).order === "number"
      ) {
        return [[
          (board as Record<string, unknown>).id as string,
          (board as Record<string, unknown>).order as number,
        ]];
      }
      return [];
    }),
  );
}

function requireAuthenticatedUid(
  request: CallableRequest<unknown>,
): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "ログインが必要です。");
  }
  return uid;
}

function authenticatedDisplayName(request: CallableRequest<unknown>): string {
  const token = request.auth?.token;
  const name = typeof token?.name === "string" ? token.name.trim() : "";
  const email = typeof token?.email === "string" ? token.email.trim() : "";
  return name || email || "参加者";
}

async function reserveLiveAudioJoinCode({
  sessionId,
  ownerUid,
}: {
  sessionId: string;
  ownerUid: string;
}): Promise<string> {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    const joinCode = randomInt(10000).toString().padStart(4, "0");
    const reference = db.collection(joinCodeCollection).doc(joinCode);
    const reserved = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (snapshot.exists) {
        return false;
      }
      transaction.create(reference, {
        sessionId,
        ownerUid,
        createdAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (reserved) {
      return joinCode;
    }
  }
  throw new HttpsError(
    "resource-exhausted",
    "現在は新しい配信コードを発行できません。しばらくしてからお試しください。",
  );
}

async function releaseLiveAudioJoinCode({
  joinCode,
  sessionId,
}: {
  joinCode: string;
  sessionId: string;
}): Promise<void> {
  try {
    const reference = db.collection(joinCodeCollection).doc(joinCode);
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (snapshot.data()?.sessionId === sessionId) {
        transaction.delete(reference);
      }
    });
  } catch (error) {
    logger.warn("Failed to release unused live audio join code", {
      errorName: error instanceof Error ? error.name : "UnknownError",
    });
  }
}

function requireSessionId(value: unknown): string {
  if (!isValidProbeSessionId(value)) {
    throw new HttpsError("invalid-argument", "配信コードが不正です。");
  }
  return value;
}

function requireLiveAudioJoinCode(value: unknown): string {
  if (!isValidLiveAudioJoinCode(value)) {
    throw new HttpsError("invalid-argument", "4桁の配信コードを入力してください。");
  }
  return value;
}

function requireNonEmptyString(value: unknown, message: string): string {
  if (
    typeof value !== "string" ||
    !/^[A-Za-z0-9_-]{1,128}$/.test(value)
  ) {
    throw new HttpsError("invalid-argument", message);
  }
  return value;
}

function stringField(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function isObjectRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringListField(value: unknown): string[] {
  return Array.isArray(value) ?
    value.filter((entry): entry is string => typeof entry === "string") :
    [];
}

function numberListField(value: unknown): number[] {
  return Array.isArray(value) ?
    value.filter(
      (entry): entry is number =>
        typeof entry === "number" && Number.isSafeInteger(entry),
    ) :
    [];
}

function safeNonNegativeInteger(value: unknown): number {
  return typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= 0 ?
    value :
    0;
}

function logArchiveError(stage: string, error: unknown): void {
  if (error instanceof AgoraCloudRecordingError) {
    const operation = error.operation ?? "unknown";
    const status = error.httpStatus ?? "none";
    const providerCode = error.providerCode ?? "none";
    console.error(
      `[LiveAudioArchive] ${stage} failed ` +
      `(AgoraCloudRecordingError operation=${operation} ` +
      `status=${status} providerCode=${providerCode}).`,
    );
    return;
  }
  const name = error instanceof Error ? error.name : "UnknownError";
  console.error(`[LiveAudioArchive] ${stage} failed (${name}).`);
}
