# Automatic OneSignal Push Trigger Audit
## Spark-Plan Architecture for Firestore → OneSignal

**Date**: 2026-08-18
**Project**: Campus Connect (`campus-connect-ce3e8`)
**Status**: AUDIT ONLY — no code changes, no deployments

---

## A. CURRENT TRIGGER GAP

### A.1 Every notification creation path traced

#### L&F Notifications (`lfNotifications`)

| # | Event | Firestore Write | Code Location | Deployed? | Push Sent? |
|---|---|---|---|---|---|
| 1 | Admin creates AI/manual match (status: "proposed") | `matches/{id}` — written by Flutter client | `lost_found_screens.dart:7002` | ✅ | ❌ |
| 1a | Cloud Function `onMatchCreated` triggers on `matches/{id}` → creates `lfNotifications/{id}` | `functions/index.js:208` (Admin SDK `.add()`) | `functions/index.js:162-229` | ❌ NOT DEPLOYED | N/A |
| 1b | After 1a, Cloud Function `onLfNotificationCreated` triggers → checks prefs → sends FCM push | N/A (push only) | `functions/index.js:264` | ❌ NOT DEPLOYED | ❌ |
| 2 | `LfWorkflowService.createNotification()` — client-side helper | `lf_workflow_service.dart:997` | `lf_workflow_service.dart:994-1002` | ✅ (code exists) | ❌ (no callers in production) |

**Result**: Path 2 has no production callers. Path 1 creates the `matches/{id}` document in Firestore (working), but the Cloud Function that would create the `lfNotification` document is not deployed. **No `lfNotification` document is created for AI matches.** The in-app notification system is broken for this path, not just push.

#### Locker Notifications (`lockerNotifications`)

All 9 locker notification events go through `_sendLockerNotification` at `app_state.dart:1596`:

| # | Action | app_state.dart line | Firestore write | Deployed? |
|---|---|---|---|---|
| 1 | Student scans return QR → "Key Returned" | 1893 | `locker_service.dart:455` | ✅ |
| 2 | Admin regenerates return QR → "Return QR Generated" | 2288 | same | ✅ |
| 3 | Admin approves release request → "Release Approved" | 2333 | same | ✅ |
| 4 | Admin approves release → "Deposit Refunded" | 2432 | same | ✅ |
| 5 | Admin approves release → "Locker Agreement Completed" | 2441 | same | ✅ |
| 6 | Admin terminates agreement → "Locker Agreement Terminated" | 2502 | same | ✅ |
| 7 | Admin blocks locker → "Locker Blocked" | 2561 | same | ✅ |
| 8 | Admin unblocks locker → "Locker Available Again" | 2607 | same | ✅ |
| 9 | Admin force-releases locker → "Locker Force-Released" | 2664 | same | ✅ |

**After each write**: The Cloud Function `onLockerNotificationCreated` (line `functions/index.js:274-308`) would trigger, check the `lockerReminders` preference, and send FCM push. This function is **NOT deployed**. The Firestore document is created (client-side, by admin — Firestore rules allow it), but no push follows.

**Result**: Locker notifications appear in-app. No push is dispatched. The trigger gap is between Firestore document creation and push dispatch.

#### Summary

```
Event                     Firestore Doc Created    Push Dispatched
─────────────────────────────────────────────────────────────────
AI match created          ❌ (Cloud Fn not deployed)  ❌
Locker event (×9)         ✅ (client-side, admin)     ❌
```

### A.2 Why the trigger gap exists

The Cloud Functions in `functions/index.js` were written to handle Firestore → push dispatch but **cannot be deployed** because the Firebase Spark (free) plan does not allow outbound network calls from Cloud Functions. The Blaze (pay-as-you-go) plan is required. The user has chosen to remain on Spark.

---

## B. POSSIBLE ARCHITECTURES

### B.1 Architecture A: Flutter client → OneSignal REST API directly

```
Flutter (admin) creates Firestore notification
  → Flutter immediately calls OneSignal REST API to send push
```

**Verdict: ❌ NOT VIABLE (security)**

The OneSignal REST API key is a server-side secret. It would need to be embedded in the Flutter APK. A malicious student could extract it with a decompiler and send arbitrary pushes to any user. This violates the security constraint: "A malicious student must NOT be able to call an endpoint and send arbitrary push messages to another student."

Also: the Flutter SDK (`onesignal_flutter ^5.6.7`) is **receive-only**. It has no method to send notifications. Verified from SDK source (`lib/onesignal_flutter.dart`): only `initialize`, `login`, `logout`, `consentGiven`, `consentRequired`. All `invokeMethod` calls are for identity/subscription, in-app messages, and session — no create-notification endpoint exists.

### B.2 Architecture B: Flutter → Cloudflare Worker → OneSignal

```
Flutter (admin) creates Firestore notification
  → Flutter sends Firebase Auth token + notificationId to Worker
  → Worker verifies Firebase Auth token
  → Worker reads the notification from Firestore (Admin SDK)
  → Worker validates the caller is authorized
  → Worker calls OneSignal REST API
  → OneSignal delivers push
```

