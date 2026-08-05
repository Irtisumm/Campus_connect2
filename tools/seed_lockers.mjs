// One-time locker seeder for Campus Connect.
//
// Seeds the `lockers/{lockerId}` Firestore collection with the 12 lockers
// previously hard-coded in `lib/data/mock_data.dart` (MockData.lockers).
// After this runs, the LockerService streams have data to read and the
// Phase 3c screen migration can go live against Firestore.
//
// This uses the Firebase Admin SDK, which bypasses Firestore security rules
// the way a Cloud Function would. That is intentional and required: the
// `lockers` rules in firestore.rules allow client reads for any signed-in
// user but restrict writes to admins, and even admins are expected to manage
// lockers through the app — the initial inventory must be created out-of-band,
// and this script is that out-of-band path.
//
// It mirrors seed_admin.mjs: same service-account key, same idempotency
// guarantees, same console output style. It never edits documents by hand in
// the console; it writes them through the Admin SDK, the same path a server
// would.
//
// ── How to run ─────────────────────────────────────────────────────────────
//   cd tools
//   npm install
//   # put your Firebase service-account key at tools/serviceAccount.json
//   node seed_lockers.mjs
//
// The script is idempotent: re-running it rewrites each locker document with
// the seeded values (merge), so drift is repaired rather than duplicated.

import admin from 'firebase-admin';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// ── The 12 lockers from MockData.lockers ───────────────────────────────────
// Copied verbatim from lib/data/mock_data.dart. `studentId` values are the
// campus IDs used by the mock rows (e.g. S220334); they are preserved so the
// seeded Firestore documents match the mock data the screens were built
// against. `daysLeft` is preserved as stored in the mock (client-computed).
const LOCKERS = [
  { id: 'LK-A01', location: 'Block A, Level 1', status: 'Available', lockType: 'digital' },
  { id: 'LK-A02', location: 'Block A, Level 1', status: 'Active', studentId: 'S220334', startDate: '2026-01-04', endDate: '2026-06-30', daysLeft: 98, lockType: 'key', monthlyRent: 10.0, deposit: 100.0 },
  { id: 'LK-A03', location: 'Block A, Level 1', status: 'Available', lockType: 'key' },
  { id: 'LK-A04', location: 'Block A, Level 1', status: 'Pending Pickup', studentId: 'S220045', lockType: 'key' },
  { id: 'LK-A05', location: 'Block A, Level 1', status: 'Available', lockType: 'digital' },
  { id: 'LK-A06', location: 'Block A, Level 1', status: 'Overdue', studentId: 'S219001', startDate: '2025-12-01', endDate: '2026-03-01', daysLeft: -23, lockType: 'key', monthlyRent: 10.0, deposit: 100.0 },
  { id: 'LK-B01', location: 'Block B, Level 2', status: 'Available', lockType: 'digital' },
  { id: 'LK-B02', location: 'Block B, Level 2', status: 'Active', studentId: 'S221010', startDate: '2026-01-04', endDate: '2026-06-30', daysLeft: 98, lockType: 'digital' },
  { id: 'LK-B03', location: 'Block B, Level 2', status: 'Available', lockType: 'key' },
  { id: 'LK-B04', location: 'Block B, Level 2', status: 'Blocked', lockType: 'key' },
  { id: 'LK-C01', location: 'Block C, Level 1', status: 'Available', lockType: 'digital' },
  { id: 'LK-C02', location: 'Block C, Level 1', status: 'Available', lockType: 'key' },
];
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

/**
 * Converts a locker seed entry to the Firestore document shape.
 *
 * Matches `Locker.toMap()` in lib/models/locker.dart exactly: dates stored as
 * Timestamps, numbers as numbers, missing optional fields stored as null so
 * the Dart `fromMap` reads a stable schema on every document.
 */
function toFirestoreDoc(locker) {
  const ts = (iso) =>
    iso ? admin.firestore.Timestamp.fromDate(new Date(iso)) : null;

  return {
    location: locker.location,
    status: locker.status,
    studentId: locker.studentId ?? null,
    startDate: ts(locker.startDate),
    endDate: ts(locker.endDate),
    daysLeft: locker.daysLeft ?? null,
    lockType: locker.lockType ?? 'key',
    // SECURITY: `digitalCode` is deliberately absent. The locker collection is
    // readable by every signed-in user, so the unlock code must never live
    // here — it belongs only to the owner-scoped lockerBookings document.
    // Legacy documents that still carry the field get it stripped below.
    digitalCode: admin.firestore.FieldValue.delete(),
    monthlyRent: locker.monthlyRent ?? 10.0,
    deposit: locker.deposit ?? 100.0,
    depositRefunded: false,
  };
}

async function main() {
  const serviceAccount = loadKey();

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    // projectId is read from the service-account key, so no hard-coded id.
  });

  const db = admin.firestore();
  const lockersCol = db.collection('lockers');

  console.log(`Seeding ${LOCKERS.length} lockers into lockers/{lockerId} ...\n`);

  let created = 0;
  let repaired = 0;

  for (const locker of LOCKERS) {
    const ref = lockersCol.doc(locker.id);
    const snap = await ref.get();
    const data = toFirestoreDoc(locker);

    if (snap.exists) {
      // merge:true rewrites the seeded fields over the top while preserving
      // any keys a live system may have added (e.g. future fields). Re-running
      // the seeder therefore repairs drift rather than failing.
      await ref.set(data, { merge: true });
      repaired++;
      console.log(`  ${locker.id}  ·  exists — repaired (${locker.status})`);
    } else {
      // FieldValue.delete() is only legal on a merge write, so a fresh doc
      // simply omits the legacy key instead.
      const { digitalCode: _drop, ...fresh } = data;
      await ref.set(fresh);
      created++;
      console.log(`  ${locker.id}  ✓  created (${locker.status})`);
    }
  }

  console.log(`\n✅ Done. ${created} created, ${repaired} repaired.`);
  console.log('   Collection: lockers/{lockerId}  ·  12 documents');
}

main().catch((e) => {
  console.error('\n❌ Seeder failed:', e);
  process.exit(1);
});
