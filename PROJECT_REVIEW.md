# Campus Connect — Complete Project Review

## Executive summary

Campus Connect is an advanced Flutter/Firebase campus platform with:

- Student and admin authentication
- Lost-and-found reporting and AI matching
- QR-based handover workflows
- Locker booking and payments
- Events and elections
- Issue reporting
- OneSignal/FCM push notifications
- Firebase Cloud Functions
- A Cloudflare AI Worker

The project is suitable for an advanced prototype or internal pilot. It is not production-ready yet because several authorization, payment, AI endpoint, privacy, and data-consistency issues need to be resolved first.

This review was performed against the current local checkout. No project files were intentionally modified during the review.

## Highest-priority findings

### 1. Registration identity can be forged — Critical

In [`firestore.rules`](/D:/Campus_connect2/firestore.rules:49), a new user only needs to provide an `authEmail` string. The value is not securely bound to the authenticated Firebase account.

A malicious user could create a profile claiming another student ID or email. Student IDs are also not enforced as unique through an atomic server-side operation.

Recommended fix:

- Use server-side registration or a trusted email/token binding.
- Enforce unique student IDs transactionally.
- Consider a server-managed registration workflow.

### 2. Students can modify sensitive locker-booking fields — Critical

The student booking update rule in [`firestore.rules`](/D:/Campus_connect2/firestore.rules:698) restricts only a few fields, such as `studentId`, `lockerId`, `status`, and `releaseStatus`.

It does not clearly prevent students from modifying fields such as:

- Payment amount
- Deposit
- Digital locker code
- Refund flags
- Key-return flags
- Dates
- Payment IDs

Recommended fix:

- Use `diff().affectedKeys()` to allow only specific fields.
- Enforce valid state transitions.
- Move sensitive transitions to trusted server code.

### 3. Payments are simulated and client-controlled — Critical before real payments

[`payment_service.dart`](/D:/Campus_connect2/lib/services/payment_service.dart:14) explicitly implements a demo payment gateway. Any valid 16-digit card number succeeds except the simulated failure cards.

The client then creates a completed payment document, while [`firestore.rules`](/D:/Campus_connect2/firestore.rules:733) mainly verifies the student ID.

This is acceptable for a demonstration but unsafe for real payments.

Recommended fix:

- Use Stripe or another real payment provider.
- Create payment intents server-side.
- Verify payment webhooks server-side.
- Bind payments to the correct booking.
- Never trust client-provided amounts or completed status.

### 4. AI test routes appear publicly callable — Critical

The Worker routes several AI endpoints directly in [`campus-connect-ai/src/index.js`](/D:/Campus_connect2/campus-connect-ai/src/index.js:1513), including:

- `/ai/match-test`
- `/ai/vision-test`
- `/ai/multi-image-test`
- `/ai/openrouter-multi-image-test`
- `/ai/gemini-match-test`
- `/ai/batch-match`

The notification endpoint has Firebase/admin verification, but these test routes do not appear to have equivalent authentication.

This could allow unauthorized users to consume Workers AI/OpenRouter quota, submit arbitrary image URLs, or abuse the service.

Recommended fix:

- Remove test routes from production, or authenticate every route.
- Add rate limits and request-size limits.
- Restrict or validate external image URLs.
- Separate development and production Workers.

### 5. Demo credentials are hardcoded — High

[`login_screen.dart`](/D:/Campus_connect2/lib/screens/auth/login_screen.dart:507) contains saved student credentials, including `Student@123`.

Recommended fix:

- Remove the credentials from release builds.
- Isolate demo login behind a development-only flag.
- Never ship demo passwords in the production application.

A local Firebase service-account file also exists under `tools/`. It is ignored and not tracked, but it contains a private key. If it has ever been shared, uploaded, or copied outside the machine, revoke and rotate it.

### 6. Android cleartext traffic is enabled globally — High

[`AndroidManifest.xml`](/D:/Campus_connect2/android/app/src/main/AndroidManifest.xml:12) enables `usesCleartextTraffic="true"`.

This may be useful for local Worker development, but release builds should use HTTPS only.

Recommended fix:

- Enable cleartext traffic only for debug builds.
- Use HTTPS for the production Worker URL.
- Add a release build validation check.

## Architecture review

### Strengths

- Firebase authentication, Firestore, storage, and messaging are integrated.
- Service classes provide useful boundaries between screens and backend operations.
- Firestore rules generally use default-deny behavior.
- User identity fields are mostly immutable.
- Hard deletes are disabled for important audit collections.
- QR handover rules use `getAfter()` for atomic validation.
- AI scoring and notification behavior have dedicated tests.
- The Cloudflare Worker keeps important API secrets in environment bindings rather than hardcoding them.

### Main architecture concern: oversized `AppState`

`AppState` has become a central controller for authentication, profiles, notifications, lost-and-found, AI, lockers, events, elections, and other features.

This creates:

- High coupling
- A large regression surface
- Difficult testing
- Difficult feature ownership

Recommended direction: split it into feature-specific controllers such as `AuthController`, `LostFoundController`, `LockerController`, and `NotificationController`.

