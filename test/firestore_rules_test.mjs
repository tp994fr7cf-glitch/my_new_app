import { readFile } from 'node:fs/promises';
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const projectId = 'demo-lesson-rules';
const courseId = 'course-1';
const ownerId = 'teacher-owner';
const otherTeacherId = 'teacher-other';
const inactiveTeacherId = 'teacher-inactive';

let testEnvironment;

function userData({ activeRole = 'teacher' } = {}) {
  return {
    roles: ['teacher'],
    activeRole,
  };
}

function courseData({ lessonContentVersion } = {}) {
  return {
    courseCode: 'RULES01',
    title: 'ルールテスト講座',
    instructorId: ownerId,
    instructorName: '先生',
    category: 'テスト',
    level: '初級',
    duration: '1レッスン',
    lessonCount: 1,
    rating: 0,
    priceLabel: '無料',
    description: 'ルールテスト用',
    lessons: [{ title: 'レッスン1', duration: '1分' }],
    lessonEvents: [],
    status: 'published',
    source: 'teacherCreated',
    ...(lessonContentVersion === undefined ? {} : { lessonContentVersion }),
  };
}

function boardSet(boardCount = 1) {
  return {
    boards: Array.from({ length: boardCount }, (_, index) => ({
      id: `board-${index + 1}`,
      order: index,
      layers: [],
    })),
    switchEvents: [],
  };
}

function draftData({
  baseLessonContentVersion = 0,
  draftRevision = 1,
  boardCount = 1,
  extraFields = {},
} = {}) {
  return {
    lessonNumber: '1',
    boardSet: boardSet(boardCount),
    baseLessonContentVersion,
    draftRevision,
    updatedAt: serverTimestamp(),
    ...extraFields,
  };
}

function firestoreFor(userId) {
  return testEnvironment.authenticatedContext(userId).firestore();
}

async function seed({ lessonContentVersion } = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all([
      setDoc(doc(firestore, 'users', ownerId), userData()),
      setDoc(doc(firestore, 'users', otherTeacherId), userData()),
      setDoc(
        doc(firestore, 'users', inactiveTeacherId),
        userData({ activeRole: 'student' }),
      ),
      setDoc(
        doc(firestore, 'courses', courseId),
        courseData({ lessonContentVersion }),
      ),
    ]);
  });
}

async function seedDraft(data = draftData()) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'courses', courseId, 'lessonDrafts', '1'),
      data,
    );
  });
}

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: await readFile(
        new URL('../firestore.rules', import.meta.url),
        'utf8',
      ),
    },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
});

after(async () => {
  await testEnvironment.cleanup();
});

test('course instructor can create, update, read, and delete a draft', async () => {
  await seed();
  const draftReference = doc(
    firestoreFor(ownerId),
    'courses',
    courseId,
    'lessonDrafts',
    '1',
  );

  await assertSucceeds(setDoc(draftReference, draftData()));
  const createdSnapshot = await assertSucceeds(getDoc(draftReference));
  assert.equal(createdSnapshot.data().draftRevision, 1);

  await assertSucceeds(
    updateDoc(draftReference, draftData({ draftRevision: 2 })),
  );
  await assertSucceeds(deleteDoc(draftReference));
});

test('draft base version must match the current course version', async () => {
  await seed({ lessonContentVersion: 2 });
  const draftReference = doc(
    firestoreFor(ownerId),
    'courses',
    courseId,
    'lessonDrafts',
    '1',
  );

  await assertFails(
    setDoc(
      draftReference,
      draftData({ baseLessonContentVersion: 1 }),
    ),
  );
  await assertSucceeds(
    setDoc(
      draftReference,
      draftData({ baseLessonContentVersion: 2 }),
    ),
  );
});

test('draft revisions must start at one and increment by one', async () => {
  await seed();
  const draftReference = doc(
    firestoreFor(ownerId),
    'courses',
    courseId,
    'lessonDrafts',
    '1',
  );

  await assertFails(setDoc(draftReference, draftData({ draftRevision: 2 })));
  await assertSucceeds(setDoc(draftReference, draftData()));
  await assertFails(
    updateDoc(draftReference, draftData({ draftRevision: 3 })),
  );
  await assertSucceeds(
    updateDoc(draftReference, draftData({ draftRevision: 2 })),
  );
});

test('non-owner and inactive teacher cannot access instructor drafts', async () => {
  await seed();
  await seedDraft();

  for (const userId of [otherTeacherId, inactiveTeacherId]) {
    const draftReference = doc(
      firestoreFor(userId),
      'courses',
      courseId,
      'lessonDrafts',
      '1',
    );
    await assertFails(getDoc(draftReference));
    await assertFails(setDoc(draftReference, draftData()));
  }

  const unauthenticatedReference = doc(
    testEnvironment.unauthenticatedContext().firestore(),
    'courses',
    courseId,
    'lessonDrafts',
    '1',
  );
  await assertFails(getDoc(unauthenticatedReference));
});

test('draft payload enforces board limits and exact top-level fields', async () => {
  await seed();
  const draftReference = doc(
    firestoreFor(ownerId),
    'courses',
    courseId,
    'lessonDrafts',
    '1',
  );

  await assertFails(setDoc(draftReference, draftData({ boardCount: 21 })));
  await assertFails(
    setDoc(
      draftReference,
      draftData({ extraFields: { unexpected: true } }),
    ),
  );
});
