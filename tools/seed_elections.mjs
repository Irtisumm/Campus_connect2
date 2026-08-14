// One-time elections seeder for Campus Connect.
//
// Seeds two Firestore collections used by the Student Elections module:
//
//   1. `electionCandidates/{candidateId}` — the four candidates previously
//      hard-coded in `lib/data/mock_data.dart` (MockData.candidates). Each
//      document mirrors `Candidate.toMap()` in `lib/models/candidate.dart`.
//
//   2. `electionMeta/election_2026` — the single published election
//      configuration document that previously lived as the `_electionContent`
//      const in `lib/screens/events/election_info_screen.dart`. The document
//      shape mirrors `ElectionMeta.toMap()` in
//      `lib/models/election_meta.dart`.
//
// After this runs, the ElectionService streams have data to read and the
// ElectionsInfoScreen renders live Firestore data instead of the old
// hard-coded constants.
//
// This uses the Firebase Admin SDK, which bypasses Firestore security rules
// the way a Cloud Function would. That is intentional and required: the
// `electionCandidates` / `electionMeta` rules in firestore.rules allow client
// reads for any signed-in user but restrict writes to admins, and even admins
// are expected to manage elections through the app — the initial published
// data must be created out-of-band, and this script is that out-of-band path.
//
// It mirrors seed_lockers.mjs: same service-account key, same idempotency
// guarantees, same console output style.
//
// ── How to run ─────────────────────────────────────────────────────────────
//   cd tools
//   npm install
//   # put your Firebase service-account key at tools/serviceAccount.json
//   node seed_elections.mjs
//
// The script is idempotent: re-running it rewrites each document with the
// seeded values (merge), so drift is repaired rather than duplicated.

import admin from 'firebase-admin';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// ── The 4 candidates from MockData.candidates ──────────────────────────────
// Copied verbatim from lib/data/mock_data.dart. The `id` is preserved as the
// Firestore document key so the seeded documents match the mock data the
// screens were built against. `status` is 'Published' so students can read
// them immediately (the rules allow reads only on Published docs).
const CANDIDATES = [
  {
    id: 'C-001',
    name: 'Amirul Hakim',
    programme: 'BEng Electrical Engineering',
    position: 'President',
    manifesto:
      'Committed to bridging the gap between students and management. Will focus on student welfare, better facilities, and improved mental health resources.',
  },
  {
    id: 'C-002',
    name: 'Priya Devi',
    programme: 'BSc Computer Science',
    position: 'Vice President',
    manifesto:
      'Advocating for tech-forward student services, faster WiFi across campus, and more collaboration opportunities with industry partners.',
  },
  {
    id: 'C-003',
    name: 'Lim Wei Jian',
    programme: 'BA Business Administration',
    position: 'Secretary General',
    manifesto:
      'Focused on transparent communication between the student council and the student body. Will publish monthly newsletters.',
  },
  {
    id: 'C-004',
    name: 'Nur Aisyah binti Rosli',
    programme: 'BEd TESL',
    position: 'Treasurer',
    manifesto:
      'Will ensure responsible and transparent management of student activity funds with detailed public financial reports each semester.',
  },
];

