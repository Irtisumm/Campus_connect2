# Campus Connect — Backend Integration Plan

**Status:** Proposed
**Created:** 2026-07-26
**Approach:** Incremental — one capability at a time, app stays runnable after every phase.

---

## 1. Where the project stands today

| Aspect | Current state |
|---|---|
| Networking packages | **None.** No `http`, `dio`, `firebase_*`, or `supabase_flutter` in `pubspec.yaml` |
| Data layer | `lib/services/data_service.dart` — 2,048 lines, ~75 methods, 17 in-memory collections on a `ChangeNotifier` |
| Async code in data layer | **Zero.** `grep -c "async\|Future<"` returns `0` |
| Auth | `lib/services/auth_service.dart` — 5 hardcoded accounts, plaintext passwords |
| Persistence | Only `shared_preferences` (profile overrides + saved password). Everything else is lost on restart |
| UI size | 8,451 lines across 11 screen files |

`documentation.md:11` and `:727` already name **Firebase Firestore** as the intended backend. This plan follows that decision.

### The 17 collections currently held in memory

`myLostReports`, `myFoundReports`, `allLostReports`, `matches`, `myIssues`, `allIssues`, `issueHistory`, `eventJoiningRequests`, `allEvents`, `pendingEvents`, `candidates`, `lockers`, `myBookings`, `lockerIssues`, `lockerHistory`, `notifications`, `pendingRegistrations`, `eventRoles`.

---

## 2. Service recommendation per capability

| # | Capability | Recommended service | Why this one |
|---|---|---|---|
| 1 | Login / signup / sessions | **Firebase Authentication** | Removes plaintext passwords entirely; handles session restore, token refresh, and password reset (your login screen already has a "Forgot Password?" link with nothing behind it) |
| 2 | Student vs admin roles | **Firebase Auth custom claims** (set via Cloud Functions) | Your app already has separate `ADMIN001`/`ADMIN002` accounts — claims map onto that cleanly and can't be forged client-side |
| 3 | Structured data | **Cloud Firestore** | Your models are document-shaped already (`Event` embeds `messages`, `attendeeIds`, `pendingJoiningIds`). Realtime listeners replace `notifyListeners()` naturally |
| 4 | Images & documents | **Firebase Storage** | `Issue.imagePaths` and `Event.approvalLetterPath` currently hold **local device paths**, which already fail across devices |
| 5 | QR verification | **Cloud Functions** (callable) | `verifyAndMarkAttendance()` runs on the phone today, so a forged QR cannot be detected. Must move server-side |
| 6 | Approval notifications | **Firebase Cloud Messaging** | Covers the "email notifications" roadmap item; works while the app is closed |
| 7 | Access control | **Firestore Security Rules** | Replaces `canAccessFilePath()` and `canPerformAction()`, which are client-side and therefore advisory only |

### Alternative: Supabase

Swap in **Supabase Auth + Postgres + Supabase Storage + Realtime** if you want SQL, need to avoid vendor lock-in, or the university requires self-hosting. Every phase below applies unchanged — only the client library and the data-mapping code differ. Pick one now; mixing later is expensive.

---

## Phase 0 — Foundation

**Goal:** Firebase wired in, app still runs on mock data.

1. Create the Firebase project (enable Auth, Firestore, Storage).
2. `dart pub global activate flutterfire_cli`, then `flutterfire configure`.
3. Add `firebase_core`; call `Firebase.initializeApp()` in `main.dart` before `runApp`.
4. Commit `firebase_options.dart`; **add `google-services.json` to `.gitignore`**.

**Files:** `pubspec.yaml`, `lib/main.dart`, `android/`
**Done when:** app launches on device with Firebase initialised and no behaviour change.
**Risk:** Low. **Rough effort:** half a day.

---

## Phase 1 — Authentication

**Goal:** Real accounts. This is the phase you asked to do first, and it's correctly ordered — it's the most self-contained.

