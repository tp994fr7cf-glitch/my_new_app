#!/usr/bin/env node

/**
 * Safely plans or applies retention cleanup for raw Agora Cloud Recording data.
 *
 * The default mode is read-only. Apply requires an exact token from a current
 * plan plus explicit project, bucket, and permanent-deletion confirmations.
 */

import {createHash} from 'node:crypto';
import {existsSync} from 'node:fs';
import {createRequire} from 'node:module';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath} from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = path.resolve(SCRIPT_DIR, '..');
const FUNCTIONS_PACKAGE_PATH = path.join(
  REPOSITORY_ROOT,
  'functions',
  'package.json',
);
const RETENTION_RUNTIME_PATH = path.join(
  REPOSITORY_ROOT,
  'functions',
  'lib',
  'live_audio_probe_retention_runtime.js',
);
const PROJECT_ID_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/u;
const BUCKET_NAME_PATTERN =
  /^(?=.{3,222}$)(?!goog)(?!.*google)[a-z0-9][a-z0-9._-]*[a-z0-9]$/u;
const APPLY_ACKNOWLEDGEMENT = 'DELETE_RAW_ARCHIVES_PERMANENTLY';
const PLAN_TOKEN_VERSION = 2;
const SELECTION_POLICY = 'allEligible';

const HELP = `
Usage:
  node scripts/prune_live_audio_probe_raw.mjs [options]

Read-only plan (default):
  --mode plan
  --project <firebase-project-id>
  --raw-bucket <agora-recording-bucket>
  --completed-copy-bucket <firebase-storage-bucket>

Destructive apply (all confirmations are required):
  --mode apply
  --project <firebase-project-id>
  --raw-bucket <agora-recording-bucket>
  --completed-copy-bucket <firebase-storage-bucket>
  --confirm-project <same-firebase-project-id>
  --confirm-raw-bucket <same-agora-recording-bucket>
  --confirm-completed-copy-bucket <same-firebase-storage-bucket>
  --confirm-plan <token-printed-by-a-current-plan>
  --acknowledge-permanent-delete ${APPLY_ACKNOWLEDGEMENT}

Other:
  --help

Safety:
  * Omitting --mode always selects the read-only plan.
  * This one-time tool selects every eligible session, even below 9 GB.
  * Apply is refused if a live/finalizing session or unsafe inventory is found.
  * Only liveAudioProbeSessions/{validated-session-id}/ objects can be deleted.
  * Linked sessions are eligible only after the runtime verifies their MP4 copy.
  * Authentication uses Application Default Credentials; no HMAC key is needed.
`.trim();

function parseArgs(argv) {
  const parsed = {
    mode: 'plan',
    projectId: '',
    rawBucketName: '',
    completedCopyBucketName: '',
    confirmProjectId: '',
    confirmRawBucketName: '',
    confirmCompletedCopyBucketName: '',
    confirmPlan: '',
    acknowledgement: '',
    help: false,
  };
  const valueFlags = new Map([
    ['--mode', 'mode'],
    ['--project', 'projectId'],
    ['--raw-bucket', 'rawBucketName'],
    ['--completed-copy-bucket', 'completedCopyBucketName'],
    ['--confirm-project', 'confirmProjectId'],
    ['--confirm-raw-bucket', 'confirmRawBucketName'],
    [
      '--confirm-completed-copy-bucket',
      'confirmCompletedCopyBucketName',
    ],
    ['--confirm-plan', 'confirmPlan'],
    ['--acknowledge-permanent-delete', 'acknowledgement'],
  ]);
  const seen = new Set();

  for (let index = 2; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--help' || argument === '-h') {
      parsed.help = true;
      continue;
    }
    const property = valueFlags.get(argument);
    if (property === undefined) {
      throw new Error(`Unknown argument: ${argument}`);
    }
    if (seen.has(argument)) {
      throw new Error(`Argument may be supplied only once: ${argument}`);
    }
    const value = argv[index + 1];
    if (value === undefined || value.startsWith('--')) {
      throw new Error(`Missing value for ${argument}`);
    }
    parsed[property] = value.trim();
    seen.add(argument);
    index += 1;
  }
  return parsed;
}