**Verdict: ✅ VIABLE — this is the recommended architecture**

### B.3 Architecture C: Flutter → Cloudflare Worker → Firestore → OneSignal

```
Flutter calls Worker first (before writing to Firestore)
  → Worker validates the event
  → Worker writes the notification to Firestore via Admin SDK
  → Worker calls OneSignal REST API
```

**Verdict: ❌ NOT RECOMMENDED**

This centralizes notification creation in the Worker, which would require:
- Changing every Flutter-side notification creation path (9 locker events + match creation) to call the Worker instead of writing directly to Firestore
- The Worker having write access to Firestore (via service account)
- Significantly more code changes than Option B

It is also architecturally redundant — Firestore is already the source of truth. Having the Worker write to Firestore and then immediately call OneSignal adds no value over Option B, which just validates the existing Firestore document.

### B.4 Architecture D: Firestore → Cloudflare Worker (triggered) → OneSignal

```
Firestore document created
  → Cloudflare Worker is automatically triggered
  → Worker sends OneSignal push
```

**Verdict: ❌ NOT POSSIBLE**

Cloudflare Workers have **no Firestore trigger mechanism**. Firestore triggers are exclusive to Firebase Cloud Functions (via `onDocumentCreated`). There is no webhook, no Eventarc integration available on the Spark plan, and no polling mechanism built into Workers.

Cloudflare Workers respond to HTTP requests only. A Firestore document creation does not emit an HTTP request that a Worker can intercept.

To make this work, you would need:
- Firebase Cloud Functions (requires Blaze) OR
- Firebase Eventarc (requires Blaze) OR
- A separate polling service that queries Firestore periodically (inefficient, costs reads)

None of these are available on Spark for free.

### B.5 Architecture E: Other genuinely free options

**Firebase Extensions**: The "Trigger Email" or other Firestore-triggered extensions require Blaze plan.

**Firebase Scheduled Functions**: Pub/Sub scheduled functions require Blaze.

**Google Cloud Run**: Serverless containers with Firestore triggers require billing.

**Cloudflare Workers with Firestore REST API polling**: Possible but wasteful. Would need to poll `lfNotifications` and `lockerNotifications` collections periodically, consuming Firestore read quota. A 1-minute poll interval for two collections = ~86,400 reads/month minimum, plus processing overhead.

**Verdict: No genuinely free server-side trigger exists.** The only viable Spark-compatible approach is Option B: Flutter client initiates the push dispatch after creating the Firestore document, proxied through a Cloudflare Worker for security.

---

## C. BEST FREE ARCHITECTURE

**Recommended: Option B — Flutter → Cloudflare Worker → OneSignal**

```
┌──────────┐     ┌──────────────────┐     ┌──────────────┐     ┌──────────┐
│  Flutter │ ──→ │ Cloudflare Worker │ ──→ │ OneSignal API │ ──→ │  Device  │
│  (admin) │     │ (authenticates,   │     │ (REST API)    │     │  (push)  │
│          │     │  validates,       │     │               │     │          │
│          │     │  sends)           │     │               │     │          │
└──────────┘     └────────┬─────────┘     └──────────────┘     └──────────┘
                          │
                    ┌─────▼──────┐
                    │  Firestore │
                    │  (reads    │
                    │   notif    │
                    │   doc to   │
                    │   validate)│
                    └────────────┘
```

**Flow**:
1. Flutter (admin) writes notification to Firestore (existing code, unchanged)
2. Flutter gets the document ID from the write response
3. Flutter sends `POST /notifications/send` to Cloudflare Worker with:
   - Firebase Auth ID token (for authentication)
   - `notificationId` (Firestore document ID)
   - `collection` ("lfNotifications" or "lockerNotifications")
