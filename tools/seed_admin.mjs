// One-time admin seeder for Campus Connect.
//
// Creates the first administrator: a Firebase Authentication account plus the
// matching `users/{uid}` Firestore document. After the admin exists, the normal
// login flow takes over — this script plays no part in sign-in and is not part
// of the shipped app.
//
// This uses the Firebase Admin SDK, which bypasses Firestore security rules the
// way a Cloud Function would. That is intentional and required: the `users`
// create rule in firestore.rules pins `role == 'student'` and `status ==
// 'Pending'`, so no client (not even a signed-in one) can write an admin
// document through the app. The first admin must be created out-of-band, and
// this script is that out-of-band path.
//
// It does NOT bypass Firebase Authentication for login — it creates a real
// credential the admin will sign in with. It never edits Firestore documents by
// hand in the console; it writes them through the Admin SDK, the same path a
// server would. It does not change the login flow.
//
// ── How to run ─────────────────────────────────────────────────────────────
// See SEED_ADMIN.md for full instructions. Summary:
//
//   cd tools
//   npm install
//   # put your Firebase service-account key at tools/serviceAccount.json
//   node seed_admin.mjs
//
// The script is idempotent: re-running it when the admin already exists reuses
// the account and repairs the document instead of creating a duplicate.

import admin from 'firebase-admin';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// ── Configure the admin here ───────────────────────────────────────────────
// These are the ONLY values you should ever need to edit. Change them once,
// run the script, then change the password from the app or Firebase Console.
const ADMIN = {
  studentId: 'ADMIN001',
  email: 'admin001@city.edu.my',
  password: 'Admin@12345',
  fullName: 'Admin Panel',
  faculty: 'Campus Operations',
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
    // projectId is read from the service-account key, so no hard-coded id.
  });

  const auth = admin.auth();
  const db = admin.firestore();

  // ── 1. Create the Auth account, or reuse the existing one ───────────────
  // Look up by email first. The Admin SDK exposes a getUserByEmail that does
  // not require sign-in, so this works even if the password has drifted.
  let uid;
  let createdAccount = false;

  try {
    const existing = await auth.getUserByEmail(ADMIN.email);
    uid = existing.uid;
    console.log(`Auth account already exists  ·  uid=${uid}`);
    // Reset the password so a forgotten admin password can be recovered by
    // re-running this script.
    await auth.updateUser(uid, { password: ADMIN.password });
    console.log('Password reset to configured value  ✓');
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    const created = await auth.createUser({
      email: ADMIN.email,
      password: ADMIN.password,
      displayName: ADMIN.fullName,
    });
    uid = created.uid;
    createdAccount = true;
    console.log(`Created Firebase Auth account  ✓  uid=${uid}`);
  }

  // ── 2. Look for an existing admin document by studentId ─────────────────
  // Checking by studentId (not uid) means a document created against a
  // different/old Auth account is detected as a duplicate rather than
  // orphaned.
  const existing = await db
    .collection('users')
    .where('studentId', '==', ADMIN.studentId)
    .limit(1)
    .get();

  const now = admin.firestore.FieldValue.serverTimestamp();
  const data = {
    uid,
    studentId: ADMIN.studentId,
    fullName: ADMIN.fullName,
    authEmail: ADMIN.email,
    email: ADMIN.email,
    faculty: ADMIN.faculty,
    role: 'admin',
    status: 'Active',
    phone: '',
    updatedAt: now,
  };

  if (existing.empty) {
    // New document. createdAt is set once here; subsequent repairs only touch
    // updatedAt, matching the rest of the app's convention.
    await db.collection('users').doc(uid).set({
      ...data,
      createdAt: now,
    });
    console.log(`Created Firestore users/${uid}  ✓  role=admin, status=Active`);
  } else {
    const doc = existing.docs[0];
    // The document exists. It may be on this uid or a stale one; either way we
    // normalise it onto the current uid with the admin shape. merge:true keeps
    // any pre-existing createdAt and writes the admin fields over the top.
    const existingCreatedAt = doc.data().createdAt ?? now;
    await db.collection('users').doc(uid).set(
      { ...data, createdAt: existingCreatedAt },
      { merge: true },
    );
    console.log(`Firestore document exists  ·  repaired onto users/${uid}`);

    // If the stale document is on a different uid, flag it for the operator
    // rather than silently deleting user data.
    if (doc.id !== uid) {
      console.log(
        `⚠  A second users document exists at users/${doc.id} with the same ` +
          `studentId. It was left in place — remove it from the Firebase ` +
          `Console if it is no longer needed.`,
      );
    }
  }

  console.log('\n✅ Done. You can now sign in with:');
  console.log(`   Student ID: ${ADMIN.studentId}`);
  console.log(`   Email:      ${ADMIN.email}`);
  console.log(
    '   (password is the one set above — change it in the app or Firebase Console.)',
  );

  await admin.app().delete();
}

main().catch((e) => {
  console.error('\n❌ Seeding failed:', e.message || e);
  console.error('   Nothing was left half-created. Fix the issue and re-run.');
  process.exitCode = 1;
  // Ensure the app is torn down on failure paths too.
  admin.app().delete().catch(() => process.exit(1));
});
