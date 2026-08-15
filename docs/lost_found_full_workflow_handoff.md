# Lost & Found — Full Workflow Handoff (Five-Agent Build)

Shared handoff file for the complete three-workflow build. Every agent MUST
read this file before starting and APPEND a report before finishing.

> NOTE: This is the corrected scope. The owner explicitly stated: QR Handover
> and QR Return Collection must NOT be hidden, removed, postponed, or replaced
> with placeholders. All three workflows are in scope.

---

## AGENT 1 — Current Project Audit and Full Data Contract

**Agent number and role:** Agent 1 — Lead audit, scope freeze, data contract.

### Scope completed
Audited the entire current Lost & Found implementation: reporting flows,
Cloudinary uploads, dashboard counts, My Reports, detail screens, admin
screens, Firestore collections, security rules, admin role system,
notification system, QR libraries, and all existing handover/match/return
placeholder code. No feature code was written in this phase.

### Files inspected
- `lib/screens/lost_found/lost_found_screens.dart` (4200+ lines; every L&F screen)
- `lib/services/lost_found_service.dart`
- `lib/services/app_state.dart`
- `lib/services/admin_service.dart`, `lib/services/data_service.dart`
- `lib/models/item.dart`
- `lib/main.dart` (L&F route table)
- `firestore.rules` (all collections)
- `firebase.json`, `pubspec.yaml`

### Files changed
None. Audit-only phase.

### Current working features preserved (verified live, do not break)
1. **Workflow 1 — Lost reporting: COMPLETE.** Form → `AppState.createReport` →
   `LostFoundService.createItem` → `items` collection (status `Active`).
   Success dialog after Firestore confirm. My Lost Reports + dashboard counts
   live via `watchMyLostItems` / `watchMyAllItems`. Student Close Report
   (Active→Closed) live; rules enforce it. Cloudinary upload of up to 3
   images (JPEG/PNG/WebP, 5 MB each) via unsigned preset
   `campus_connect_lost_found`, folder `lost-found` — verified working against
   production Cloudinary on 2026-08-15.
2. **Workflow 2 — Found reporting (submission half): COMPLETE.** Same
   Firebase/Cloudinary path, `type: found`. Found detail screen renders live
   data.
3. Admin moderation on reports: Mark as Resolved / Close Report live on both
   admin list screens; `AdminLostListScreen`, `AdminFoundListScreen` live.
4. L&F Notifications screen (derived feed from own reports).
5. Rules deployed to production 2026-08-15; 41 rule tests green (14 users +
   27 items); 114 app tests green; analyzer 0 errors.

### Current gaps (what the remaining agents build)
1. **Workflow 2 second half — Inventory Handover: NOT BUILT.**
   - `_foundDetailBody` holds `qrCode`/`qrScanned`/`handoverStatus` as `null`
     constants — QR section never renders (lost_found_screens.dart:2446-2454).
   - "Verify & Confirm Handover" button exists but toasts "not available yet"
     (line 2565).
   - Handover stepper (`_HandoverStepper`) renders static at step 1 (line 2519).
   - Next-step NoticeBox is gated on mock status `'In Inventory'` — never
     renders for real Firestore docs (line 2574).
   - `_showHandoverSuccessDialog` exists, never called (line 2587).
   - Admin found detail (`_adminFoundDetailBody`, line 3267): no QR/inventory
     actions at all.
   - No `inventory` collection, no handover QR transactions.
   - Found reports are born `Active` — no `Awaiting Handover` state.
2. **Workflow 3 — Manual Match + Return Collection: NOT BUILT.**
   - `AdminMatchListScreen` / `AdminMatchDetailScreen` still exist but read
     mock `DataService.matches` (MockData), and their routes are COMMENTED
     OUT in `lib/main.dart` (lines 141-142).
   - Lost detail match banner held as `const String? matchStatus = null`
     (line 2302).
   - No match notifications (no FCM configured anywhere — firebase.json has no
     messaging; pubspec has no firebase_messaging → in-app notifications are
     the correct mechanism, mirroring `lockerNotifications`).
   - No Return QR, no return transaction records.