### 1a. Migrate sign-in

- Add `firebase_auth`.
- Rewrite `AuthService.login()` to call `signInWithEmailAndPassword`.
- **Student IDs are not emails.** Map `S001` → `s001@student.city.edu.my` (the convention `auth_service.dart:222` already uses), or add a `users` lookup keyed by student ID. Decide this before writing code.
- Move `UserProfile` out of the hardcoded maps into a Firestore `users/{uid}` document.

### 1b. Delete the plaintext password path

- Remove `saveCredentials()` / `loadSavedCredentials()` / `clearSavedCredentials()`. Firebase Auth persists sessions natively — "Remember Me" becomes the default, not a stored password.
- **Do not port `shared_preferences` password storage.** It is the single worst security issue in the codebase.

### 1c. Roles

- Give admins the custom claim `{admin: true}`.
- `AppState.isAdmin` reads the claim, not a login flag.
- `switchRole()` currently re-logs-in with admin credentials — keep that UX, but it must be a real second Firebase account.

### 1d. Registration flow

- `submitRegistration()` writes to `registrations/{id}` with status `Pending`.
- `approveRegistration()` becomes a **Cloud Function** that creates the Auth user and sets claims — a client cannot be trusted to create accounts.
- Delete `StudentRegistration.password`; the student sets their own via an invite/reset link.

**Files:** `lib/services/auth_service.dart`, `lib/services/app_state.dart`, `lib/screens/auth/*` (709 lines), `lib/screens/admin/admin_registrations_screen.dart`
**Done when:** you can register → admin approves → new account signs in, app restart keeps the session, and no password exists in `shared_preferences`.
**Risk:** Medium — touches every screen via `AppState.userId`.
**Rough effort:** 3–5 days.

---

## Phase 2 — Async refactor (do this before any data migration)

**Goal:** Convert `DataService` to `Future`/`Stream` **while still on mock data.**

This phase ships no features and is the one most likely to be skipped. Don't skip it.

`documentation.md:823` claims migration is possible "without significant UI changes." That holds for writes — `void createEvent()` → `Future<void>` barely affects an `onPressed`. It does **not** hold for reads. Methods like `getEventAttendees()` and `getJoiningRequestsForEvent()` return a `List` **synchronously inside `build()`** (`my_events_screen.dart:202-204`). A network call cannot do that, so each becomes a `StreamBuilder` with loading and error states the UI does not currently have.

Doing this on mock data means you debug *one* thing — the async plumbing — instead of async plus network plus rules simultaneously.

1. Define repository interfaces (`AuthRepository`, `EventRepository`, `IssueRepository`, `LockerRepository`, `LostFoundRepository`) with `Future`/`Stream` signatures.
2. Make `DataService` implement them, still backed by the in-memory lists.
3. Update call sites to `await` / `StreamBuilder`. Add loading and error UI.

**Known call sites needing `StreamBuilder`:** `events_screens.dart`, `manage_event_screen.dart`, `my_events_screen.dart`, `lost_found_screens.dart`.

**Done when:** app behaves identically, but every data read is async.
**Risk:** High churn, low logic risk — mechanical but wide.
**Rough effort:** 5–8 days.

---

## Phase 3 — Data storage, domain by domain

**Goal:** Replace the mock implementation one domain at a time. Order is smallest blast radius first.

| Order | Domain | Firestore shape | Screen LOC | Notes |
|---|---|---|---|---|
| 3a | **Issues** | `issues/{id}` + `history` subcollection | 529 | Simplest CRUD — use it to prove the pattern |
| 3b | **Lost & Found** | `lostReports`, `foundReports`, `matches` | 999 | `_checkForMatches()` should become a Cloud Function trigger |
| 3c | **Lockers** | `lockers/{id}`, `bookings`, `lockerIssues`, `history` sub | 1,383 | Heaviest state machine; QR collection/return flows |
| 3d | **Events** | `events/{id}` + `joinings`, `messages`, `roles` subs | 3,772 (3 files) | Largest and most nested — do it last, with the pattern proven |

