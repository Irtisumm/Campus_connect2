// Firestore security-rule tests for the Lost & Found full-workflow
// collections: the extended `items` statuses plus `qrTransactions`,
// `inventory`, `matches`, and `lfNotifications`.
//
// Covers the allowed/denied matrix for Workflow 2 (handover) and
// Workflow 3 (match + return) under the client-only enforcement model:
//   - items: found reports born 'Awaiting Handover'; student closes own
//     Awaiting Handover report; 'In Inventory'/'Returned' are admin-only
//   - qrTransactions: admin-only issuance with bounded expiry; intended
//     student single scan (Issued -> Scanned); wrong student, expired,
//     re-scan and student-confirm all denied; admin confirms only after
//     scan, within expiry; cancellation allowed; identity fields pinned
//   - inventory: admin-only create/update; finder reads own; status moves
//     In Inventory -> Returned only
//   - matches: admin-only create/update; lost owner reads own safe summary
//   - lfNotifications: admin creates; recipient reads own and flips `read`
//     only
//
// Run:  (cd tools/rules-test && npm install && npm test)

import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { Timestamp } from 'firebase/firestore';
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

const NOW = Date.now();
const in10Min = () => Timestamp.fromMillis(Date.now() + 10 * 60 * 1000);
const pastMin = () => Timestamp.fromMillis(Date.now() - 60 * 1000);
const issuedAt = () => Timestamp.fromMillis(Date.now() - 1000);

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

function itemDoc({ uid, studentId, type = 'lost', status = 'Active', isDeleted = false }) {
  return {
    type, title: 'Test Item', category: 'Phone', description: 'desc',
    whereLost: 'Block A', whenLost: new Date(),
    reportedByUid: uid, reportedByStudentId: studentId,
    imageUrls: [], status, isDeleted,
  };
}

function qrDoc({ kind = 'handover', token, intendedUid, intendedStudentId, foundReportId = 'itemB1', lostReportId = '', inventoryItemId = '', status = 'Issued', expiresAt }) {
  return {
    kind, token, intendedStudentUid: intendedUid,
    intendedStudentId, foundReportId, lostReportId, inventoryItemId,
    status, issuedAt: issuedAt(), expiresAt,
  };
}

env = await initializeTestEnvironment({ projectId: PROJECT_ID, firestore: { rules } });

// Seed users and fixtures with rules disabled so the test itself only
// exercises the rules under test.
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await db.collection('users').doc('uidAdmin').set({ uid: 'uidAdmin', studentId: 'ADMIN001', fullName: 'Administrator', authEmail: adminEmail, email: adminEmail, faculty: 'Staff', role: 'admin', status: 'Active', phone: '' });
  await db.collection('users').doc('uidA').set({ uid: 'uidA', studentId: 'S001', fullName: 'Student A', authEmail: studentAEmail, email: studentAEmail, faculty: 'Computing', role: 'student', status: 'Active', phone: '' });
  await db.collection('users').doc('uidB').set({ uid: 'uidB', studentId: 'S002', fullName: 'Student B', authEmail: studentBEmail, email: studentBEmail, faculty: 'Engineering', role: 'student', status: 'Active', phone: '' });

  // items fixtures
  await db.collection('items').doc('itemA1').set(itemDoc({ uid: 'uidA', studentId: 'S001' }));
  await db.collection('items').doc('itemB1').set(itemDoc({ uid: 'uidB', studentId: 'S002', type: 'found', status: 'Awaiting Handover' }));
  await db.collection('items').doc('itemB2').set(itemDoc({ uid: 'uidB', studentId: 'S002', type: 'found', status: 'Awaiting Handover', title: 'Close target' }));
  await db.collection('items').doc('itemB3').set(itemDoc({ uid: 'uidB', studentId: 'S002', type: 'found', status: 'Awaiting Handover', title: 'Return target' }));
  await db.collection('items').doc('itemB4').set(itemDoc({ uid: 'uidB', studentId: 'S002', type: 'found', status: 'Awaiting Handover', title: 'Inventory target' }));

  // qrTransactions fixtures
  await db.collection('qrTransactions').doc('txnHandover').set(qrDoc({ token: 'tokH', intendedUid: 'uidB', intendedStudentId: 'S002', expiresAt: in10Min() }));
  await db.collection('qrTransactions').doc('txnIssued2').set(qrDoc({ token: 'tokI2', intendedUid: 'uidB', intendedStudentId: 'S002', expiresAt: in10Min() }));
  await db.collection('qrTransactions').doc('txnScanned').set(qrDoc({ token: 'tokS', intendedUid: 'uidB', intendedStudentId: 'S002', status: 'Scanned', expiresAt: in10Min() }));
  await db.collection('qrTransactions').doc('txnScannedExpired').set(qrDoc({ token: 'tokSE', intendedUid: 'uidB', intendedStudentId: 'S002', status: 'Scanned', expiresAt: pastMin() }));
  await db.collection('qrTransactions').doc('txnExpired').set(qrDoc({ token: 'tokE', intendedUid: 'uidB', intendedStudentId: 'S002', expiresAt: pastMin() }));
  await db.collection('qrTransactions').doc('txnOther').set(qrDoc({ token: 'tokO', intendedUid: 'uidA', intendedStudentId: 'S001', expiresAt: in10Min() }));

  // inventory fixture
  await db.collection('inventory').doc('invB1').set({ foundReportId: 'itemB1', finderUid: 'uidB', finderStudentId: 'S002', title: 'Found Phone', category: 'Phone', description: 'desc', imageUrls: [], status: 'In Inventory', createdAt: new Date(), updatedAt: new Date() });

  // matches fixture
  await db.collection('matches').doc('match1').set({ lostReportId: 'itemA1', inventoryItemId: 'invB1', lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', status: 'Proposed', notes: 'Looks like a match', createdAt: new Date(), updatedAt: new Date() });

  // lfNotifications fixture
  await db.collection('lfNotifications').doc('notif1').set({ studentId: 'S001', title: 'Possible match found', body: 'Visit the Inventory Office', type: 'match', read: false, relatedReportId: 'itemA1', createdAt: new Date() });
});