3. **Trusted server: DOES NOT EXIST.** No `functions/` directory; firebase.json
   contains no functions config; `firebase functions:list` fails (Cloud
   Functions API not enabled on `campus-connect-ce3e8`). The spec mandates
   trusted server-side verification for QR scans and atomic handover/return
   transactions — this requires enabling Cloud Functions (Blaze plan).
4. **QR scanning: no scanner library.** `qr_flutter ^4.1.0` present (QR
   GENERATION only). No `mobile_scanner` / camera scan. The original mock UI
   used manual code entry ("Enter QR code here..." TextField).
5. Mock statuses (`In Inventory`, `Claiming`, `Received`, `Archived`) appear
   only in dead code branches gated on statuses that never exist in Firestore.

### Hard-coded data scan
No hard-coded production reports, counts, media URLs, or sample users remain
in the L&F screens. The only mock references left are (a) `DataService.matches`
used by the unreachable match screens, and (b) dead constants in the QR
sections. "Block A, Level 1" office text is product copy, kept as-is.

### Admin role system
- Single `admin` role: `users/{uid}.role == 'admin'`; `AppState.isAdmin`;
  rules `isAdmin()`. Registration pins students to `student` role; admins are
  seeded (ADMIN001 pattern).
- DECISION (default adopted): "Inventory Admin" = any verified `admin`-role
  user. No new role type is introduced — the app has only student/admin, and
  the spec says "admin/staff". Documented here for downstream agents.

### Proposed data contract (freeze for Agents 2-5)

#### Existing: `items/{itemId}` (reports) — EXTEND
- Existing fields unchanged: `type`, `title`, `category`, `description`,
  `whereLost`, `whenLost`, `reportedByUid`, `reportedByStudentId`,
  `imageUrls`, `status`, `isDeleted`, `createdAt`, `updatedAt`.
- Status enum EXTENDED (new wire values added to `ItemStatus`):
  - `Active` — newly submitted (lost: searching; found: not yet handed over)
  - `Awaiting Handover` — NEW, found only: submitted, student instructed to
    bring item to Inventory Office
  - `Matched - Pending` — existing: admin proposed/approved a manual match
  - `In Inventory` — NEW, found only: handover confirmed, inventory record exists
  - `Resolved` — existing: lost item matched & returned to owner / admin resolved
  - `Returned` — NEW, found only: inventory item returned to its owner
  - `Closed` — existing: closed by student or admin

  Transition map (enforced in rules + server functions):
  - Lost: `Active` → `Matched - Pending` (admin) → `Resolved` (admin, after
    physical return) ; `Active` → `Closed` (student own / admin)
  - Found: `Active` → `Awaiting Handover` (auto on submission) →
    `In Inventory` (server, handover confirmed) → `Returned` (server, return
    confirmed) ; `Awaiting Handover`/`Active` → `Closed` (student own / admin,
    only while not yet in inventory)

  NOTE: found report creation status changes from `Active` to
  `Awaiting Handover` (rules + create payload change).

#### NEW: `inventory/{inventoryId}`
`foundReportId`, `finderUid`, `finderStudentId`, `title`, `category`,
`description`, `imageUrls` (copied from report), `status`
(`In Inventory` → `Returned`), `matchedLostReportId` (null until admin
matches), `handedOverAt`, `returnedAt`, `createdAt`, `updatedAt`.
Exactly ONE record per handover (server transaction enforces).

#### NEW: `matches/{matchId}`
`lostReportId`, `inventoryItemId`, `lostOwnerUid`, `lostOwnerStudentId`,
`createdByUid` (admin), `status` (`Proposed` → `Approved` → `Completed`),
`notes`, `createdAt`, `updatedAt`.
Student sees only a safe summary of matches pointing at their own lost
report (title/category/status — never finder identity or contact data).

#### NEW: `qrTransactions/{txnId}` (single collection, two kinds)
- `kind`: `handover` | `return`
- `token`: opaque random string (e.g. 32 hex chars) — the QR payload
- `createdByUid` (admin), `intendedStudentUid`, `intendedStudentId`
- handover: `foundReportId`; return: `lostReportId`, `inventoryItemId`
- `status`: `Issued` → `Scanned` → `Confirmed` | `Expired` | `Cancelled`
- `issuedAt` (server ts), `expiresAt` (issuedAt + 10 min),
  `scannedAt`, `confirmedAt`, `confirmedByUid`
