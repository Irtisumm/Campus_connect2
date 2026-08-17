# Profile ↔ Firebase — Multi-Agent Handoff

> Shared ledger for the Profile-Firebase work. Every agent reads this before
> starting and appends a report before finishing. No agent may silently change
> the profile schema, remove functionality, deploy rules, or change auth
> behavior without recording it here.

## Project reality (read this first)

The app is **already** a Firebase-backed Flutter app — this work is mostly
finishing the Profile screen's last mock layer, not a greenfield build.

- **Firebase services**: `firebase_core ^4.12.1`, `firebase_auth ^6.5.6`,
  `cloud_firestore ^6.7.1`, `firebase_storage ^13.4.5`. Initialized in
  `lib/main.dart` via `DefaultFirebaseOptions.currentPlatform`.
- **Platform config**: Android only (`lib/firebase_options.dart`,
  project `campus-connect-ce3e8`). This is the standard non-secret client
  config (API key / app id are designed to ship in client code). No
  service-account JSON or Admin SDK key is present — and none may be added.
- **State management**: `provider ^6.0.0`. `AppState` (single
  `ChangeNotifier`) is the only object the widget tree talks to. No Firebase
  type crosses the `AppState` boundary.
- **Routing**: `go_router ^14.0.0`. `/profile` is auth-guarded
  (`appState.isAuthenticated`). Public routes: `/`, `/login`, `/register`.
- **Localization**: **none**. No `supportedLocales`, no
  `localizationsDelegates`, no `flutter_localizations`. `intl` is used only
  for date formatting. → The Language feature persists a preference only;
  it must not invent a second localization system (see contract §6).

---

## Agent 1 — Project & hard-coded-data audit

### Files inspected
- `lib/screens/profile/profile_screen.dart` (the active `ProfileScreen` + dead
  `_LegacyProfileScreen.build` + shared dialog methods)
- `lib/models/user_profile.dart`, `lib/models/auth_result.dart`
- `lib/services/auth_service.dart`, `user_service.dart`, `admin_service.dart`,
  `app_state.dart`
- `lib/screens/auth/login_screen.dart`, `registration_screen.dart`
- `lib/main.dart` (Firebase init + router)
- `lib/firebase_options.dart`, `firebase.json`, `.firebaserc`
- `firestore.rules` (679 lines; `users/{uid}` block read in full)
- `test/profile_layout_smoke_test.dart` + `test/goldens/profile_screen.png`

### What is already correct (do NOT rebuild)
1. `UserProfile` is a Firestore model keyed by Firebase UID. Fields: `uid`,
   `studentId`, `fullName`, `authEmail` (immutable), `email` (editable),
   `faculty`, `role` (student/admin), `status` (Pending/Active/Rejected),
   `phone`, `createdAt`/`updatedAt` (`FieldValue.serverTimestamp()`).
   `copyWith` deliberately omits `authEmail`, `role`, `uid`, `studentId`
   (protected). `toCreateMap()` never includes a password.
2. `AuthService` = Firebase Auth only; no password persistence; Remember-Me
   stores the identifier only and scrubs a legacy plaintext-password key.
   `deleteCurrentAccount()` exists for registration rollback.
3. `UserService.createProfile` throws on failure → `AppState.registerStudent`
   rolls back the Auth account (delete or sign-out) so no orphan credential
   survives. Registration is retry-safe (re-register is allowed because the
   failed credential is gone).
4. `AppState.loginUser` fetches the profile after sign-in and gates on
   status/role. `_onUidChanged` restores the session on cold start / token
   refresh and applies the same gates. `logout` nulls `_firebaseUid` +
   `_profile` and cancels the listener in `dispose`.
5. `firestore.rules` `users/{uid}`:
   - `create`: self only, `role=='student'`, `status=='Pending'`,
     `authEmail==request.auth.token.email`, no `password` key. → A student
     cannot self-assign admin or self-approve.
   - `update` (self): `authEmail/role/status/uid/studentId` must be unchanged,
     no `password` key. → protected identity fields immutable from client.
   - `update` (admin): status only, identity fields unchanged.
   - `get`: self or admin. `list`: `limit<=1` (ID→email lookup) or admin.
   - `delete`: false.
   These already satisfy every security requirement in the brief.

