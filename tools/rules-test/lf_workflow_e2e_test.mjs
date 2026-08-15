// End-to-end walk of the complete Lost & Found lifecycle through the
// Firestore rules (the enforcement layer of the client-only architecture).
//
// One chain, rules enabled, three workflows:
//   1. Student A reports a lost item (Active); Student B reports a found
//      item (born Awaiting Handover).
//   2. Admin issues a Handover QR → B scans → admin confirms the physical
//      handover → exactly one inventory record, report In Inventory.
//   3. Admin creates a manual match, approves it (notifying A), issues a
//      Return QR → A scans → admin confirms the return → every record lands
//      in its terminal state.
//
// The same writes the client transactions perform are replayed here one by
// one, so this test is the end-to-end proof that the rules accept the whole
// chain and reject the role boundaries around it.
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

const in10Min = () => Timestamp.fromMillis(Date.now() + 10 * 60 * 1000);
const issuedAt = () => Timestamp.fromMillis(Date.now() - 1000);

function itemDoc({ uid, studentId, type = 'lost', title = 'Test Item', status = 'Active' }) {
  return {
    type, title, category: 'Phone', description: 'desc', whereLost: 'Block A',
    whenLost: new Date(), reportedByUid: uid, reportedByStudentId: studentId,
    imageUrls: [], status, isDeleted: false,
  };
}

function qrDoc({ kind, token, intendedUid, intendedStudentId, foundReportId = '', lostReportId = '', inventoryItemId = '' }) {
  return {
    kind, token, intendedStudentUid: intendedUid, intendedStudentId,
    foundReportId, lostReportId, inventoryItemId,
    status: 'Issued', issuedAt: issuedAt(), expiresAt: in10Min(),
  };
}

env = await initializeTestEnvironment({ projectId: PROJECT_ID, firestore: { rules } });

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await db.collection('users').doc('uidAdmin').set({ uid: 'uidAdmin', studentId: 'ADMIN001', fullName: 'Administrator', authEmail: adminEmail, email: adminEmail, faculty: 'Staff', role: 'admin', status: 'Active', phone: '' });
  await db.collection('users').doc('uidA').set({ uid: 'uidA', studentId: 'S001', fullName: 'Student A', authEmail: studentAEmail, email: studentAEmail, faculty: 'Computing', role: 'student', status: 'Active', phone: '' });
  await db.collection('users').doc('uidB').set({ uid: 'uidB', studentId: 'S002', fullName: 'Student B', authEmail: studentBEmail, email: studentBEmail, faculty: 'Engineering', role: 'student', status: 'Active', phone: '' });
});

const studentA = env.authenticatedContext('uidA', { email: studentAEmail, email_verified: true });
const studentB = env.authenticatedContext('uidB', { email: studentBEmail, email_verified: true });
const admin = env.authenticatedContext('uidAdmin', { email: adminEmail, email_verified: true });

console.log('\nLost & Found end-to-end chain (rules enforced)');

// ── Workflow 1: reporting ─────────────────────────────────────────

await it('A submits a lost report (Active) and B submits a found report (Awaiting Handover)', async () => {
  await assertSucceeds(studentA.firestore().collection('items').doc('lostA1').set(itemDoc({ uid: 'uidA', studentId: 'S001' })));
  await assertSucceeds(studentB.firestore().collection('items').doc('foundB1').set(itemDoc({ uid: 'uidB', studentId: 'S002', type: 'found', title: 'Found Phone', status: 'Awaiting Handover' })));
});

await it('a found report cannot be created Active (forced Awaiting Handover)', async () => {
  await assertFails(studentB.firestore().collection('items').doc('foundBad').set(itemDoc({ uid: 'uidB', studentId: 'S002', type: 'found', status: 'Active' })));
});

// ── Workflow 2: inventory handover with QR ────────────────────────

await it('only an admin can issue the Handover QR', async () => {
  await assertFails(studentB.firestore().collection('qrTransactions').doc('handQr').set(qrDoc({ kind: 'handover', token: 'e2ehandover', intendedUid: 'uidB', intendedStudentId: 'S002', foundReportId: 'foundB1' })));
  await assertSucceeds(admin.firestore().collection('qrTransactions').doc('handQr').set(qrDoc({ kind: 'handover', token: 'e2ehandover', intendedUid: 'uidB', intendedStudentId: 'S002', foundReportId: 'foundB1' })));
});

await it('the intended finder scans the Handover QR (Issued -> Scanned)', async () => {
  await assertSucceeds(studentB.firestore().collection('qrTransactions').doc('handQr').update({ status: 'Scanned', scannedAt: new Date() }));
});

await it('admin confirms handover: report In Inventory, exactly one inventory record, QR Confirmed', async () => {
  await assertSucceeds(admin.firestore().collection('items').doc('foundB1').update({ status: 'In Inventory', updatedAt: new Date() }));
  await assertSucceeds(admin.firestore().collection('inventory').doc('invE2E').set({
    foundReportId: 'foundB1', finderUid: 'uidB', finderStudentId: 'S002',
    title: 'Found Phone', category: 'Phone', description: 'desc', imageUrls: [],
    status: 'In Inventory', handedOverAt: new Date(), createdAt: new Date(), updatedAt: new Date(),
  }));
  await assertSucceeds(admin.firestore().collection('qrTransactions').doc('handQr').update({ status: 'Confirmed', confirmedAt: new Date(), confirmedByUid: 'uidAdmin', updatedAt: new Date() }));
});

