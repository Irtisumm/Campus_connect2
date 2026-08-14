# Create Event Redesign — Handoff

Source of truth for all later agents in the Create Event screen redesign. Compiled by Agent 1 (Repository and Contract Auditor). Read-only audit; no production file was modified.

---

## Frozen contract

This section is authoritative. Later agents MUST NOT change anything listed here unless the lead explicitly re-scopes it.

### Route and class identity

| Item | Value |
|---|---|
| Route string | `/events/create` |
| Router declaration | `lib/main.dart:127` — `GoRoute(path: '/events/create', builder: (_, __) => const CreateEventScreen())` |
| Widget class | `CreateEventScreen` (StatefulWidget) |
| State class | `_CreateEventState` |
| Source file | `lib/screens/events/events_screens.dart` |
| Exact line range | **1201 – 1610** (class `CreateEventScreen` at 1201; `_CreateEventState` 1206–1610) |
| Next screen in same file | `AdminElectionsMgmtScreen` begins at line **1612** (comment) / **1613** (class). Do NOT touch anything at or after 1612. |
| Entry points | `lib/screens/events/events_hub_screen.dart:144` (`CreateEventCta`) and `:186` (`EventQuickAction` "Create Event"), both `context.push('/events/create')` |

### Payload / JSON field keys (the `events` document)

The wire schema is defined by `Event.toMap()` in `lib/models/event.dart` (lines 170–203). `id` is deliberately NOT in the map — the Firestore document key is the identity. Exact keys and types:

| Key | Type | Notes |
|---|---|---|
| `title` | String | required |
| `date` | String | display string `'YYYY-MM-DD'` |
| `time` | String | display string `'HH:MM'` |
| `location` | String | required |
| `category` | String | one of `Academic / Sport / Club / General` |
| `organizer` | String | required |
| `description` | String | required |
| `status` | String | born `'Pending'` (enforced in AppState + rules) |
| `hostStudentId` | String? | campus Student ID (e.g. `S001`), NOT Firebase UID |
| `approvalLetterPath` | String? | **local device file path** (see Risks) |
| `approvalLetterName` | String? | original filename |
| `hasApprovalLetter` | bool | default `false`; set `true` on submit |
| `rejectionReason` | String? | admin-only |
| `revisionNotes` | String? | admin-only |
| `messages` | List\<EventMessage\>? | nested admin↔host thread |
| `revisionCount` | int | default `0` |
| `submittedDate` | String? | `'YYYY-MM-DD'` |
| `eventType` | String | default `'Open'`; one of `Open / Club / Club+Payment / Paid` |
| `isPrivate` | bool | default `false` |
| `clubIdRequired` | bool | default `false` |
| `isPaid` | bool | default `false` |
| `price` | double | default `0.0` |
| `maxParticipants` | int | default `0` (0 = unlimited) |
| `attendeeIds` | List\<String\> | default `[]` |
| `pendingJoiningIds` | List\<String\> | default `[]` |
| `qrTicketPath` | String? | |
| `coverImageUrl` | String? | Cloudinary secure URL; only written when non-null/non-empty |
| `coverImagePublicId` | String? | Cloudinary public ID; only written when non-null/non-empty |

`fromMap` (lines 127–165) reads every key above; `status` defaults to `'Pending'` when empty, `eventType` defaults to `'Open'`.

### createEvent path (exact)

1. Screen builds an `Event` (lines 1567–1590) with `status: 'Pending'`, `hostStudentId: appState.userId`, `approvalLetterPath/Name`, `hasApprovalLetter: true`, `submittedDate: DateTime.now().toString().split(' ')[0]`, `eventType`, `isPrivate/clubIdRequired/isPaid/price/maxParticipants`, `coverImageUrl/coverImagePublicId`.
2. Screen calls `appState.createEvent(newEvent)` (line 1595).
3. `AppState.createEvent(Event draft) → Future<Event?>` (`lib/services/app_state.dart:1774–1786`) — copies `status:'Pending'`, `hostStudentId: draft.hostStudentId ?? userId`, `submittedDate: draft.submittedDate ?? _today()`, `attendeeIds: const []`, `pendingJoiningIds: const []`, then calls `_eventsService.createEvent(...)`. Catches `AuthFailure` → returns `null`. **Note: `createEvent` does NOT call `notifyListeners()`** (only the `_eventWrite`-wrapped mutations do).
4. `EventService.createEvent(Event) → Future<Event>` (`lib/services/event_service.dart:152–160`) — `_events.add(event.toMap())`, returns `event.copyWith(id: doc.id)`; wraps `FirebaseException` → `AuthFailure.fromCode`.
5. Screen: `created == null` → toast `'Unable to submit event. Please try again.'`; else `setState(() => _done = true)` (inline success screen).

### Validator rules (exact limits and messages)

All in `_CreateEventState.build` (`events_screens.dart:1396–1607`). **There is NO title max-length rule anywhere in the codebase** — no `maxLength`, no 100-char constant. The redesign spec's "title max 100" is a NEW requirement, not an existing one.

| Field | Validator (exact) | Notes |
|---|---|---|
| Title | `v!.isEmpty ? 'Required' : null` | no max length |
| Category | `v == null ? 'Required' : null` | dropdown |
| Event Type | `v == null ? 'Required' : null` | dropdown |
| Entry Fee (RM) | `(v!.isEmpty \|\| double.tryParse(v) == null) ? 'Enter valid amount' : null` | only shown for `Club+Payment` / `Paid` |
| Max Participants | **none** | `keyboardType: number` only; parsed `int.tryParse(...) ?? 0` (no numeric/range validation) |
| Date | `v!.isEmpty ? 'Required' : null` | read-only field, filled by picker |
| Time | `v!.isEmpty ? 'Required' : null` | free text `'HH:MM'` — **no `showTimePicker`** |
| Location | `v!.isEmpty ? 'Required' : null` | |
| Organizer | `v!.isEmpty ? 'Required' : null` | |
| Description | `v!.isEmpty ? 'Required' : null` | `maxLines: 3`, no max length |

### Date-minimum rule (exact expression)

- Picker (`_pickEventDate`, lines 1242–1257): `showDatePicker` with
  - `initialDate: _selectedDate ?? minDate`
  - `firstDate: minDate` where `minDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 10))`
  - `lastDate: now.add(const Duration(days: 365))`
- Submit re-check (lines 1521–1528):
  - `daysUntilEvent = eventDay.difference(today).inDays`
  - `if (daysUntilEvent < 10)` → toast `'Events must be submitted at least 10 days in advance'` and return.
- The two NoticeBoxes at the top (lines 1397–1405) state the same rule in copy.

### PDF (approval letter) rules

- Picker (`_pickApprovalPdf`, lines 1259–1269): `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'], allowMultiple: false)` → stores `PlatformFile? _approvalPdf`.
- **Enforced in the submit handler, NOT a form validator** (lines 1529–1532): `if (_approvalPdf == null)` → toast `'Approval letter PDF is required'` and return.
- The PDF is **mandatory** and **not uploaded anywhere** — only its local `path` and `name` are persisted (see Risks).

### Cover image (optional) rules

- `_pickCoverImage` (1271–1287) → `appState.pickEventCoverImage()` (CloudinaryService gallery pick via `image_picker`).
- Size guard: `sizeBytes > 5 * 1024 * 1024` → toast `'Image must be under 5 MB'`.
- Uploaded on submit via `appState.uploadEventCoverToCloudinary(...)` (unsigned Cloudinary preset `campus_connect_events`, cloud `xijxwdly`, folder `events`). `CloudinaryException` → toast `'Cover image upload failed: …'` and abort.
- Accepted types shown in UI: `'JPG, PNG, WebP — max 5 MB'`.

### Success / cancel navigation

- **Success**: no `pop`, no toast. `setState(() => _done = true)` swaps the body for an inline success `Scaffold` (lines 1379–1392): "Event Submitted!" + "Your event is pending admin approval…" + a `Back to Events` `ElevatedButton` → `context.go('/events')`.
- **Cancel**: `OutlineBtn('Cancel')` → `context.pop()` (line 1606). No confirmation.
- **AppBar back**: `_appBar` leading arrow → `ctx.pop()` (line 26). No confirmation.
- **No `WillPopScope` / `PopScope`** and **no discard/edited-content confirmation** exists anywhere on this screen.

### Authorization model

- Host identity: `hostStudentId = appState.userId` where `AppState.userId => _profile?.userId` (`app_state.dart:126`) — the campus-issued Student ID (e.g. `S001`), NOT the Firebase UID.
- Pre-write guard (lines 1591–1594): `if (appState.userId == null || appState.userId!.isEmpty)` → toast `'You must be logged in to create an event'`.
- Route-level guard: `main.dart:86` redirects any non-public route to `/login` when `!appState.isAuthenticated`.

