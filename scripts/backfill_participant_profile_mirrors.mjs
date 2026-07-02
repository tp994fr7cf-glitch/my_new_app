#!/usr/bin/env node

/**
 * Backfill shared profile mirror fields on participantIdentities
 * for learners currently in profile mode.
 *
 * Usage (user PC, after firebase login):
 *   node scripts/backfill_participant_profile_mirrors.mjs --mode plan
 *   node scripts/backfill_participant_profile_mirrors.mjs --mode apply --low-risk-limit 50
 */

import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const FIREBASE_CONFIG_PATH = path.join(
  process.env.USERPROFILE ?? process.env.HOME ?? '',
  '.config',
  'configstore',
  'firebase-tools.json',
);
const FIREBASERC_PATH = path.join(process.cwd(), '.firebaserc');
const BACKUP_DIR = path.join(process.cwd(), 'backup_snapshots');

function parseArgs(argv) {
  const parsed = {mode: 'plan', lowRiskLimit: 200, projectId: ''};
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--mode' && argv[i + 1]) {
      parsed.mode = argv[i + 1].trim();
      i += 1;
      continue;
    }
    if (arg === '--low-risk-limit' && argv[i + 1]) {
      parsed.lowRiskLimit = Math.max(1, Number(argv[i + 1]) || 200);
      i += 1;
      continue;
    }
    if (arg === '--project' && argv[i + 1]) {
      parsed.projectId = argv[i + 1].trim();
      i += 1;
    }
  }
  if (parsed.mode !== 'plan' && parsed.mode !== 'apply') {
    throw new Error(`Unsupported mode: ${parsed.mode}`);
  }
  return parsed;
}

function readJson(filePath) {
  return JSON.parse(readFileSync(filePath, 'utf8'));
}

function resolveProjectId(explicitProjectId) {
  if (explicitProjectId) {
    return explicitProjectId;
  }
  const firebaserc = readJson(FIREBASERC_PATH);
  return firebaserc.projects.default;
}

function readAccessToken() {
  if (!existsSync(FIREBASE_CONFIG_PATH)) {
    throw new Error(`firebase-tools config not found at ${FIREBASE_CONFIG_PATH}`);
  }
  const config = readJson(FIREBASE_CONFIG_PATH);
  return config.tokens.access_token;
}

async function apiRequest(url, method, body, accessToken) {
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      ...(body == null ? {} : {'Content-Type': 'application/json'}),
    },
    body: body == null ? undefined : JSON.stringify(body),
  });
  if (!response.ok) {
    throw new Error(`${method} ${url} failed: HTTP ${response.status}`);
  }
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

function docFields(doc) {
  const fields = doc?.fields ?? {};
  const out = {};
  for (const [key, value] of Object.entries(fields)) {
    if ('stringValue' in value) {
      out[key] = value.stringValue;
    } else if ('booleanValue' in value) {
      out[key] = value.booleanValue;
    }
  }
  return out;
}

function isProfileMode(data) {
  if (data.aliasRetired === true && data.identityMode !== 'courseAlias') {
    return true;
  }
  return data.identityMode === 'profile' && data.aliasConfiguredAtEnrollment !== true;
}

async function listCourses(projectId, token) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`;
  const payload = {
    structuredQuery: {
      from: [{collectionId: 'courses'}],
    },
  };
  const rows = await apiRequest(url, 'POST', payload, token);
  return (rows ?? [])
    .filter((row) => row.document?.name)
    .map((row) => row.document.name.split('/').pop());
}

async function listIdentities(projectId, courseId, token) {
  const listUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/courses/${courseId}/participantIdentities?pageSize=300`;
  const result = await apiRequest(listUrl, 'GET', null, token);
  return result.documents ?? [];
}

async function loadStudentProfile(projectId, userId, token) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/publicUserProfiles/${userId}_student`;
  try {
    return await apiRequest(url, 'GET', null, token);
  } catch {
    return null;
  }
}

async function main() {
  const args = parseArgs(process.argv);
  const projectId = resolveProjectId(args.projectId);
  const token = readAccessToken();
  const report = {
    generatedAt: new Date().toISOString(),
    mode: args.mode,
    projectId,
    candidates: [],
    updated: [],
    skipped: [],
  };

  const courseIds = await listCourses(projectId, token);
  for (const courseId of courseIds) {
    const identities = await listIdentities(projectId, courseId, token);
    for (const doc of identities) {
      const data = docFields(doc);
      const userId = data.userId ?? doc.name.split('/').pop();
      if (!isProfileMode(data)) {
        report.skipped.push({courseId, userId, reason: 'alias-mode'});
        continue;
      }
      if ((data.sharedDisplayName ?? '').trim().length > 0) {
        report.skipped.push({courseId, userId, reason: 'already-mirrored'});
        continue;
      }
      const profileDoc = await loadStudentProfile(projectId, userId, token);
      if (!profileDoc) {
        report.skipped.push({courseId, userId, reason: 'missing-profile'});
        continue;
      }
      const profile = docFields(profileDoc);
      report.candidates.push({courseId, userId, displayName: profile.displayName});
      if (args.mode === 'apply' && report.updated.length < args.lowRiskLimit) {
        const patchUrl = `${doc.name}?updateMask.fieldPaths=sharedDisplayName&updateMask.fieldPaths=sharedAvatarColorName&updateMask.fieldPaths=sharedBio&updateMask.fieldPaths=updatedAt`;
        await apiRequest(
          patchUrl,
          'PATCH',
          {
            fields: {
              sharedDisplayName: {stringValue: profile.displayName ?? '学習者'},
              sharedAvatarColorName: {stringValue: profile.avatarColorName ?? 'blue'},
              sharedBio: {stringValue: profile.bio ?? ''},
              updatedAt: {timestampValue: new Date().toISOString()},
            },
          },
          token,
        );
        report.updated.push({courseId, userId});
      }
    }
  }

  mkdirSync(BACKUP_DIR, {recursive: true});
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const reportPath = path.join(
    BACKUP_DIR,
    `participant_profile_mirror_${args.mode}_${stamp}.json`,
  );
  writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(`mode=${args.mode} candidates=${report.candidates.length} updated=${report.updated.length}`);
  console.log(`report=${reportPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
