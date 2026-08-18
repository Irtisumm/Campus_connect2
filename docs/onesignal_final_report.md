# OneSignal Push Notification Integration — Final Report

**App**: Campus Connect Flutter  
**Branch**: `events-module`  
**Date**: 2026-08-18  
**App ID**: `031d61a8-0a3a-4de8-9d88-d3e739896da5`

---

## A. ONE-SENTENCE SUMMARY

OneSignal SDK v5 is integrated as the push delivery layer alongside the existing FCM infrastructure, with full client-side identity management, tap-to-deep-link navigation, read/unread sync, and 25 passing tests. Automated server-side dispatch requires Cloud Functions deployment (Blaze plan), documented in the trigger gap analysis.

---

## B. FILES CREATED

| File | Lines | Purpose |
|---|---|---|
| `lib/services/onesignal_service.dart` | ~130 | OneSignal SDK wrapper: init, identity, permission, parseTap, NotificationTap |
| `test/onesignal_integration_test.dart` | ~410 | 25 test cases covering initialization, identity, push, read state, deep links, preferences, regression |
| `docs/onesignal_trigger_gap.md` | ~100 | Analysis of the Firestore→OneSignal dispatch gap and required Cloud Functions changes |
| `docs/onesignal_device_test_plan.md` | ~130 | 12-step real-device test plan with dashboard verification checklist |

## C. FILES MODIFIED

| File | Change |
|---|---|
| `pubspec.yaml` | Added `onesignal_flutter: ^5.6.7` |
| `lib/main.dart` | Replaced FCM tap handlers with `_handleOneSignalTap`; removed `_handleInitialMessage`, `_handlePushTap`, `_rootNavigator`; added OneSignal initialization |
| `lib/services/app_state.dart` | Added `OneSignalService _oneSignal` field; calls `setExternalUserId(uid)` at login, `removeExternalUserId()` at logout, `requestPermission()` after 2s delay |

## D. FILES LEFT UNCHANGED (per specification)

| File | Reason |
|---|---|
| `lib/services/push_service.dart` | FCM token lifecycle kept intact — coexistence strategy |
| `functions/index.js` | Old Cloud Functions kept until OneSignal verified on real device |
| `functions/package.json` | Unchanged — functions not deployed |
| `firestore.rules` | No changes needed — Cloud Functions use Admin SDK |
| `android/app/src/main/AndroidManifest.xml` | `POST_NOTIFICATIONS` permission already present from Phase 2 |
| `campus-connect-ai/ ` (Cloudflare Worker) | AI matching only — unchanged |

## E. ARCHITECTURE DECISIONS

1. **Coexistence strategy**: Both `firebase_messaging` and `onesignal_flutter` coexist in `pubspec.yaml`. FCM code (PushService, background handler) is kept intact but FCM routing is dead — `PushService.initialize()` is never called. The FCM background handler is inert (only calls `Firebase.initializeApp`).

2. **Firestore remains authoritative**: Notification documents (`lfNotifications`, `lockerNotifications`) are still the source of truth. Push is an additional delivery channel. Read/unread state, badge count, and in-app notification display are unchanged from Phase 1.

3. **OneSignal identity mapping**: Firebase Auth UID is mapped to OneSignal external user ID via `OneSignal.login(uid)` / `OneSignal.logout()`. The mapping is set at login and cleared at logout, ensuring cross-user isolation.

4. **Permission flow**: `OneSignal.Notifications.requestPermission(true)` is called 2 seconds after successful login. OneSignal's SDK handles the OS dialog and does not re-prompt if already granted or permanently denied.

5. **Dual NotificationTap classes**: Both `PushService` and `OneSignalService` define a `NotificationTap` data class with identical fields (`type`, `notificationId`, `relatedReportId`). This is intentional — the PushService version can be removed once OneSignal is verified.

## F. TRIGGER GAP (KNOWN LIMITATION)

**Automated push dispatch is NOT operational.** The three Cloud Functions in `functions/index.js` that would dispatch pushes are written but not deployed because the Firebase Blaze plan is not active.

Current end-to-end flow:
```
Admin creates notification in Firestore (client-side)
  → lfNotifications/{id} written
  → Student's app reads it in-app (working)
  → ❌ No push dispatched (Cloud Functions not deployed)
```

**Manual testing workaround**: Pushes can be sent from the OneSignal Dashboard → Messages → Push → New Push, targeting `include_external_user_ids` with the user's Firebase UID and the appropriate `additionalData` payload.

**What's needed for automated dispatch**: Deploy Cloud Functions (requires Blaze plan), add `ONE_SIGNAL_REST_API_KEY` as a Firebase Functions secret, and modify `sendPush` in `functions/index.js` to call OneSignal REST API instead of FCM Admin SDK. Full details in `docs/onesignal_trigger_gap.md`.

