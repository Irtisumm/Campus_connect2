// One-time Lost & Found data reset for Campus Connect.
//
// Deletes EVERY document in the five Lost & Found collections so the admin and
// student screens all read zero, ready for a fresh start:
//
//   items          — lost + found reports
//   inventory      — inventory-office records
//   matches        — lost↔inventory match records
//   qrTransactions — handover/return QR codes
//   lfNotifications— match notifications
//
// It does NOT touch `users` (auth accounts stay intact) or any other module
// (events, lockers, issues, elections). It uses the Firebase Admin SDK, which
// bypasses Firestore security rules the way a Cloud Function would.
//
// ── How to run ─────────────────────────────────────────────────────────────
//   cd tools
//   npm install          # only if node_modules is missing
//   node clear_lost_found.mjs
//
// The script is idempotent: re-running it when the collections are already
// empty is a no-op.

import admin from 'firebase-admin';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const keyPath = join(__dirname, 'serviceAccount.json');

// The five Lost & Found collections, in dependency order (derived data first).
const COLLECTIONS = [
  'qrTransactions',
  'lfNotifications',
  'matches',
  'inventory',
  'items',
];

const BATCH_SIZE = 500; // Firestore max writes per batch.

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

async function countDocs(db, name) {
  const snap = await db.collection(name).get();
  return snap.size;
}

async function deleteCollection(db, name) {
  const ref = db.collection(name);
  let deleted = 0;
  // Delete in pages until the collection is empty.
  for (;;) {
    const snap = await ref.limit(BATCH_SIZE).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += snap.docs.length;
  }
  return deleted;
}

async function main() {
  const serviceAccount = loadKey();
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  console.log('Project:', serviceAccount.project_id);
  console.log('Resetting Lost & Found collections…\n');

  let total = 0;
  for (const name of COLLECTIONS) {
    const before = await countDocs(db, name);
    if (before === 0) {
      console.log(`  ${name.padEnd(16)} 0 docs (already empty)`);
      continue;
    }
    const deleted = await deleteCollection(db, name);
    total += deleted;
    console.log(`  ${name.padEnd(16)} ${before} docs → deleted ${deleted}`);
  }

  console.log(`\nTotal documents deleted: ${total}`);

  // Verify every collection now reads zero.
  console.log('\nVerification:');
  let allZero = true;
  for (const name of COLLECTIONS) {
    const after = await countDocs(db, name);
    const ok = after === 0;
    if (!ok) allZero = false;
    console.log(`  ${name.padEnd(16)} ${after} docs ${ok ? '✓' : '✗ NOT EMPTY'}`);
  }

  console.log(
    allZero
      ? '\n✅ Done. All Lost & Found data cleared — admin and student counts are now 0.'
      : '\n⚠️  Some collections are still non-empty. Re-run the script.',
  );
}

main().catch((e) => {
  console.error('\n❌ Failed:', e.message ?? e);
  process.exit(1);
});