### firestore.rules reference

`firestore.rules` → `match /events/{eventId}` (lines 422–536). Event creation is governed by:

```
allow create: if ownsNewEvent()
  && request.resource.data.status == 'Pending'
  && request.resource.data.attendeeIds == []
  && request.resource.data.pendingJoiningIds == [];

allow create: if isAdmin();
```

`ownsNewEvent()` (lines 434–439) verifies `request.resource.data.hostStudentId == get(.../users/<uid>).data.studentId`. So a student may only create in their own name, born `Pending`, empty roster. Admin-created events have `hostStudentId == null`.

### Packages and versions (must not change)

`pubspec.yaml` dependencies (exact):

- `go_router: ^14.0.0`
- `intl: ^0.19.0`
- `flutter_animate: ^4.5.0`
- `provider: ^6.0.0`
- `cupertino_icons: ^1.0.8`
- `shared_preferences: ^2.2.0`
- `file_picker: ^8.1.7` (approval-letter PDF)
- `image_picker: ^1.1.0` (cover image via CloudinaryService)
- `qr_flutter: ^4.1.0` (used elsewhere in events_screens.dart, NOT in CreateEventScreen)
- `url_launcher: ^6.2.0`
- `firebase_core: ^4.12.1`
- `firebase_auth: ^6.5.6`
- `cloud_firestore: ^6.7.1`
- `firebase_storage: ^13.4.5`
- `http: ^1.6.0` (Cloudinary upload)
- dev: `flutter_lints: ^4.0.0`

**No new package is required** for the redesign — every current capability (PDF pick, image pick, Cloudinary upload, animation, QR) is already covered by an existing dependency.

### File-ownership boundaries

`CreateEventScreen` lives **inside** `lib/screens/events/events_screens.dart`, which also contains (do NOT disturb):

- `EventDetailScreen` — lines 29–548
- `LegacyElectionsInfoScreen` — lines 551–587
- `AdminEventsListScreen` — lines 590–918
- `AdminEventEditorScreen` — lines 921–1198 (the separate **admin** create/edit path at `/admin/events/editor`; NOT the student screen)
- **`CreateEventScreen` — lines 1201–1610 (redesign target)**
- `AdminElectionsMgmtScreen` — lines 1613–1833 (recent **uncommitted** feature)
- `_showCandidateEditor` — lines 1838–1921 (uncommitted)
- `_TL` / `_ActionChip` shared helpers — lines 1924–1962

Boundaries later agents MUST respect:

- **MAY touch**: lines 1201–1610 of `events_screens.dart` (the `CreateEventScreen` + `_CreateEventState` bodies only).
- **MUST NOT touch**: any other line range in `events_screens.dart`; `lib/main.dart` (except the already-existing `/events/create` route if the lead authorizes a route signature change — default is do not change); `lib/models/event.dart`; `lib/services/event_service.dart`; `lib/services/app_state.dart`; `lib/services/cloudinary_service.dart`; `firestore.rules`; `pubspec.yaml`; `lib/theme/*`; `lib/widgets/common.dart`; any test file.
- If the redesign needs a new reusable widget, add it to `lib/screens/events/widgets/` (new file) or `lib/widgets/` rather than editing `common.dart` in place, unless the lead says otherwise.
- The working tree is **dirty**: `events_screens.dart`, `main.dart`, `app_state.dart`, `firestore.rules` and others are already modified (uncommitted Admin Election Management feature on branch `events-module`). Do not `git checkout`/reset anything.

---

## Current screen anatomy

Line-range map of `CreateEventScreen` internals (all in `events_screens.dart`):

| Lines | What |
|---|---|
| 1201–1204 | `CreateEventScreen` StatefulWidget declaration |
| 1206–1227 | `_CreateEventState` fields: `_key` (Form key), controllers `_titleC/_descC/_dateC/_timeC/_locC/_orgC/_priceC/_maxParticipantsC`, `_catVal`, `_eventTypeVal`, `_clubIdRequired`, `_done`, `_selectedDate`, `_approvalPdf` (PlatformFile?), `_coverImage` (File?), `_uploadingCover`, `_uploadProgress`; const option lists `_cats = ['Academic','Sport','Club','General']`, `_eventTypes = ['Open','Club','Club+Payment','Paid']` |
| 1229–1240 | `dispose()` |
| 1242–1257 | `_pickEventDate()` — `showDatePicker` (10-day min, 365-day max) |
| 1259–1269 | `_pickApprovalPdf()` — `file_picker` PDF |
| 1271–1287 | `_pickCoverImage()` — gallery pick + 5 MB guard |
| 1289–1294 | `_removeCoverImage()` |
| 1296–1375 | `_buildCoverImagePicker()` — preview/upload-progress overlay, or tap-to-add placeholder |
| 1377–1392 | `build()` early-return success screen when `_done` |
| 1394–1395 | main `Scaffold` + `_appBar('Create Event')` |
| 1396 | `Form(key: _key)` + scroll column |
| 1397–1405 | two `NoticeBox`es (admin approval; 10-day rule) |
| 1406 | `SectionLabel('Event Details')` |
| 1407 | Title field |
| 1409 | Category dropdown |
| 1411–1417 | Event Type dropdown |
| 1419–1428 | Club ID checkbox (only `Club`/`Club+Payment`) |
| 1429–1437 | Entry Fee field (only `Club+Payment`/`Paid`) |
| 1438–1445 | Max Participants field |
| 1447–1460 | Date field (read-only, tap → picker) |
| 1462 | Time field (free text) |
| 1464 | Location field |
| 1466 | Organizer field |
| 1468 | Description field |
| 1470–1472 | `SectionLabel('Cover Image (Optional)')` + `_buildCoverImagePicker()` |
| 1474–1482 | `SectionLabel('Approval Letter (PDF)')` + mandatory NoticeBox |
| 1484–1512 | PDF selection row (`_approvalPdf?.name ?? 'No PDF selected'` + `Choose PDF` button) |
| 1513–1604 | `GradientButton('Submit for Approval')` — full submit handler (validation, 10-day re-check, PDF check, cover upload, `createEvent`) |
| 1605–1606 | `OutlineBtn('Cancel')` → `context.pop()` |

Old → new mapping notes for redesign agents: the current screen uses the **AppTheme** palette (not the newer `Luxe` design system), `GradientButton`/`OutlineBtn`/`NoticeBox`/`SectionLabel` from `lib/widgets/common.dart`, and a plain `Form`/`TextFormField` layout. The `Luxe` system (`lib/theme/luxe.dart`) exists but is not used here.

---

## Risks & no-change boundaries

1. **PDF is never uploaded.** `approvalLetterPath` stores the device-local `PlatformFile.path` (a temp path that will not survive across devices/sessions). There is no Firebase Storage or Cloudinary upload for the PDF, and no admin-side viewer that opens it. Any redesign that claims "PDF upload" must either (a) preserve this exact behavior, or (b) get explicit lead sign-off to add real PDF storage — which would touch `event_service.dart`, `app_state.dart`, `firestore.rules`, and possibly a new package. Do NOT silently change this.
2. **No title max-length exists.** The redesign spec's "title max 100" is a new rule. Adding it is safe (client-side only) but must be flagged as a behavior change, not a preservation.
3. **Max Participants has no validation** (no numeric/range rule). `int.tryParse(...) ?? 0` silently coerces garbage to unlimited. A redesign that adds range validation is a behavior change.
4. **No time picker** — time is free text `'HH:MM'`. If the redesign wants `showTimePicker`, that is new behavior.
5. **No discard confirmation** on back/cancel. Adding `PopScope`/confirm is new behavior and must not break the existing `context.pop()` cancel.
6. **Success is an inline screen, not a pop.** Preserve the "pending admin approval" messaging and the `context.go('/events')` return, or get lead sign-off to change it.
7. **`createEvent` does not call `notifyListeners()`.** Streams (`watchPublishedEvents`, etc.) drive UI refresh, so this is currently fine, but a redesign must not assume a synchronous rebuild after create.
8. **File-ownership collision risk**: `CreateEventScreen` shares `events_screens.dart` with an **uncommitted** `AdminElectionsMgmtScreen` (lines 1613+) and the admin `AdminEventEditorScreen` (921–1198). Editing outside 1201–1610 risks clobbering uncommitted work.
9. **Two create paths exist**: student `/events/create` (`CreateEventScreen`, status `Pending`) vs admin `/admin/events/editor` (`AdminEventEditorScreen`, status `Published`). Do not conflate them; the redesign targets only the student screen.
10. **`flutter analyze` reports 322 info-level `withOpacity` deprecation warnings** (project-wide, pre-existing; none are errors). New code should use `.withValues(alpha:)` to avoid adding more.

---

