# Lost & Found — Full Workflow: Final Report

Project: `campus-connect-ce3e8` · Branch: `events-module` · Date: 2026-08-15

The corrected three-workflow scope is complete: QR Handover and QR Return
Collection are fully built (not hidden, removed, postponed, or stubbed). Five
coordinated sub-agents built the feature; each appended a report to
`docs/lost_found_full_workflow_handoff.md`.

---

## Files changed

**New models** (`lib/models/`)
- `inventory_item.dart` — `InventoryItem` (status `In Inventory` / `Returned`)
- `lf_match.dart` — `LfMatch` (status `Proposed` / `Approved` / `Completed`)
- `lf_notification.dart` — `LfNotification` (in-app match alert)
- `qr_transaction.dart` — `QrTransaction` (kind `handover` / `return`, status
  `Issued` / `Scanned` / `Confirmed` / `Cancelled`)

**New service**
- `lib/services/lf_workflow_service.dart` — Firestore access for inventory,
  matches, QR transactions, and L&F notifications, plus the three watch streams
  (`watchHandoverQrForReport`, `watchReturnQrForInventory`, `watchMyActiveQr`).

**Modified**
- `lib/models/item.dart` — extended `ItemStatus` enum (`Awaiting Handover`,
  `In Inventory`, `Returned`).
- `lib/models/app_notification.dart` — L&F notification support.
- `lib/services/lost_found_service.dart` — extended item status handling.
- `lib/services/app_state.dart` — orchestrator wrappers for every new
  collection/action (screens never touch Firestore directly).
- `lib/screens/lost_found/lost_found_screens.dart` — all UI: student
  found-detail handover QR + scan, admin handover controls, Inventory Office
  screen + item detail, rebuilt match list/detail on Firestore, student
  lost-detail match summary + Return QR scan, notifications feed, admin
  dashboard workflow section.
- `lib/main.dart` — restored/added routes for inventory and match screens.
- `firestore.rules` — extended rules for `qrTransactions`, `inventory`,
  `matches`, `lfNotifications`, and the extended `items` status lifecycle.
- `pubspec.yaml` / `pubspec.lock` — added `mobile_scanner`, `qr_flutter`.

**Tests / docs**
- `tools/rules-test/lf_workflow_e2e_test.mjs` (new full-chain e2e),
  `lf_workflow_rules_test.mjs`, `items_rules_test.mjs`, `rules_test.mjs`,
  `package.json`.
- `test/lf_workflow_models_test.dart` (new).
- `docs/lost_found_full_workflow_handoff.md` (five agent reports),
  `docs/lost_found_final_report.md` (this file).

---

## Collections and fields

**`items/{itemId}`** (reports — extended, unchanged fields preserved)
`type`, `title`, `category`, `description`, `whereLost`, `whenLost`,
`reportedByUid`, `reportedByStudentId`, `imageUrls`, `status`, `isDeleted`,
`createdAt`, `updatedAt`. `status` enum extended with `Awaiting Handover`,
`In Inventory`, `Returned`.

**`inventory/{inventoryId}`** (new)
`foundReportId`, `finderUid`, `finderStudentId`, `title`, `category`,
`description`, `imageUrls`, `status` (`In Inventory` → `Returned`),
`matchedLostReportId`, `handedOverAt`, `returnedAt`, `createdAt`, `updatedAt`.

**`matches/{matchId}`** (new)
`lostReportId`, `inventoryItemId`, `lostOwnerUid`, `lostOwnerStudentId`,
`createdByUid`, `status` (`Proposed` → `Approved` → `Completed`), `notes`,
`createdAt`, `updatedAt`.

**`qrTransactions/{txnId}`** (new — one collection, two kinds)
`kind` (`handover` | `return`), `token` (opaque), `createdByUid`,
`intendedStudentUid`, `intendedStudentId`, `foundReportId` (handover),
`lostReportId` + `inventoryItemId` (return), `status`
(`Issued` → `Scanned` → `Confirmed` | `Cancelled`), `issuedAt`, `expiresAt`,
`scannedAt`, `confirmedAt`, `confirmedByUid`.

**`lfNotifications/{notificationId}`** (new)
`studentId`, `title`, `body`, `type` (`match`), `read`, `relatedReportId`,
`createdAt`.

---

## Cloudinary setup

Unchanged from the existing, verified configuration:
- Unsigned preset **`campus_connect_lost_found`** (no API secret in Flutter).
- Upload folder **`lost-found`**; formats `jpg`/`jpeg`/`png`/`webp`; 5 MB max;
  up to 3 images per report.
- Inventory records **copy** `imageUrls` from the source report — no re-upload.

---

## Status transitions