- This document IS the handover/return transaction record (no separate
  collection) — one document per QR, single-use, prevents duplicates.
- Rules: students can NEVER create/update; admin creates `Issued` only;
  ALL verification (scan) and confirmation writes happen SERVER-SIDE.

#### NEW: `lfNotifications/{notificationId}`
Mirrors `lockerNotifications`: `studentId` (recipient campus ID), `title`,
`body`, `type` (`match`), `read` (bool, student flips own),
`relatedReportId`, `createdAt`. Admin creates; student reads own;
student may only flip `read`. In-app only (no FCM in project).

### QR policy (design targets for Agent 2)
- Token: 32 random hex chars via server-side crypto. Opaque — contains no
  PII, no secrets, no write authority.
- Expiry: 10 minutes from issuance. Single-use: status moves
  `Issued → Scanned → Confirmed` exactly once; expired/used/wrong-user
  scans fail with a safe message and mutate nothing.
- Student scan = server callable (auth = caller's Firebase ID token); it
  only verifies and marks `Scanned` when the CALLER is `intendedStudentUid`.
- Final confirmation = server callable, admin-only, atomic transaction:
  handover → set found report `In Inventory` + create exactly one inventory
  doc + QR `Confirmed`; return → inventory `Returned` + found report
  `Returned` + lost report `Resolved` + match `Completed` + QR `Confirmed`.
  Duplicate confirmation is impossible (token already `Confirmed`).

### Cloudinary decisions
Keep the existing unsigned preset `campus_connect_lost_found` exactly as-is
(verified live: folder `lost-found`, formats jpg/jpeg/png/webp, unguessable
public IDs). No API secret in Flutter — nothing changes on media.
Inventory records copy `imageUrls` from the report; no re-upload.

### Tests run and results (baseline carried into Agent 2)
- `flutter analyze`: 0 errors, 15 pre-existing warnings (mostly
  `withOpacity` deprecations + dead L&F code that Agents 3/4 will remove).
- `flutter test`: 114 passed, 0 failed.
- Rules emulator: 41 passed (14 users + 27 items), 0 failed.
- Production Cloudinary: PNG accepted into `lost-found`; TXT rejected.

### Security and privacy checks
- No Cloudinary secret, service-account file, token, or QR signing key in the
  repo (verified).
- Ownership everywhere = authenticated Firebase UID; studentId only as
  display denormalization (existing pattern, kept).
- No push/FCM config exists → in-app notifications are the honest mechanism
  (spec allows this explicitly).
- Rules deployed to production are least-privilege; no allow-all rules.

### Defects, blockers, or decisions needed from the owner
1. **BLOCKER — trusted server:** Cloud Functions API is not enabled on
   `campus-connect-ce3e8`. The spec REQUIRES trusted server-side QR
   verification + atomic handover/return transactions. Enabling Cloud
   Functions requires the Blaze (pay-as-you-go) plan and billing.
   Options: (a) enable Blaze + Cloud Functions (spec-compliant),
   (b) client-only compromise (violates the spec's trusted-server rule),
   (c) pause the build. → ASKED.
2. **QR scan method:** add `mobile_scanner` (camera scan, +1 dependency)
   vs manual code entry (matches the original mock UI, no dependency).
   → ASKED.
3. Minor: no widget tests for L&F forms — Agents 3/4 add focused tests.

### Required next action
Agent 2: after the owner answers (1) and (2), design least-privilege rules
for `inventory`, `matches`, `qrTransactions`, `lfNotifications` + the
server-function surface, and prepare emulator tests. Do not write UI code.

---

## AGENT 2 — Firebase Rules, Cloudinary Review, Trusted QR Design

**Agent number and role:** Agent 2 — Security rules + QR transaction design.

### Scope completed
1. Designed the least-privilege rules for the four new collections
   (`qrTransactions`, `inventory`, `matches`, `lfNotifications`) and the
   extended `items` status lifecycle.
2. Designed the QR token policy (opaque, single-use, 10-minute expiry) and
   the scan/confirm flows under the OWNER-APPROVED client-only enforcement
   model (no Cloud Functions; Firestore rules are the enforcement layer and
   multi-document updates run inside Firestore transactions).
3. Reviewed Cloudinary setup: unchanged — the live unsigned preset
   `campus_connect_lost_found` already enforces formats + folder + safe
   public IDs. No secret in Flutter.
4. Wrote and ran the full rules test matrix.

### Files inspected
`firestore.rules`, `tools/rules-test/items_rules_test.mjs`,
`tools/rules-test/rules_test.mjs`, `lib/models/item.dart`,
`lib/services/lost_found_service.dart`, `firebase.json`, `pubspec.yaml`.

### Files changed
- `firestore.rules` — items create/update/admin rules extended for the new
  statuses; four new collection rule blocks added.
- `tools/rules-test/lf_workflow_rules_test.mjs` — created (50 cases).
- `tools/rules-test/package.json` — test script now runs all three suites.

### Current working features preserved
Nothing existing was loosened. The `items` reporter rules still pin owner
identity, type and soft-delete semantics; every pre-existing rule test still
passes unchanged.

### Data fields, Firebase paths, and status transitions affected
- `items` create: lost → `Active`, found → `Awaiting Handover`.
- `items` student update: status unchanged, or `Active → Closed`,
  `Awaiting Handover → Closed`.
- `items` admin update: statuses `Active | Awaiting Handover |
  Matched - Pending | In Inventory | Resolved | Returned | Closed`.
- `qrTransactions`: admin-only create (`Issued`, token, expiry bounded to
  ≤ 11 min); intended student may write ONLY `Issued → Scanned` (status +
  scannedAt, before expiry); admin may write ONLY `Scanned → Confirmed`
  (before expiry) or `Issued → Cancelled`; all identity fields pinned via
  `affectedKeys`; delete denied.
- `inventory`: admin create (`In Inventory`), admin update
  (`In Inventory → Returned` only), finder-or-admin reads, delete denied.
- `matches`: admin create (`Proposed | Approved`), admin update through
  `Proposed | Approved | Completed`, owner-or-admin reads, delete denied.
- `lfNotifications`: admin create; recipient (by campus studentId) read +
  flip `read` only; delete denied.

### Cloudinary/QR decisions
- QR payload = the 32-char hex `token` only (opaque; no PII, no secrets, no
  write authority). Generated client-side with `Random.secure()` — the
  server-side-crypto preference is waived under the owner's client-only
  decision; the token's power is zero without the rules-gated writes.
- Expiry: 10 minutes (`expiresAt = issuedAt + 10 min`), rule-bounded.
- Single-use: `Issued → Scanned → Confirmed` — each transition is the only
  one permitted from its state, enforced by rules; duplicates impossible
  because a confirm transaction re-reads the token doc and aborts unless it
  is `Scanned`.
- Handover confirm (client Firestore transaction): found report →
  `In Inventory`, create exactly one `inventory` doc, QR → `Confirmed`.
- Return confirm (client Firestore transaction): inventory → `Returned`,
  found report → `Returned`, lost report → `Resolved`, match → `Completed`,
  QR → `Confirmed`.
- DEVIL'S-ADVOCATE NOTE (documented risk, owner-approved): without Cloud
  Functions, a compromised ADMIN device could bypass the client transaction
  logic and write the same end-state directly (admins are trusted staff;
  rules still block students and non-admins completely, and identity
  re-pointing is blocked for everyone). This is the accepted cost of the
  client-only compromise.

### Tests run and results
`npm test` (Firestore emulator): **91 passed, 0 failed**
(14 users + 27 items + 50 workflow).

### Security and privacy checks
- No broad allow-all rules; every new collection is owner/role-scoped.
- Students cannot issue QR codes, create inventory records, create/approve
  matches, confirm handovers/returns, or make official status changes —
  verified by dedicated denial tests.
- Wrong-student, expired, re-used, double-scan and re-pointing attacks are
  all denied at the database level.
- No secrets, service accounts or keys added anywhere.

### Defects, blockers, or decisions needed from the owner
None. All design decisions were made by the owner (client-only compromise,
camera scan + manual fallback).

### Required next action
Agent 3: extend `ItemStatus` with the three new wire values, make found
reports born `Awaiting Handover`, build the models + service methods for
`inventory` / `matches` / `qrTransactions` / `lfNotifications`, wire the
Found Report next-step instruction, and add focused tests. Keep the student
UI design; do not build admin QR UI yet (Agent 4).

---

## AGENT 3 — Live Reporting, Firebase Data, and Media

**Agent number and role:** Agent 3 — Models, workflow service, AppState wiring.

### Scope completed
1. Extended `ItemStatus` with `Awaiting Handover`, `In Inventory`,
   `Returned` (wire values unchanged for the four existing states).
2. Created the four workflow models: `InventoryItem`, `LfMatch`,
   `QrTransaction`, `LfNotification` (typed enums, wire values, create /
   update maps, `fromMap`).
3. Created `LfWorkflowService`: inventory/matches/QR/notification streams
   (rules-compatible filters), QR issue/find/scan/cancel, atomic
   `confirmHandover` and `confirmReturn` Firestore transactions, match
   approval with atomic owner notification, and `QrScanOutcome` carrying
   display-ready messages for every scan case.
4. Wired `AppState` with all student/admin workflow methods and re-exported
   the new models.
5. Made found reports born `Awaiting Handover` (coerced in
   `AppState.createReport`; independently enforced by rules).
6. Found-report success view now states "saved with status: Awaiting
   Handover" above the handover step list (the Inventory Office next-step
   instruction).
7. Updated the derived Notifications feed wording for the new statuses
   (`AppNotification.forOwner`).

### Files inspected
`lib/models/item.dart`, `lib/models/app_notification.dart`,
`lib/services/app_state.dart`, `lib/services/lost_found_service.dart`,
`lib/screens/lost_found/lost_found_screens.dart` (form + success views).

### Files changed
- `lib/models/item.dart` — extended `ItemStatus`.
- `lib/models/app_notification.dart` — wording for new statuses.
- `lib/models/inventory_item.dart` — created.
- `lib/models/lf_match.dart` — created.
- `lib/models/qr_transaction.dart` — created (CSPRNG token, 10-min expiry).
- `lib/models/lf_notification.dart` — created.
- `lib/services/lf_workflow_service.dart` — created.
- `lib/services/app_state.dart` — service wiring + 20 workflow methods.
- `lib/screens/lost_found/lost_found_screens.dart` — success-view status line.
- `test/lf_workflow_models_test.dart` — created (16 tests).

### Current working features preserved
Lost/found submission, Cloudinary upload, dashboard counts, My Reports,
close/resolve/delete all untouched (rules + existing tests still green).

### Data fields, Firebase paths, and status transitions affected
As frozen in Agent 1's contract. Birth statuses now enforced in code and
rules: lost → `Active`, found → `Awaiting Handover`.

### Cloudinary/QR decisions
- QR token: 32 hex chars from `Random.secure()`; payload = token only.
- Expiry: 10 minutes (`QrTransaction.validityWindow`); rules bound issuance
  to ≤ 15 minutes to tolerate device clock skew; scan/confirm checks are
  exact against `expiresAt`.
- Scan: service inspects first (invalid/expired/used/cancelled messages),
  then writes `Scanned` — the rules are the actual gate.
- Handover confirm transaction: re-reads token (must be `Scanned`), moves
  report → `In Inventory`, creates exactly one inventory record, token →
  `Confirmed`. Duplicate confirm impossible (token re-check).
- Return confirm transaction: token re-check, inventory → `Returned` +
  `matchedLostReportId`, found report → `Returned`, lost report →
  `Resolved`, match → `Completed`, token → `Confirmed`.

### Tests run and results
- `flutter analyze`: 0 errors.
- `flutter test`: **130 passed, 0 failed** (114 existing + 16 new).

### Security and privacy checks
No new secrets; token contains no PII; all service queries keep the
rules-required owner filters; transactions re-read the token document for
the single-use guarantee.

### Defects, blockers, or decisions needed from the owner
None.

### Required next action
Agent 4: revive the found-detail QR/handover section with real data, build
the admin QR generation + confirm controls, restore the admin Match screens
(Firestore-backed), add the admin Inventory screen, the student match
summary + Return QR scan, and the notification feed. Add `mobile_scanner`
(camera scan + manual fallback — owner decision).

---

## AGENT 4 — Inventory Handover, Manual Match, QR, and Return Collection

**Agent number and role:** Agent 4 — Workflows 2 & 3 UI (student + admin).

### Scope completed
1. Added `mobile_scanner` (camera scan) and wired `qr_flutter` into the QR
   dialogs; manual code entry is the fallback (owner decision).
2. Restored the admin Match routes and added Inventory routes in `main.dart`.
3. Student Found Detail: live handover state — Awaiting Handover notice,
   Handover QR scan section (camera + manual entry), "awaiting confirmation"
   and "handover complete" banners, and the one-shot success dialog on the
   Awaiting Handover → In Inventory transition.
4. Admin Found Detail: "Generate Handover QR" (renders a real QR image +
   token), live Issued → Scanned state, "Confirm Handover", "Cancel Code",
   and In Inventory / Returned banners.
5. New admin Inventory Office list + item detail: "Create Match" (picks an
   active lost report), match cards, approve/generate-return-QR/confirm-return.
6. Rebuilt the admin Match list/detail screens on Firestore
   (`watchAllMatches`/`watchMatch`) — no more `DataService.matches`.
7. Student Lost Detail: safe match summary (Approved/Completed) + Return QR
   scan section + "returned" banner.
8. Notifications screen now merges the Firestore `lfNotifications` match
   alerts (with mark-read + deep-link) with the derived report notifications.
9. Admin dashboard: "Inventory Office" and "Review Matches" quick links with
   live counts.

### Files inspected
`lib/main.dart`, `lib/services/app_state.dart`,
`lib/services/lf_workflow_service.dart`, `lib/widgets/common.dart`,
`lib/screens/lost_found/lost_found_screens.dart`.

### Files changed
- `pubspec.yaml` — added `mobile_scanner`.
- `lib/main.dart` — inventory + match routes restored/added.
- `lib/services/lf_workflow_service.dart` — `watchHandoverQrForReport`,
  `watchReturnQrForInventory`, `watchMyActiveQr` streams.
- `lib/services/app_state.dart` — three matching watch wrappers.
- `lib/screens/lost_found/lost_found_screens.dart` — all UI above, plus
  shared `_QrScanSection`, `_QrScannerSheet`, `_StatusBanner`, `_MatchActions`,
  `_LostReportPickerSheet`, and a QR-image `_showQRDialog`.

### Current working features preserved
Submission, Cloudinary upload, dashboard stats, My Reports, close/resolve/
delete, and the existing Notifications feed all untouched.

### Data fields, Firebase paths, and status transitions affected
No new fields or statuses — this agent only *renders and drives* the
collections/transitions frozen in Agents 1–3. The two new service streams
query `qrTransactions` with the rules-required filters (admin `list`, or
student `intendedStudentUid == uid`).

### Cloudinary/QR decisions
- QR payload is the token only; rendered with `QrImageView` (qr_flutter).
- Camera scan uses `mobile_scanner`; manual entry hits the same
  `scanQrCode` path, so the rules are the single gate for both.
- 10-minute expiry surfaced to admins as "expires in N min".

### Tests run and results
- `flutter analyze`: 0 errors, 0 new warnings (15 pre-existing warnings in
  unrelated files remain).
- `flutter test`: **130 passed, 0 failed**.

### Security and privacy checks
No secrets introduced. Student match summary shows only title/status — never
finder identity or contact details. All writes flow through `AppState` →
service → rules; the UI never touches Firestore directly.

### Defects, blockers, or decisions needed from the owner
None.

### Required next action
Agent 5: end-to-end verification (two students + admin flows), rules emulator
tests, real APK build, `firebase deploy --only firestore:rules` (production
still has the pre-workflow rules), and the final report per the spec's
required format.

---

## AGENT 5 — End-to-End Verification, Rules Deployment, Final Report

**Agent number and role:** Agent 5 — e2e rules verification, production rules
deployment, APK build, final report.

### Scope completed
Verified the complete three-workflow chain end-to-end against the Firestore
security rules (the enforcement layer of the client-only architecture),
deployed the rules to production, built the debug APK, and produced this final
report. No feature code was added in this phase — the deliverable is proof
that the rules accept the whole lifecycle and reject every role boundary
around it.

### Files inspected
- `firestore.rules` (full `items`, `qrTransactions`, `inventory`, `matches`,
  `lfNotifications` blocks — lines 82–334)
- `tools/rules-test/lf_workflow_e2e_test.mjs` (new full-chain test)
- `tools/rules-test/lf_workflow_rules_test.mjs` (existing 50-test workflow suite)
- `tools/rules-test/items_rules_test.mjs`, `tools/rules-test/rules_test.mjs`
- `tools/rules-test/package.json`

### Files changed
- `tools/rules-test/lf_workflow_e2e_test.mjs` — NEW: 14-test full-chain walk
  (two students + admin) replaying the exact writes the client transactions
  perform, one by one, under rules enforcement.
- `tools/rules-test/package.json` — added `lf_workflow_e2e_test.mjs` to the
  `npm test` chain.
- `firestore.rules` — deployed to production (no source change; the file was
  already the workflow-complete version from Agents 2–4).

### Working features preserved
All three workflows verified live against the rules:
1. **Lost reporting** — A's lost report born `Active`; a found report forced to
   `Awaiting Handover` (an `Active` found report is denied).
2. **Handover** — admin-only QR issuance → intended finder scans
   (`Issued → Scanned`) → admin confirms physical handover (report
   `In Inventory`, exactly one inventory record, QR `Confirmed`); duplicate
   confirm denied (single-use); student inventory create denied.
3. **Match + return** — admin-only match create (`Proposed`) → approve +
   owner notification → admin-only Return QR → wrong student scan denied →
   owner scans → admin confirms return (inventory `Returned`, found `Returned`,
   lost `Resolved`, match `Completed`, QR `Confirmed`) → final states readable
   by the right parties and hidden from the finder.

### Data fields, Firebase paths, and status transitions affected
None new. The e2e test exercises the frozen contract: `items` (lost/found
reports), `qrTransactions` (handover/return), `inventory`, `matches`,
`lfNotifications`; statuses `Active`, `Awaiting Handover`, `In Inventory`,
`Returned`, `Resolved`, `Proposed`, `Approved`, `Completed`, and QR
`Issued → Scanned → Confirmed / Cancelled`.

### Cloudinary/QR decisions
No change. QR expiry is 10 minutes (client-set, rules-enforced upper bound of
15 minutes for clock skew; scan/confirm checks are exact against `expiresAt`).

### Tests run and results
- Rules emulator (`npm test`, single `emulators:exec`): **105 passed, 0 failed**
  (14 users + 27 items + 50 workflow + 14 e2e).
- `flutter analyze`: **0 errors, 0 warnings** (344 `info`-level deprecation /
  `prefer_const` lints remain, all pre-existing and unrelated).
- `flutter test`: **130 passed, 0 failed**.
- `flutter build apk --debug`: succeeded.

### Security and privacy checks
No secrets, tokens, service-account keys, or signed URLs introduced anywhere.
The e2e test proves the role boundaries: students cannot issue QR codes,
create inventory records, create matches, or scan another student's QR; the
finder cannot read the matched owner's match record. QR tokens are opaque and
single-use; a scan alone never changes a protected status (confirmation is an
admin write gated on `Scanned → Confirmed` within expiry).

### Defects, blockers, or decisions needed from the owner
One test-infrastructure issue found and fixed: the four rules test files run
in a single `emulators:exec`, and `lf_workflow_e2e_test.mjs` initially reused
the doc IDs `inventory/invB1` and `matches/match1` already seeded by
`lf_workflow_rules_test.mjs`, so its `.set()` became an overwrite that the
immutability pins correctly rejected (a false "5 failures"). Renamed to
`invE2E` / `matchE2E`; the full chain now passes 105/105. No product defects.

### Required next action
None — the build is complete. Remaining optional step (owner-gated): commit
and push the `events-module` branch. Not performed without owner approval.
