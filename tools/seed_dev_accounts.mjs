// Dev account seeder for Campus Connect.
//
// Creates 5 student and 2 admin Firebase Auth accounts plus their matching
// `users/{uid}` Firestore documents. Uses the Admin SDK to bypass Firestore
// security rules (same pattern as seed_admin.mjs).
//
//   cd tools
//   node seed_dev_accounts.mjs
//
// Idempotent — re-running repairs existing accounts rather than duplicating.

import admin from 'firebase-admin';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ACCOUNTS = [
  // ── Admins ──────────────────────────────────────────────────────────
  { studentId: 'ADMIN001', email: 'admin1@city.edu.my',  password: 'Admin@12345',  fullName: 'Admin One',   faculty: 'Campus Operations', role: 'admin',   status: 'Active' },
  { studentId: 'ADMIN002', email: 'admin2@city.edu.my',  password: 'Admin@12345',  fullName: 'Admin Two',   faculty: 'Campus Operations', role: 'admin',   status: 'Active' },
  // ── Students ────────────────────────────────────────────────────────
  { studentId: 'S001',     email: 'student1@city.edu.my', password: 'Student@123', fullName: 'Student One',   faculty: 'Engineering', role: 'student', status: 'Active' },
  { studentId: 'S002',     email: 'student2@city.edu.my', password: 'Student@123', fullName: 'Student Two',   faculty: 'Business',    role: 'student', status: 'Active' },
  { studentId: 'S003',     email: 'student3@city.edu.my', password: 'Student@123', fullName: 'Student Three', faculty: 'Computing',   role: 'student', status: 'Active' },
  { studentId: 'S004',     email: 'student4@city.edu.my', password: 'Student@123', fullName: 'Student Four',  faculty: 'Design',      role: 'student', status: 'Active' },
  { studentId: 'S005',     email: 'student5@city.edu.my', password: 'Student@123', fullName: 'Student Five',  faculty: 'Science',     role: 'student', status: 'Active' },
];

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

async function seedOne(auth, db, cfg) {
  let uid;
  let createdAccount = false;

  // ── 1. Auth account ───────────────────────────────────────────────
  try {
    const existing = await auth.getUserByEmail(cfg.email);
    uid = existing.uid;
    console.log(`  Auth exists  ·  uid=${uid}`);
    await auth.updateUser(uid, { password: cfg.password });
    console.log('  Password reset  ✓');
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    const created = await auth.createUser({
      email: cfg.email,
      password: cfg.password,
      displayName: cfg.fullName,
    });
    uid = created.uid;
    createdAccount = true;
    console.log(`  Auth created  ✓  uid=${uid}`);
  }

  // ── 2. Firestore document ─────────────────────────────────────────
  const existing = await db
    .collection('users')
    .where('studentId', '==', cfg.studentId)
    .limit(1)
    .get();

  const now = admin.firestore.FieldValue.serverTimestamp();
  const data = {
    uid,
    studentId: cfg.studentId,
    fullName: cfg.fullName,
    authEmail: cfg.email,
    email: cfg.email,
    faculty: cfg.faculty,
    role: cfg.role,
    status: cfg.status,
    phone: '',
    updatedAt: now,
  };

  if (existing.empty) {
    await db.collection('users').doc(uid).set({
      ...data,
      createdAt: now,
    });
    console.log(`  Firestore created  ✓  role=${cfg.role}, status=${cfg.status}`);
  } else {
    const doc = existing.docs[0];
    const existingCreatedAt = doc.data().createdAt ?? now;
    await db.collection('users').doc(uid).set(
      { ...data, createdAt: existingCreatedAt },
      { merge: true },
    );
    console.log(`  Firestore repaired onto users/${uid}  ✓`);
    if (doc.id !== uid) {
      console.log(`  ⚠  Stale doc at users/${doc.id} — left in place.`);
    }
  }

  return { uid, ...cfg };
}

async function main() {
  const serviceAccount = loadKey();

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  const auth = admin.auth();
  const db = admin.firestore();

  console.log(`Seeding ${ACCOUNTS.length} dev accounts…\n`);

  const results = [];
  for (const cfg of ACCOUNTS) {
    console.log(`── ${cfg.studentId} (${cfg.role}) ──`);
    try {
      const r = await seedOne(auth, db, cfg);
      results.push(r);
      console.log('');
    } catch (e) {
      console.error(`  ❌ FAILED: ${e.message || e}`);
      console.log('');
    }
  }

  console.log('══════════════════════════════════════');
  console.log('✅ Done. Quick-reference:');
  console.log('');
  console.log('Admins:');
  for (const r of results.filter(x => x.role === 'admin')) {
    console.log(`  ${r.studentId}  |  ${r.email}  |  ${r.password}`);
  }
  console.log('');
  console.log('Students:');
  for (const r of results.filter(x => x.role === 'student')) {
    console.log(`  ${r.studentId}  |  ${r.email}  |  ${r.password}`);
  }

  await admin.app().delete();
}

main().catch((e) => {
  console.error('\n❌ Seeding failed:', e.message || e);
  process.exitCode = 1;
  admin.app().delete().catch(() => process.exit(1));
});