### Hard-coded profile values still in production code (TO REMOVE)
Active `ProfileScreen.build` (`profile_screen.dart`):
- L60 `studentId = profile?.userId ?? appState.userId ?? 'GUEST'`
- L62 `name = profile?.name ?? (isAdmin ? 'Administrator' : 'Guest User')`
- L64 `email = profile?.email ?? (isAdmin ? 'admin@city.edu.my' : 'guest@student.city.edu.my')`
- L65 `programme = profile?.programme ?? 'General Studies'`
- L72 `role = isAdmin ? 'Administrator' : 'Student'` (derived, acceptable)
Dead `_LegacyProfileScreen.build` (L808–L815): the same five fallbacks.

### Fake / dead Profile actions (TO MAKE REAL)
- **Change Password** (`_showChangePasswordDialog`): only checks
  match+length and toasts success. Does NOT call Firebase. → wire to
  `reauthenticateWithCredential` + `updatePassword`.
- **Notification Preferences** (`_showNotificationSettings`): four toggles
  hardcoded `true`, `onChanged` is a no-op, "Save" only toasts. → persist to
  Firestore on the user's own doc; load current values.
- **Language**: toasts "Language settings coming soon"; row hardcodes
  'English'. → persist `preferredLanguage` (English only; no i18n system to
  apply).
- **Help & Support**: toast only. → open `mailto:` via `url_launcher`
  (already a dependency).
- **Privacy Policy**: toast only. → show a real policy dialog.
- **About**: already a real dialog. Keep.

### Other hard-coded notes (out of Profile scope, flagged only)
- `login_screen.dart` L274/L277/L377: "Demo credentials: S001 / pass123" and
  "ADMIN001 / admin123" hints. These are login hints, not profile data; left
  as-is unless explicitly requested.

### Firebase Console steps the owner must personally approve
- None required to *build/run*. The project `campus-connect-ce3e8` already has
  Auth + Firestore enabled. Rules are **not** deployed by code; the owner must
  run `firebase deploy --only firestore:rules` (or use the Console) to publish
  the reviewed `firestore.rules`. We will not deploy production rules from
  code without the owner's go-ahead.

---

## Agent 2 — Profile data contract & permissions

### Final field set (Firestore `users/{uid}`)
| field | type | student-editable | protected | notes |
|---|---|---|---|---|
| `uid` | string | ❌ | ✔ | == Auth UID; == doc id |
| `studentId` | string | ❌ | ✔ | campus ID, uppercase |
| `authEmail` | string | ❌ | ✔ | == Auth token email; immutable |
| `fullName` | string | ✔ | — | Edit Profile |
| `email` | string | ✔ | — | display/contact only |
| `faculty` | string | ✔ | — | shown as "Programme" |
| `phone` | string | ✔ | — | optional |
| `role` | 'student'\|'admin' | ❌ | ✔ | set at create; rules enforce 'student' |
| `status` | Pending\|Active\|Rejected | ❌ | ✔ | admin-controlled |
| `notificationPrefs` | map<string,bool> | ✔ (own keys) | — | **NEW** |
| `preferredLanguage` | string | ✔ | — | **NEW**; 'English' default |
| `createdAt` | server timestamp | ❌ | — | set once at create |
| `updatedAt` | server timestamp | ❌ | — | touched on every write |

A normal student may **never** edit `role`, `status`, `uid`, `studentId`, or
`authEmail`. These are enforced both in `copyWith`/`UserService` and in
`firestore.rules` (self-update requires each protected field unchanged).

### Profile lifecycle
- **Create once after registration**: `AppState.registerStudent` already
  creates the Auth credential then `users/{uid}` in one flow; on Firestore
  failure the Auth account is deleted (rollback). No duplicate record can
  form because a re-register after rollback starts fresh. ✔ retry-safe.
- **Load on start/relogin**: `_onUidChanged` (cold start) and `loginUser`
  (sign-in) both `fetchProfile(uid)`. Identity comes **only** from the Auth
  `uid` — never from a screen param or text field. ✔
- **Missing/inaccessible profile**: if `fetchProfile` returns null (missing
  doc) or throws (permission/offline), the screen shows a **retry/recovery
  state** — never another student's or hard-coded fallback data. (loginUser
  already signs out + returns a clear message for a missing profile.)
