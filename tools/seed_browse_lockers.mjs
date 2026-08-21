// Idempotent seeder for the 10 locker documents shown by the
// "Browse Available Lockers" screen.
//
// Seeds `lockers/{lockerId}` in the SAME Firebase project the Flutter app
// connects to (campus-connect-ce3e8, via tools/serviceAccount.json). It uses
// the Firestore Admin SDK so it bypasses security rules exactly like a Cloud
// Function; the client never creates lockers — inventory is seeded out-of-band.
//
// Matches the schema in lib/models/locker.dart (`Locker.toMap`):
//   location, status, studentId, startDate(Timestamp), endDate(Timestamp),
//   daysLeft, lockType, monthlyRent, deposit, depositRefunded.
// `digitalCode` is deliberately absent — the locker collection is readable by
// every signed-in user, so the unlock code must never live here.
//
// Locations use the exact strings the Browse screen filters on:
//   'Block A, Level 1', 'Block B, Level 2', 'Block C, Level 1'.
//
// Safety: an existing document is NEVER overwritten or deleted. For the 10
// required IDs, missing documents are created as 'Available'; ones that
// already exist are left untouched (they may be rented/active). Re-running is
// therefore a no-op on present docs and only creates the gaps.

import admin from 'firebase-admin';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// The 10 locker documents this browser must show (locations match browse logic).
const LOCKERS = [
  // Block A, Level 1
  { id: 'LK-A01', location: 'Block A, Level 1', status: 'Available', lockType: 'digital' },
  { id: 'LK-A02', location: 'Block A, Level 1', status: 'Available', lockType: 'key' },
  { id: 'LK-A03', location: 'Block A, Level 1', status: 'Available', lockType: 'digital' },
  { id: 'LK-A04', location: 'Block A, Level 1', status: 'Available', lockType: 'key' },
  // Block B, Level 2
  { id: 'LK-B01', location: 'Block B, Level 2', status: 'Available', lockType: 'digital' },
  { id: 'LK-B02', location: 'Block B, Level 2', status: 'Available', lockType: 'key' },
  { id: 'LK-B03', location: 'Block B, Level 2', status: 'Available', lockType: 'key' },
  // Block C, Level 1
  { id: 'LK-C01', location: 'Block C, Level 1', status: 'Available', lockType: 'digital' },
  { id: 'LK-C02', location: 'Block C, Level 1', status: 'Available', lockType: 'key' },
  { id: 'LK-C03', location: 'Block C, Level 1', status: 'Available', lockType: 'key' },
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
        '   Place the project service-account key there and re-run.\n',
    );
    throw e;
  }
}

function toFirestoreDoc(locker) {
  return {
    location: locker.location,
    status: locker.status,
    studentId: null,
    startDate: null,
    endDate: null,
    daysLeft: null,
    lockType: locker.lockType ?? 'key',
    monthlyRent: 10.0,
    deposit: 100.0,
    depositRefunded: false,
    // Deliberate absence of `digitalCode` (see header doc block).
  };
}

async function main() {
  const serviceAccount = loadKey();
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    // projectId is read from the service-account key = the app's project.
  });
  const db = admin.firestore();
  const col = db.collection('lockers');

  console.log(`Project: ${serviceAccount.project_id}`);
  console.log('Seeding 10 browse lockers (idempotent) ...\n');

  // ── Snapshot BEFORE (what currently exists) ────────────────────
  const before = await col.get();
  const existing = new Map(before.docs.map((d) => [d.id, true]));
  console.log('Existing locker docs right now:', before.size);
  console.log('  ids:', before.docs.map((d) => d.id).sort().join(', '));
  console.log('');

  // ── Seed the 10 (create missing, never overwrite present) ──────
  let created = 0;
  let skipped = 0;
  for (const locker of LOCKERS) {
    const ref = col.doc(locker.id);
    const snap = await ref.get();
    if (snap.exists) {
      skipped++;
      console.log(`  ${locker.id}  ·  exists — SKIPPED (left as-is)`);
    } else {
      await ref.set(toFirestoreDoc(locker));
      created++;
      console.log(`  ${locker.id}  ✓  created (${locker.status}, ${locker.location})`);
    }
  }
  console.log(`\nDone. ${created} created, ${skipped} already present (untouched).`);

  // ── Verify AFTER ───────────────────────────────────────────────
  const after = await col.get();
  console.log('\nTotal locker docs after seed:', after.size);
  const report = after.docs
    .map((d) => {
      const x = d.data();
      return `  ${d.id.padEnd(8)} ${String(x.status).padEnd(16)} ${x.location}`;
    })
    .sort();
  console.log(report.join('\n'));

  // ── Verify the 10 required specifically ────────────────────────
  const missing = LOCKERS.filter((l) => !existing.has(l.id));
  const requiredNow = await Promise.all(
    missing.map((l) => col.doc(l.id).get()),
  );
  const allPresent = requiredNow.every((s) => s.exists);
  console.log('');
  console.log(
    allPresent
      ? '✅ All 10 required locker documents exist in Firestore.'
      : '❌ Some required documents are missing!',
  );

  // ── Confirm they map to the Browse screen's filter locations ───
  const blockKeys = {
    'Block A, Level 1': 'LK-A',
    'Block B, Level 2': 'LK-B',
    'Block C, Level 1': 'LK-C',
  };
  const matches = LOCKERS.every((l) => {
    const prefix = blockKeys[l.location];
    return prefix != null && l.id.startsWith(prefix);
  });
  console.log(
    matches
      ? '✅ Locations match the Browse screen block filter.'
      : '⚠️  A locker location does not match a browse block.',
  );

  admin.app().delete();
}

main().catch((e) => {
  console.error('\n❌ Seeder failed:', e);
  process.exit(1);
});