// ── The election configuration from the old _electionContent const ─────────
// Mirrors ElectionMeta.toMap() in lib/models/election_meta.dart. The timeline
// entries carry a `tone` string ('accent' | 'current' | 'muted') that the
// timeline widget maps to its colour enum — see _TimelineData.fromEntry in
// election_info_screen.dart.
//
// Seeded as 'Pending' so the admin must explicitly publish the election
// before students can see it — matching the publish workflow the student
// screen now enforces.
const ELECTION_META = {
  id: 'election_2026',
  title: 'Student Elections 2026',
  allPositionsLabel: 'All Positions',
  noticeTitle: 'This is an information-only page.',
  noticeBody: 'No online voting is conducted here.',
  aboutTitle: 'About the Elections',
  aboutBody:
    'The Student Council Elections are held annually to elect the student representatives who will voice student concerns, organise campus activities, and work with the administration to improve campus life. Every enrolled student is encouraged to participate — either as a candidate or as a voter.',
  timelineTitle: 'Timeline',
  upcomingLabel: 'Upcoming',
  positionsTitle: 'Open Positions',
  howToVoteTitle: 'How to Vote',
  pollingLocation: 'Main Hall, Block A',
  pollingDate: '1 Apr 2026',
  pollingTime: '09:00 – 16:00',
  positions: [
    'President',
    'Vice President',
    'Secretary General',
    'Treasurer',
  ],
  timeline: [
    { date: '10 Mar 2026', description: 'Nomination period opens', tone: 'accent' },
    { date: '25 Mar 2026', description: 'Registration closes', tone: 'current' },
    { date: '1 Apr 2026', description: 'Polling Day', tone: 'muted' },
  ],
  voteSteps: [
    'Check your name on the voter list at the entrance of the Main Hall.',
    'Present your student ID to the election officer.',
    'Receive your ballot paper and mark your choice in private.',
    'Drop your completed ballot into the sealed ballot box.',
    'Exit the polling station. Results are announced within 24 hours.',
  ],
  status: 'Pending',
  createdAt: new Date().toISOString().slice(0, 10),
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

/**
 * Converts a candidate seed entry to the Firestore document shape.
 *
 * Matches `Candidate.toMap()` in lib/models/candidate.dart exactly. The
 * document is world-readable once published, so no secrets live here.
 */
function candidateToDoc(candidate) {
  return {
    name: candidate.name,
    programme: candidate.programme,
    position: candidate.position,
    manifesto: candidate.manifesto,
    // Seeded as 'Pending' so the admin must explicitly publish each
    // candidate before students can see them — matching the publish
    // workflow the student screen now enforces.
    status: 'Pending',
  };
}

/**
 * Converts the election meta seed to the Firestore document shape.
 *
 * Matches `ElectionMeta.toMap()` in lib/models/election_meta.dart exactly.
 * The `id` is the document key, so it is not stored inside the map.
 */
function metaToDoc(meta) {
  const { id: _drop, ...doc } = meta;
  return doc;
}

async function main() {
  const serviceAccount = loadKey();

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    // projectId is read from the service-account key, so no hard-coded id.
  });

  const db = admin.firestore();

  // ── Candidates ───────────────────────────────────────────────────────────
  const candidatesCol = db.collection('electionCandidates');
  console.log(
    `Seeding ${CANDIDATES.length} candidates into electionCandidates/{candidateId} ...\n`,
  );

  let cCreated = 0;
  let cRepaired = 0;

  for (const candidate of CANDIDATES) {
    const ref = candidatesCol.doc(candidate.id);
    const snap = await ref.get();
    const data = candidateToDoc(candidate);

    if (snap.exists) {
      // merge:true rewrites the seeded fields over the top while preserving
      // any keys a live system may have added. Re-running the seeder
      // therefore repairs drift rather than failing.
      await ref.set(data, { merge: true });
      cRepaired++;
      console.log(`  ${candidate.id}  ·  exists — repaired (${candidate.position})`);
    } else {
      await ref.set(data);
      cCreated++;
      console.log(`  ${candidate.id}  ✓  created (${candidate.position})`);
    }
  }

  console.log(
    `\n✅ Candidates done. ${cCreated} created, ${cRepaired} repaired.`,
  );

  // ── Election meta ────────────────────────────────────────────────────────
  const metaRef = db.collection('electionMeta').doc(ELECTION_META.id);
  console.log(
    `\nSeeding election configuration into electionMeta/${ELECTION_META.id} ...`,
  );

  const metaSnap = await metaRef.get();
  const metaData = metaToDoc(ELECTION_META);

  if (metaSnap.exists) {
    await metaRef.set(metaData, { merge: true });
    console.log(`  ${ELECTION_META.id}  ·  exists — repaired (status: ${ELECTION_META.status})`);
  } else {
    await metaRef.set(metaData);
    console.log(`  ${ELECTION_META.id}  ✓  created (status: ${ELECTION_META.status})`);
  }

  console.log('\n✅ Election meta done.');
  console.log(
    `   Collections: electionCandidates/{candidateId}  ·  ${CANDIDATES.length} documents`,
  );
  console.log(
    `                electionMeta/{metaId}  ·  1 document (${ELECTION_META.id})`,
  );
}

main().catch((e) => {
  console.error('\n❌ Seeder failed:', e);
  process.exit(1);
});