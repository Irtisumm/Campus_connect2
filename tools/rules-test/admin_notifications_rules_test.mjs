// Firestore security-rule tests for the `adminNotifications` collection.
//
// Phase 5A (Lost & Found) introduces the first real admin work queue.
// The rules enforce:
//   - Students may only CREATE self-attributed notes with an allowlisted
//     type, pointing at an `items` document they own whose type matches
//     the notification type.
//   - Students may never READ or UPDATE any adminNotifications document.
//   - Admins may READ every document and may UPDATE only the `readBy`
//     field (array-union to mark it seen for themselves).
//   - No one may DELETE any document.
//
// Run:  (cd tools/rules-test && npm install && npm test)

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

function itemDoc({ uid, studentId, type = 'lost', status = 'Active' }) {
  return {
    type, title: 'Test Item', category: 'Phone', description: 'desc',
    whereLost: 'Block A', whenLost: new Date(),
    reportedByUid: uid, reportedByStudentId: studentId,
    imageUrls: [], status, isDeleted: false,
  };
}

const env = await initializeTestEnvironment({ projectId: PROJECT_ID, firestore: { rules } });

// Seed users and items with rules disabled so the test itself only
// exercises the adminNotifications rules.
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await db.collection('users').doc('uidAdmin').set({
    uid: 'uidAdmin', studentId: 'ADMIN001', fullName: 'Administrator',
    authEmail: adminEmail, email: adminEmail, faculty: 'Staff', role: 'admin',
    status: 'Active', phone: '',
  });
  await db.collection('users').doc('uidA').set({
    uid: 'uidA', studentId: 'S001', fullName: 'Student A',
    authEmail: studentAEmail, email: studentAEmail, faculty: 'Computing',
    role: 'student', status: 'Active', phone: '',
  });
  await db.collection('users').doc('uidB').set({
    uid: 'uidB', studentId: 'S002', fullName: 'Student B',
    authEmail: studentBEmail, email: studentBEmail, faculty: 'Engineering',
    role: 'student', status: 'Active', phone: '',
  });
  // items: A owns a lost report, B owns a found report.
  await db.collection('items').doc('itemA1').set(itemDoc({ uid: 'uidA', studentId: 'S001' }));
  await db.collection('items').doc('itemB1').set(itemDoc({ uid: 'uidB', studentId: 'S002', type: 'found', status: 'Awaiting Handover' }));
});

const admin = env.authenticatedContext('uidAdmin', { email: adminEmail });
const studentA = env.authenticatedContext('uidA', { email: studentAEmail });
const studentB = env.authenticatedContext('uidB', { email: studentBEmail });

// ── Tests ────────────────────────────────────────────────────────────

console.log('\nadminNotifications rules');

// --- Student creates valid self-attributed notes ----------------------
await it('student A creates lost_report_submitted for own lost item', async () => {
  await assertSucceeds(studentA.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'lost_report_submitted',
    studentId: 'S001',
    title: 'New Lost Report',
    body: 'Student S001 reported a lost item.',
    relatedEntityId: 'itemA1',
    relatedScreen: '/lost-found/lost/itemA1',
    readBy: [],
  }));
});

await it('student B creates found_report_submitted for own found item', async () => {
  await assertSucceeds(studentB.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'found_report_submitted',
    studentId: 'S002',
    title: 'New Found Report',
    body: 'Student S002 reported a found item.',
    relatedEntityId: 'itemB1',
    relatedScreen: '/lost-found/found/itemB1',
    readBy: [],
  }));
});

await it('student A creates close_request_submitted for own lost item', async () => {
  await assertSucceeds(studentA.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'close_request_submitted',
    studentId: 'S001',
    title: 'Close Request',
    body: 'Student S001 requests to close the report.',
    relatedEntityId: 'itemA1',
    relatedScreen: '/lost-found/lost/itemA1',
    readBy: [],
  }));
});

// --- Student denied: mismatched studentId -----------------------------
await it('student A denied when studentId does not match profile', async () => {
  await assertFails(studentA.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'lost_report_submitted',
    studentId: 'S002',
    title: 'New Lost Report',
    body: 'body',
    relatedEntityId: 'itemA1',
    relatedScreen: '/lost-found/lost/itemA1',
    readBy: [],
  }));
});