- **After edit**: `AppState.updateCurrentUserProfile` already refreshes
  `_profile` from the service result and `notifyListeners()`. The card
  rebuilds from saved data. ✔
- **After logout**: `logout` nulls `_firebaseUid` + `_profile`; `dispose`
  cancels `_authSub`. No prior-user data lingers. ✔

### Loading / error / retry states (new, minimal)
`AppState` gains a `profileLoadStatus` enum: `idle | loading | ready | missing
| error`. Set: `loading` before fetch in `_onUidChanged`; `ready`/`missing`/
`error` after; `idle` on logout. A `retryLoadProfile()` re-fetches for the
current uid. The Profile screen's **card area** adapts:
- profile present → real data (unchanged visuals).
- loading → "Loading…" placeholders; Edit disabled.
- missing/error (signed in) → "Couldn't load your profile" + Retry; Edit
  disabled.
- not signed in (test/unauth) → neutral "Sign in to view your profile" card.
The Settings/About/Logout sections remain visible so the layout shell is
preserved (and the layout smoke test keeps finding `SETTINGS` + version).

### Settings actions contract
1. **Change Password**: `AuthService.changePassword(current, new)` =
   reauthenticate with `EmailAuthProvider` (email from `currentUser.email` ==
   `authEmail`) then `updatePassword`. Map: wrong-current → "Incorrect
   password.", weak → "Password must contain at least six characters.",
   requires-recent-login → sign back in. Never log/cache passwords.
2. **Notification Preferences**: new `notificationPrefs` map with keys
   `lostFoundMatches`, `eventUpdates`, `issueStatus`, `lockerReminders`
   (default all `true`). Save/load via `UserService.updateNotificationPrefs`.
3. **Language**: new `preferredLanguage` (default `'English'`). Save/load via
   `UserService.updatePreferredLanguage`. English is the **only** supported
   value (no i18n system exists). The preference persists and is reflected on
   the row + dialog; no UI translation is attempted.
4. **About / Help / Privacy**: About stays a dialog. Help opens
   `mailto:support@student.city.edu.my` via `url_launcher`. Privacy shows a
   real policy dialog. No dead buttons.
5. **Logout**: unchanged flow (confirm → `appState.logout()` → `context.go('/login')`).

### Compatibility note
New fields (`notificationPrefs`, `preferredLanguage`) are optional with
defaults in `fromMap`, so existing user documents load without migration. The
existing self-update rule already permits adding/changing non-protected
fields, so no rules change is required for the new fields.

---

### Agent 1 + 2 sign-off
Audit complete; contract approved. Proceeding to rules verification (A3),
data layer (A4), screen (A5), tests (A6), final (A7).

---

## Agent 3 — Security rules verification & rule-test harness

### Work completed
Verified that the existing `firestore.rules` already satisfy every security
requirement in the brief. No rules change was needed — the self-update rule
permits adding non-protected fields (`notificationPrefs`,
`preferredLanguage`) because it only enforces immutability of `authEmail`,
`role`, `status`, `uid`, `studentId` and rejects a `password` key.

Built a portable Firestore security-rule test harness using
`@firebase/rules-unit-testing` v5 + `firebase emulators:exec`.

### Files inspected / changed
- **Inspected**: `firestore.rules` (679 lines; full `users/{uid}` block).
  Confirmed: `create` enforces `role=='student'`, `status=='Pending'`,
  `authEmail==request.auth.token.email`, no `password` key; `update` (self)
  enforces protected fields unchanged + no `password`; `get` self-or-admin;
  `list` `limit<=1` or admin; `delete` false.
- **Changed**: `firebase.json` — added `emulators.firestore.port` +
  `singleProjectMode` (local-test config only; does not affect production).
- **Created**: `tools/rules-test/package.json` (devDeps:
  `@firebase/rules-unit-testing ^5.0.1`, `firebase ^12.0.0`; test script
  wraps in `firebase emulators:exec`).
- **Created**: `tools/rules-test/rules_test.mjs` — 14 test cases.