const unauth = env.unauthenticatedContext();
const studentA = env.authenticatedContext('uidA', { email: studentAEmail, email_verified: true });
const studentB = env.authenticatedContext('uidB', { email: studentBEmail, email_verified: true });
const admin = env.authenticatedContext('uidAdmin', { email: adminEmail, email_verified: true });

console.log('\nLost & Found full-workflow rules');

// ── items: extended statuses ──────────────────────────────────────

await it('allows a found report to be created with status Awaiting Handover', async () => {
  await assertSucceeds(studentB.firestore().collection('items').doc('newFound').set(itemDoc({ uid: 'uidB', studentId: 'S002', type: 'found', status: 'Awaiting Handover' })));
});

await it('denies a found report created with status Active', async () => {
  await assertFails(studentB.firestore().collection('items').doc('badFound').set(itemDoc({ uid: 'uidB', studentId: 'S002', type: 'found', status: 'Active' })));
});

await it('denies a lost report created with status Awaiting Handover', async () => {
  await assertFails(studentA.firestore().collection('items').doc('badLost').set(itemDoc({ uid: 'uidA', studentId: 'S001', type: 'lost', status: 'Awaiting Handover' })));
});

await it('allows the finder to close their own Awaiting Handover report', async () => {
  await assertSucceeds(studentB.firestore().collection('items').doc('itemB2').update({ status: 'Closed', isDeleted: false, updatedAt: new Date() }));
});

await it('denies the finder from setting their own report to In Inventory', async () => {
  await assertFails(studentB.firestore().collection('items').doc('itemB4').update({ status: 'In Inventory', isDeleted: false, updatedAt: new Date() }));
});

await it('allows admin to set a found report to In Inventory', async () => {
  await assertSucceeds(admin.firestore().collection('items').doc('itemB4').update({ status: 'In Inventory', isDeleted: false, updatedAt: new Date() }));
});

await it('allows admin to set a found report to Returned', async () => {
  await assertSucceeds(admin.firestore().collection('items').doc('itemB3').update({ status: 'Returned', isDeleted: false, updatedAt: new Date() }));
});

// ── qrTransactions ────────────────────────────────────────────────

await it('allows admin to issue a handover QR', async () => {
  await assertSucceeds(admin.firestore().collection('qrTransactions').doc('newHandover').set(qrDoc({ token: 'tokN1', intendedUid: 'uidB', intendedStudentId: 'S002', expiresAt: in10Min() })));
});

await it('allows admin to issue a return QR', async () => {
  await assertSucceeds(admin.firestore().collection('qrTransactions').doc('newReturn').set(qrDoc({ kind: 'return', token: 'tokN2', intendedUid: 'uidA', intendedStudentId: 'S001', lostReportId: 'itemA1', inventoryItemId: 'invB1', expiresAt: in10Min() })));
});

await it('denies a student from issuing a QR', async () => {
  await assertFails(studentB.firestore().collection('qrTransactions').doc('evilTxn').set(qrDoc({ token: 'tokX', intendedUid: 'uidB', intendedStudentId: 'S002', expiresAt: in10Min() })));
});

