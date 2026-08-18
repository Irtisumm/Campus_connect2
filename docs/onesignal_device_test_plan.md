# OneSignal Real Device Test Plan

## Prerequisites

1. **Physical Android device** with OneSignal subscription active
2. **OneSignal Dashboard** access (https://app.onesignal.com)
3. **App ID**: `031d61a8-0a3a-4de8-9d88-d3e739896da5`
4. **Debug APK** installed: `build/app/outputs/flutter-apk/app-debug.apk`
5. **Firestore access** to create test notifications

## Test Scenarios

### S-1: SDK Initialization
**Goal**: Verify OneSignal SDK initializes and registers the device.

1. Install the debug APK on the device
2. Launch the app — observe logcat for `[OneSignal]` messages
3. Verify in OneSignal Dashboard → Audience → Subscriptions: a new subscription appears
4. **Expected**: No crash. Subscription visible in dashboard.

### S-2: Permission Prompt
**Goal**: Verify the notification permission dialog appears and is respected.

1. Fresh install (clear app data if previously installed)
2. Login with a student account
3. Wait 2-3 seconds after login screen settles
4. **Expected**: Android system notification permission dialog appears
5. Tap "Allow" → verify `[OneSignal] permission: true` in logcat
6. **Expected**: Subscription status in dashboard shows "Subscribed"

### S-3: Permission Denied
**Goal**: App remains functional when permission is denied.

1. Fresh install, login, deny the permission dialog
2. Verify `[OneSignal] permission: false` in logcat
3. Navigate to Notifications screen → in-app notifications still visible
4. **Expected**: App does not crash. Firestore notifications load normally.

### S-4: User Identity — Login
**Goal**: Verify Firebase Auth UID is mapped to OneSignal external user ID.

1. Login with student account (known Firebase UID)
2. Check logcat for `[OneSignal] login: <uid>`
3. In OneSignal Dashboard → Audience → Subscriptions, find the subscription
4. **Expected**: Subscription shows `external_user_id` matching the Firebase UID

### S-5: User Identity — Logout
**Goal**: Verify external user ID is removed on logout.

1. Login, verify subscription has external_user_id
2. Logout from the app
3. Check logcat for `[OneSignal] logout`
4. In OneSignal Dashboard, the subscription should no longer show the external_user_id
5. **Expected**: Clean identity handoff. Next login maps new user correctly.

### S-6: Manual Push — Foreground
**Goal**: Notification appears when app is in foreground.

1. Login, keep app in foreground
2. Use OneSignal Dashboard → Messages → Push → New Push
   - Target: `include_external_user_ids` = the logged-in Firebase UID
   - Title: "Test Foreground"
   - Body: "This is a foreground test"
   - Additional Data: `{"type": "lfNotification", "notificationId": "test-fg-1", "relatedReportId": ""}`
3. Send the push
4. **Expected**: Notification appears as a heads-up/in-app banner within 10 seconds
5. No crash, no duplicate display

### S-7: Manual Push — Background
**Goal**: Notification appears in system tray when app is backgrounded.

1. Login, then press Home to background the app
2. Send push from OneSignal Dashboard (same as S-6 but with `notificationId: "test-bg-1"`)
3. **Expected**: System tray notification appears
4. Pull down notification drawer → notification is visible with correct title/body

### S-8: Manual Push — Terminated
**Goal**: Notification appears when app is completely killed.

1. Login, then force-stop the app (swipe from recents)
2. Send push from OneSignal Dashboard (`notificationId: "test-term-1"`)
3. **Expected**: System tray notification appears
4. Tap the notification → app launches

### S-9: Notification Click — Deep Link
**Goal**: Tapping a notification navigates to the correct screen.

1. Create a test `lfNotification` document in Firestore:
   ```
   studentId: "<test-student-id>"
   title: "Test Match"
   body: "Test notification body"
   type: "match"
   relatedReportId: "<existing-lost-report-id>"
   read: false
   createdAt: serverTimestamp
   ```
2. From OneSignal Dashboard, send a push targeting the user with additional data:
   ```
   {"type": "lfNotification", "notificationId": "<doc-id>", "relatedReportId": "<existing-lost-report-id>"}
   ```
3. Tap the notification
4. **Expected**: App opens to the Lost Report detail screen for `relatedReportId`
5. The notification is now marked `read: true` in Firestore

### S-10: Read/Unread Sync
**Goal**: Badge count decreases after tapping a notification.

1. Note the current badge count on the Notifications tab
2. Create a new `lfNotification` with `read: false` (creates document directly in Firestore)
3. Refresh the app → badge count increases by 1
4. Send a push for this notification via OneSignal Dashboard
5. Tap the notification when it arrives
6. Verify the `lfNotification` document now has `read: true`
7. Go to Notifications screen → badge count decreased, notification marked read
8. **Expected**: Firestore read state is authoritative. Badge matches unread count.

### S-11: Multiple Sessions — Identity Isolation
**Goal**: Logging out and logging in as a different user prevents cross-user pushes.

1. Login as Student A, verify external_user_id
2. Logout
3. Login as Student B, verify external_user_id changed
4. From OneSignal Dashboard, send push targeting Student A's UID
5. **Expected**: Student B does NOT receive Student A's push

## Dashboard Verification

1. **Audience → Subscriptions**: Verify the device appears after app launch
2. **Messages → Deliveries**: Verify sent pushes show "Delivered" status
3. **Settings → Platforms → Android**: Verify FCM service account is configured (already done)
4. **Settings → Keys & IDs**: Note the **REST API Key** (for future Cloud Functions use — do NOT put this in Flutter code)

## Success Criteria

| Check | Pass? |
|---|---|
| App launches without crash | |
| Permission dialog appears after login | |
| Subscription visible in OneSignal dashboard | |
| external_user_id matches Firebase UID | |
| Foreground push received | |
| Background push appears in tray | |
| Terminated push appears in tray | |
| Notification tap opens correct screen | |
| Tapped notification is marked read in Firestore | |
| Badge count updates after tap | |
| Logout/login cycles maintain correct identity | |
| Cross-user isolation (Student B doesn't get Student A's push) | |

## Known Limitation

**Automated push dispatch is not active.** Until Cloud Functions are deployed (requires Firebase Blaze plan), all pushes must be sent manually from the OneSignal Dashboard. Firestore notification documents are created normally by admin users — the app reads them in-app — but no push is dispatched automatically. See `docs/onesignal_trigger_gap.md` for details.