### Confirmed fields / permissions
All protected fields (`uid`, `studentId`, `authEmail`, `role`, `status`)
are immutable from the client. Editable fields (`fullName`, `email`,
`faculty`, `phone`, `notificationPrefs`, `preferredLanguage`) are writable
by the document owner only. No `password` key may be written.

### Firebase / database decisions
- **No rules change.** The existing `firestore.rules` already enforce
  least-privilege. New fields are permitted by the existing self-update rule.
- **No production data touched.** Tests run against the local Firestore
  emulator only; no project credentials are used.

### Tests run / results
`npm test` in `tools/rules-test/` → **14 passed, 0 failed**:
1. ✓ denies unauthenticated read
2. ✓ allows student A own read
3. ✓ allows student A editable-field update (incl. notificationPrefs, preferredLanguage)
4. ✓ denies student A reading student B
5. ✓ denies student A writing student B
6. ✓ denies self-assign admin role
7. ✓ denies changing protected studentId
8. ✓ denies changing protected authEmail
9. ✓ denies writing password field
10. ✓ denies changing own status
11. ✓ allows valid registration create (student/Pending/authEmail==token)
12. ✓ denies self-promote create (role=admin)
13. ✓ denies self-approve create (status=Active)
14. ✓ denies authEmail-mismatch create

### Security / privacy checks
- No service-account JSON, Admin SDK key, or private key in test code or
  commits. `tools/rules-test/` uses only the public emulator.
- No production credentials, tokens, or real user data in test fixtures.
- Test fixture emails are synthetic (`a.student@city.edu.my`, etc.).

### Remaining risks
None for rules. The `allow list: if request.query.limit <= 1` rule (pre-
existing, for the student-ID→email login lookup) is documented in
`firestore.rules` with a trade-off note; not in scope for this work.

### Exact next action
Agent 4: implement the data-layer methods (`UserProfile` fields,
`UserService` update methods, `AuthService.changePassword`,
`AppState` wrappers + `profileLoadStatus`).

---

## Agent 4 — Data layer implementation

### Work completed
Added the new profile fields, Firestore write methods, real change-password,
and `profileLoadStatus` lifecycle to the data layer. No existing
functionality was removed; no schema-breaking change was made.

### Files changed
- **`lib/models/user_profile.dart`**: Added `notificationPrefs`
  (`Map<String,bool>`) and `preferredLanguage` (`String`) fields; static
  consts `defaultNotificationPrefs` (all four keys `true`) and
  `defaultLanguage = 'English'`; updated constructor defaults, `copyWith`
  (new params), `toCreateMap` (both fields), `fromMap` (merges
  `notificationPrefs` over defaults via `_readPrefs`, reads
  `preferredLanguage` via `_readLanguage`). Added
  `enum ProfileLoadStatus { idle, loading, ready, missing, error }` after
  `AccountStatus`.
- **`lib/services/user_service.dart`**: Added
  `updateNotificationPrefs({uid, prefs})` and
  `updatePreferredLanguage({uid, language})` — both write to
  `users/{uid}` with `FieldValue.serverTimestamp()` `updatedAt`; throw
  `AuthFailure` on `FirebaseException`.
- **`lib/services/auth_service.dart`**: Added
  `changePassword({currentPassword, newPassword})` — builds
  `EmailAuthProvider.credential` from `user.email` (== `authEmail`),
  `reauthenticateWithCredential`, then `updatePassword`. Validates
  `newPassword.length >= 6`. Throws `AuthFailure` with user-safe messages
  for wrong-current / weak / requires-recent-login. Never logs or caches
  passwords.
- **`lib/services/app_state.dart`**: Added `_profileStatus` field +
  `profileLoadStatus` getter (exported `ProfileLoadStatus`); set status in
  `_onUidChanged` (loading → ready/missing/error), `loginUser` (ready on
  success), `logout` (idle); added `retryLoadProfile()`; added
  `changePassword()` wrapper returning `({bool success, String? message})`;
  added `updateNotificationPrefs(Map<String,bool>)` and
  `updatePreferredLanguage(String)` wrappers that refresh `_profile` via
  `copyWith` + `notifyListeners`; added
  `@visibleForTesting factory AppState.forTesting({profile, status})`.