## Lead decisions — conflict resolutions (2026-08-14)

Recorded by the lead before any screen code is written. Binding on Agents 3–7; where a section above disagrees with this section, this section wins.

1. **Design spec approved.** `docs/create_event_design_spec.md` and `lib/theme/create_event_tokens.dart` are the visual source of truth, with the amendments in items 2–8 and 11 below.
2. **Price and Club-ID fields are KEPT (conditional).** Agent 2's §8.4 recommended dropping them; the master spec forbids silently removing functionality, so they stay as conditional field cards in the same design language, immediately after the Event Type card: a **Price card** (only when `eventType ∈ {Club+Payment, Paid}`, numeric keyboard, validator `'Enter valid amount'`) and a **Club-ID toggle card** (only when `eventType ∈ {Club, Club+Payment}`). The exact submit mapping from the current handler (`events_screens.dart:1537–1540, 1583–1586`) is preserved verbatim: `isPrivate = eventType ∈ {Club, Club+Payment}`; `clubIdRequired = isClub && _clubIdRequired`; `isPaid = eventType ∈ {Club+Payment, Paid}`; `price = isPaid ? double.tryParse(priceText) ?? 0.0 : 0.0`. A paid event type must never submit price 0.0 from a blank field — the price validator blocks it.
3. **Cover-image UI removed; backend untouched.** No Cloudinary pick/upload on the new screen; submit passes `coverImageUrl`/`coverImagePublicId` as null (`Event.toMap` already omits nulls). `AppState.pickEventCoverImage` / `uploadEventCoverToCloudinary` / model fields stay for future reuse.
4. **Title: UI-only 100-char cap + live 0/100 counter.** No model/server change. The counter is rendered because the enforced max IS 100 (spec: "if it is 100, show the live 0/100 counter").
5. **Max Participants: digits-only input, empty → 0 (unlimited).** `FilteringTextInputFormatter.digitsOnly` kills negatives/decimals/unsafe text (spec: "do not accept negative values, decimal values, or unsafe text"); `int.tryParse(trim) ?? 0` preserves 0 = unlimited.
6. **Time: native `showTimePicker`, stored as `DateFormat('h:mm a')`** (e.g. `'09:00 AM'`). Verified against `lib/data/mock_data.dart:212–216` — the app convention is `'09:00 AM'`, so the frozen-contract note of `'HH:MM'` is superseded. The wire field stays a plain display string.
7. **Description: NO maxLength.** Drop Agent 2's 2000-char cap — the current screen has no limit and the master spec adds none. Required-only validation; the 160 px card uses `minLines: 5, maxLines: 5`.
8. **Discard confirmation via `PopScope` on ALL exit paths.** `canPop = !_isDirty || _done || _discardConfirmed`; when a pop is vetoed, show an accessible `AlertDialog` ("Discard changes?" / "Keep editing" / "Discard"). Header back stays `context.pop()` (the PopScope intercepts it while dirty); the Cancel button shows the same dialog when dirty and pops directly when clean. `_isDirty` = any text controller non-empty OR any dropdown chosen OR date/time chosen OR PDF selected. Satisfies "back/close must not silently discard content" without changing navigation when the form is clean.
9. **10-day rule preserved exactly.** Picker `firstDate = today + 10d` (unchanged) AND the submit re-check with the existing toast copy `'Events must be submitted at least 10 days in advance'` stays as the final guard. The per-field error (design-spec copy) covers the empty-date case.
10. **PDF flow preserved exactly.** Same `FilePicker` config (`FileType.custom`, `['pdf']`, `allowMultiple: false`), mandatory, enforced at submit; after a failed submit the error renders on the upload card ("Approval letter is required"). The PDF is still not uploaded anywhere (latent defect, out of scope — do not add storage, do not log the path).
11. **Extraction to new files approved.** `CreateEventScreen` moves to `lib/screens/events/create_event_screen.dart`; presentational widgets go to `lib/screens/events/widgets/create_event_widgets.dart`; `events_screens.dart` gets a surgical delete of exactly lines 1201–1610 plus `export 'create_event_screen.dart';` after the existing exports (lines 15–16). **Authorized cleanup:** the imports `dart:io`, `package:flutter/services.dart`, and `package:file_picker/file_picker.dart` in `events_screens.dart` become unused after the delete (verified 0 remaining usages outside the range) and must be removed. `main.dart` is untouched — its import of `events_screens.dart` resolves `CreateEventScreen` through the new export (the only external reference, verified). **Amendment to Agent 2's §6:** the form-state/validation layer is extracted to `lib/screens/events/create_event_form_state.dart` (owned by Agent 3) so Agent 3 can deliver a unit-testable, stable interface before Agent 4 builds the screen against it. Agent 3 may also CREATE new test files (e.g. `test/create_event_form_state_test.dart`); the frozen boundary against touching test files applies to *modifying existing* tests, not creating new ones — the master spec requires unit validation/payload tests from Agent 3.
12. **Success/cancel behavior preserved.** `_done` inline success screen ("Event Submitted!" + pending-admin copy + Back to Events → `context.go('/events')`); submit failure keeps form data, shows the existing toast `'Unable to submit event. Please try again.'`, re-enables the button; the `'You must be logged in to create an event'` guard stays; duplicate submits blocked by a `_submitting` flag.

---

## Agent 1 — Repository and Contract Auditor — 2026-08-14T13:09:24Z

### Scope completed
- Read `CreateEventScreen` in full (state, controllers, validators, pickers, submit handler, toast usage, cover-image and approval-letter sections) and mapped its exact line range (1201–1610) within `events_screens.dart`.
- Read `/events/create` route and auth guard in `lib/main.dart`.
- Read `Event` model (`lib/models/event.dart`) — every field, `toMap`/`fromMap` wire keys, defaults.
- Read `EventService.createEvent` and the events section of `AppState` (`createEvent`, cover-image pick/upload, `userId`, `_eventWrite`, `_today`).
- Documented every validator rule, the 10-day date rule, PDF mechanism, date/time pickers, category/event-type option lists.
- Read theme (`app_theme.dart`, `luxe.dart`) and reusable widgets (`common.dart`).
- Enumerated all test files and confirmed no Create Event tests exist.
- Read the events section of `firestore.rules` and confirmed the create rule.
- Ran `flutter analyze` and `flutter test`; recorded outcomes.

### Files inspected
- `D:\Campus_connect2\lib\screens\events\events_screens.dart` (full, 1963 lines)
- `D:\Campus_connect2\lib\main.dart`
- `D:\Campus_connect2\lib\models\event.dart`
- `D:\Campus_connect2\lib\services\event_service.dart`
- `D:\Campus_connect2\lib\services\app_state.dart` (session header + events/cloudinary sections)
- `D:\Campus_connect2\lib\services\cloudinary_service.dart`
- `D:\Campus_connect2\lib\theme\app_theme.dart`
- `D:\Campus_connect2\lib\theme\luxe.dart`
- `D:\Campus_connect2\lib\widgets\common.dart`
- `D:\Campus_connect2\lib\screens\events\events_hub_screen.dart` (entry points)
- `D:\Campus_connect2\lib\screens\events\widgets\event_widgets.dart` (class index)
- `D:\Campus_connect2\firestore.rules` (events section, lines 413–630)
- `D:\Campus_connect2\pubspec.yaml`
- `D:\Campus_connect2\test\hub_render_test.dart`, `election_meta_model_test.dart`, `delete_countdown_dialog_test.dart`, `admin_election_archive_test.dart`

### Files changed
- Created `D:\Campus_connect2\docs\create_event_redesign_handoff.md` (this file; the `docs/` directory did not previously exist).
- No production source, config, rule, or test file was modified.

### Decisions and constraints preserved
- Frozen contract captured above: route `/events/create`, class `CreateEventScreen`, full `Event` wire schema, exact validator rules, 10-day date rule, mandatory-PDF rule, inline-success + `context.go('/events')` navigation, `context.pop()` cancel with no confirmation, `hostStudentId = appState.userId` authorization, `firestore.rules` create rule, and the exact dependency versions.
- File-ownership boundary: redesign may touch only `events_screens.dart:1201–1610`; everything else (including the uncommitted `AdminElectionsMgmtScreen` at 1613+ and admin `AdminEventEditorScreen` at 921–1198) is off-limits.

### Tests/commands run and outcome
- `flutter analyze` → exit 0; 322 issues, all info-level `withOpacity` deprecation warnings (pre-existing, no errors).
- `flutter test` → exit 0; 9 tests, all passed.
- `git status --short` → working tree dirty on branch `events-module` (uncommitted Admin Election Management feature, including modifications to `events_screens.dart`, `main.dart`, `app_state.dart`, `firestore.rules`).

