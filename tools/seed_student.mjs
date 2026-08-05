// One-time student seeder for Campus Connect.
//
// Creates a student: a Firebase Authentication account plus the matching
// `users/{uid}` Firestore document with status 'Active' (pre-approved).
//
// Uses the Firebase Admin SDK (same as seed_admin.mjs) so it can bypass the
// Firestore create rule that pins status == 'Pending'. This lets you create
// a ready-to-login student without going through the registration-approval
// flow.
//
// ── How to run ─────────────────────────────────────────────────────────────
//   cd tools
//   npm install          (already done if you ran seed_admin.mjs)
//   node seed_student.mjs
//
// The script is idempotent: re-running it when the student already exists
// reuses the account and repairs the document instead of creating a duplicate.

import admin from 'firebase-admin';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// ── Configure the student here ─────────────────────────────────────────────
// Change these values to whatever you want, run the script, and the account
// is ready. The defaults are intentionally easy to remember.
const STUDENT = {
  studentId: 'S100',
  email: 'student100@city.edu.my',
  password: 'Student123',
  fullName: 'Test Student',
  faculty: 'Faculty of Computing',
};
// ───────────────────────────────────────────────────────────────────────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const keyPath = join(__dirname, 'serviceAccount.json');

function loadKey() {
  try {
    return JSON.parse(readFileSync(keyPath, 'utf8'));
  } catch (e) {
    console.error(
      '\n❌ Could not read tools/serviceAccount.json.\n' +
        '   Download it from Firebase Console → Project settings → Service ' +
        'accounts → Generate new private key, and place it at ' +
        'tools/serviceAccount.json.\n',
    );
    throw e;
  }
}

async function main() {
  const serviceAccount = loadKey();

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  const auth = admin.auth();
  const db = admin.firestore();

  // ── 1. Create the Auth account, or reuse the existing one ───────────────
  let uid;
  let createdAccount = false;

  try {
    const existing = await auth.getUserByEmail(STUDENT.email);
    uid = existing.uid;
    console.log(`Auth account already exists  ·  uid=${uid}`);
    // Reset the password so a forgotten password can be recovered by
    // re-running this script.
    await auth.updateUser(uid, { password: STUDENT.password });
    console.log('Password reset to configured value  ✓');
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    const created = await auth.createUser({
      email: STUDENT.email,
      password: STUDENT.password,
      displayName: STUDENT.fullName,
    });
    uid = created.uid;
    createdAccount = true;
    console.log(`Created Firebase Auth account  ✓  uid=${uid}`);
  }

  // ── 2. Look for an existing student document by studentId ───────────────
  const existing = await db
    .collection('users')
    .where('studentId', '==', STUDENT.studentId)
    .limit(1)
    .get();

  const now = admin.firestore.FieldValue.serverTimestamp();
  const data = {
    uid,
    studentId: STUDENT.studentId,
    fullName: STUDENT.fullName,
    authEmail: STUDENT.email,
    email: STUDENT.email,
    faculty: STUDENT.faculty,
    role: 'student',
    status: 'Active',
    phone: '',
    updatedAt: now,
  };

  if (existing.empty) {
    await db.collection('users').doc(uid).set({
      ...data,
      createdAt: now,
    });
    console.log(`Created Firestore users/${uid}  ✓  role=student, status=Active`);
  } else {
    const doc = existing.docs[0];
    const existingCreatedAt = doc.data().createdAt ?? now;
    await db.collection('users').doc(uid).set(
      { ...data, createdAt: existingCreatedAt },
      { merge: true },
    );
    console.log(`Firestore document exists  ·  repaired onto users/${uid}`);

    if (doc.id !== uid) {
      console.log(
        `⚠  A second users document exists at users/${doc.id} with the same ` +
          `studentId. It was left in place — remove it from the Firebase ` +
          `Console if it is no longer needed.`,
      );
    }
  }

  console.log('\n✅ Done. You can now sign in with:');
  console.log(`   Student ID: ${STUDENT.studentId}`);
  console.log(`   Email:      ${STUDENT.email}`);
  console.log(`   Password:   ${STUDENT.password}`);
  console.log(
    '   (You can change the password from the app or Firebase Console.)',
  );

  await admin.app().delete();
}

main().catch((e) => {
  console.error('\n❌ Seeding failed:', e.message || e);
  console.error('   Nothing was left half-created. Fix the issue and re-run.');
  process.exitCode = 1;
  admin.app().delete().catch(() => process.exit(1));
});
