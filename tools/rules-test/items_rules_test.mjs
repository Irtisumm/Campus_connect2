// Firestore security-rule tests for the `items/{itemId}` Lost & Found
// collection.
//
// Covers the allowed/denied matrix required by the Lost & Found brief:
//   - unauthenticated read/write denied
//   - student creates own report (type/status/authUid/isDeleted valid)
//   - student creates with wrong reportedByUid denied
//   - student creates with non-Active status denied
//   - student reads own report allowed
//   - student reads another student's report denied
//   - student updates own report fields allowed
//   - student closes own active report (Active -> Closed) allowed
//   - student sets status to Resolved denied (admin-only)
//   - student sets status to Matched - Pending denied (admin-only)
//   - student changes type denied
//   - student changes reportedByUid denied
//   - student updates another student's report denied
//   - admin reads any report allowed
//   - admin sets status to Resolved allowed
//   - admin sets status to Matched - Pending allowed
//   - admin changes type denied
//   - hard delete denied
//
// Run:  (cd tools/rules-test && npm install && npm test)
// `npm test` wraps this file in `firebase emulators:exec` which starts the
// Firestore emulator and sets FIRESTORE_EMULATOR_HOST so
// initializeTestEnvironment auto-discovers it. Requires `firebase` CLI
// and Java on PATH.

import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const here = dirname(fileURLToPath(import.meta.url));
const rulesPath = join(here, '..', '..', 'firestore.rules');
const rules = readFileSync(rulesPath, 'utf8');

const PROJECT_ID = 'campus-connect-ce3e8';

const adminEmail = 'admin@city.edu.my';
const studentAEmail = 'a.student@city.edu.my';
const studentBEmail = 'b.student@city.edu.my';

let env;
let passed = 0;
let failed = 0;

