#!/usr/bin/env node

import {execSync} from 'node:child_process';
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const FIREBASE_CONFIG_PATH = path.join(
  process.env.USERPROFILE ?? '',
  '.config',
  'configstore',
  'firebase-tools.json',
);
const FIREBASERC_PATH = path.join(process.cwd(), '.firebaserc');
const BACKUP_DIR = path.join(process.cwd(), 'backup_snapshots');

const LESSON_QUESTIONS_COLLECTION = 'lessonQuestions';
const PUBLIC_QUESTIONS_COLLECTION = 'publicLessonQuestions';
const VISIBILITY_TEACHER_ONLY = 'teacherOnly';
const VISIBILITY_PUBLIC = 'public';
const DEFAULT_LOW_RISK_LIMIT = 200;

function parseArgs(argv) {
  const parsed = {
    mode: 'plan',
    applyWhenLowRisk: false,
    lowRiskLimit: DEFAULT_LOW_RISK_LIMIT,
    projectId: '',
    applyReportPath: '',
  };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--mode' && argv[i + 1]) {
      parsed.mode = argv[i + 1].trim();
      i += 1;
      continue;
    }
    if (arg === '--apply-when-low-risk') {
      parsed.applyWhenLowRisk = true;
      continue;
    }
    if (arg === '--low-risk-limit' && argv[i + 1]) {
      const value = Number(argv[i + 1]);
      if (Number.isFinite(value) && value > 0) {
        parsed.lowRiskLimit = Math.floor(value);
      }
      i += 1;
      continue;
    }
    if (arg === '--project' && argv[i + 1]) {
      parsed.projectId = argv[i + 1].trim();
      i += 1;
      continue;
    }
    if (arg === '--apply-report' && argv[i + 1]) {
      parsed.applyReportPath = argv[i + 1].trim();
      i += 1;
      continue;
    }
  }
  if (
    parsed.mode !== 'plan' &&
    parsed.mode !== 'apply' &&
    parsed.mode !== 'rollback'
  ) {
    throw new Error(`Unsupported mode: ${parsed.mode}`);
  }
  return parsed;
}

function readJson(pathName) {
  return JSON.parse(readFileSync(pathName, 'utf8'));
}

function resolveProjectId(explicitProjectId) {
  if (explicitProjectId) {
    return explicitProjectId;
  }
  if (!existsSync(FIREBASERC_PATH)) {
    throw new Error(`.firebaserc not found at ${FIREBASERC_PATH}`);
  }
  const firebaserc = readJson(FIREBASERC_PATH);
  const projectId = firebaserc?.projects?.default;
  if (!projectId || typeof projectId !== 'string') {
    throw new Error('Could not resolve default projectId from .firebaserc');
  }
  return projectId;
}

function readAccessToken() {
  if (!existsSync(FIREBASE_CONFIG_PATH)) {
    throw new Error(`firebase-tools config not found at ${FIREBASE_CONFIG_PATH}`);
  }
  const config = readJson(FIREBASE_CONFIG_PATH);
  const token = config?.tokens?.access_token;
  if (!token || typeof token !== 'string') {
    throw new Error('No access token in firebase-tools config');
  }
  return token;
}

function refreshFirebaseLoginSession() {
  execSync('firebase login:list', {
    stdio: 'ignore',
    cwd: process.cwd(),
    env: process.env,
  });
}