- **Lost report:** `Active` → `Matched - Pending` (admin) → `Resolved` (admin,
  after physical return); `Active` → `Closed` (student/admin).
- **Found report:** born `Awaiting Handover` → `In Inventory` (admin, handover
  confirmed) → `Returned` (admin, return confirmed); `Awaiting Handover` →
  `Closed` (student/admin, only before inventory).
- **Inventory:** `In Inventory` → `Returned`.
- **Match:** `Proposed` → `Approved` → `Completed`.
- **QR transaction:** `Issued` → `Scanned` (intended student) → `Confirmed`
  (admin, within expiry); `Issued` → `Cancelled` (admin).

---

## QR expiry policy

- Token: 32 random hex chars (`Random.secure()`), opaque — no PII, no secrets,
  no write authority.
- Expiry: **10 minutes** from issuance (client-set); rules enforce an upper
  bound of 15 minutes for clock skew, with exact `expiresAt` checks on scan and
  confirm.
- Single-use: `Issued → Scanned → Confirmed` exactly once; a duplicate confirm
  is denied by the rules.
- A scan alone never changes a protected status — the final handover/return
  change happens only on the admin confirmation write, after physical
  confirmation, in one atomic Firestore transaction (duplicate inventory or
  return records are therefore impossible).

---

## Tests

- Rules emulator (`npm test`, single `emulators:exec`): **105 passed, 0 failed**
  (14 users + 27 items + 50 workflow + 14 end-to-end).
- `flutter analyze`: **0 errors, 0 warnings** (344 `info`-level deprecation /
  `prefer_const` lints remain, all pre-existing and unrelated).
- `flutter test`: **130 passed, 0 failed**.
- `flutter build apk --debug`: succeeded
  (`build/app/outputs/flutter-apk/app-debug.apk`).

---

## Limitations

1. **Client-only enforcement (owner-approved).** Cloud Functions is not enabled
   on this project (Blaze plan not active), so there is no trusted server.
   Firestore security rules + Firestore transactions are the enforcement layer;
   the deviation from "trusted server-side verification" is documented as an
   owner-approved risk.
2. **No push notifications.** FCM is not configured in the project, so match
   alerts are in-app only (mirroring `lockerNotifications`).
3. **Admin match list labels show raw document IDs** (`Lost <id> ↔ Item <id>`)
   rather than human-readable titles — cosmetic, not functional.
4. **QR expiry is client-computed** (`issuedAt`/`expiresAt`); the rules only
   type-check `issuedAt` and enforce the 15-minute upper bound, so a malicious
   client could mint a token with a slightly longer (≤15 min) window. The
   scan/confirm expiry checks remain exact against `expiresAt`.

---

## Console steps (Firebase)

1. **Deploy rules** (already done this session):
   `firebase deploy --only firestore:rules`
2. **Verify rules** in Firebase Console → Firestore Database → Rules: confirm
   the `qrTransactions`, `inventory`, `matches`, and `lfNotifications` blocks
   are present and that no `allow read, write: if true` rule exists.
3. **Cloudinary** (unchanged): confirm preset `campus_connect_lost_found`
   remains unsigned and scoped to folder `lost-found`.
4. **Seed an admin** if not already present: a `users/{uid}` document with
   `role: 'admin'` (the app has only `student`/`admin`; registration pins
   students to `student`).
5. **Run the emulator suite** locally before any future rules change:
   `cd tools/rules-test && npm install && npm test`.

---

## Acceptance checklist (10 items)

1. **Workflow 1 — Lost Item Reporting** — complete. ✅
2. **Workflow 2 — Found Item Reporting + Inventory Handover with Handover QR**
   — complete (not hidden/removed/postponed). ✅
3. **Workflow 3 — Matched Item Return + Collection with Return QR, manual
   admin-reviewed matching** — complete. ✅
4. **Five coordinated sub-agents** each appended a report to the shared
   handoff file. ✅
5. **Enforcement layer** — Firestore rules + transactions (client-only
   compromise documented as owner-approved). ✅
6. **Camera scan + manual fallback** — `mobile_scanner` scan with manual code
   entry, both gated by the same rules. ✅
7. **QR token security** — opaque/random, single-use, 10-minute expiry, tied to
   one intended student/report/item/action; scan alone never changes a
   protected status; final change only after admin physical confirmation in one
   atomic transaction. ✅
8. **Duplicate inventory/return records impossible** — single-use QR +
   transaction. ✅
9. **Security constraints honored** — no secrets in client code, server
   timestamps where supported, no allow-all rules, UID-only identity for all
   report reads/writes. ✅
10. **Tests green + rules deployed** — 105 rules tests, 130 app tests, analyzer
    0 errors, rules deployed to production. ✅