await it('denies an admin-issued QR with expiry beyond 15 minutes', async () => {
  await assertFails(admin.firestore().collection('qrTransactions').doc('farExpiry').set(qrDoc({ token: 'tokF', intendedUid: 'uidB', intendedStudentId: 'S002', expiresAt: Timestamp.fromMillis(Date.now() + 20 * 60 * 1000) })));
});

await it('denies an unauthenticated read of a QR transaction', async () => {
  await assertFails(unauth.firestore().collection('qrTransactions').doc('txnHandover').get());
});

await it('allows the intended student to read their own QR transaction', async () => {
  await assertSucceeds(studentB.firestore().collection('qrTransactions').doc('txnHandover').get());
});

await it('denies the wrong student from reading someone else\'s QR transaction', async () => {
  await assertFails(studentA.firestore().collection('qrTransactions').doc('txnHandover').get());
});

await it('allows the intended student to scan an Issued QR (Issued -> Scanned)', async () => {
  await assertSucceeds(studentB.firestore().collection('qrTransactions').doc('txnHandover').update({ status: 'Scanned', scannedAt: Timestamp.now() }));
});

await it('denies the wrong student from scanning', async () => {
  await assertFails(studentA.firestore().collection('qrTransactions').doc('txnIssued2').update({ status: 'Scanned', scannedAt: Timestamp.now() }));
});

await it('denies scanning an expired QR', async () => {
  await assertFails(studentB.firestore().collection('qrTransactions').doc('txnExpired').update({ status: 'Scanned', scannedAt: Timestamp.now() }));
});

await it('denies a second scan of an already-Scanned QR', async () => {
  await assertFails(studentB.firestore().collection('qrTransactions').doc('txnHandover').update({ status: 'Scanned', scannedAt: Timestamp.now() }));
});

await it('denies the student from confirming a QR (Scanned -> Confirmed is admin-only)', async () => {
  await assertFails(studentB.firestore().collection('qrTransactions').doc('txnHandover').update({ status: 'Confirmed', confirmedAt: Timestamp.now(), confirmedByUid: 'uidB' }));
});

await it('denies the student from changing the token', async () => {
  await assertFails(studentB.firestore().collection('qrTransactions').doc('txnIssued2').update({ token: 'hacked', status: 'Scanned', scannedAt: Timestamp.now() }));
});

await it('allows admin to confirm a Scanned QR (Scanned -> Confirmed)', async () => {
  await assertSucceeds(admin.firestore().collection('qrTransactions').doc('txnScanned').update({ status: 'Confirmed', confirmedAt: Timestamp.now(), confirmedByUid: 'uidAdmin', updatedAt: new Date() }));
});

await it('denies admin from confirming an Issued QR directly (must be scanned first)', async () => {
  await assertFails(admin.firestore().collection('qrTransactions').doc('txnIssued2').update({ status: 'Confirmed', confirmedAt: Timestamp.now(), confirmedByUid: 'uidAdmin', updatedAt: new Date() }));
});

await it('denies admin from confirming an expired Scanned QR', async () => {
  await assertFails(admin.firestore().collection('qrTransactions').doc('txnScannedExpired').update({ status: 'Confirmed', confirmedAt: Timestamp.now(), confirmedByUid: 'uidAdmin', updatedAt: new Date() }));
});

await it('allows admin to cancel an Issued QR (Issued -> Cancelled)', async () => {
  await assertSucceeds(admin.firestore().collection('qrTransactions').doc('txnIssued2').update({ status: 'Cancelled', updatedAt: new Date() }));
});

await it('denies admin from re-pointing the intended student', async () => {
  await assertFails(admin.firestore().collection('qrTransactions').doc('txnScanned').update({ intendedStudentUid: 'uidA', status: 'Confirmed', confirmedAt: Timestamp.now(), confirmedByUid: 'uidAdmin', updatedAt: new Date() }));
});

await it('denies deletion of a QR transaction', async () => {
  await assertFails(admin.firestore().collection('qrTransactions').doc('txnHandover').delete());
});

// ── inventory ─────────────────────────────────────────────────────

await it('allows admin to create an inventory record', async () => {
  await assertSucceeds(admin.firestore().collection('inventory').doc('invNew').set({ foundReportId: 'itemB1', finderUid: 'uidB', finderStudentId: 'S002', title: 'Phone', category: 'Phone', description: 'desc', imageUrls: [], status: 'In Inventory', createdAt: new Date(), updatedAt: new Date() }));
});