function validateArgs(args) {
  if (args.mode !== 'plan' && args.mode !== 'apply') {
    throw new Error('--mode must be plan or apply.');
  }
  if (!PROJECT_ID_PATTERN.test(args.projectId)) {
    throw new Error(
      '--project is required and must be an explicit Firebase project ID.',
    );
  }
  validateBucketName('--raw-bucket', args.rawBucketName);
  validateBucketName(
    '--completed-copy-bucket',
    args.completedCopyBucketName,
  );

  if (args.mode === 'plan') {
    const applyOnlyValues = [
      args.confirmProjectId,
      args.confirmRawBucketName,
      args.confirmCompletedCopyBucketName,
      args.confirmPlan,
      args.acknowledgement,
    ];
    if (applyOnlyValues.some((value) => value !== '')) {
      throw new Error('Apply confirmation flags cannot be used in plan mode.');
    }
    return;
  }

  const mismatches = [];
  if (args.confirmProjectId !== args.projectId) {
    mismatches.push('--confirm-project');
  }
  if (args.confirmRawBucketName !== args.rawBucketName) {
    mismatches.push('--confirm-raw-bucket');
  }
  if (
    args.confirmCompletedCopyBucketName !== args.completedCopyBucketName
  ) {
    mismatches.push('--confirm-completed-copy-bucket');
  }
  if (mismatches.length > 0) {
    throw new Error(
      `Apply confirmation does not exactly match: ${mismatches.join(', ')}`,
    );
  }
  if (args.confirmPlan === '') {
    throw new Error('Apply requires --confirm-plan from a current plan run.');
  }
  if (args.acknowledgement !== APPLY_ACKNOWLEDGEMENT) {
    throw new Error(
      `Apply requires --acknowledge-permanent-delete ` +
        APPLY_ACKNOWLEDGEMENT,
    );
  }
}

function validateBucketName(flag, value) {
  if (
    !BUCKET_NAME_PATTERN.test(value) ||
    value.startsWith('gs://') ||
    value.includes('/') ||
    isIpAddress(value)
  ) {
    throw new Error(`${flag} is required and must be a bucket name only.`);
  }
}

function isIpAddress(value) {
  const parts = value.split('.');
  return (
    parts.length === 4 &&
    parts.every((part) => /^[0-9]{1,3}$/u.test(part)) &&
    parts.every((part) => Number(part) <= 255)
  );
}

function loadDependencies() {
  if (!existsSync(FUNCTIONS_PACKAGE_PATH)) {
    throw new Error('functions/package.json was not found.');
  }
  if (!existsSync(RETENTION_RUNTIME_PATH)) {
    throw new Error(
      'Compiled retention runtime was not found. Run ' +
        '"npm --prefix functions run build" first.',
    );
  }
  const requireFromFunctions = createRequire(FUNCTIONS_PACKAGE_PATH);
  return {
    ...requireFromFunctions('firebase-admin/app'),
    ...requireFromFunctions('firebase-admin/firestore'),
    ...requireFromFunctions('firebase-admin/storage'),
    ...requireFromFunctions(RETENTION_RUNTIME_PATH),
  };
}

function planToken(args, result, operationalSessions) {
  const tokenInput = {
    version: PLAN_TOKEN_VERSION,
    projectId: args.projectId,
    rawBucketName: args.rawBucketName,
    completedCopyBucketName: args.completedCopyBucketName,
    selectionPolicy: SELECTION_POLICY,
    operationalSessions,
    totalBytes: result.plan.totalBytes,
    inventoryObjectCount: result.inventoryObjectCount,
    unassignedObjectCount: result.unassignedObjectCount,
    unassignedBytes: result.unassignedBytes,
    selectedSessions: normalizeSessions(result.plan.selectedSessions),
    eligibleSessions: normalizeSessions(result.plan.eligibleSessions),
    protectedSessions: [...result.plan.protectedSessions]
      .map((session) => ({
        sessionId: session.sessionId,
        archivePrefix: session.archivePrefix,
        sizeBytes: session.sizeBytes,
        reason: session.reason,
      }))
      .sort(compareSessions),
  };
  const digest = createHash('sha256')
    .update(JSON.stringify(tokenInput))
    .digest('hex')
    .slice(0, 32)
    .toUpperCase();
  return `RAW-${digest}`;
}

function normalizeSessions(sessions) {
  return [...sessions]
    .map((session) => ({
      sessionId: session.sessionId,
      archivePrefix: session.archivePrefix,
      sizeBytes: session.sizeBytes,
      startedAtMs: session.startedAtMs,
    }))
    .sort(compareSessions);
}

function compareSessions(left, right) {
  return (
    left.sessionId.localeCompare(right.sessionId) ||
    left.archivePrefix.localeCompare(right.archivePrefix)
  );
}

function unsafeApplyReasons(result, operationalSessions) {
  const reasons = new Set(
    result.plan.protectedSessions.map((session) => session.reason),
  );
  const blockers = [];
  if (operationalSessions.length > 0) {
    blockers.push('live, recording, or finalizing Firestore session');
  }
  if (result.unassignedObjectCount > 0 || result.unassignedBytes > 0) {
    blockers.push('unassigned raw objects');
  }
  if (reasons.has('liveOrRecording')) {
    blockers.push('live or recording session');
  }
  if (reasons.has('finalizing')) {
    blockers.push('finalizing session');
  }
  if (reasons.has('unsafeArchivePrefix')) {
    blockers.push('unsafe archive prefix');
  }
  if (reasons.has('duplicateSession')) {
    blockers.push('duplicate session inventory');
  }
  return blockers;
}