## G. SECURITY VERIFICATION

| Check | Status |
|---|---|
| No Firebase service-account credentials in client code | ✅ |
| No FCM secrets in client code | ✅ |
| No OneSignal REST API key in client code | ✅ |
| OneSignal App ID is safe for client-side | ✅ (intentional — SDK requires it) |
| No hardcoded Firebase Admin credentials | ✅ |
| Firestore rules unchanged | ✅ |
| No weakened security rules | ✅ |
| Cross-user isolation preserved | ✅ (Firebase UID ↔ OneSignal external user ID) |

## H. TEST RESULTS

```
flutter analyze:  0 errors, 0 new warnings, 17 pre-existing infos
flutter test:     369 tests passed (344 existing + 25 new)
flutter build apk --debug:  APK built successfully
```

**New test file**: `test/onesignal_integration_test.dart` — 25 tests in 6 groups:

| Group | Tests | Coverage |
|---|---|---|
| OneSignalService initialization | 3 | Constructor injection, default construction |
| OneSignal user identity | 5 | setExternalUserId, removeExternalUserId, logout lifecycle, empty UID guard, PushService coexistence |
| Notification permission | 1 | requestPermission returns boolean |
| Push notification handle | 4 | parseTap full payload, missing notificationId, empty map, defaults |
| Read/unread state | 3 | NotificationTap fields, equality, inequality |
| Deep link payload | 2 | relatedReportId preserved, absent key defaults |
| Notification preferences | 2 | No preference flags in payload, Firestore unaffected |
| Phase 1 regression | 5 | AppState without OneSignal, forTesting factory, PushService coexistence, badge import, type isolation |

## I. ANDROID COMPATIBILITY

| Check | Status |
|---|---|
| `POST_NOTIFICATIONS` permission in manifest | ✅ (line 7) |
| OneSignal SDK v5 compatible with Android API 21+ | ✅ |
| APK builds without errors | ✅ |
| No breaking changes to existing Android config | ✅ |
| FCM background handler retained (coexistence) | ✅ |

## J. WHAT WAS NOT DONE (per specification)

- ❌ Did NOT deploy Firebase Cloud Functions
- ❌ Did NOT change Firebase billing (still on Spark)
- ❌ Did NOT deploy Cloudflare Worker
- ❌ Did NOT remove old FCM Cloud Functions (kept until OneSignal verified)
- ❌ Did NOT modify AI matching, Gemini/OpenRouter, QR workflow, Inventory workflow
- ❌ Did NOT modify approval workflow, Event module, Election module, Locker module
- ❌ Did NOT add `flutter_local_notifications` dependency
- ❌ Did NOT make unrelated UI changes
- ❌ Did NOT weaken Firestore rules
- ❌ Did NOT expose privileged credentials in APK, Dart code, or Git

## K. ROLLBACK INSTRUCTIONS

To remove OneSignal and restore pure FCM:

1. Remove `onesignal_flutter: ^5.6.7` from `pubspec.yaml`
2. Delete `lib/services/onesignal_service.dart`
3. Delete `test/onesignal_integration_test.dart`
4. In `lib/main.dart`:
   - Remove `import 'services/onesignal_service.dart';`
   - Replace `_handleOneSignalTap` with the original `_handlePushTap(RemoteMessage, AppState)`
   - Restore `_handleInitialMessage` for terminated-app launches
   - Replace `oneSignal.initialize(onClick: ...)` with the original FCM listener setup
5. In `lib/services/app_state.dart`:
   - Remove `import 'onesignal_service.dart';`
   - Remove `final OneSignalService _oneSignal;` field
   - Remove `OneSignalService? oneSignalService,` parameter
   - Remove `_oneSignal = oneSignalService ?? OneSignalService(),` initializer
   - Remove `unawaited(_oneSignal.setExternalUserId(uid));` from loginUser
   - Remove `unawaited(_oneSignal.removeExternalUserId());` from logout
6. Run `flutter clean && flutter pub get`
7. Run `flutter test` — verify all 344 tests pass

## L. NEXT STEPS

1. **Real device testing**: Follow the 12-step test plan in `docs/onesignal_device_test_plan.md`
2. **OneSignal Dashboard verification**: Confirm subscriptions, deliveries, and FCM service account
3. **Activate Firebase Blaze plan** (when ready to deploy Cloud Functions)
4. **Deploy modified Cloud Functions** (replace FCM with OneSignal REST API in `sendPush`)
5. **Remove PushService NotificationTap class** (after OneSignal verified — use OneSignal's version)
6. **Remove `PushService.initialize()` mention and dead FCM routing code** (after OneSignal verified)
7. **Remove FCM background handler** from `main.dart` (after OneSignal verified)
