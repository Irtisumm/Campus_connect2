// Firestore security-rule tests for the `users/{uid}` profile collection.
//
// Covers the allowed/denied matrix required by the Profile-Firebase brief:
//   - unauthenticated read is denied
//   - student A reads their own profile (allowed)
//   - student A updates their own editable fields incl. notification/language (allowed)
//   - student A reading student B is denied
//   - student A writing student B is denied
//   - student A cannot self-assign an admin role
//   - student A cannot change protected identity (studentId) or write a password
//   - registration create enforces role='student', status='Pending', authEmail==token
//   - registration create denies self-promotion to admin
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
const regEmail = 'reg.student@city.edu.my';
const promoEmail = 'promo.student@city.edu.my';
const approveEmail = 'approve.student@city.edu.my';
const mismatchEmail = 'mismatch.student@city.edu.my';

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

function userDoc({ uid, studentId, fullName, authEmail, faculty = 'Faculty of Computing', role = 'student', status = 'Active' }) {
  return { uid, studentId, fullName, authEmail, email: authEmail, faculty, role, status, phone: '' };
}

env = await initializeTestEnvironment({ projectId: PROJECT_ID, firestore: { rules } });

// Seed with rules disabled (replaces the old adminContext) so isAdmin() resolves.
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await db.collection('users').doc('uidAdmin').set(userDoc({ uid: 'uidAdmin', studentId: 'ADMIN001', fullName: 'Administrator', authEmail: adminEmail, role: 'admin', status: 'Active' }));
  await db.collection('users').doc('uidA').set(userDoc({ uid: 'uidA', studentId: 'S001', fullName: 'Student A', authEmail: studentAEmail }));
  await db.collection('users').doc('uidB').set(userDoc({ uid: 'uidB', studentId: 'S002', fullName: 'Student B', authEmail: studentBEmail }));
});

const unauth = env.unauthenticatedContext();
const studentA = env.authenticatedContext('uidA', { email: studentAEmail, email_verified: true });
const studentB = env.authenticatedContext('uidB', { email: studentBEmail, email_verified: true });
// Separate identities for create tests — each doc path must match the auth uid.
const studentReg = env.authenticatedContext('uidReg', { email: regEmail, email_verified: true });
const studentPromo = env.authenticatedContext('uidPromo', { email: promoEmail, email_verified: true });
const studentApprove = env.authenticatedContext('uidApprove', { email: approveEmail, email_verified: true });
const studentMismatch = env.authenticatedContext('uidMismatch', { email: mismatchEmail, email_verified: true });

console.log('\nusers/{uid} profile rules');

await it('denies an unauthenticated read of any profile', async () => {
  await assertFails(unauth.firestore().collection('users').doc('uidA').get());
});

await it('allows student A to read their own profile', async () => {
  await assertSucceeds(studentA.firestore().collection('users').doc('uidA').get());
});

await it('allows student A to update editable fields (name/email/faculty/phone/notifications/language)', async () => {
  await assertSucceeds(studentA.firestore().collection('users').doc('uidA').update({
    fullName: 'Student A2',
    email: 'a2@city.edu.my',
    faculty: 'Faculty of Engineering',
    phone: '0123456789',
    notificationPrefs: { lostFoundMatches: false, eventUpdates: true, issueStatus: true, lockerReminders: true },
    preferredLanguage: 'English',
    updatedAt: new Date(),
  }));
});

await it('denies student A from reading student B', async () => {
  await assertFails(studentA.firestore().collection('users').doc('uidB').get());
});

await it('denies student A from writing student B', async () => {
  await assertFails(studentA.firestore().collection('users').doc('uidB').update({ fullName: 'Hijacked' }));
});

await it('denies student A from self-assigning an admin role', async () => {
  await assertFails(studentA.firestore().collection('users').doc('uidA').update({ role: 'admin' }));
});

await it('denies student A from changing their protected studentId', async () => {
  await assertFails(studentA.firestore().collection('users').doc('uidA').update({ studentId: 'S999' }));
});

await it('denies student A from changing their protected authEmail', async () => {
  await assertFails(studentA.firestore().collection('users').doc('uidA').update({ authEmail: 'attacker@city.edu.my' }));
});

await it('denies student A from writing a password field', async () => {
  await assertFails(studentA.firestore().collection('users').doc('uidA').update({ password: 'secret' }));
});

await it('denies student A from changing their own status (Active -> Pending)', async () => {
  await assertFails(studentA.firestore().collection('users').doc('uidA').update({ status: 'Pending' }));
});

await it('allows a valid registration create (student/Pending/authEmail==token)', async () => {
  await assertSucceeds(studentReg.firestore().collection('users').doc('uidReg').set(userDoc({ uid: 'uidReg', studentId: 'S003', fullName: 'New Student', authEmail: regEmail, status: 'Pending' })));
});

await it('denies a registration create that self-promotes to admin', async () => {
  await assertFails(studentPromo.firestore().collection('users').doc('uidPromo').set(userDoc({ uid: 'uidPromo', studentId: 'S004', fullName: 'Evil', authEmail: promoEmail, role: 'admin', status: 'Pending' })));
});

await it('denies a registration create that self-approves (status=Active)', async () => {
  await assertFails(studentApprove.firestore().collection('users').doc('uidApprove').set(userDoc({ uid: 'uidApprove', studentId: 'S005', fullName: 'Self', authEmail: approveEmail, status: 'Active' })));
});

await it('denies a registration create whose authEmail != token email', async () => {
  await assertFails(studentMismatch.firestore().collection('users').doc('uidMismatch').set(userDoc({ uid: 'uidMismatch', studentId: 'S006', fullName: 'Mismatch', authEmail: 'someone-else@city.edu.my', status: 'Pending' })));
});

await env.cleanup();
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