await it('a student can never create an inventory record', async () => {
  await assertFails(studentB.firestore().collection('inventory').doc('evilInv').set({
    foundReportId: 'foundB1', finderUid: 'uidB', finderStudentId: 'S002',
    title: 'X', category: 'X', description: 'X', imageUrls: [],
    status: 'In Inventory', createdAt: new Date(), updatedAt: new Date(),
  }));
});

await it('the same scanned QR cannot be confirmed twice (single-use)', async () => {
  await assertFails(admin.firestore().collection('qrTransactions').doc('handQr').update({ status: 'Confirmed', confirmedAt: new Date(), confirmedByUid: 'uidAdmin', updatedAt: new Date() }));
});

// ── Workflow 3: manual match + return collection ──────────────────

await it('only an admin can create a match (Proposed)', async () => {
  await assertFails(studentA.firestore().collection('matches').doc('matchE2E').set({ lostReportId: 'lostA1', inventoryItemId: 'invE2E', lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', status: 'Proposed', notes: 'Looks right', createdAt: new Date(), updatedAt: new Date() }));
  await assertSucceeds(admin.firestore().collection('matches').doc('matchE2E').set({ lostReportId: 'lostA1', inventoryItemId: 'invE2E', lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', status: 'Proposed', notes: 'Looks right', createdAt: new Date(), updatedAt: new Date() }));
});

await it('admin approves the match and delivers the owner notification', async () => {
  await assertSucceeds(admin.firestore().collection('matches').doc('matchE2E').update({ status: 'Approved', updatedAt: new Date() }));
  await assertSucceeds(admin.firestore().collection('lfNotifications').doc('notifA1').set({ studentId: 'S001', title: 'Possible match found', body: 'Visit the Inventory Office to verify ownership.', type: 'match', read: false, relatedReportId: 'lostA1', createdAt: new Date() }));
});

await it('only an admin can issue the Return QR; A is the only intended student', async () => {
  await assertFails(studentA.firestore().collection('qrTransactions').doc('retQr').set(qrDoc({ kind: 'return', token: 'e2ereturn', intendedUid: 'uidA', intendedStudentId: 'S001', lostReportId: 'lostA1', inventoryItemId: 'invE2E' })));
  await assertSucceeds(admin.firestore().collection('qrTransactions').doc('retQr').set(qrDoc({ kind: 'return', token: 'e2ereturn', intendedUid: 'uidA', intendedStudentId: 'S001', lostReportId: 'lostA1', inventoryItemId: 'invE2E' })));
});

await it('the wrong student cannot scan the Return QR', async () => {
  await assertFails(studentB.firestore().collection('qrTransactions').doc('retQr').update({ status: 'Scanned', scannedAt: new Date() }));
});

await it('the owner scans the Return QR (Issued -> Scanned)', async () => {
  await assertSucceeds(studentA.firestore().collection('qrTransactions').doc('retQr').update({ status: 'Scanned', scannedAt: new Date() }));
});

await it('admin confirms return: every record lands in its terminal state', async () => {
  await assertSucceeds(admin.firestore().collection('inventory').doc('invE2E').update({ status: 'Returned', matchedLostReportId: 'lostA1', returnedAt: new Date(), updatedAt: new Date() }));
  await assertSucceeds(admin.firestore().collection('items').doc('foundB1').update({ status: 'Returned', updatedAt: new Date() }));
  await assertSucceeds(admin.firestore().collection('items').doc('lostA1').update({ status: 'Resolved', updatedAt: new Date() }));
  await assertSucceeds(admin.firestore().collection('matches').doc('matchE2E').update({ status: 'Completed', updatedAt: new Date() }));
  await assertSucceeds(admin.firestore().collection('qrTransactions').doc('retQr').update({ status: 'Confirmed', confirmedAt: new Date(), confirmedByUid: 'uidAdmin', updatedAt: new Date() }));
});

await it('final states are visible to the right people', async () => {
  const inv = await admin.firestore().collection('inventory').doc('invE2E').get();
  if (inv.data().status !== 'Returned' || inv.data().matchedLostReportId !== 'lostA1') {
    throw new Error('inventory did not reach Returned with the matched lost report');
  }
  const lost = await studentA.firestore().collection('items').doc('lostA1').get();
  if (lost.data().status !== 'Resolved') throw new Error('lost report did not reach Resolved');
  const match = await studentA.firestore().collection('matches').doc('matchE2E').get();
  if (match.data().status !== 'Completed') throw new Error('match did not reach Completed');
  const notif = await studentA.firestore().collection('lfNotifications').doc('notifA1').get();
  if (notif.data().title !== 'Possible match found') throw new Error('owner notification missing');
  // The finder (B) must NOT be able to read A's match.
  await assertFails(studentB.firestore().collection('matches').doc('matchE2E').get());
});

await env.cleanup();
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