**Merge `allEvents` + `pendingEvents` into one `events` collection filtered by `status`.** Keeping two lists is what caused the original "events disappear from My Events" bug.

**Done when:** data survives app restart and appears across two devices.
**Risk:** Medium per domain, isolated.
**Rough effort:** 2–4 days per domain (~10–14 days total).

---

## Phase 4 — File storage

**Goal:** Images and documents work across devices.

- Upload on capture in `issues_screens.dart`; store the **download URL**, not the local path.
- Same for `Event.approvalLetterPath` / `approvalLetterName`.
- Replace `canAccessFilePath()` with Storage Security Rules.
- Migrate `photo_service.dart` (54 lines) to upload rather than copy locally.

**Risk:** Low. **Rough effort:** 2–3 days.

---

## Phase 5 — Server-side integrity

**Goal:** Close the gaps a client cannot close itself.

1. **QR verification → callable Cloud Function.** Today `verifyAndMarkAttendance()` (`data_service.dart:976`) validates on-device; anyone can forge a ticket. The function should verify and mark attendance atomically.
2. **Move `_generateQRCode()` server-side** so codes are unguessable and single-use.
3. **Firestore Security Rules** — students read/write only their own documents; status transitions restricted to admins. `canPerformAction()` stays as a UI hint only.
4. **FCM** for approval/rejection notifications.

**Risk:** Medium. **Rough effort:** 4–6 days.

---

## 3. Cross-cutting issues to fix during migration

- **Client-generated IDs.** `S001`, `ISS-001`, `QR-{eventId}-{studentId}-{random}` are generated on-device and can collide. Use Firestore auto-IDs or UUIDs.
- **Denormalized arrays.** Concurrent approvals to `attendeeIds` / `pendingJoiningIds` will clobber each other. Use `FieldValue.arrayUnion` or a transaction.
- **`_showEditDialog` field loss.** `my_events_screen.dart:713-723` rebuilds `Event` with only 9 fields, dropping `hostStudentId`, `messages`, `attendeeIds`, and more. On Firestore this becomes silent permanent data loss. **Fix before Phase 3d** — copy the field-preservation pattern from `_showResubmitDialog`.
- **Dates are strings.** Stored as `YYYY-MM-DD` text; migrate to Firestore `Timestamp` for correct sorting and range queries.
- **Deprecated API.** Two `withOpacity()` calls remain amid `withValues(alpha:)` usage.

---

## 4. Summary timeline

| Phase | Deliverable | Rough effort | Risk |
|---|---|---|---|
| 0 | Firebase initialised | 0.5 day | Low |
| 1 | **Authentication live** | 3–5 days | Medium |
| 2 | Async refactor on mock data | 5–8 days | High churn |
| 3 | **Data storage live** (4 domains) | 10–14 days | Medium |
| 4 | File storage | 2–3 days | Low |
| 5 | Server-side integrity + rules | 4–6 days | Medium |

**Total: roughly 5–7 weeks of focused work.** Estimates are rough and assume one developer already familiar with the codebase.

### Recommended sequence

```
Phase 0 → Phase 1 (auth) → Phase 2 (async) → Phase 3a → 3b → 3c → 3d → Phase 4 → Phase 5
```

Phase 2 is the one to protect. Every phase after it is mechanical; skipping it makes Phase 3 a rewrite instead of a swap.

---

## 5. Immediate next step

Phase 1 depends on one decision that is cheaper to make now than to reverse later:

> **How do student IDs map to Firebase Auth identities?**
> Synthesise emails (`S001` → `s001@student.city.edu.my`, matching the existing convention at `auth_service.dart:222`), or keep a `users` collection keyed by student ID and look up the email before sign-in?

Synthesising is simpler; the lookup table is more flexible if real student emails differ from the pattern. Everything in Phase 1 follows from this answer.