### Confirmed fields / permissions
| field | student-editable | protected |
|---|---|---|
| `uid`, `studentId`, `authEmail`, `role`, `status` | ❌ | ✔ |
| `fullName`, `email`, `faculty`, `phone` | ✔ | — |
| `notificationPrefs`, `preferredLanguage` | ✔ (own) | — |

`copyWith` deliberately omits `authEmail`, `role`, `uid`, `studentId`.

### Firebase / database decisions
- New fields are optional with defaults in `fromMap` — existing user
  documents load without migration.
- `toCreateMap` includes the new fields with defaults so newly registered
  accounts get them from the start.
- All writes use `FieldValue.serverTimestamp()` for `updatedAt`.

### Security / privacy checks
- `changePassword` never logs, caches, or stores passwords.
- All UID arguments come from `_firebaseUid` (Auth UID), never from a
  screen parameter or text field.
- No secrets, tokens, or service-account keys in any changed file.

### Remaining risks
None at the data layer.

### Exact next action
Agent 5: wire the Profile screen to `profileLoadStatus` + real dialog actions.

---

## Agent 5 — Screen integration

### Work completed
Removed every hard-coded profile value from the production Profile screen.
Replaced the fake/dead dialogs with real Firebase-backed actions. Added
honest loading / error / retry states. Preserved the existing design,
layout, colors, icons, scroll behavior, back button, Edit button, Settings,
About & Help, and Logout.

### Files changed
- **`lib/screens/profile/profile_screen.dart`** (major rewrite):
  - **Removed imports**: `flutter_animate`, `widgets/common` (became unused
    after dead-code removal).
  - **Added import**: `url_launcher` (for `mailto:` Help link).
  - **Removed hard-coded fallbacks**: deleted the `studentId = … ?? 'GUEST'`,
    `name = … ?? 'Guest User'`, `email = … ?? 'guest@student.city.edu.my'`,
    `programme = … ?? 'General Studies'` derivation chain. The card now
    shows real profile data or a `_ProfileLoadStateCard`.
  - **`_ProfileLoadStateCard`** (new widget): shows a spinner for `loading`,
    `cloud_off` icon + Retry button for `error`, lock icon + "Sign in to
    view your profile" for `idle`, "Profile not found" for `missing`.
  - **`_CombinedProfileCard`**: renders the real `UserProfile` fields
    (`fullName`, `email`, `faculty`, `studentId`) — no hard-coded values.
  - **Settings rows rewired**:
    - Change Password → `_showChangePasswordDialog(context, appState)`:
      `StatefulBuilder` with submitting state; calls
      `appState.changePassword(current, new)`; user-safe toasts for
      success / mismatch / weak / wrong-current / error.
    - Notification → `_showNotificationSettings(context, appState)`:
      loads current prefs from `profile.notificationPrefs`; four toggles
      (const `<(String,String)>[...]` label→key pairs); saves via
      `appState.updateNotificationPrefs`.
    - Language → `_showLanguageDialog(context, appState)`: trailing shows
      `profile?.preferredLanguage ?? defaultLanguage`; ListTile + check
      icon (no deprecated `RadioListTile`); saves via
      `appState.updatePreferredLanguage`.
  - **About & Help rewired**:
    - Help → `_showHelpDialog(context)`: `mailto:support@student.city.edu.my`
      via `canLaunchUrl` / `launchUrl`; toast fallback if no mail app.
    - Privacy → `_showPrivacyDialog(context)`: real policy text in a
      `const SingleChildScrollView` + `Column`.
    - About → `_showAboutDialog(context)`: unchanged real dialog.
  - **Logout** → `_showLogoutDialog(context, appState)`: unchanged confirm →
    `appState.logout()` → `context.go('/login')`.
  - **`_LegacyProfileScreen` → abstract class**: the dead `build` method
    (which held the same five hard-coded fallbacks) was removed. The
    shared dialog methods are inherited by the real `ProfileScreen`.

### Files inspected (not changed)
- `lib/theme/app_theme.dart` — colors/gradients used by the card and
  dialogs (unchanged).
- `lib/widgets/common.dart` — confirmed no profile-specific hard-coded
  values; import removed from profile_screen (was unused).