async function apiRequest(url, method, body, accessToken) {
  const headers = {
    Authorization: `Bearer ${accessToken}`,
  };
  if (body != null) {
    headers['Content-Type'] = 'application/json';
  }
  const response = await fetch(url, {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });
  if (!response.ok) {
    const text = await response.text();
    const error = new Error(`${method} ${url} failed: HTTP ${response.status}`);
    error.status = response.status;
    error.body = text;
    throw error;
  }
  const text = await response.text();
  if (!text) {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

async function withTokenRetry(operation) {
  let token = readAccessToken();
  try {
    return await operation(token);
  } catch (error) {
    if (error?.status !== 401) {
      throw error;
    }
    refreshFirebaseLoginSession();
    token = readAccessToken();
    return operation(token);
  }
}

function parseRunQueryDocuments(payload) {
  if (!Array.isArray(payload)) {
    return [];
  }
  const docs = [];
  for (const row of payload) {
    if (row?.document && row.document.name) {
      docs.push(row.document);
    }
  }
  return docs;
}

function parseDocPath(documentName) {
  const match = documentName.match(
    /\/documents\/users\/([^/]+)\/lessonQuestions\/([^/]+)$/u,
  );
  if (!match) {
    return null;
  }
  return {
    userId: match[1],
    questionId: match[2],
  };
}

function decodeString(fields, key, fallback = '') {
  return fields?.[key]?.stringValue ?? fallback;
}

function decodeInt(fields, key, fallback = 0) {
  const raw = fields?.[key]?.integerValue;
  if (typeof raw === 'string') {
    const value = Number(raw);
    return Number.isFinite(value) ? value : fallback;
  }
  if (typeof raw === 'number') {
    return Math.floor(raw);
  }
  return fallback;
}

function decodeBool(fields, key, fallback = false) {
  const raw = fields?.[key]?.booleanValue;
  if (typeof raw === 'boolean') {
    return raw;
  }
  return fallback;
}

function deepCloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function toInteractionSettingId(courseId, lessonNumber) {
  if (!courseId || !lessonNumber) {
    return '';
  }
  return `${courseId}_${lessonNumber}`;
}

function ensureDir(pathName) {
  if (!existsSync(pathName)) {
    mkdirSync(pathName, {recursive: true});
  }
}

function nowStamp() {
  return new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
}

async function fetchTeacherOnlyQuestions(projectId) {
  const users = await listTopLevelUsers(projectId);
  const docs = [];
  for (const user of users) {
    const lessonQuestions = await listUserLessonQuestions(projectId, user.userId);
    for (const questionDoc of lessonQuestions) {
      const visibility = decodeString(questionDoc.fields ?? {}, 'visibility');
      if (visibility == VISIBILITY_TEACHER_ONLY) {
        docs.push(questionDoc);
      }
    }
  }
  return docs;
}

async function listTopLevelUsers(projectId) {
  const allUsers = [];
  let nextPageToken = '';
  do {
    const params = new URLSearchParams({pageSize: '300'});
    if (nextPageToken) {
      params.set('pageToken', nextPageToken);
    }
    const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users?${params.toString()}`;
    const page = await withTokenRetry((token) => apiRequest(url, 'GET', null, token));
    const docs = Array.isArray(page?.documents) ? page.documents : [];
    for (const doc of docs) {
      const match = doc?.name?.match(/\/documents\/users\/([^/]+)$/u);
      if (!match) {
        continue;
      }
      allUsers.push({userId: match[1], name: doc.name});
    }
    nextPageToken = typeof page?.nextPageToken === 'string' ? page.nextPageToken : '';
  } while (nextPageToken);
  return allUsers;
}

async function listUserLessonQuestions(projectId, userId) {
  const docs = [];
  let nextPageToken = '';
  do {
    const params = new URLSearchParams({pageSize: '500'});
    if (nextPageToken) {
      params.set('pageToken', nextPageToken);
    }
    const url =
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/` +
      `users/${userId}/${LESSON_QUESTIONS_COLLECTION}?${params.toString()}`;
    const page = await withTokenRetry((token) => apiRequest(url, 'GET', null, token));
    const pageDocs = Array.isArray(page?.documents) ? page.documents : [];
    docs.push(...pageDocs);
    nextPageToken = typeof page?.nextPageToken === 'string' ? page.nextPageToken : '';
  } while (nextPageToken);
  return docs;
}

async function fetchMirror(projectId, questionId) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${PUBLIC_QUESTIONS_COLLECTION}/${questionId}`;
  try {
    return await withTokenRetry((token) => apiRequest(url, 'GET', null, token));
  } catch (error) {
    if (error?.status === 404) {
      return null;
    }
    throw error;
  }
}

function buildPublicMirrorFields(sourceDoc, questionId) {
  const sourceFields = sourceDoc?.fields ?? {};
  const nextFields = deepCloneJson(sourceFields);
  const courseId = decodeString(sourceFields, 'courseId');
  const lessonNumber = decodeInt(sourceFields, 'lessonNumber');
  const sourceVisibility =
    decodeString(sourceFields, 'studentVisibility') ||
    decodeString(sourceFields, 'visibility') ||
    VISIBILITY_TEACHER_ONLY;
  const interactionSettingId =
    decodeString(sourceFields, 'interactionSettingId') ||
    toInteractionSettingId(courseId, lessonNumber);

  nextFields.questionId = {stringValue: questionId};
  nextFields.visibility = {stringValue: VISIBILITY_PUBLIC};
  nextFields.studentVisibility = {stringValue: sourceVisibility};
  nextFields.interactionSettingId = {stringValue: interactionSettingId};
  if (!nextFields.moderationStatus) {
    nextFields.moderationStatus = {stringValue: 'visible'};
  }
  if (!nextFields.isDeleted) {
    nextFields.isDeleted = {booleanValue: false};
  }
  if (!nextFields.updatedAt) {
    nextFields.updatedAt = {timestampValue: new Date().toISOString()};
  }
  if (!nextFields.createdAt) {
    nextFields.createdAt = {timestampValue: new Date().toISOString()};
  }
  return {fields: nextFields, interactionSettingId};
}

async function createMirrorIfMissing(projectId, questionId, fieldsPayload) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/` +
    `${PUBLIC_QUESTIONS_COLLECTION}/${questionId}?currentDocument.exists=false`;
  try {
    await withTokenRetry((token) =>
      apiRequest(url, 'PATCH', {fields: fieldsPayload}, token),
    );
    return {status: 'created'};
  } catch (error) {
    if (error?.status === 409 || error?.status === 412) {
      return {status: 'already-exists'};
    }
    return {
      status: 'failed',
      error: {
        status: error?.status ?? null,
        message: String(error?.message ?? error),
        body: typeof error?.body === 'string' ? error.body.slice(0, 1000) : null,
      },
    };
  }
}

async function deleteMirror(projectId, questionId) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${PUBLIC_QUESTIONS_COLLECTION}/${questionId}`;
  try {
    await withTokenRetry((token) => apiRequest(url, 'DELETE', null, token));
    return {status: 'deleted'};
  } catch (error) {
    if (error?.status === 404) {
      return {status: 'already-missing'};
    }
    return {
      status: 'failed',
      error: {
        status: error?.status ?? null,
        message: String(error?.message ?? error),
        body: typeof error?.body === 'string' ? error.body.slice(0, 1000) : null,
      },
    };
  }
}

async function main() {
  const args = parseArgs(process.argv);
  const projectId = resolveProjectId(args.projectId);
  const startedAt = new Date().toISOString();
  ensureDir(BACKUP_DIR);

  if (args.mode === 'rollback') {
    if (!args.applyReportPath) {
      throw new Error('Rollback mode requires --apply-report <path>');
    }
    const reportPath = path.isAbsolute(args.applyReportPath)
      ? args.applyReportPath
      : path.join(process.cwd(), args.applyReportPath);
    if (!existsSync(reportPath)) {
      throw new Error(`Apply report not found: ${reportPath}`);
    }
    const applyReport = readJson(reportPath);
    const createdItems = (applyReport?.results ?? []).filter(
      (row) => row?.status === 'created' && row?.questionId,
    );
    const rollbackResults = [];
    for (const item of createdItems) {
      const result = await deleteMirror(projectId, String(item.questionId));
      rollbackResults.push({
        questionId: String(item.questionId),
        status: result.status,
        error: result.error ?? null,
      });
    }
    const deletedCount = rollbackResults.filter(
      (row) => row.status === 'deleted',
    ).length;
    const alreadyMissingCount = rollbackResults.filter(
      (row) => row.status === 'already-missing',
    ).length;
    const failedCount = rollbackResults.filter(
      (row) => row.status === 'failed',
    ).length;
    const rollbackReport = {
      meta: {
        startedAt,
        finishedAt: new Date().toISOString(),
        projectId,
        applyReportPath: reportPath,
      },
      summary: {
        attempted: rollbackResults.length,
        deletedCount,
        alreadyMissingCount,
        failedCount,
      },
      results: rollbackResults,
    };
    const stamp = nowStamp();
    const rollbackPath = path.join(
      BACKUP_DIR,
      `teacher_only_question_mirror_rollback_${stamp}.json`,
    );
    writeFileSync(rollbackPath, JSON.stringify(rollbackReport, null, 2), 'utf8');
    console.log(`projectId=${projectId}`);
    console.log(`rollbackPath=${rollbackPath}`);
    console.log(`deletedCount=${deletedCount}`);
    console.log(`alreadyMissingCount=${alreadyMissingCount}`);
    console.log(`failedCount=${failedCount}`);
    return;
  }

  const teacherOnlyDocs = await fetchTeacherOnlyQuestions(projectId);
  const candidates = [];
  for (const doc of teacherOnlyDocs) {
    const pathInfo = parseDocPath(doc.name);
    if (!pathInfo) {
      continue;
    }
    const sourceFields = doc.fields ?? {};
    if (decodeBool(sourceFields, 'isDeleted', false)) {
      continue;
    }
    candidates.push({
      userId: pathInfo.userId,
      questionId: pathInfo.questionId,
      sourceDoc: doc,
    });
  }

  const missing = [];
  const existing = [];
  for (const item of candidates) {
    const mirror = await fetchMirror(projectId, item.questionId);
    if (mirror == null) {
      missing.push(item);
    } else {
      existing.push({questionId: item.questionId, mirrorName: mirror.name});
    }
  }

  const plan = {
    meta: {
      startedAt,
      finishedAt: new Date().toISOString(),
      projectId,
      mode: args.mode,
      applyWhenLowRisk: args.applyWhenLowRisk,
      lowRiskLimit: args.lowRiskLimit,
    },
    summary: {
      teacherOnlySourceCount: teacherOnlyDocs.length,
      candidateCount: candidates.length,
      missingMirrorCount: missing.length,
      existingMirrorCount: existing.length,
    },
    missingMirrors: missing.map((item) => ({
      userId: item.userId,
      questionId: item.questionId,
      sourceName: item.sourceDoc.name,
      sourceFields: item.sourceDoc.fields ?? {},
    })),
  };

  const stamp = nowStamp();
  const planPath = path.join(
    BACKUP_DIR,
    `teacher_only_question_mirror_plan_${stamp}.json`,
  );
  writeFileSync(planPath, JSON.stringify(plan, null, 2), 'utf8');

  console.log(`projectId=${projectId}`);
  console.log(`teacherOnlySourceCount=${plan.summary.teacherOnlySourceCount}`);
  console.log(`candidateCount=${plan.summary.candidateCount}`);
  console.log(`missingMirrorCount=${plan.summary.missingMirrorCount}`);
  console.log(`existingMirrorCount=${plan.summary.existingMirrorCount}`);
  console.log(`planPath=${planPath}`);

  const shouldApply =
    (args.mode === 'apply' || args.applyWhenLowRisk) &&
    plan.summary.missingMirrorCount > 0;
  if (!shouldApply) {
    console.log('applySkipped=true reason=plan-only-or-no-missing');
    return;
  }
  if (plan.summary.missingMirrorCount > args.lowRiskLimit) {
    console.log(
      `applySkipped=true reason=over-low-risk-limit missing=${plan.summary.missingMirrorCount} limit=${args.lowRiskLimit}`,
    );
    return;
  }

  const applyResults = [];
  for (const item of missing) {
    const payload = buildPublicMirrorFields(item.sourceDoc, item.questionId);
    if (!payload.interactionSettingId) {
      applyResults.push({
        userId: item.userId,
        questionId: item.questionId,
        status: 'failed',
        error: {message: 'Missing interactionSettingId and could not derive'},
      });
      continue;
    }
    const result = await createMirrorIfMissing(
      projectId,
      item.questionId,
      payload.fields,
    );
    applyResults.push({
      userId: item.userId,
      questionId: item.questionId,
      status: result.status,
      error: result.error ?? null,
    });
  }

  const createdCount = applyResults.filter((row) => row.status === 'created').length;
  const alreadyExistsCount = applyResults.filter(
    (row) => row.status === 'already-exists',
  ).length;
  const failedCount = applyResults.filter((row) => row.status === 'failed').length;

  const applyReport = {
    meta: {
      startedAt,
      finishedAt: new Date().toISOString(),
      projectId,
      lowRiskLimit: args.lowRiskLimit,
      planPath,
    },
    summary: {
      attempted: applyResults.length,
      createdCount,
      alreadyExistsCount,
      failedCount,
    },
    results: applyResults,
  };
  const applyPath = path.join(
    BACKUP_DIR,
    `teacher_only_question_mirror_apply_${stamp}.json`,
  );
  writeFileSync(applyPath, JSON.stringify(applyReport, null, 2), 'utf8');

  console.log(`applyPath=${applyPath}`);
  console.log(`createdCount=${createdCount}`);
  console.log(`alreadyExistsCount=${alreadyExistsCount}`);
  console.log(`failedCount=${failedCount}`);
}

main().catch((error) => {
  console.error('backfill_failed');
  console.error(error?.message ?? String(error));
  if (error?.body) {
    console.error(String(error.body).slice(0, 1000));
  }
  process.exit(1);
});
