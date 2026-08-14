// Publishes the Student Elections data seeded by seed_elections.mjs.
//
// The seeder writes everything as 'Pending' — both electionMeta/election_2026
// and every electionCandidates document — but the student elections screen
// only ever queries `status == 'Published'`. Until the admin publish flow is
// wired to a screen, this script is the out-of-band path that flips the
// seeded documents to 'Published' so students can see them.
//
// It uses the Firebase Admin SDK (bypasses security rules), exactly like
// seed_elections.mjs, and it is idempotent: re-running it just re-asserts
// 'Published' on every document.
//
// ── How to run ─────────────────────────────────────────────────────────────
//   cd tools
//   npm install
//   node publish_elections.mjs

import admin from 'firebase-admin';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

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

  const db = admin.firestore();

  // ── Election meta ────────────────────────────────────────────────────────
  const metaRef = db.collection('electionMeta').doc('election_2026');
  const metaSnap = await metaRef.get();
  if (!metaSnap.exists) {
    console.error(
      '\n❌ electionMeta/election_2026 does not exist. ' +
        'Run `node seed_elections.mjs` first.\n',
    );
    process.exit(1);
  }
  await metaRef.update({ status: 'Published' });
  console.log('✅ electionMeta/election_2026  →  status: Published');

  // ── Candidates ───────────────────────────────────────────────────────────
  const candidatesSnap = await db.collection('electionCandidates').get();
  if (candidatesSnap.empty) {
    console.warn(
      '\n⚠️  electionCandidates is empty. Run `node seed_elections.mjs` first.',
    );
  }

  let published = 0;
  for (const doc of candidatesSnap.docs) {
    await doc.ref.update({ status: 'Published' });
    published++;
    console.log(`  ${doc.id}  →  status: Published`);
  }
  console.log(`\n✅ ${published} candidate(s) published.`);
  console.log(
    '\nThe student Elections screen queries status == "Published" — it ' +
      'should now render the election configuration and all candidates.',
  );
}

main().catch((e) => {
  console.error('\n❌ Publish failed:', e);
  process.exit(1);
});