### Hybrid mock and Firestore persistence

Some screens still use legacy `MockData` or `DataService`, while other features use Firestore. Event-related screens are examples of areas that still reference mock data.

This creates a risk that data appears to work during one session but disappears or reverts after restarting the application.

Recommended fix:

- Decide which features are production-backed.
- Remove mock persistence from production flows.
- Keep mock data only in tests or an explicit demo mode.

## Firestore security review

### User privacy

[`firestore.rules`](/D:/Campus_connect2/firestore.rules:37) permits listing one user profile without an explicit authentication requirement in that rule. A caller who guesses a valid student ID may be able to retrieve a full profile document.

Recommended fix: create a minimal server-managed `studentIndex/{studentId}` document containing only the lookup fields required by login.

### Issues

Issue updates allow broad status values rather than strictly enforcing valid lifecycle transitions. A student may be able to jump directly to a later status or reopen an issue.

Recommended fix: define an explicit transition matrix and enforce it in rules or trusted backend code.

### Lockers and inventory

All signed-in users can read some locker, inventory, or history data. This may expose occupancy, student IDs, dates, or item information.

Recommended fix:

- Decide which fields are public to authenticated students.
- Use separate public and private documents where appropriate.
- Restrict staff-only history to admins.

### Inventory and match ownership

Some inventory and AI-match writes validate the caller but do not fully validate the ownership and existence of every linked document.

Recommended fix: use `get()` checks in rules or move creation and approval to trusted backend functions.

## Notification system

The project currently contains both OneSignal and FCM notification paths. This creates duplicated delivery logic and makes operational behavior harder to reason about.

Define one canonical responsibility for:

- Foreground notifications
- Background notifications
- Admin notifications
- AI-match notifications
- Device-token registration and cleanup

There is also an analyzer warning in [`onesignal_service.dart`](/D:/Campus_connect2/lib/services/onesignal_service.dart:123) where `await` is used on a boolean value. This should be corrected or verified against the installed OneSignal API.

## Testing and code quality

### Tests that passed

- Selected Flutter domain, AI, and QR tests: 212 tests
- Notification and push tests: 168 tests
- Cloudflare Worker tests: 168 tests across 34 suites
- Admin create-event widget tests
- Profile layout smoke tests
- Model and service analysis completed without compilation errors

### Quality issues found

- Screen analysis reported 336 issues, mostly style, deprecation, and lifecycle warnings.
- Several `BuildContext`-after-`await` warnings could cause invalid UI updates or crashes.
- Test analysis reported 167 issues.
- The complete Flutter test suite did not finish conclusively because of runner timeout/output issues.
- Firestore rule fixtures are out of date.

### Firestore rule-test problems

- The registration email-binding test genuinely fails.
- Some item tests fail because fixtures are missing newer fields such as `reportedByName`.
- Lost-and-found workflow tests use outdated fixtures missing fields such as `matchId` and `handoverTxnId`.
- Some expectations conflict with the current intended inventory visibility rule.

Update the fixtures and add CI checks so stale tests cannot create false confidence.

## Cloudflare Worker deployment

The Worker tests are healthy, but production route security needs improvement.

The Worker should also have explicit observability and a tested compatibility-date update process. Cloudflare recommends periodically updating and testing compatibility dates, and Wrangler supports observability configuration for Worker logs:

- [Cloudflare compatibility dates](https://developers.cloudflare.com/workers/configuration/compatibility-dates/)
- [Wrangler configuration and observability](https://developers.cloudflare.com/workers/wrangler/configuration/)

## Documentation and repository hygiene

`README.md` and `project_context.md` are behind the actual implementation. The project context still describes the application as mainly using in-memory mock data, while the current code includes substantial Firebase, AI, notification, locker, and payment functionality.

Documentation should cover:

- Current architecture
- Firebase setup
- Firestore rules and indexes
- Worker secrets and routes
- Demo versus production features
- Test commands
- Admin setup
- Payment limitations
- Notification architecture

The worktree currently contains existing uncommitted changes in Android branding, Firebase rules, Dart screens/services, `pubspec`, and untracked branding/seed files. These changes were preserved.

## Recommended implementation order

1. Fix registration identity binding and student-ID uniqueness.
2. Lock down locker-booking and payment fields.
3. Remove or authenticate all AI test endpoints.
4. Remove hardcoded demo credentials and rotate exposed credentials if necessary.
5. Disable cleartext networking in release builds.
6. Decide which features are Firestore-backed and remove mock persistence.
7. Tighten privacy rules for users, lockers, inventory, and issue history.
8. Update rule fixtures and resolve analyzer warnings.
9. Establish CI checks for Flutter tests, Worker tests, Firestore rules, and release builds.

## Final assessment

Campus Connect has a strong feature foundation and meaningful automated coverage. Its main weakness is not functionality; it is trust-boundary design.

Before real student accounts, payments, or sensitive campus data are introduced, the authorization rules, payment workflow, AI endpoints, privacy model, and Firestore/MockData split should be corrected.