### Confirmed fields / permissions
The screen reads only from `appState.profile` (a `UserProfile?`) and
`appState.profileLoadStatus`. No screen parameter, local variable, or text
field is used to choose which profile to load — identity comes from
`_firebaseUid` (Auth UID) inside `AppState`.

### Firebase / database decisions
- All Profile actions call `AppState` methods, which in turn call
  `UserService` / `AuthService` → Firestore / Firebase Auth. No direct
  Firestore calls from the screen.
- `notificationPrefs` and `preferredLanguage` are written to the user's own
  `users/{uid}` doc only.

### Security / privacy checks
- No passwords, tokens, emails, or paths are logged.
- `mailto:` link opens the user's own mail client — no data is sent to a
  third-party service.
- No hard-coded profile data ships in production UI or state.

### Remaining risks
- `login_screen.dart` has "Demo credentials: S001 / pass123" /
  "ADMIN001 / admin123" hints (login screen, not profile; out of scope;
  flagged in Agent 1 report).

### Exact next action
Agent 6: write/rewrite tests, regenerate golden, run rules tests.

---

## Agent 6 — Testing & review

### Work completed
Rewrote the profile layout smoke test with real-data fixtures. Built and ran
the Firestore security-rule test harness. Verified no hard-coded profile
values remain in production code.

### Files changed
- **`test/profile_layout_smoke_test.dart`** (rewritten): 5 tests using a
  `_fakeProfile` fixture (synthetic data inside the test file only, as the
  brief permits) + `AppState.forTesting` factory:
  1. Real data renders: asserts 'TEST STUDENT', email, faculty, Back,
     SETTINGS; golden match; scroll → 'Campus Connect v3.0'.
  2. Unsigned-in state: asserts 'Sign in to view your profile.', no
     'TEST STUDENT' / 'Guest User' / 'guest@student.city.edu.my'.
  3. Load-failure retry: asserts "couldn't load your profile" + 'Retry'.
  4. Change-password validation: fills 3 fields, taps 'Change', asserts
     'New passwords do not match' toast.
  5. Notification preferences: asserts 4 labels + 4 Switches render.
- **`test/goldens/profile_screen.png`** (regenerated): matches the new
  card layout with real fixture data.
- **`tools/rules-test/`** (created): package.json + rules_test.mjs (14
  rule tests; see Agent 3 report).

### Tests run / results
- `flutter test` → **115 passed, 0 failed** (5 profile + 110 existing).
- Firestore rule tests (`npm test` in `tools/rules-test/`) → **14 passed,
  0 failed**.

### Hard-coded-value scan
`grep` for `Guest User`, `guest@student`, `GUEST`, `General Studies` in
`lib/screens/profile/profile_screen.dart` → only matches are in doc comments
describing what was removed. No production code holds hard-coded profile
data.

### Security / privacy checks
- Test fixtures use synthetic data only (uid `test-uid-001`, email
  `test.student@city.edu.my`, etc.) — no real user data.
- No service-account JSON or secrets in test files.
- Rules tests run against the local emulator only.

### Remaining risks
None.

### Exact next action
Agent 7: `flutter analyze`, `flutter test`, `flutter build apk`, then
final report.

---

## Agent 7 — Final integration & report

### Work completed
Ran the full quality gate: static analysis, test suite, and a real APK
build. Confirmed the Definition of Done.

### Commands run / results
| step | command | result |
|---|---|---|
| Static analysis | `flutter analyze` | **0 errors, 0 warnings** in changed files (18 pre-existing warnings in unrelated modules: events, lockers, lost_found, issues — all `withOpacity` deprecation or unused-element) |
| Tests | `flutter test` | **115 passed, 0 failed** |
| Rules | `npm test` (tools/rules-test) | **14 passed, 0 failed** |
| Build | `flutter build apk --debug` | **Success** — `build/app/outputs/flutter-apk/app-debug.apk` |

### Definition of Done — checklist
- [x] Account creates one profile record (existing `registerStudent` flow).
- [x] Profile loads on relogin / cold start / token refresh (`_onUidChanged`).
- [x] No hard-coded profile data in production UI or state.
- [x] Student A cannot access or update student B's profile (rule tests 4–5).
- [x] Student cannot self-assign admin or change protected identity (rule
      tests 6–10; `copyWith` omits protected fields).