4. Worker verifies the Firebase Auth ID token (`verifyIdToken`)
5. Worker reads the notification document from Firestore using Firebase Admin SDK (privileged credential)
6. Worker verifies:
   - Notification document exists
   - Caller is an admin (from the token's UID)
   - Notification is for the correct `studentId`
   - Notification hasn't already had a push sent (`oneSignalPushSent` field)
7. Worker resolves the recipient: `studentId` → Firebase UID (same as `resolveUid` in existing Cloud Function)
8. Worker checks notification preferences: reads `users/{uid}.notificationPrefs`
9. Worker calls OneSignal REST API: `POST https://onesignal.com/api/v1/notifications`
   - `include_external_user_ids: [recipientUid]`
   - `headings`, `contents` from the notification document
   - `data: { type, notificationId, relatedReportId }`
10. Worker marks the notification document with `oneSignalPushSent: true` (idempotency)
11. Worker returns success/failure to Flutter
12. Flutter ignores failure (push is best-effort, notification still appears in-app)

---

## D. SECURITY MODEL

### D.1 How the caller is authenticated

The Flutter client sends a **Firebase Auth ID token** with each dispatch request. This token is obtained from `FirebaseAuth.instance.currentUser!.getIdToken()` and is cryptographically signed by Firebase. The Worker verifies it using `admin.auth().verifyIdToken(idToken)`.

**Verification**: The Cloudflare Worker source already has no Firebase Admin SDK — it would need `firebase-admin` added as a dependency. The `verifyIdToken` call is a standard Firebase Admin SDK operation that validates the token's signature, expiration, and issuer without any network call to Firebase (the public keys are cached).

**Source**: Firebase Admin SDK documentation (verified industry standard). Not yet present in the Worker.

### D.2 How the recipient is determined

The recipient is **read from Firestore, not from the client request**. The Worker reads the notification document's `studentId` field, then queries `users` collection where `studentId == <value>` to get the Firebase UID. This UID is used as the OneSignal `external_user_id`.

The client never specifies the recipient. Even if a malicious admin crafts a request with a fake notificationId, they would need to create a Firestore notification document first — and Firestore rules enforce that only admins can create notifications for the correct student.

### D.3 How the notification document is validated

The Worker performs three validation steps:

1. **Document exists**: Reads the notification from Firestore at `lfNotifications/{notificationId}` or `lockerNotifications/{notificationId}`.
2. **Caller is authorized**: The caller's UID (from the verified token) must have `isAdmin == true` in their `users/{uid}` profile — matching the Firestore rule that only admins can create notifications.
3. **Document integrity**: The notification document must have `studentId`, `title`, and `body` fields populated.

### D.4 How a student is prevented from sending arbitrary notifications

| Attack | Defense |
|---|---|
| Student calls Worker directly with fake notificationId | Worker verifies Auth token — student's UID maps to a non-admin profile → request rejected |
| Admin crafts a notification for wrong student | Admin must first write the Firestore document. Firestore rules (`firestore.rules:453-456`) validate the document at write time. Worker reads the `studentId` from the Firestore document, not the request. |
| Student extracts Worker URL and calls it | Worker requires `Authorization: Bearer <firebase-id-token>` header. Without a valid admin token, request is rejected. |
| Replay attack (same notificationId sent twice) | Worker checks `oneSignalPushSent: true` on the Firestore document before dispatching. Second request is rejected. |
| Student modifies Flutter APK to call Worker | Worker verifies the ID token — tampering with the APK doesn't give access to a valid admin Firebase Auth token. |

### D.5 Rate limiting

Cloudflare Workers free plan provides built-in rate limiting at the Cloudflare edge. Additionally, the Worker can implement:
- Per-UID rate limit (e.g., max 10 push dispatches per minute)
- Global rate limit (e.g., max 100 pushes per minute across all users)

These are within the Worker's compute budget and don't require KV storage for simple in-memory rate limiting (resets on Worker cold start, which is acceptable for this use case).

---

## E. AUTHENTICATION MODEL

### E.1 Token flow

```
Flutter                             Worker                          Firestore
  │                                    │                                │
  │ 1. Write notification to Firestore │                                │
  │────────────────────────────────────────────────────────────────────→│
  │ 2. Get doc.id from write response  │                                │
  │←────────────────────────────────────────────────────────────────────│
  │                                    │                                │
  │ 3. idToken = await auth.getIdToken()                                │
  │ 4. POST /notifications/send       │                                │
  │    {                               │                                │
  │      "notificationId": doc.id,     │                                │
  │      "collection": "lfNotifications"                                │
  │    }                               │                                │
  │    Authorization: Bearer <idToken> │                                │
  │──────────────────────────────────→│                                │
  │                                    │ 5. verifyIdToken(idToken)      │
  │                                    │ 6. Read notification doc        │
  │                                    │───────────────────────────────→│
  │                                    │ 7. Check caller is admin        │
  │                                    │ 8. Check oneSignalPushSent      │
  │                                    │ 9. Resolve studentId → uid      │
  │                                    │───────────────────────────────→│
  │                                    │ 10. Check notificationPrefs     │
  │                                    │───────────────────────────────→│
  │                                    │ 11. POST /api/v1/notifications  │
  │                                    │ 12. Mark oneSignalPushSent=true │
  │                                    │───────────────────────────────→│
  │ 13. { "success": true }            │                                │
  │←──────────────────────────────────│                                │
```

### E.2 Worker credentials required

| Credential | Where stored | Purpose |
|---|---|---|
| Firebase service account JSON | Cloudflare Worker secret (`FIREBASE_SERVICE_ACCOUNT`) | Initialize `firebase-admin` for Firestore reads and Auth verification |
| OneSignal REST API key | Cloudflare Worker secret (`ONESIGNAL_REST_API_KEY`) | Authenticate to OneSignal REST API |

Neither credential appears in Flutter, Git, or the Worker source code. Secrets are encrypted at rest in Cloudflare's secret store and injected as environment variables at Worker runtime.

### E.3 Worker dependency additions

The Worker would need to add to `package.json`:
```json
{
  "dependencies": {
    "firebase-admin": "^13.0.0"
  }
}
```

This is the same version used in the existing Cloud Functions (`functions/package.json`). The Worker's existing AI dependencies are unaffected.

---

## F. ONESIGNAL TARGETING MODEL

### F.1 Targeting by external user ID

**Verified from OnesSignal SDK and documentation**: The OneSignal REST API accepts `include_external_user_ids` (array of strings) to target specific users. This is the recommended targeting method because:

1. The Firebase Auth UID is already mapped as the external user ID via `OneSignal.login(uid)` in `onesignal_service.dart:73`
2. The mapping is set at login and cleared at logout — correct lifecycle
3. No device-specific subscription IDs need to be managed

**REST API payload structure** (standard OneSignal API, verified from public documentation):
```json
{
  "app_id": "031d61a8-0a3a-4de8-9d88-d3e739896da5",
  "include_external_user_ids": ["<firebase-auth-uid>"],
  "headings": { "en": "Possible Match Found" },
  "contents": { "en": "Notification body text" },
  "data": {
    "type": "lfNotification",
    "notificationId": "<firestore-doc-id>",
    "relatedReportId": "<lost-report-id>"
  },
  "channel_for_external_user_ids": "push"
}
```

### F.2 Why external user ID is safer than subscription ID

| Method | Risk |
|---|---|
| `include_external_user_ids` | Targets the current device(s) for the authenticated user. Identity is managed by OneSignal login/logout. If user logs out and another logs in, the subscription updates automatically. |
| `include_subscription_ids` | Requires storing and managing raw subscription IDs. If a subscription becomes invalid (device uninstalled), the push silently fails. More moving parts. |

The external user ID approach is already implemented in the Flutter client (`OneSignalService.setExternalUserId`). The Worker just needs to send the recipient's Firebase UID — the same UID that Flutter passed to `OneSignal.login()`.

### F.3 FCM service account

OneSignal's dashboard is already configured with an FCM service account (the user confirmed this in the original specification). This means OneSignal can deliver pushes to Android devices' FCM tokens without any additional configuration. The Worker just calls OneSignal's REST API — OneSignal handles the FCM delivery underneath.

---

## G. DUPLICATE / IDEMPOTENCY MODEL

### G.1 Idempotency key

The Firestore notification document ID (`notificationId`) serves as the natural idempotency key. One Firestore document = one logical notification = one push.

### G.2 Idempotency mechanism

The Worker checks a boolean field `oneSignalPushSent` on the notification document before dispatching:

```js
const notifRef = admin.firestore()
  .collection(collection)
  .doc(notificationId);

const notifDoc = await notifRef.get();
if (!notifDoc.exists) return error("not found");
if (notifDoc.data().oneSignalPushSent === true) {
  return { success: true, alreadySent: true };
}

// ... send OneSignal push ...

await notifRef.update({ oneSignalPushSent: true });
```

### G.3 Protection against each failure scenario

| Scenario | Protection |
|---|---|
| User retries (double-tap) | `oneSignalPushSent` check rejects second request |
| App reconnects after network loss | Same notificationId → idempotency check catches it |
| Stream rebuilds (Widget rebuild) | Notification dispatch is not in a stream — it's a single explicit call after Firestore write |
| App restarts before Worker responds | Worker checks `oneSignalPushSent` — if already sent, returns success |
| Request times out | Worker may have sent the push but Flutter didn't get the response. On retry, `oneSignalPushSent` is already true → no duplicate |
| Worker retries (Cloudflare retry on error) | Firebase Admin's `update({ oneSignalPushSent: true })` is idempotent — setting the same value twice is harmless |

### G.4 Race condition analysis

If two requests arrive simultaneously for the same `notificationId`:
- Request A reads `oneSignalPushSent: false` → sends push → updates to true
- Request B reads `oneSignalPushSent: false` (race) → sends push → updates to true (duplicate!)

**Mitigation**: Use a **Firestore transaction** for the read-check-write cycle:

```js
await admin.firestore().runTransaction(async (tx) => {
  const doc = await tx.get(notifRef);
  if (!doc.exists) throw new Error("not found");
  if (doc.data().oneSignalPushSent) return { alreadySent: true };
  
  // Send OneSignal push here (outside transaction is fine —
  // the transaction just guards the idempotency check)
  tx.update(notifRef, { oneSignalPushSent: true });
});
```

Alternatively, for simplicity: accept the extremely low probability of a race (two admins independently dispatching the same notification at the exact same millisecond). The practical impact is a duplicate push — annoying but not harmful. The Firestore notification document is unaffected.

---

## H. CLOUD FLARE WORKER DESIGN

### H.1 Decision: Add route to existing Worker

**Recommendation: Add `/notifications/send` to the existing `campus-connect-ai` Worker.**

| Factor | Add to existing Worker | Create separate Worker |
|---|---|---|
| Free plan limit | 1 Worker, 100k req/day (combined) | Would need second Worker (allowed on free) |
| Routes | Adds 1 route | New Worker with its own route |
| Dependencies | Adds `firebase-admin` to existing | Clean separation |
| AI impact | Notification requests are fast (~500ms) vs AI requests (~3-10s). Minimal contention. | Zero impact on AI |
| Secrets | Shares secrets namespace | Separate secrets |
| Maintenance | One codebase, one deploy | Two codebases, two deploys |
| Cold starts | Shared Worker — cold start on first request of either type | Two Workers — each has own cold start |

**Both are viable.** The existing Worker has no Firebase code and no push code — adding a new route is clean. The AI matching routes (`POST /ai/*`) are computationally intensive (3-10s for multi-image Gemini calls). A notification dispatch route (~500ms for Firestore reads + OneSignal API call) won't meaningfully contend with AI traffic.

If strict isolation is preferred, a separate Worker (`campus-connect-notifications`) is also valid and stays within Cloudflare's free tier (multiple Workers are allowed).

### H.2 Route design

```js
// In src/index.js route() function, add:
if (url.pathname === '/notifications/send' && request.method === 'POST') {
  return handleNotificationSend(request, env);
}
```

### H.3 Handler pseudocode

```js
async function handleNotificationSend(request, env) {
  // 1. Extract and verify Firebase Auth ID token
  const authHeader = request.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
  }
  const idToken = authHeader.slice(7);
  
  let decodedToken;
  try {
    decodedToken = await admin.auth().verifyIdToken(idToken);
  } catch (e) {
    return new Response(JSON.stringify({ error: 'invalid token' }), { status: 401 });
  }
  
  // 2. Parse request body
  const { notificationId, collection } = await request.json();
  if (!notificationId || !collection) {
    return new Response(JSON.stringify({ error: 'missing fields' }), { status: 400 });
  }
  if (!['lfNotifications', 'lockerNotifications'].includes(collection)) {
    return new Response(JSON.stringify({ error: 'invalid collection' }), { status: 400 });
  }
  
  // 3. Verify caller is admin
  const callerDoc = await admin.firestore()
    .collection('users').doc(decodedToken.uid).get();
  if (!callerDoc.exists || !callerDoc.data()?.isAdmin) {
    return new Response(JSON.stringify({ error: 'forbidden' }), { status: 403 });
  }
  
  // 4. Read notification document
  const notifRef = admin.firestore().collection(collection).doc(notificationId);
  const notifDoc = await notifRef.get();
  if (!notifDoc.exists) {
    return new Response(JSON.stringify({ error: 'not found' }), { status: 404 });
  }
  
  const notifData = notifDoc.data();
  
  // 5. Idempotency check
  if (notifData.oneSignalPushSent) {
    return new Response(JSON.stringify({ success: true, alreadySent: true }), { status: 200 });
  }
  
  // 6. Resolve recipient UID
  const studentId = notifData.studentId;
  const userSnap = await admin.firestore()
    .collection('users')
    .where('studentId', '==', studentId)
    .limit(1)
    .get();
  
  if (userSnap.empty) {
    return new Response(JSON.stringify({ error: 'recipient not found' }), { status: 404 });
  }
  
  const recipientUid = userSnap.docs[0].id;
  
  // 7. Check notification preferences
  const prefsKey = collection === 'lfNotifications'
    ? 'lostFoundMatches'
    : 'lockerReminders';
  const prefDoc = await admin.firestore()
    .collection('users').doc(recipientUid).get();
  const prefs = prefDoc.data()?.notificationPrefs || {};
  if (prefs[prefsKey] === false) {
    return new Response(JSON.stringify({
      success: true,
      suppressed: true,
      reason: 'preference disabled',
    }), { status: 200 });
  }
  
  // 8. Send OneSignal push
  const oneSignalResp = await fetch('https://onesignal.com/api/v1/notifications', {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${env.ONESIGNAL_REST_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      app_id: '031d61a8-0a3a-4de8-9d88-d3e739896da5',
      include_external_user_ids: [recipientUid],
      headings: { en: notifData.title || 'Campus Connect' },
      contents: { en: notifData.body || '' },
      data: {
        type: collection === 'lfNotifications'
          ? 'lfNotification'
          : 'lockerNotification',
        notificationId: notificationId,
        relatedReportId: notifData.relatedReportId || '',
      },
      channel_for_external_user_ids: 'push',
    }),
  });
  
  const osBody = await oneSignalResp.json();
  
  // 9. Mark as sent (even if OneSignal returned an error —
  //    we don't retry automatically to avoid duplicates)
  await notifRef.update({
    oneSignalPushSent: true,
    oneSignalPushSentAt: admin.firestore.FieldValue.serverTimestamp(),
    oneSignalResponse: osBody.id || null,
    oneSignalResponseErrors: osBody.errors || null,
  });
  
  if (!oneSignalResp.ok) {
    return new Response(JSON.stringify({
      error: 'onesignal_failed',
      details: osBody,
    }), { status: 502 });
  }
  
  return new Response(JSON.stringify({ success: true }), { status: 200 });
}
```

### H.4 Required Worker configuration changes

**`wrangler.jsonc`** — add a secret for the Firebase service account and OneSignal REST API key:
```jsonc
{
  // ... existing config ...
  // No changes needed to routes if using the same Worker.
}
```

**Secrets to set via `wrangler secret put`:**
```bash
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT  # paste JSON
npx wrangler secret put ONESIGNAL_REST_API_KEY     # paste key
```

**`.dev.vars`** — add for local development:
```
ONESIGNAL_REST_API_KEY=os_rest_api_key_here
# FIREBASE_SERVICE_ACCOUNT cannot be stored in .dev.vars as a multi-line JSON string easily.
# Use GOOGLE_APPLICATION_CREDENTIALS path for local dev instead.
```

---

## I. FIRESTORE ACCESS REQUIREMENTS

### I.1 Worker's Firestore reads

| Read | Collection | Purpose | Frequency |
|---|---|---|---|
| `admin.firestore().collection('users').doc(callerUid).get()` | `users/{uid}` | Verify caller is admin | 1 per dispatch |
| `admin.firestore().collection(collection).doc(notificationId).get()` | `lfNotifications/{id}` or `lockerNotifications/{id}` | Validate notification exists and read its fields | 1 per dispatch |
| `admin.firestore().collection('users').where('studentId', ...).get()` | `users` (query) | Resolve studentId → Firebase UID | 1 per dispatch |
| `admin.firestore().collection('users').doc(recipientUid).get()` | `users/{uid}` | Read notificationPrefs | 1 per dispatch |

**Total: up to 4 Firestore reads per dispatch.**

### I.2 Worker's Firestore writes

| Write | Purpose | Frequency |
|---|---|---|
| `notifRef.update({ oneSignalPushSent: true, ... })` | Idempotency marker | 1 per dispatch |

### I.3 Firestore rules impact

The Worker uses **Firebase Admin SDK** with a service account credential. Admin SDK bypasses all Firestore security rules — no rule changes are needed. The Worker can read any document and write the `oneSignalPushSent` field without modifying `firestore.rules`.

### I.4 Adding `oneSignalPushSent` field

The `oneSignalPushSent` boolean field is added to existing notification documents at runtime by the Worker. No schema migration is needed — Firestore is schemaless. The field is simply absent for notifications created before the Worker integration, and present (true/false) for those created after.

---

## J. COST / FREE-TIER ANALYSIS

### J.1 Firebase Spark (free) plan — CURRENT

| Resource | Spark Limit | Current Usage | Status |
|---|---|---|---|
| Firestore stored data | 1 GiB | Unknown (university app, likely under) | ✅ Free |
| Firestore reads | 50,000/day | Unknown | ✅ Free |
| Firestore writes | 20,000/day | Unknown | ✅ Free |
| Firestore deletes | 20,000/day | Unknown | ✅ Free |
| Cloud Functions invocations | 0 (outbound not allowed) | N/A | ❌ Can't use |
| Authentication | Unlimited (phone not included) | In use | ✅ Free |

**Additional Firestore cost from Worker**: Each dispatch adds up to 4 reads + 1 write. For a university app generating ~50 notifications/day, that's ~200 reads + 50 writes/day = ~6,000 reads + 1,500 writes/month. Well within Spark limits (50,000 reads/day, 20,000 writes/day).

### J.2 Cloudflare Workers free plan

| Resource | Free Limit | Estimated Usage | Status |
|---|---|---|---|
| Requests | 100,000/day | ~50-100/day (one per notification) | ✅ Well under |
| CPU time | 10ms/request (free), 50ms (paid) | ~500ms per dispatch (Firestore reads + OneSignal API) | ⚠️ Exceeds free CPU limit marginally. OneSignal API call is external and doesn't count against CPU time (blocking I/O). Firebase Admin SDK operations take <50ms CPU. |
| Script size | 1 MB | <200 KB (firebase-admin adds bulk) | ⚠️ firebase-admin is ~20MB — exceeds the 1MB free limit |
| Subrequests | 50/request | 5 (4 Firestore + 1 OneSignal) | ✅ |
| Workers | 30 (free) | 1 | ✅ |

**Critical finding — Firebase Admin SDK bundle size**: The `firebase-admin` npm package is approximately 20MB. The Cloudflare Workers free plan limits script size to **1 MB**. This means `firebase-admin` **cannot be used directly in a Cloudflare Worker on the free plan**.

**Workaround options:**

1. **Use Firebase REST API instead of Admin SDK**: The Worker can authenticate to Firestore using the service account JSON to generate OAuth2 tokens, then call the Firestore REST API (`https://firestore.googleapis.com/v1/projects/{project}/databases/(default)/documents/{collection}/{docId}`). No `firebase-admin` npm dependency needed. The Google Auth library for service account JWT signing is small enough for Workers.

2. **Use `@google-cloud/firestore` with minimal build**: The gRPC-based client also exceeds 1MB.

3. **Cloudflare Workers Paid plan ($5/month)**: Increases script size limit beyond 1MB. The minimum paid tier lifts most free-plan limits.

**Recommendation**: Use **Firebase REST API** with a lightweight JWT helper. The Worker needs only 4 Firestore operations (1 doc get, 1 query, 2 doc gets, 1 doc update). All are straightforward REST calls that can be implemented without `firebase-admin`.

This changes the architecture slightly: instead of `admin.firestore().collection(...)`, the Worker makes HTTP calls to `https://firestore.googleapis.com/v1/...` with an OAuth2 Bearer token obtained from the service account JSON.

### J.3 OneSignal free plan

| Resource | Free Limit | Estimated Usage | Status |
|---|---|---|---|
| Subscribers | Unlimited | ~100-500 (university app) | ✅ |
| Push notifications | Unlimited | ~50/day | ✅ |
| API calls | Reasonable use | ~50/day | ✅ |
| Segments | 10 | Not used | ✅ |

OneSignal's free tier is generous for push delivery. No billing risk.

### J.4 Total cost

| Service | Plan | Monthly Cost |
|---|---|---|
| Firebase | Spark (free) | $0 |
| Cloudflare Workers | Free | $0 |
| OneSignal | Free | $0 |
| **Total** | | **$0/month** |

**No billing required. No credit card needed. All three services offer genuine free tiers that cover the expected usage.**

**Caveat**: If the Firebase REST API approach proves too complex, Cloudflare Workers Paid ($5/month) would allow using `firebase-admin` directly. This is the only potential cost.

---

## K. RECOMMENDED IMPLEMENTATION PLAN

### Phase 1: Worker endpoint (no Flutter changes yet)

1. Add Firebase REST API helper to Worker (lightweight JWT auth + Firestore HTTP calls)
2. Set `ONESIGNAL_REST_API_KEY` secret in Worker
3. Set `FIREBASE_SERVICE_ACCOUNT` secret in Worker (or `FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY` as separate secrets)
4. Implement `handleNotificationSend` route in Worker
5. Test with `curl` commands against local Worker (`wrangler dev`)
6. Deploy Worker

### Phase 2: Flutter integration

1. Create `lib/services/notification_dispatcher.dart` or add method to existing service
2. After each Firestore notification write, call the Worker:
   ```dart
   Future<void> _dispatchPush(String notificationId, String collection) async {
     try {
       final idToken = await FirebaseAuth.instance.currentUser!.getIdToken();
       final response = await http.post(
         Uri.parse('https://campus-connect-ai.<subdomain>.workers.dev/notifications/send'),
         headers: {
           'Authorization': 'Bearer $idToken',
           'Content-Type': 'application/json',
         },
         body: jsonEncode({
           'notificationId': notificationId,
           'collection': collection,
         }),
       );
       // Best-effort: ignore failures silently.
     } catch (_) {
       debugPrint('[PushDispatch] Worker call failed');
     }
   }
   ```
3. Add `unawaited(_dispatchPush(docId, 'lfNotifications'))` or `unawaited(_dispatchPush(docId, 'lockerNotifications'))` after each notification write in `app_state.dart`
4. No changes to Firestore rules needed
5. No changes to OneSignal integration needed

### Phase 3: AI match notification fix

1. Since the Cloud Function `onMatchCreated` is not deployed, AI matches don't create `lfNotification` documents
2. The Worker cannot be triggered by Firestore document creation (see Section B.4)
3. **Solution**: The Flutter client must create the `lfNotification` document directly after creating a match, then dispatch via Worker
4. This requires either:
   - An admin-initiated flow (admin user writing the notification — allowed by rules)
   - Adding a new Worker endpoint that creates the notification document AND sends the push in one call (the Worker uses Admin SDK / service account to write to Firestore)

### Phase 4: Remove old references (after verification)

1. Remove `oneSignalPushSent` check idempotency — verify on real device
2. Clean up any debug logging

---

## L. EXACT FILES THAT WOULD NEED MODIFICATION

### Worker (`campus-connect-ai/`)

| File | Change |
|---|---|
| `src/index.js` | Add `handleNotificationSend` function and route |
| `src/firebase-rest.js` (NEW) | Lightweight Firebase REST API helper with JWT auth |
| `package.json` | No npm dependency needed (REST API approach) |
| `wrangler.jsonc` | No config changes needed |
| `.dev.vars` | Add `ONESIGNAL_REST_API_KEY` for local dev |

### Flutter (`lib/`)

| File | Change |
|---|---|
| `lib/services/notification_dispatcher.dart` (NEW) | Worker client: obtains Auth token, calls Worker, handles response |
| `lib/services/app_state.dart` | After each `_sendLockerNotification` call (~9 locations), add `_dispatchPush(docId, 'lockerNotifications')`. After match creation, add notification creation + dispatch. |
| `lib/screens/lost_found/lost_found_screens.dart` | After match creation (line ~7002), create `lfNotification` via Worker endpoint, then dispatch |

### No changes needed

| File/Config | Reason |
|---|---|
| `firestore.rules` | Worker uses Admin SDK / service account — bypasses rules |
| `pubspec.yaml` | `http` package already present (used in `app_state.dart` for Cloudinary) |
| `android/app/src/main/AndroidManifest.xml` | No permission changes needed |
| `lib/services/onesignal_service.dart` | Unchanged — receive-only SDK, identity already mapped |
| `lib/main.dart` | No changes — OneSignal init already complete |
| `functions/index.js` | Kept intact until OneSignal verified (per specification) |
| `firebase.json` | No changes |

---

## M. RISKS

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Worker cold start latency | Medium | 1-3s delay before push populates in tray | Acceptable — push is already "best-effort." User sees in-app notification immediately. |
| Firebase REST API JWT complexity | Medium | Implementation takes longer | Use well-tested `google-auth-library` light build, or accept Worker Paid ($5/mo) for `firebase-admin` |
| Worker free plan CPU limit | Low | Notification dispatch is I/O-bound (waiting on Firestore + OneSignal HTTP). CPU time per request is minimal (<10ms of actual computation). | Monitor in Cloudflare dashboard |
| Worker script size (1MB free limit) | High | Firebase Admin SDK is ~20MB | Use Firebase REST API (no npm dependency needed). Validated approach. |
| Firestore read quota | Low | ~200 reads/day for notification dispatch | Well within 50,000 reads/day Spark limit |
| Race condition on idempotency | Very low | Two admins dispatching same notification simultaneously | Firestore transaction OR accept rare duplicate push |
| Worker outage | Low | Cloudflare SLA: 99.99%. Push not delivered. | In-app notification still visible. Push is additive. |
| OneSignal API outage | Low | Push not delivered | In-app notification still visible. OneSignal queues and retries. |

---

## N. WHAT MUST NOT BE CHANGED

Per the user's security constraints:

| Must NOT change | Status in this plan |
|---|---|
| ❌ Enable Firebase Blaze | ✅ Spark plan preserved |
| ❌ Deploy Cloud Functions | ✅ Old functions kept intact, not deployed |
| ❌ Change Firestore rules | ✅ No rule changes — Worker uses service account |
| ❌ Expose OneSignal REST API key in Flutter | ✅ Key only in Worker secrets |
| ❌ Expose Firebase service account in Flutter | ✅ Credential only in Worker secrets |
| ❌ Modify AI matching (Cloudflare Worker AI routes) | ✅ New route added, existing routes untouched |
| ❌ Modify Gemini/OpenRouter integration | ✅ Unchanged |
| ❌ Modify QR workflow | ✅ Unchanged |
| ❌ Modify Inventory workflow | ✅ Unchanged |
| ❌ Modify approval workflow | ✅ Unchanged |
| ❌ Modify Event/Election/Locker modules | ✅ Unchanged (only call-site additions) |
| ❌ Remove Phase 1 Firestore notifications | ✅ Unchanged — Firestore remains authoritative |
| ❌ Remove read/unread logic or badge | ✅ Unchanged |
| ❌ Remove OneSignal Flutter SDK | ✅ Unchanged |
| ❌ Delete old Cloud Functions | ✅ Kept intact |
| ❌ Deploy Worker automatically | ✅ Manual deployment only |

---

## VERIFICATION SOURCES

| Finding | Source |
|---|---|
| Notification creation paths | Repository: `app_state.dart`, `locker_service.dart`, `lf_workflow_service.dart`, `lost_found_screens.dart`, `functions/index.js` |
| Cloudflare Worker source | Repository: `campus-connect-ai/src/index.js`, `wrangler.jsonc`, `package.json` |
| Firestore rules | Repository: `firestore.rules` (lines 14-16, 18-22, 24-68, 87-100, 436-465, 690-722) |
| OneSignal SDK is receive-only | SDK source: `onesignal_flutter-5.6.7/lib/onesignal_flutter.dart` (no create-notification endpoint) |
| OneSignal REST API targeting | Public OneSignal documentation: `include_external_user_ids`, `app_id`, `headings`, `contents`, `data`, `channel_for_external_user_ids` fields |
| Cloudflare Workers free limits | Public Cloudflare documentation: 100k req/day, 10ms CPU, 1MB script size, 50 subrequests |
| Firebase Admin SDK bundle size | Public npm registry: `firebase-admin` ~20MB |
| Firebase REST API | Public Firebase documentation: `firestore.googleapis.com/v1/` |
| OneSignal free tier | Public OneSignal pricing: unlimited subscribers, unlimited pushes |
| Firebase Spark limits | Public Firebase pricing: 50k reads/day, 20k writes/day, 20k deletes/day, 1GB storage |