async function it(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  \u2713 ${name}`);
  } catch (e) {
    failed++;
    console.error(`  \u2717 ${name}  -> ${e.message ?? e}`);
  }
}

function itemDoc({ uid, studentId, type = 'lost', title = 'Test Item', category = 'Phone', description = 'desc', whereLost = 'Block A', status = 'Active', isDeleted = false }) {
  return {
    type, title, category, description, whereLost,
    whenLost: new Date(),
    reportedByUid: uid, reportedByStudentId: studentId,
    imageUrls: [], status, isDeleted,
  };
}

env = await initializeTestEnvironment({ projectId: PROJECT_ID, firestore: { rules } });

// Seed admin + two students with rules disabled so isAdmin() resolves.
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await db.collection('users').doc('uidAdmin').set({ uid: 'uidAdmin', studentId: 'ADMIN001', fullName: 'Administrator', authEmail: adminEmail, email: adminEmail, faculty: 'Staff', role: 'admin', status: 'Active', phone: '' });
  await db.collection('users').doc('uidA').set({ uid: 'uidA', studentId: 'S001', fullName: 'Student A', authEmail: studentAEmail, email: studentAEmail, faculty: 'Computing', role: 'student', status: 'Active', phone: '' });
  await db.collection('users').doc('uidB').set({ uid: 'uidB', studentId: 'S002', fullName: 'Student B', authEmail: studentBEmail, email: studentBEmail, faculty: 'Engineering', role: 'student', status: 'Active', phone: '' });
  // Seed one active lost report owned by student A.
  await db.collection('items').doc('itemA1').set(itemDoc({ uid: 'uidA', studentId: 'S001' }));
  // Seed one closed lost report owned by student A (for reopen/transition tests).
  await db.collection('items').doc('itemA2').set(itemDoc({ uid: 'uidA', studentId: 'S001', status: 'Closed' }));
  // Seed a separate active report for the soft-delete test (itemA1 is modified by earlier tests).
  await db.collection('items').doc('itemA3').set(itemDoc({ uid: 'uidA', studentId: 'S001', title: 'Soft-delete target' }));
  // Seed one active found report owned by student B.
  await db.collection('items').doc('itemB1').set(itemDoc({ uid: 'uidB', studentId: 'S002', type: 'found' }));
});

const unauth = env.unauthenticatedContext();
const studentA = env.authenticatedContext('uidA', { email: studentAEmail, email_verified: true });
const studentB = env.authenticatedContext('uidB', { email: studentBEmail, email_verified: true });
const admin = env.authenticatedContext('uidAdmin', { email: adminEmail, email_verified: true });

console.log('\nitems/{itemId} Lost & Found rules');

// ── Reads ──────────────────────────────────────────────────────────

await it('denies an unauthenticated read of any report', async () => {
  await assertFails(unauth.firestore().collection('items').doc('itemA1').get());
});

await it('allows student A to read their own report', async () => {
  await assertSucceeds(studentA.firestore().collection('items').doc('itemA1').get());
});

await it('denies student A from reading student B\'s report', async () => {
  await assertFails(studentA.firestore().collection('items').doc('itemB1').get());
});

await it('allows admin to read any report', async () => {
  await assertSucceeds(admin.firestore().collection('items').doc('itemA1').get());
  await assertSucceeds(admin.firestore().collection('items').doc('itemB1').get());
});

await it('denies student A from listing all reports without uid filter', async () => {
  await assertFails(studentA.firestore().collection('items').where('isDeleted', '==', false).get());
});

await it('allows student A to list their own reports (filtered by uid)', async () => {
  await assertSucceeds(
    studentA.firestore().collection('items')
      .where('isDeleted', '==', false)
      .where('reportedByUid', '==', 'uidA')
      .get(),
  );
});

await it('allows admin to list all reports', async () => {
  await assertSucceeds(
    admin.firestore().collection('items').where('isDeleted', '==', false).get(),
  );
});

// ── Create ────────────────────────────────────────────────────────

await it('denies an unauthenticated create', async () => {
  await assertFails(unauth.firestore().collection('items').doc('new1').set(itemDoc({ uid: 'uidA', studentId: 'S001' })));
});

await it('allows student A to create their own lost report (Active, isDeleted=false)', async () => {
  await assertSucceeds(studentA.firestore().collection('items').doc('newA').set(itemDoc({ uid: 'uidA', studentId: 'S001' })));
});

await it('denies student A from creating a report attributed to student B', async () => {
  await assertFails(studentA.firestore().collection('items').doc('evilA').set(itemDoc({ uid: 'uidB', studentId: 'S002' })));
});

await it('denies a create with status != Active', async () => {
  await assertFails(studentA.firestore().collection('items').doc('badStatus').set(itemDoc({ uid: 'uidA', studentId: 'S001', status: 'Resolved' })));
});

await it('denies a create with isDeleted = true', async () => {
  await assertFails(studentA.firestore().collection('items').doc('badDeleted').set(itemDoc({ uid: 'uidA', studentId: 'S001', isDeleted: true })));
});

await it('denies a create with an invalid type', async () => {
  await assertFails(studentA.firestore().collection('items').doc('badType').set(itemDoc({ uid: 'uidA', studentId: 'S001', type: 'stolen' })));
});

// ── Update (reporter) ─────────────────────────────────────────────

await it('allows student A to update their own report fields (title, description, imageUrls)', async () => {
  await assertSucceeds(studentA.firestore().collection('items').doc('itemA1').update({
    title: 'Updated Title',
    description: 'Updated description',
    imageUrls: ['https://res.cloudinary.com/test/photo1.jpg'],
    status: 'Active',
    isDeleted: false,
    updatedAt: new Date(),
  }));
});

await it('allows student A to close their own active report (Active -> Closed)', async () => {
  await assertSucceeds(studentA.firestore().collection('items').doc('itemA1').update({
    status: 'Closed',
    isDeleted: false,
    updatedAt: new Date(),
  }));
});

await it('denies student A from setting status to Resolved (admin-only)', async () => {
  await assertFails(studentA.firestore().collection('items').doc('itemA1').update({
    status: 'Resolved',
    isDeleted: false,
    updatedAt: new Date(),
  }));
});

await it('denies student A from setting status to Matched - Pending (admin-only)', async () => {
  await assertFails(studentA.firestore().collection('items').doc('itemA1').update({
    status: 'Matched - Pending',
    isDeleted: false,
    updatedAt: new Date(),
  }));
});

await it('denies student A from changing the report type (lost -> found)', async () => {
  await assertFails(studentA.firestore().collection('items').doc('itemA1').update({
    type: 'found',
    status: 'Active',
    isDeleted: false,
    updatedAt: new Date(),
  }));
});

await it('denies student A from reassigning reportedByUid to someone else', async () => {
  await assertFails(studentA.firestore().collection('items').doc('itemA1').update({
    reportedByUid: 'uidB',
    reportedByStudentId: 'S002',
    status: 'Active',
    isDeleted: false,
    updatedAt: new Date(),
  }));
});

await it('denies student A from updating student B\'s report', async () => {
  await assertFails(studentA.firestore().collection('items').doc('itemB1').update({
    title: 'Hijacked',
    status: 'Active',
    isDeleted: false,
    updatedAt: new Date(),
  }));
});

await it('allows student A to soft-delete their own report (isDeleted -> true)', async () => {
  await assertSucceeds(studentA.firestore().collection('items').doc('itemA3').update({
    status: 'Active',
    isDeleted: true,
    updatedAt: new Date(),
  }));
});

// ── Update (admin) ───────────────────────────────────────────────

await it('allows admin to set status to Resolved on any report', async () => {
  await assertSucceeds(admin.firestore().collection('items').doc('itemB1').update({
    status: 'Resolved',
    isDeleted: false,
    updatedAt: new Date(),
  }));
});

await it('allows admin to set status to Matched - Pending on any report', async () => {
  await assertSucceeds(admin.firestore().collection('items').doc('itemB1').update({
    status: 'Matched - Pending',
    isDeleted: false,
    updatedAt: new Date(),
  }));
});

await it('denies admin from changing the report type', async () => {
  await assertFails(admin.firestore().collection('items').doc('itemB1').update({
    type: 'lost',
    status: 'Active',
    isDeleted: false,
    updatedAt: new Date(),
  }));
});

await it('denies admin from reassigning reportedByUid', async () => {
  await assertFails(admin.firestore().collection('items').doc('itemB1').update({
    reportedByUid: 'uidA',
    reportedByStudentId: 'S001',
    status: 'Active',
    isDeleted: false,
    updatedAt: new Date(),
  }));
});

// ── Delete ────────────────────────────────────────────────────────

await it('denies a hard delete by a student', async () => {
  await assertFails(studentA.firestore().collection('items').doc('itemA1').delete());
});

await it('denies a hard delete by an admin', async () => {
  await assertFails(admin.firestore().collection('items').doc('itemA1').delete());
});

await env.cleanup();
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