### Risks, defects, or blockers
- PDF is mandatory but never actually uploaded — only its local device path is stored (likely a latent defect for cross-device/admin review).
- No title max-length (spec's "100" is new), no max-participants validation, no time picker, no discard confirmation.
- `createEvent` does not call `notifyListeners()`.
- CreateEventScreen shares a file with uncommitted work — high clobber risk if agents edit outside 1201–1610.
- Two distinct create paths (student vs admin) that must not be conflated.

### Next agent must do
- Read this handoff's "Frozen contract" before any edit.
- Restrict all edits to `events_screens.dart:1201–1610` (or new files under `lib/screens/events/widgets/`), preserving the exact payload keys, validator rules, date rule, PDF requirement, success/cancel navigation, and authorization model documented above.
- Flag (do not silently change) any spec item that conflicts with the frozen contract — especially the "no cover-image section visible on screen" spec vs the current mandatory-cover-optional-PDF reality, and the "title max 100" rule which does not exist today.

---

## Agent 2 — Visual-system and Component Architect — 2026-08-14T13:52:00Z

### Scope completed
- Analyzed the reference image `D:\Aa . MAY - Semister All Subject\Project-2\Photos of work\Event detils.png` and derived a complete visual system: pinned gradient header + overlapping white sheet, two info cards, uppercase section headers, nine field cards, a dashed PDF upload card, and gradient submit / outlined cancel actions.
- Produced the full component tree, a per-field state/validation spec (§3), an icon + semantic-label map (§4), a responsive plan (§5), an accessibility checklist (§7), and a risks/conflicts list (§8).
- Extracted every visual value into a constants-only Dart class `CreateEventTokens` (colors, spacing, radii, sizes, border widths, shadows, type scale) — no widgets, no logic, no service imports.

### Files inspected
- `D:\Aa . MAY - Semister All Subject\Project-2\Photos of work\Event detils.png` (reference)
- `docs/create_event_redesign_handoff.md` (Agent 1's frozen contract)
- `lib/screens/events/events_screens.dart` (read-only; mapped the old screen's layout/widgets)
- `lib/main.dart`, `lib/models/event.dart`, `lib/services/app_state.dart`, `lib/services/event_service.dart`, `lib/services/cloudinary_service.dart`, `lib/theme/app_theme.dart`, `lib/theme/luxe.dart`, `lib/widgets/common.dart`

### Files changed
- Created `D:\Campus_connect2\docs\create_event_design_spec.md` (this spec).
- Created `D:\Campus_connect2\lib\theme\create_event_tokens.dart` (constants only).
- No production screen, model, service, rule, or test file was modified.

### Decisions and constraints preserved
- No new packages and no raster assets — every icon is an existing Material icon; all values are code constants.
- Class identity preserved: `CreateEventScreen` name and const constructor survive the move; route `/events/create` unchanged.
- File-layout plan: extract the screen to `lib/screens/events/create_event_screen.dart` + `lib/screens/events/widgets/create_event_widgets.dart`, surgical delete of `events_screens.dart` 1201–1610, and an `export` so `main.dart` keeps resolving the class.
- Flagged (did not silently resolve) every spec-vs-contract conflict for the lead: cover-image omission, title 100 cap, max-participants validation, time picker, discard confirmation, and the missing price/Club-ID UI.

### Tests/commands run and outcome
- `flutter analyze` → 0 new errors/warnings introduced by the two new artifacts (baseline 322 pre-existing `withOpacity` infos remain).

### Risks, defects, or blockers
- Reference omits the cover-image, price, and Club-ID sections that exist in the current screen — resolved by lead decisions (cover hidden; price/Club-ID kept conditionally).
- Title "100" cap and time picker are new behaviors not present in the current code — resolved by lead decisions (UI-only cap; native picker with `h:mm a` format).
- `Max Participants` had no validation; spec requires rejecting negatives/decimals — resolved via `digitsOnly` + empty→0.

### Next agent must do
- Read this handoff (Frozen contract + Lead decisions) and `docs/create_event_design_spec.md` §3 before writing any code.
- Implement the form-state/validation layer in `lib/screens/events/create_event_form_state.dart` against the exact validator copy, the 10-day rule, the price/Club-ID mapping, and the payload builder — with unit tests in a new `test/create_event_form_state_test.dart`.
- Do NOT edit `create_event_screen.dart`, `create_event_widgets.dart`, or `events_screens.dart` (Agent 4's exclusive turf). Append your own handoff entry when done.

---

## Agent 3 — Form-state and Validation Engineer — 2026-08-14T13:30:27Z

### Scope completed
- Delivered the pure, unit-testable form-state + validation layer in `lib/screens/events/create_event_form_state.dart` (new file, this agent's exclusive deliverable) plus `test/create_event_form_state_test.dart` (new file, authorized by lead decision #11).
- Implemented the exact frozen validator copy, the 10-day submit re-check, the mandatory-PDF check, the price/Club-ID mapping, the `isDirty` definition (lead decision #8), and a `buildDraftEvent` payload builder that mirrors the legacy submit handler (`events_screens.dart:1567–1590`) byte-for-byte.
- Implemented the pure submit state machine `evaluateSubmit` with priority ordering field-errors → 10-day → missing-PDF → not-logged-in → ready.

### Files inspected
- `docs/create_event_redesign_handoff.md` (frozen contract + lead decisions), `docs/create_event_design_spec.md` (§3, §8), `lib/theme/create_event_tokens.dart` (read-only).
- `lib/models/event.dart` (full `Event` model + `toMap`/`fromMap` — copied the constructor's named-parameter list exactly), `lib/services/app_state.dart` (`createEvent` at 1774–1786), `lib/screens/events/events_screens.dart` (legacy submit handler 1567–1590 + pickers 1242–1269).
- `lib/data/mock_data.dart` (time convention `'09:00 AM'` / `'02:00 PM'`), `file_picker-8.3.7` `PlatformFile` constructor signature.

### Files changed
- Created `D:\Campus_connect2\lib\screens\events\create_event_form_state.dart`.
- Created `D:\Campus_connect2\test\create_event_form_state_test.dart`.
- No model/service/theme/rules/pubspec/main/screen file modified; no existing test modified.

### Decisions and constraints preserved
- Exact error copy frozen as `CreateEventErrorCopy` (13 strings) and asserted character-for-character in tests.
- 10-day rule preserved exactly: `tenDayError` returns the preserved copy `'Events must be submitted at least 10 days in advance'`; both sides normalized to date-only (calendar `day + 10`, DST-immune) so time-of-day can't skew the boundary.
- Payload mirrors legacy handler: `status 'Pending'`, `hasApprovalLetter true`, `submittedDate 'yyyy-MM-dd'`, cover-image fields `null`, and explicit model defaults (`rejectionReason`/`revisionNotes`/`messages` null, `revisionCount 0`, `qrTicketPath` null, `attendeeIds`/`pendingJoiningIds` `[]`) so `Event.toMap()` stays on the frozen key list (asserted: no `id`, no `coverImageUrl`, no `coverImagePublicId`).
- `isDirty` matches lead decision #8 exactly — `clubIdRequired` alone does NOT dirty the form (tested).
- **Time pattern resolved to `hh:mm a` (zero-padded hour), not the literal `h:mm a`.** The task's `h:mm a` would render `9:00 AM` / `2:00 PM`, contradicting both the frozen wire convention (`lib/data/mock_data.dart` shows `'09:00 AM'`, `'02:00 PM'`) and the required test assertions. Locale pinned to `en_US` for determinism (app never sets `Intl.defaultLocale`). Flagging for the lead in case the literal pattern was intentional.
- **`maxParticipants` negative text is NOT rejected by the validator** — the frozen rule is literally `int.tryParse(trim) == null`, and `int.tryParse('-5')` succeeds; negatives are blocked at input by `digitsOnly` (lead decision #5), not by this defense rule. Documented + tested.
- Security: no file path/contents/token ever logged; tests use synthetic names (`approval_letter.pdf`, `C:/synthetic/...`); no I/O, no network, no new packages.

### Tests/commands run and outcome
- `flutter analyze` → exit 0; 322 issues, all pre-existing (project-wide `withOpacity` infos plus a handful of pre-existing `use_build_context_synchronously`/`unused_import`/`prefer_const_constructors` in untouched files). **0 issues in the two new files.**
- `flutter test test/create_event_form_state_test.dart` → 83 tests, all passed.
- `flutter test` → 92 tests, all passed (9 pre-existing + 83 new).

### Risks, defects, or blockers
- The `h:mm a` vs `hh:mm a` discrepancy (above) is the only deviation from the literal task wording; it was resolved in favor of the byte-exact wire examples and mock data. If the lead intended unpadded `9:00 AM`, change `createEventTimeFormat` to `DateFormat('h:mm a', 'en_US')` — one line, tests would need the two `timeText` expectations updated.
- `buildDraftEvent` uses `!` on `approvalPdf`/`category`/`eventType`/`eventDate` and falls back to `''` for `date`/`time` only in the (unreachable, gated) null case — it MUST only be called when `evaluateSubmit` returns `ready`.
- PDF remains never-uploaded (latent defect, out of scope) — `approvalLetterPath` carries the device-local path; the screen must not log/display it.

### Next agent must do
- Build the screen against this stable interface (import `package:campus_connect/screens/events/create_event_form_state.dart`):
  - `CreateEventFormModel extends ChangeNotifier` — setters for `title`, `description`, `location`, `organizer`, `priceText`, `maxParticipantsText`, `category`, `eventType`, `clubIdRequired`, `eventDate`, `eventTime`, `approvalPdf`, `submitting`, `done`; getters `isClub`, `isPaid`, `timeText`, `isDirty`.
  - `Map<String, String?> fieldErrors()` and `String? firstError()` (keyed by `CreateEventFieldIds.*`).
  - `String? tenDayError({required DateTime today})`.
  - `SubmitEvaluation evaluateSubmit({required DateTime today, required bool loggedIn})` → `SubmitEvaluation.ready` / `.message` / `.fieldId` / `.block` (`SubmitBlock` enum). The screen performs the actual `await appState.createEvent(...)` only when `ready`.
  - `Event buildDraftEvent({required String hostStudentId, required DateTime today})`.
  - Pure validators + `CreateEventErrorCopy` / `CreateEventFieldIds` are top-level for reuse.
- Read this handoff (Frozen contract + Lead decisions) and `docs/create_event_design_spec.md` §3 before writing code.
- Own ONLY `lib/screens/events/create_event_screen.dart`, `lib/screens/events/widgets/create_event_widgets.dart`, and the surgical `events_screens.dart` delete of lines 1201–1610 + `export 'create_event_screen.dart';` (plus removing the now-unused `dart:io` / `flutter/services.dart` / `file_picker` imports per lead decision #11). Do not edit this form-state file or its test.

---

## Agent 4 — Screen Implementation Engineer — 2026-08-14T13:47:35Z

### Scope completed
- Built the full redesigned `CreateEventScreen` (route `/events/create`) against Agent 3's `create_event_form_state.dart` interface: pinned gradient header (back button, title/subtitle, translucent CustomPainter bubbles clipped + IgnorePointer), overlapping white sheet (30 px top radii, ONE `SingleChildScrollView`, `keyboardDismissBehavior: onDrag`, `Center` + `ConstrainedBox(maxWidth: 560)`), both `EventInfoCard`s, "EVENT DETAILS" + "APPROVAL LETTER (PDF)" section headers, all 9 base field cards in spec order, conditional Club-ID toggle card (`model.isClub`) and Entry Fee card (`model.isPaid`, decimal keyboard), `PdfUploadCard` (dashed pink border via private painter, Choose PDF + remove affordance, narrow <360 stacked layout), `PdfSecurityNote`, 56 px gradient submit (spinner + "Submitting…" + liveRegion while submitting), 56 px outlined Cancel, discard-confirmation `PopScope` + `AlertDialog`, and the preserved inline success screen.
- Implemented the exact submit state machine: `fieldError` → flip `AutovalidateMode.onUserInteraction` + `validate()` + scroll/focus first invalid field via per-field `GlobalKey`s; `tenDay`/`notLoggedIn` → toasts (frozen copy); `missingPdf` → inline "Approval letter is required" below the upload card + scroll to card; `ready` → `model.submitting = true` → `buildDraftEvent` → `await appState.createEvent`; `created == null` → toast "Unable to submit event. Please try again." + re-enable (data kept); success → `model.done = true` with `submitting` left true (success body replaces the form, button can never re-enable). `context.mounted` guarded after awaits.
- Surgical extraction from `events_screens.dart`: deleted exactly lines 1200–1611 (the "Screen 26: Create Event (Student)" banner + `CreateEventScreen` + `_CreateEventState` + all pickers/cover-image helper, 412 lines) via an assertion-checked Python script; added `export 'create_event_screen.dart';` after the two existing exports; removed the now-unused `dart:io` and `package:file_picker/file_picker.dart` imports. `AdminElectionsMgmtScreen` banner and everything below is byte-identical.

### Files inspected
- `docs/create_event_redesign_handoff.md` (frozen contract + lead decisions), `docs/create_event_design_spec.md` (§1–§8), `lib/theme/create_event_tokens.dart`, `lib/screens/events/create_event_form_state.dart`, `lib/screens/events/events_screens.dart` (legacy block 1200–1611 + `_toast` at 18–21 + success copy at 1379–1392), `lib/theme/app_theme.dart`, `lib/services/app_state.dart` (signature checks), Flutter 3.38.9 SDK `material/dropdown.dart` (API surface check: `underline`/`isExpanded`/`initialValue` current).

### Files changed
- CREATED `D:\Campus_connect2\lib\screens\events\create_event_screen.dart` (~600 lines: `CreateEventScreen` + `_CreateEventScreenState`, private `_toast` copy, pickers, submit/cancel/discard logic, success screen).
- CREATED `D:\Campus_connect2\lib\screens\events\widgets\create_event_widgets.dart` (~1000 lines: `CreateEventHeader`, `CreateEventSheet`, `EventInfoCard` (+`EventInfoVariant`), `CreateEventSectionHeader`, `CreateEventFieldCard`, `CreateEventCounter`, `CreateEventTextField`, `CreateEventDropdownField`, `CreateEventPickerField`, `PdfUploadCard`, `PdfSecurityNote`, `CreateEventSubmitButton`, `CreateEventCancelButton`, private `_HeaderBubblesPainter` + `_DashedRRectPainter`).
- MODIFIED `D:\Campus_connect2\lib\screens\events\events_screens.dart` (delete + export + 2 import removals only; 1963 → 1551 lines).
- `lib/main.dart`, `create_event_form_state.dart`, `create_event_tokens.dart`, tests: untouched.

### Decisions and constraints preserved
- All frozen copy preserved character-for-character: success screen "Event Submitted!" / "Your event is pending admin approval.\nWe'll notify you when it's approved." / "Back to Events" → `context.go('/events')` (re-skinned with tokens: raspberry check icon, `fieldLabelColor`/`fieldHelperColor` text, raspberry button); toasts "Events must be submitted at least 10 days in advance", "You must be logged in to create an event", "Unable to submit event. Please try again."; PDF inline error "Approval letter is required".
- Picker configs exact: `showDatePicker(initialDate: model.eventDate ?? minDate, firstDate: DateTime(today.y, today.m, today.d + 10), lastDate: DateTime(today.y, today.m, today.d + 365))`; `showTimePicker` → model `timeText` (`hh:mm a`, Agent 3's resolved format); `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: false)`, null/empty → state unchanged, `result.files.single` → `model.approvalPdf`. No path ever logged or displayed (only `name`).
- Payload, price/Club-ID mapping, 10-day rule, `isDirty`/PopScope semantics, cover-image omission — all delegated to Agent 3's model/`buildDraftEvent`; the screen performs no payload logic of its own.
- Deviations (deliberate, justified):
  1. Text/dropdown `validator:`s call Agent 3's exported pure validators on the FormField's own value (`v`) rather than literally reading `model.fieldErrors()[id]` — TextFormField revalidates *before* `onChanged` syncs the model, so a model read renders errors one keystroke stale (e.g. "Event title is required" would persist after a valid title). Frozen copy strings are identical (same functions). Date/Time picker fields (not FormFields) DO read `model.fieldErrors()` gated by the autovalidate flag, matching the intent.
  2. `import 'package:flutter/services.dart';` KEPT in `events_screens.dart` — `Clipboard.setData` is still used at post-delete lines 265/535 (the lead's "0 remaining usages" claim was incorrect for services; `dart:io` and `file_picker` were removed as authorized).
  3. `create_event_widgets.dart` imports `package:flutter/services.dart` in addition to material + tokens — required for the `TextInputFormatter` type on `CreateEventTextField.inputFormatters`. It is a Flutter SDK import; no Provider/FilePicker/AppState/project imports were added.
  4. `flutter analyze` exits 1, not 0 — the baseline already exited 1 (pre-existing `warning`-severity issues like `unused_local_variable`/`dead_code` in untouched files). Deliverable criterion met instead: **0 issues (errors, warnings, or infos) in all three changed/new files**, total project issues 322 → 312 (the 10 legacy-block issues were deleted with the block).
  5. Title counter uses `characters.length` (grapheme-correct vs `maxLength`); dropdown hint text "Select", price input hint "0.00", date placeholder "Select event date", time placeholder "Select start time" are small additions beyond the spec table (helpers match §3.2 exactly).
  6. `missingPdf` does not flip autovalidate (all fields are provably valid there — priority ordering); the PDF error is gated on the failed submit, clears on pick, re-shows on remove.

### Tests/commands run and outcome
- `flutter analyze` → 312 issues, ALL pre-existing (identical set, shifted lines in `events_screens.dart`; verified no new line appears in `create_event_screen.dart` / `create_event_widgets.dart` / the edited region). Exit code 1 only because the pre-existing warnings are fatal by default.
- `flutter test` → **92/92 passed** (9 pre-existing + Agent 3's 83).
- `grep -n "CreateEventScreen" lib/screens/events/events_screens.dart` → no matches (class fully extracted; only the file-level export remains, line 15).
- `grep -n "class CreateEventScreen" lib/screens/events/create_event_screen.dart` → exactly 1 (line 30).
- `lib/main.dart:127` untouched (`GoRoute(path: '/events/create', builder: (_, __) => const CreateEventScreen())` — resolves via the new export).
- No `print(`/`debugPrint(` of any file path in the new code.

### Risks, defects, or blockers
- PDF remains never-uploaded (frozen latent defect): `approvalLetterPath` persists the device-local temp path; no size cap, no MIME double-check, only the extension filter. Path is never displayed/logged.
- `FilePicker.pickFiles` platform-channel exceptions are not wrapped in try/catch (legacy behavior parity; a platform failure would surface as an unhandled async error).
- `events_screens.dart` `_toast`/`_appBar`/`GradientButton`/`NoticeBox` remain for other screens (untouched, still pre-existing withOpacity infos).
- Working tree still dirty with the uncommitted Admin Election feature (as expected — nothing reset or stashed).

### Next agent must do
- You may test/harden but NOT redesign the screen. Platform/file behavior implemented (verbatim): date via `showDatePicker` (today+10 → today+365, calendar-day arithmetic), time via `showTimePicker` displayed as `model.timeText` (`hh:mm a` en_US from Agent 3), PDF via `FilePicker.platform.pickFiles(custom, ['pdf'], allowMultiple: false)` with cancel → no state change. Current PDF validation gaps you should close WITHOUT breaking the screen: no size cap, no content/MIME double-check (extension filter only), picker exceptions unhandled. The PDF is still not uploaded anywhere — do not add storage; if you add guards (e.g. max size), put them in the screen's `_pickApprovalPdf` only and surface via the existing `_toast` (do not touch the model or the wire contract).
- Submit flow to preserve: exact evaluation order fieldError → tenDay → missingPdf → notLoggedIn → ready; inline errors (no toast) for field/PDF, toasts only for tenDay/notLoggedIn; failure keeps all form data and re-enables submit; success leaves `submitting` true and swaps to the inline success body.
- Exit paths: `PopScope(canPop: !isDirty || done || _discardConfirmed)` intercepts header back while dirty; Cancel shows the same "Discard changes?" dialog when dirty, pops directly when clean.
- If you run widget tests against `CreateEventScreen`, wrap in the real `AppState` provider (it calls `context.read<AppState>()` only inside `_handleSubmit`) and expect `MaterialApp`/GoRouter `context.pop`/`context.go` extensions.

---

## Lead review note — PopScope discard-loop defect (2026-08-14)

Found by the lead reviewing Agent 4's `create_event_screen.dart`. **Do not fix in Agents 5/6 — Agent 7 owns the fix.** Agent 6 must write a regression test that reproduces it; Agent 7 applies the remedy below.

**Defect:** `_confirmDiscard()` sets `_discardConfirmed = true` WITHOUT `setState`, then calls `context.pop()` synchronously. `PopScope.canPop` is a `bool` captured at build time and only re-synced to the route's internal `ValueNotifier` in `didUpdateWidget` — so at the moment of the pop, `canPop` is still `false` (dirty + not confirmed). The pop is vetoed, `onPopInvokedWithResult(didPop: false)` fires, and `_confirmDiscard()` runs again → the "Discard changes?" dialog re-appears instead of leaving. This affects BOTH the Cancel button and the header/system back when the form is dirty.

**Exact remedy (Agent 7):** in `_confirmDiscard`, replace the two lines
```dart
_discardConfirmed = true;
context.pop();
```
with
```dart
setState(() => _discardConfirmed = true);
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) Navigator.of(context).pop();
});
```
Rationale: `setState` schedules the rebuild so `PopScope.didUpdateWidget` flips the internal `canPopNotifier` to `true`; the post-frame `pop` then succeeds, and the subsequent `onPopInvokedWithResult(didPop: true)` returns early (no re-dialog). Keep the `_discardConfirmed` term in `canPop` so a clean form still pops immediately.

---

## Agent 5 — Platform and File Integration Engineer — 2026-08-14T13:53:57Z

### Scope completed
- Hardened `_pickApprovalPdf` in `create_event_screen.dart` ONLY (additive; no redesign, no model/wire/widgets/route/test changes):
  1. Wrapped `FilePicker.platform.pickFiles(...)` in try/catch; on any exception it shows a generic toast and returns with state unchanged (nothing leaked).
  2. Added a 10 MB size cap (reject > 10 * 1024 * 1024 with a toast; `size == 0` = "unknown" is admitted, never rejected).
  3. Added an extension double-check after picking (`file.extension?.toLowerCase()` must be `'pdf'`, or a null extension is accepted only if `file.name.toLowerCase().endsWith('.pdf')`); non-PDF → toast, state unchanged.
  4. Confirmed only `file.name` is ever displayed (`PdfUploadCard.fileName: model.approvalPdf?.name`); `file.path` is passed to the model (Agent 3's `buildDraftEvent`) but never printed/displayed/logged. No `print`/`debugPrint`/`log` added.
  5. Preserved cancel semantics: `result == null || result.files.isEmpty` → return with no state change. Added `if (!mounted) return;` guards so a disposed State can't toast or mutate the disposed model after the await.
- Verified `_pickEventDate` / `_pickEventTime` against the frozen contract; found and minimally fixed ONE genuine edge-case bug in `_pickEventDate` (see Risks).

### Files inspected
- `docs/create_event_redesign_handoff.md` (frozen contract + lead decisions + lead review note)
- `docs/create_event_design_spec.md` (§3.2 PDF field, §5 responsive)
- `lib/screens/events/create_event_screen.dart` (Agent 4's screen)
- `lib/screens/events/widgets/create_event_widgets.dart` (Agent 4's widgets — read-only)
- `lib/screens/events/create_event_form_state.dart` (Agent 3's model — read-only)
- `file_picker-8.3.7/lib/src/platform_file.dart` (confirmed `PlatformFile.name`/`size`/`extension`/`path` semantics; `extension` = `name.split('.').last`, `size` defaults 0, `path` throws on web)

### Files changed
- `D:\Campus_connect2\lib\screens\events\create_event_screen.dart` — `_pickApprovalPdf` (lines ~126–161) hardened; `_pickEventDate` (lines ~103–122) initialDate clamp added.
- `D:\Campus_connect2\docs\create_event_redesign_handoff.md` — this handoff entry appended.
- No model, wire contract, tokens, widgets, `events_screens.dart`, `main.dart`, or test file touched.

### Decisions and constraints preserved
- Frozen PDF flow preserved: same `FilePicker` config (`FileType.custom`, `['pdf']`, `allowMultiple: false`), mandatory, enforced at submit; PDF still never uploaded (latent defect, out of scope — no storage added, no path logged).
- Frozen date bounds preserved: `firstDate = today + 10d`, `lastDate = today + 365d`, calendar-day arithmetic (`DateTime(y, m, d + 10)` / `+ 365`). Time via `showTimePicker` → `model.timeText` (`hh:mm a` en_US) unchanged.
- New toast copy added (plain strings, existing `_toast` helper, no `.withOpacity` anywhere): `'Unable to open file picker. Please try again.'`, `'Approval letter must be under 10 MB'`, `'Only PDF files are allowed'`.
- PopScope/discard code (`_confirmDiscard`, `canPop`, `onPopInvokedWithResult`) NOT touched — the lead review note defect is Agent 7's fix.

### Tests/commands run and outcome
- `flutter analyze` → 312 issues, ALL pre-existing (identical set; exit 1 from untouched-file warnings). **0 issues in `create_event_screen.dart`** (grep for the file returned nothing).
- `flutter test` → **92/92 passed**.
- `grep -n "print(\|debugPrint(\|log(" lib/screens/events/create_event_screen.dart` → only match is the substring `log(` inside `AlertDialog(` (line ~180) — a false positive; no real logging of any path/contents.

### Risks, defects, or blockers
- **Date picker edge-case bug (found + fixed, pre-existing from legacy `_selectedDate ?? minDate` pattern):** if the user picks the earliest allowed date (today+10) and keeps the form open past midnight, the next `showDatePicker` call received `initialDate` (yesterday+10) below the new `firstDate` (today+10) — a debug-build assertion crash / undefined release behavior. Fixed by clamping: `initialDate = current != null && !current.isBefore(minDate) ? current : minDate`. Contract behavior (initialDate = selected date) is preserved in the normal case.
- PDF remains never-uploaded (frozen latent defect): `approvalLetterPath` persists a device-local temp path; no size/MIME enforcement at the model layer — the new 10 MB cap and extension check are screen-level guards only.
- `PlatformFile.extension` is effectively never null (`name.split('.').last`), so the null-extension fallback branch is defensive-only.

### Next agent must do
- Regression-test the platform/file behavior in `_pickApprovalPdf`:
  - **Cancel path:** cancel the picker → no state change, no toast.
  - **Size path:** a file > 10 MB → toast `'Approval letter must be under 10 MB'`, `model.approvalPdf` unchanged.
  - **Extension path:** a non-PDF (e.g. `.txt`/`.png`) that slips past the filter → toast `'Only PDF files are allowed'`, state unchanged; a `.PDF` (uppercase) must be accepted.
  - **Exception path:** a platform-channel failure (e.g. missing plugin / mocked throw) → toast `'Unable to open file picker. Please try again.'`, no exception details/stack/path surfaced, state unchanged.
  - Confirm only `file.name` is ever rendered (never `file.path`).
- Regression-test the date/time pickers: date picker bounds today+10 → today+365 (calendar-day arithmetic); the midnight-reopen clamp (pick earliest date, advance the clock, reopen — no assertion crash); time picker → `model.timeText` (`hh:mm a` en_US).
- **PopScope discard-loop defect (lead review note):** write a regression test that reproduces it (dirty form → Cancel/back → "Discard changes?" dialog re-appears instead of popping) and REPORT it — do NOT fix it (Agent 7 owns the remedy).

---

## Agent 6 — Quality, Accessibility and Regression Tester — 2026-08-14T14:18:33Z

### Scope completed
- Wrote ONE new test file `test/create_event_screen_test.dart` (17 tests) plus a generated golden `test/goldens/create_event_screen.png`.
- Reproduced and characterized the PopScope discard behavior under this app's GoRouter 14.8.1, and found the real observable defect (header back silently discards a dirty form).
- Found three real defects total (1 PopScope bypass + 2 overflow families). REPORT-ONLY: no `lib/` code, no existing test, and no existing handoff content was modified.

### Files inspected
- `docs/create_event_redesign_handoff.md` (frozen contract + lead decisions + lead review note) — read-only.
- `docs/create_event_design_spec.md` (§3 field spec, §4 semantics labels, §5 responsive, §7 a11y) — read-only.
- `lib/screens/events/create_event_screen.dart` (Agent 4) — read-only.
- `lib/screens/events/widgets/create_event_widgets.dart` (Agent 4) — read-only.
- `lib/screens/events/create_event_form_state.dart` (Agent 3) — read-only.
- `lib/theme/create_event_tokens.dart` — read-only.
- `lib/services/app_state.dart` (constructor + `createEvent` + `Event` re-export) — read-only.
- `test/hub_render_test.dart`, `test/admin_election_archive_test.dart` (setup patterns) — read-only.

### Files changed
- `D:\Campus_connect2\test\create_event_screen_test.dart` — NEW (17 tests; my deliverable).
- `D:\Campus_connect2\test\goldens\create_event_screen.png` — NEW (generated via `--update-goldens`).
- `D:\Campus_connect2\docs\create_event_redesign_handoff.md` — this entry appended (existing content untouched).
- No `lib/` code, no existing test, no existing handoff content modified.

### Decisions and constraints preserved
- Report-only role honored: I did NOT modify `lib/`, any existing test, or the handoff doc's existing content; I did NOT fix any defect.
- Test setup mirrors the existing tests: a `GoRouter`-backed `MaterialApp` with a minimal route table (`/events/create` → `CreateEventScreen`, `/events` → placeholder `Scaffold`), `AppState` provided via `ChangeNotifierProvider`. `FilePicker` has no plugin in widget tests, so Agent 5's try/catch yields the toast `'Unable to open file picker. Please try again.'`.
- All frozen error copy asserted character-for-character (via the `_errorText` matcher keyed on `fieldErrorTextColor`, which disambiguates helper/error collisions like `'Pick the start time'`).
- Golden rendered at 390×844 logical (physical 1170×2532, DPR 3) with the bundled Inter font loaded via `FontLoader('Inter')` from `assets/fonts/Inter.ttf` (font IS bundled — no placeholder-box caveat applies).

### Tests/commands run and outcome
- `flutter analyze` → 312 issues, ALL pre-existing `withOpacity` deprecation infos across the codebase; **0 issues in `test/create_event_screen_test.dart`** (grep for the file returned nothing).
- `flutter test test/create_event_screen_test.dart` → **14 passed, 3 failed** (tests 10b, 14, 15 — all three are the intended defect reproductions; see below).
- `flutter test` (full suite) → **106 passed, 3 failed** (the same three; all 92 prior tests still pass).
- `flutter test --update-goldens test/create_event_screen_test.dart` → `test/goldens/create_event_screen.png` generated (80,259 bytes); golden test passes in the normal run.

### Risks, defects, or blockers
**DEFECT 1 — PopScope discard guard bypassed by the header back (HIGH — silent data loss).**
Lead decision #8 says "Header back stays `context.pop()` (the PopScope intercepts it while dirty)". Reality under GoRouter 14.8.1: `context.pop()` is an IMPERATIVE pop. `Navigator.onPopPage` → `GoRouterDelegate._handlePopPageWithRouteMatch` calls `route.didPop(result)`, which fires the PopScope veto and `onPopInvokedWithResult(false)` → `_confirmDiscard()` (dialog transiently created), but then IGNORES the `false` return and completes the pop anyway. Net effect: on a DIRTY form, the header back arrow pops the route with NO discard dialog — the user's data is silently discarded. (System back DOES show the dialog, because `maybePop` → `willPop` respects `canPopNotifier`.) Reproduced by test 10b, which fails with:

```
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Discard changes?": []>
   Which: means none were found but one was expected
```

**Note on the lead-review-note "discard loop" (test 10):** the mandated repro does NOT fail under GoRouter. `_confirmDiscard()` sets `_discardConfirmed = true` WITHOUT `setState` then calls `context.pop()` synchronously; in a PLAIN Navigator this re-vetoes the pop and the dialog re-appears (a loop). But GoRouter's imperative pop ignores the veto, so Cancel → Discard pops cleanly and test 10 PASSES. The latent code smell (`_discardConfirmed = true` without `setState`) is still real and should be fixed, but the observable symptom is DEFECT 1 above, not a dialog loop.

**DEFECT 2 — Submit button overflows at 320px width (MEDIUM — a11y/layout).**
`create_event_widgets.dart:870:25` — the Submit button's `Row [Icon(send), SizedBox(8), Text('Submit for Approval')]` is not flexible; at the 320px viewport (design §5 narrowest) it overflows by 35px. Reproduced by test 14:

```
Expected: null
  Actual: FlutterError:<A RenderFlex overflowed by 35 pixels on the right.>
```

**DEFECT 3 — Section header + Submit button overflow at 2.0 text scale (MEDIUM — a11y/layout).**
`create_event_widgets.dart:218:12` — `CreateEventSectionHeader`'s `Row [Text(label.toUpperCase()), SizedBox(10), Expanded(Container(height:1))]` leaves the label un-wrapped, overflowing by 147px ('APPROVAL LETTER (PDF)'). `create_event_widgets.dart:870:25` — the same Submit button Row overflows by 250px ('Submit for Approval' not flexible/wrapped). Reproduced by test 15:

```
Expected: null
  Actual: 'Multiple exceptions (2) were detected during the running of the current test, and at least one was unexpected.'
```

### Next agent must do
Fix the following defects (Agent 7 owns the fixes; after the fix ALL tests must pass, including my repro tests 10b, 14, and 15):

1. **PopScope discard guard (DEFECT 1, HIGH).** Apply the lead's exact remedy to `_confirmDiscard()` in `lib/screens/events/create_event_screen.dart` — replace
   ```dart
   _discardConfirmed = true; context.pop();
   ```
   with
   ```dart
   setState(() => _discardConfirmed = true);
   WidgetsBinding.instance.addPostFrameCallback((_) {
     if (mounted) Navigator.of(context).pop();
   });
   ```
   **IMPORTANT — this remedy alone does NOT fix DEFECT 1.** The header back (`onBack: () => context.pop()`) is an imperative pop that GoRouter completes regardless of the PopScope veto. To make test 10b pass, the header back must be routed through the discard guard (e.g. point `onBack` at `_handleCancel` / `_confirmDiscard` rather than a bare `context.pop()`). Coordinate with the lead if this changes the "header back stays `context.pop()`" decision — the current behavior silently discards a dirty form.

2. **Submit button overflow (DEFECT 2).** Make the Submit button's label flexible at narrow widths (e.g. wrap the `Text('Submit for Approval')` in `Flexible`/`Expanded` with `textAlign: center` and/or `FittedBox`) so it does not overflow at 320px.

3. **Text-scale overflows (DEFECT 3).** Wrap the section-header label in `Expanded`/`Flexible` (allow it to wrap) and make the Submit button label flexible, so 2.0 text scale does not overflow.

4. After the fixes, run `flutter test test/create_event_screen_test.dart` and confirm ALL 17 tests pass (10b, 14, 15 must flip to green), then the full `flutter test` suite (expect 109/109).


---

## Agent 7 — Final Reviewer and Fixer — 2026-08-14T14:28:35Z

### Scope completed
Fixed all 3 defects from Agent 6's report (plus the latent 1b smell) and closed the pipeline:

1. **DEFECT 1 (HIGH) — header back silently discards a dirty form.** `create_event_screen.dart` header now routes through the discard guard: `onBack: _handleCancel` (was `onBack: () => context.pop()`). With GoRouter 14, a bare `context.pop()` is an imperative pop that ignores the PopScope veto, so the dirty check must run BEFORE the pop — `_handleCancel` shows the "Discard changes?" dialog when `_model.isDirty` and pops directly when clean (plain-pop behavior preserved for clean forms). Flips Agent 6's test 10b to green.
2. **DEFECT 1b (latent smell).** `_confirmDiscard` now uses `setState(() => _discardConfirmed = true);` BEFORE the existing `context.pop()` (still guarded by `mounted`). `context.pop()` kept as-is per instruction (GoRouter project idiom; it completes the confirmed discard). `PopScope(canPop: ...)` expression and `onPopInvokedWithResult` unchanged — they correctly serve the SYSTEM back gesture, which does respect the veto. Agent 6's test 10 (discard loop repro) still passes.
3. **DEFECT 2 (MEDIUM) — submit button Row overflow (35 px @ 320 px).** `create_event_widgets.dart` submit button: label wrapped in `Flexible` with `maxLines: 1`, `overflow: TextOverflow.ellipsis`, `textAlign: TextAlign.center`. Icon, 56 px height, radius, gradient, and spinner-while-submitting untouched; the whole Row stays `const`. Flips test 14 to green.
4. **DEFECT 3 (MEDIUM) — 2.0 text-scale overflows.** (a) `CreateEventSectionHeader` label is now width-capped via `LayoutBuilder` + `ConstrainedBox` (maxWidth = row width − 10 px gap) so it wraps at 2.0 scale and the trailing rule always renders; at 1.0 scale the label keeps its natural single-line width and the rule spans to the right edge EXACTLY as before (golden unchanged). Deliberate deviation from the literal "wrap in Flexible" prescription, documented below. (b) Submit-button label covered by the same Defect 2 `Flexible` fix (~250 px overflow eliminated). `textScaler` NOT clamped anywhere (design spec §5). Flips test 15 to green.

### Files inspected
- `docs/create_event_redesign_handoff.md` (full — frozen contract, lead decisions, lead review note, Agent 6's defect list)
- `docs/create_event_design_spec.md` (§1, §3, §5)
- `lib/screens/events/create_event_screen.dart` (full)
- `lib/screens/events/widgets/create_event_widgets.dart` (full)
- `lib/theme/create_event_tokens.dart` (sectionLabel / primaryButtonLabel / spacing values)
- `test/create_event_screen_test.dart` (full — read-only; assertions not weakened)
- `lib/main.dart` (route line 127), `lib/screens/events/events_screens.dart` (exports)

### Files changed
- `D:\Campus_connect2\lib\screens\events\create_event_screen.dart` — 2 edits: (1) `onBack: _handleCancel` in `CreateEventHeader` (was `() => context.pop()`); (2) `_confirmDiscard`: `setState(() => _discardConfirmed = true);` before `context.pop()`.
- `D:\Campus_connect2\lib\screens\events\widgets\create_event_widgets.dart` — 2 edits: (1) `CreateEventSectionHeader.build` → `LayoutBuilder` + `ConstrainedBox` label cap; (2) submit-button label → `Flexible(Text(..., maxLines: 1, overflow: ellipsis, textAlign: center))`.
- `D:\Campus_connect2\docs\create_event_redesign_handoff.md` — this entry appended.
- NO changes to: `create_event_form_state.dart`, `create_event_tokens.dart`, `events_screens.dart`, `main.dart`, models, services, `firestore.rules`, `pubspec.yaml`, any test file, or the golden PNG.

### Decisions and constraints preserved
- Wire contract / `Event` payload, validator copy, toasts, success screen copy — byte-identical, untouched.
- Lead decision #8 satisfied on ALL exit paths: header back, Cancel, and system back now all honor the discard guard; clean forms pop without a dialog on every path.
- Lead-review-note remedy applied with the Agent-6-verified adaptation: `setState` before the pop, but `context.pop()` kept (NOT `Navigator.of(context).pop()` + post-frame callback) because under GoRouter 14.8.1 the imperative pop completes the confirmed discard — the post-frame `Navigator.pop()` would be redundant here and the plain `context.pop()` is the project idiom.
- `PopScope(canPop: !_model.isDirty || _model.done || _discardConfirmed)` and `onPopInvokedWithResult` left exactly as-is (system back still respects the veto; test 10 confirms no dialog loop).
- No `textScaler` clamping (accessibility-hostile; spec §5). No `print`/`debugPrint`/`log` added. No `.withOpacity` (none introduced).
- **Deviation note (section header):** a naive `Flexible` around the label with the existing `Expanded` rule would split free space 50/50 — shortening the rule at 1.0 scale (golden change + visual regression vs the reference) AND could still overflow an unbreakable word (`'APPROVAL'` ≈ 193 px > the 170 px half-width allocation at 2.0 scale with wide fonts). The `LayoutBuilder` + `ConstrainedBox` cap achieves the prescribed intent — label wraps when needed, trailing rule always renders, style kept, 1.0-scale pixels identical.

### Tests/commands run and outcome
- `flutter test test/create_event_screen_test.dart` → **17/17 passed** (10b header-back dialog, 14 narrow-viewport, 15 text-scale all flipped to green).
- `flutter test` (full suite) → **109/109 passed** (9 pre-existing + 83 Agent 3 + 17 Agent 6).
- Golden: **NO regeneration needed** — `test/goldens/create_event_screen.png` untouched; the fixes are pixel-neutral at 1.0 scale (golden test passed in both runs).
- `flutter analyze` → 312 issues, ALL pre-existing info-level `withOpacity` deprecations in untouched files (baseline; exit 1 expected/acceptable). **0 issues in `create_event_screen.dart`, `create_event_widgets.dart`, `create_event_form_state.dart`, `create_event_tokens.dart`.**
- `grep -n "class CreateEventScreen" lib/screens/events/create_event_screen.dart` → exactly 1 (line 30).
- `lib/main.dart:127` unchanged (`GoRoute(path: '/events/create', builder: (_, __) => const CreateEventScreen())`).
- `events_screens.dart:15` still has `export 'create_event_screen.dart';`; no circular imports (screen → widgets/form_state/tokens only; widgets → material/services/tokens only).

### Risks, defects, or blockers
- PDF still never uploaded (frozen latent defect, out of scope) — `approvalLetterPath` persists the device-local temp path.
- No device-side visual parity run (golden is the only pixel reference; screen not verified on a physical 320 px device or with a real screen reader).
- `FilePicker.pickFiles` screen-level guards (10 MB cap, extension check, try/catch) remain screen-only; the model layer has no such guards (by design).
- Working tree remains dirty (uncommitted Admin Election Management feature + this redesign) — nothing reset, stashed, or checked out.

### Next agent must do
The pipeline is COMPLETE. Final state: route `/events/create` → redesigned `CreateEventScreen` in `lib/screens/events/create_event_screen.dart` (+ `create_event_widgets.dart`, `create_event_form_state.dart`, `create_event_tokens.dart`); `events_screens.dart` exports it; 109/109 tests green; 312 pre-existing analyze infos (0 new); golden unchanged. No further agent work is assigned. The lead should perform the final quality gate: (1) visual parity of the golden `test/goldens/create_event_screen.png` against the reference image (note: no device-side run was performed); (2) a one-time confirmation that the 10 MB PDF size cap and the "Only PDF files are allowed" toast are acceptable behavior additions; (3) the known limitation that the approval-letter PDF is still never uploaded anywhere; (4) after that, commit the branch (`events-module`) as one coherent changeset.