await it('denies a student from creating an inventory record', async () => {
  await assertFails(studentB.firestore().collection('inventory').doc('invEvil').set({ foundReportId: 'itemB1', finderUid: 'uidB', finderStudentId: 'S002', title: 'Phone', category: 'Phone', description: 'desc', imageUrls: [], status: 'In Inventory' }));
});

await it('allows the finder to read their own inventory record', async () => {
  await assertSucceeds(studentB.firestore().collection('inventory').doc('invB1').get());
});

await it('denies another student from reading the inventory record', async () => {
  await assertFails(studentA.firestore().collection('inventory').doc('invB1').get());
});

await it('allows admin to mark an inventory record Returned', async () => {
  await assertSucceeds(admin.firestore().collection('inventory').doc('invB1').update({ status: 'Returned', returnedAt: new Date(), updatedAt: new Date() }));
});

await it('denies admin from flipping a Returned record back to In Inventory', async () => {
  await assertFails(admin.firestore().collection('inventory').doc('invB1').update({ status: 'In Inventory', updatedAt: new Date() }));
});

await it('denies a student from updating an inventory record', async () => {
  await assertFails(studentB.firestore().collection('inventory').doc('invB1').update({ title: 'Hijacked' }));
});

await it('denies deletion of an inventory record', async () => {
  await assertFails(admin.firestore().collection('inventory').doc('invB1').delete());
});

// ── matches ───────────────────────────────────────────────────────

await it('allows admin to create a Proposed match', async () => {
  await assertSucceeds(admin.firestore().collection('matches').doc('matchNew').set({ lostReportId: 'itemA1', inventoryItemId: 'invB1', lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', status: 'Proposed', notes: '', createdAt: new Date(), updatedAt: new Date() }));
});

await it('allows admin to create a match directly Approved', async () => {
  await assertSucceeds(admin.firestore().collection('matches').doc('matchAppr').set({ lostReportId: 'itemA1', inventoryItemId: 'invB1', lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', status: 'Approved', notes: '', createdAt: new Date(), updatedAt: new Date() }));
});

await it('denies a student from creating a match', async () => {
  await assertFails(studentA.firestore().collection('matches').doc('matchEvil').set({ lostReportId: 'itemA1', inventoryItemId: 'invB1', lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', status: 'Proposed' }));
});

await it('allows the lost owner to read their own match', async () => {
  await assertSucceeds(studentA.firestore().collection('matches').doc('match1').get());
});

await it('denies another student from reading the match', async () => {
  await assertFails(studentB.firestore().collection('matches').doc('match1').get());
});

await it('allows admin to approve a Proposed match', async () => {
  await assertSucceeds(admin.firestore().collection('matches').doc('match1').update({ status: 'Approved', updatedAt: new Date() }));
});

await it('allows admin to complete an Approved match', async () => {
  await assertSucceeds(admin.firestore().collection('matches').doc('match1').update({ status: 'Completed', updatedAt: new Date() }));
});

await it('denies a student from updating a match', async () => {
  await assertFails(studentA.firestore().collection('matches').doc('match1').update({ status: 'Completed' }));
});

await it('denies deletion of a match', async () => {
  await assertFails(admin.firestore().collection('matches').doc('match1').delete());
});

// ── lfNotifications ───────────────────────────────────────────────

await it('allows admin to create a notification', async () => {
  await assertSucceeds(admin.firestore().collection('lfNotifications').doc('notifNew').set({ studentId: 'S001', title: 'Match found', body: 'Visit the office', type: 'match', read: false, relatedReportId: 'itemA1', createdAt: new Date() }));
});

await it('denies a student from creating a notification', async () => {
  await assertFails(studentA.firestore().collection('lfNotifications').doc('notifEvil').set({ studentId: 'S001', title: 'x', body: 'y', type: 'match', read: false, createdAt: new Date() }));
});

await it('allows the recipient to read their own notification', async () => {
  await assertSucceeds(studentA.firestore().collection('lfNotifications').doc('notif1').get());
});

await it('denies another student from reading the notification', async () => {
  await assertFails(studentB.firestore().collection('lfNotifications').doc('notif1').get());
});

await it('allows the recipient to mark their notification read', async () => {
  await assertSucceeds(studentA.firestore().collection('lfNotifications').doc('notif1').update({ read: true }));
});

await it('denies the recipient from changing the notification title', async () => {
  await assertFails(studentA.firestore().collection('lfNotifications').doc('notif1').update({ title: 'Hijacked' }));
});

await it('denies deletion of a notification', async () => {
  await assertFails(admin.firestore().collection('lfNotifications').doc('notif1').delete());
});

await env.cleanup();
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