- [x] Edit Profile saves and refreshes (`updateCurrentUserProfile` →
      `notifyListeners`).
- [x] Notification preferences persist after relogin
      (`notificationPrefs` in `toCreateMap`/`fromMap`/`updateNotificationPrefs`).
- [x] Language preference persists after relogin (`preferredLanguage` in
      `toCreateMap`/`fromMap`/`updatePreferredLanguage`).
- [x] Change Password works safely (`reauthenticateWithCredential` +
      `updatePassword`; user-safe messages; no password logging).
- [x] Logout works and clears data (`logout` nulls `_firebaseUid` +
      `_profile`; `dispose` cancels listener).
- [x] Design remains clean / scrollable / responsive / accessible (unchanged
      layout, colors, icons; loading/error/retry card is minimal).
- [x] Database rules have passing allowed/denied tests (14/14).
- [x] Formatting / static analysis / tests / build all pass.

### Final report

#### All files changed
| file | change |
|---|---|
| `lib/models/user_profile.dart` | +`notificationPrefs`, +`preferredLanguage`, +`ProfileLoadStatus` enum, defaults, `copyWith`/`toCreateMap`/`fromMap` updates |
| `lib/services/user_service.dart` | +`updateNotificationPrefs`, +`updatePreferredLanguage` |
| `lib/services/auth_service.dart` | +`changePassword` (reauthenticate + updatePassword) |
| `lib/services/app_state.dart` | +`profileLoadStatus`, +`retryLoadProfile`, +`changePassword`/`updateNotificationPrefs`/`updatePreferredLanguage` wrappers, +`forTesting` factory |
| `lib/screens/profile/profile_screen.dart` | Removed hard-coded values; +`_ProfileLoadStateCard`; rewired all dialogs to real Firebase actions; +`url_launcher` import; `_LegacyProfileScreen` → abstract |
| `test/profile_layout_smoke_test.dart` | Rewritten: 5 tests with real-data fixture |
| `test/goldens/profile_screen.png` | Regenerated |
| `firebase.json` | +emulator config (local-test only) |
| `tools/rules-test/package.json` | Created (rules test harness) |
| `tools/rules-test/rules_test.mjs` | Created (14 rule test cases) |
| `docs/profile_firebase_handoff.md` | This file |

#### Firebase services used
- **Firebase Auth** — authentication, reauthentication for change-password,
  session restore via `uidChanges()`.
- **Cloud Firestore** — `users/{uid}` profile documents (CRUD, security
  rules).
- **Firebase Storage** — already used elsewhere in the app; not touched by
  this work.

#### Fields stored (Firestore `users/{uid}`)
`uid`, `studentId`, `authEmail`, `fullName`, `email`, `faculty`, `phone`,
`role`, `status`, `notificationPrefs` (map: `lostFoundMatches`,
`eventUpdates`, `issueStatus`, `lockerReminders`), `preferredLanguage`,
`createdAt`, `updatedAt`.

#### Fields editable by the student
`fullName`, `email`, `faculty`, `phone`, `notificationPrefs` (own keys),
`preferredLanguage`.

#### Rule test results
14 passed, 0 failed (see Agent 3 report for the full case list).

#### App test results
115 passed, 0 failed (5 profile smoke tests + 110 existing tests).

#### Remaining limitations
1. **Language**: English only. The preference persists to Firestore and is
   reflected in the UI, but no localization system exists and none was
   invented.
2. **Login demo hints**: `login_screen.dart` shows "Demo credentials: S001 /
   pass123" and "ADMIN001 / admin123". These are login-screen hints, not
   profile data; out of scope for this work.
3. **Firestore rules deployment**: The reviewed `firestore.rules` are in
   the repo but are **not** deployed by this code. The owner must deploy
   them (see Firebase Console step below).

#### Firebase Console steps the owner must personally approve
1. **Deploy rules**: Run `firebase deploy --only firestore:rules` (or use
   the Firebase Console) to publish the reviewed `firestore.rules` to the
   `campus-connect-ce3e8` project. No code change deploys rules.
2. No other Console steps required — Auth and Firestore are already
   enabled; the new fields are optional with defaults so no migration is
   needed.