function reportFor(args, result, token, operationalSessions) {
  return {
    generatedAt: new Date().toISOString(),
    mode: result.mode,
    scope: {
      projectId: args.projectId,
      rawBucketName: args.rawBucketName,
      completedCopyBucketName: args.completedCopyBucketName,
      rawPrefixRoot: 'liveAudioProbeSessions/',
      selectionPolicy: SELECTION_POLICY,
    },
    safety: {
      applyConfirmationToken: token,
      applyBlockers: unsafeApplyReasons(result, operationalSessions),
      operationalSessions,
      completedCopyVerification:
        'Verified by retention runtime for every eligible linked session.',
      credentialsPrinted: false,
    },
    summary: {
      hardLimitExceeded: result.plan.hardLimitExceeded,
      targetReached: result.targetReached,
      totalBytes: result.plan.totalBytes,
      projectedBytes: result.plan.projectedBytes,
      selectedBytes: result.plan.selectedBytes,
      protectedBytes: result.protectedBytes,
      deletedBytes: result.deletedBytes,
      deletedObjectCount: result.deletedObjectCount,
      remainingBytes: result.remainingBytes,
      inventoryObjectCount: result.inventoryObjectCount,
      unassignedObjectCount: result.unassignedObjectCount,
      unassignedBytes: result.unassignedBytes,
    },
    selectedSessions: result.plan.selectedSessions,
    protectedSessions: result.plan.protectedSessions,
    sessionResults: result.sessionResults,
  };
}

function printReport(args, result, token, operationalSessions) {
  console.log(
    JSON.stringify(
      reportFor(args, result, token, operationalSessions),
      null,
      2,
    ),
  );
}

async function findOperationalSessions(db) {
  const snapshot = await db.collection('liveAudioProbeSessions').get();
  return snapshot.docs
    .filter((document) => isOperationalSession(document.data()))
    .map((document) => document.id)
    .sort();
}

function isOperationalSession(data) {
  const lifecycleValues = [data.status, data.state, data.archiveStatus];
  return (
    lifecycleValues.some((value) => value === 'active' || value === 'live') ||
    lifecycleValues.includes('finalizing') ||
    data.archiveStatus === 'starting' ||
    data.archiveStatus === 'recording' ||
    data.archiveStatus === 'available' ||
    data.archiveStatus === 'stopping'
  );
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(HELP);
    return;
  }
  validateArgs(args);

  const {
    applicationDefault,
    initializeApp,
    deleteApp,
    getFirestore,
    getStorage,
    runLiveAudioProbeRawRetention,
  } = loadDependencies();
  if (typeof runLiveAudioProbeRawRetention !== 'function') {
    throw new Error('Compiled retention runtime does not export the shared API.');
  }

  const app = initializeApp({
    credential: applicationDefault(),
    projectId: args.projectId,
  });
  try {
    const db = getFirestore(app);
    const storage = getStorage(app);
    const commonOptions = {
      db,
      rawBucket: storage.bucket(args.rawBucketName),
      completedCopyBucket: storage.bucket(args.completedCopyBucketName),
      log: (entry) => {
        console.error(JSON.stringify({retentionEvent: entry}));
      },
    };
    const [preflight, operationalSessions] = await Promise.all([
      runLiveAudioProbeRawRetention({
        ...commonOptions,
        mode: 'plan',
        selectionPolicy: SELECTION_POLICY,
      }),
      findOperationalSessions(db),
    ]);
    const currentPlanToken = planToken(
      args,
      preflight,
      operationalSessions,
    );

    if (args.mode === 'plan') {
      printReport(args, preflight, currentPlanToken, operationalSessions);
      return;
    }

    const blockers = unsafeApplyReasons(preflight, operationalSessions);
    if (blockers.length > 0) {
      printReport(args, preflight, currentPlanToken, operationalSessions);
      throw new Error(
        `Apply refused because preflight found: ${blockers.join(', ')}.`,
      );
    }
    if (preflight.plan.selectedSessions.length === 0) {
      printReport(args, preflight, currentPlanToken, operationalSessions);
      throw new Error('Apply refused because no safe session was selected.');
    }
    if (args.confirmPlan !== currentPlanToken) {
      printReport(args, preflight, currentPlanToken, operationalSessions);
      throw new Error(
        'Apply refused because the current plan differs. Review the new plan ' +
          'and use its new confirmation token.',
      );
    }

    console.error(
      'Apply authorized: starting generation-scoped raw archive deletion.',
    );
    const applied = await runLiveAudioProbeRawRetention({
      ...commonOptions,
      mode: 'apply',
      selectionPolicy: SELECTION_POLICY,
    });
    printReport(args, applied, currentPlanToken, operationalSessions);
    if (
      !applied.targetReached ||
      applied.sessionResults.some((session) => session.status !== 'deleted')
    ) {
      process.exitCode = 2;
    }
  } finally {
    await deleteApp(app);
  }
}

main().catch((error) => {
  console.error('raw_archive_retention_failed');
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
