# OneSignal Push Dispatch: Trigger Gap Analysis

## Current State

Three Cloud Functions in `functions/index.js` handle notification dispatch:

| Trigger | Firestore Path | Action |
|---|---|---|
| `onMatchCreated` | `matches/{matchId}` (status: "proposed") | Creates `lfNotification` via Admin SDK |
| `onLfNotificationCreated` | `lfNotifications/{notificationId}` | Checks `lostFoundMatches` pref, sends FCM push |
| `onLockerNotificationCreated` | `lockerNotifications/{notificationId}` | Checks `lockerReminders` pref, sends FCM push |

All three use `admin.messaging().sendEachForMulticast()` — **FCM Admin SDK**.

## Why They Cannot Send OneSignal Pushes Today

1. **Cloud Functions are NOT deployed.** Firebase Blaze plan is required for outbound FCM calls. The project is on Spark.
2. **No alternative server-side trigger exists.** The Cloudflare Worker (`campus-connect-ai`) is stateless AI matching only — no Firebase Admin SDK, no Firestore triggers, no OneSignal REST API.
3. **Client-side dispatch is not acceptable.** The Flutter client cannot hold the OneSignal REST API key (security constraint).

## End-to-End Flow Available Today

```
Admin creates notification in Firestore (client-side)
      ↓
lfNotifications/{id} or lockerNotifications/{id} written
      ↓
Student's Flutter app reads Firestore notifications in-app
      ↓
No push delivered — notification visible only inside the app
```

## Required Changes for OneSignal Dispatch

When Cloud Functions can be deployed, modify `sendPush` to call OneSignal's REST API:

```js
// REPLACE: admin.messaging().sendEachForMulticast(message)
// WITH:
const ONE_SIGNAL_APP_ID = process.env.ONE_SIGNAL_APP_ID;
const ONE_SIGNAL_API_KEY = process.env.ONE_SIGNAL_REST_API_KEY; // secret!

await fetch("https://onesignal.com/api/v1/notifications", {
  method: "POST",
  headers: {
    "Authorization": `Basic ${ONE_SIGNAL_API_KEY}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    app_id: ONE_SIGNAL_APP_ID,
    include_external_user_ids: [uid],
    headings: { en: title },
    contents: { en: body },
    data: dataPayload, // { type, notificationId, relatedReportId }
    channel_for_external_user_ids: "push",
  }),
});
```

**Key mappings:**

| FCM Concept | OneSignal Equivalent |
|---|---|
| FCM token → `deviceTokens/{id}` | OneSignal subscription (automatic) |
| `admin.messaging().sendEachForMulticast()` | `POST /api/v1/notifications` with `include_external_user_ids` |
| `message.data` payload | `data` field in OneSignal REST API |
| Stale token cleanup by error code | OneSignal handles invalid subscriptions internally |

**Secrets required (via `firebase functions:secrets:set`):**
- `ONE_SIGNAL_REST_API_KEY` — the server-side REST API key from OneSignal dashboard

**Safe for client-side (already configured):**
- OneSignal App ID: `031d61a8-0a3a-4de8-9d88-d3e739896da5` (used in Flutter SDK)

## What Works WITHOUT Cloud Functions

| Feature | Status | Notes |
|---|---|---|
| OneSignal SDK initialization | ✅ | `main.dart` initializes SDK |
| User identity mapping | ✅ | `setExternalUserId(uid)` at login |
| Permission request | ✅ | 2s delay after login |
| Notification click → deep link | ✅ | `_handleOneSignalTap` → GoRouter |
| Read/unread sync | ✅ | Tap marks Firestore read |
| Badge count | ✅ | Firestore unread count (unchanged) |
| Firestore notifications (in-app) | ✅ | Phase 1, unchanged |
| **Push delivery** | ❌ | Requires server-side dispatch |

## Recommendation

Keep the existing Cloud Functions intact (they are the correct architecture). When the Firebase Blaze plan is activated and OneSignal REST API key is configured as a secret, modify `sendPush` as documented above and deploy. Until then, in-app Firestore notifications remain fully functional — push is the only missing layer.