// --- Student denied: unknown type -------------------------------------
await it('student A denied for unrecognised type', async () => {
  await assertFails(studentA.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'match_approved',
    studentId: 'S001',
    title: 'Match',
    body: 'body',
    relatedEntityId: 'itemA1',
    relatedScreen: '/lost-found/lost/itemA1',
    readBy: [],
  }));
});

// --- Student denied: non-owned entity ---------------------------------
await it('student A denied when relatedEntityId belongs to B', async () => {
  await assertFails(studentA.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'lost_report_submitted',
    studentId: 'S001',
    title: 'body',
    body: 'body',
    relatedEntityId: 'itemB1',
    relatedScreen: '/lost-found/found/itemB1',
    readBy: [],
  }));
});

// --- Student denied: type does not match item type --------------------
await it('student B denied — found_report_submitted on a lost item', async () => {
  // B tries to create found_report_submitted pointing at A's lost item.
  await assertFails(studentB.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'found_report_submitted',
    studentId: 'S002',
    title: 'Found',
    body: 'body',
    relatedEntityId: 'itemA1',
    relatedScreen: '/lost-found/lost/itemA1',
    readBy: [],
  }));
});

// --- Student denied: read and update ----------------------------------
await it('student A cannot read any adminNotification', async () => {
  // Seed one via admin first.
  await admin.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'lost_report_submitted',
    studentId: 'S001',
    title: 'New Lost Report',
    body: 'body',
    relatedEntityId: 'itemA1',
    relatedScreen: '/lost-found/lost/itemA1',
    readBy: [],
  });
  await assertFails(studentA.firestore().collection('adminNotifications').get());
});

	await it('student A cannot update readBy', async () => {
	  const ref = await admin.firestore().collection('adminNotifications').add({
	    source: 'lostFound',
	    type: 'lost_report_submitted',
	    studentId: 'S001',
	    title: 'New Lost Report',
	    body: 'body',
	    relatedEntityId: 'itemA1',
	    relatedScreen: '/lost-found/lost/itemA1',
	    readBy: [],
	  });
	  // Must use studentA's Firestore context — ref carries the admin auth.
	  await assertFails(studentA.firestore().collection('adminNotifications').doc(ref.id).update({ readBy: ['uidA'] }));
	});

// --- Admin read and update -------------------------------------------
await it('admin can list all adminNotifications', async () => {
  await admin.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'lost_report_submitted',
    studentId: 'S001',
    title: 'New Lost Report',
    body: 'body',
    relatedEntityId: 'itemA1',
    relatedScreen: '/lost-found/lost/itemA1',
    readBy: [],
  });
  await assertSucceeds(admin.firestore().collection('adminNotifications').get());
});

await it('admin can mark read by updating readBy', async () => {
  const ref = await admin.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'lost_report_submitted',
    studentId: 'S001',
    title: 'New Lost Report',
    body: 'body',
    relatedEntityId: 'itemA1',
    relatedScreen: '/lost-found/lost/itemA1',
    readBy: [],
  });
  // Write a plain array — the real code uses arrayUnion in the app layer
  // but the *rule* only cares that the value is a list on write.
  await assertSucceeds(ref.update({ readBy: ['uidAdmin'] }));
});

await it('admin cannot modify fields other than readBy', async () => {
  const ref = await admin.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'lost_report_submitted',
    studentId: 'S001',
    title: 'New Lost Report',
    body: 'body',
    relatedEntityId: 'itemA1',
    relatedScreen: '/lost-found/lost/itemA1',
    readBy: [],
  });
  await assertFails(ref.update({ title: 'tampered' }));
});

// --- No deletes -------------------------------------------------------
await it('admin cannot delete an adminNotification', async () => {
  const ref = await admin.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'lost_report_submitted',
    studentId: 'S001',
    title: 'New Lost Report',
    body: 'body',
    relatedEntityId: 'itemA1',
    relatedScreen: '/lost-found/lost/itemA1',
    readBy: [],
  });
  await assertFails(ref.delete());
});

// --- Admin can create any adminNotification ---------------------------
await it('admin can directly create an adminNotification', async () => {
  await assertSucceeds(admin.firestore().collection('adminNotifications').add({
    source: 'lostFound',
    type: 'lost_report_submitted',
    studentId: 'S001',
    title: 'Manual',
    body: 'body',
    relatedEntityId: 'itemA1',
    relatedScreen: '/lost-found/lost/itemA1',
    readBy: [],
  }));
});

await env.cleanup();
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);