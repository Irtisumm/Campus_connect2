/**
 * Campus Connect — Push Notification Dispatch
 *
 * Three Firestore-triggered Cloud Functions:
 *
 *   1. onMatchCreated
 *      When an AI match document is created with status "proposed", this
 *      function creates the corresponding `lfNotification` document.  This
 *      is the **fix** for the student-triggered AI-match path: the Flutter
 *      client can only write notifications as an admin, but AI matching
 *      runs from the student's client.  Writing from a trusted server-side
 *      trigger bypasses that restriction.
 *
 *   2. onLfNotificationCreated
 *      Reads the new L&F notification, resolves the recipient, checks
 *      their `lostFoundMatches` preference, and sends an FCM push.
 *
 *   3. onLockerNotificationCreated
 *      Same pattern for locker notifications; checks `lockerReminders`.
 *
 * Firestore remains the authoritative notification store.  Push is an
 * additional delivery channel — a push failure never deletes or rolls
 * back the Firestore notification document.
 */

const functions = require("firebase-functions/v2");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

admin.initializeApp();

// ── Helper: studentId → Firebase UID ─────────────────────────────

/**
 * Looks up the Firebase Auth UID for a campus Student ID by reading
 * the `users` collection.  Caches nothing — the query is simple and
 * runs once per notification.
 */
async function resolveUid(studentId) {
  const snap = await admin
    .firestore()
    .collection("users")
    .where("studentId", "==", studentId)
    .limit(1)
    .get();
  if (snap.empty) {
    logger.warn("resolveUid: no user found for studentId", {
      studentId,
    });
    return null;
  }
  return snap.docs[0].id;
}

// ── Helper: notification-preference check ────────────────────────

/**
 * Reads `notificationPrefs` from the user's profile document.  Returns
 * the boolean value for the given key, or `true` (default) when the key
 * is missing.
 */
async function checkPreference(uid, key) {
  try {
    const doc = await admin.firestore().collection("users").doc(uid).get();
    if (!doc.exists) return true;
    const prefs = doc.data().notificationPrefs || {};
    return prefs[key] !== false; // missing key → default true
  } catch (e) {
    logger.error("checkPreference: failed to read profile", { uid, error: e.message });
    return true; // fail open — deliver the push
  }
}

// ── Helper: send FCM push ────────────────────────────────────────

/**
 * Reads every device token for the given user, sends an FCM multicast,
 * and cleans up any tokens FCM reports as invalid/unregistered.
 */
async function sendPush(uid, title, body, dataPayload) {
  const tokensSnap = await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("deviceTokens")
    .get();

  if (tokensSnap.empty) {
    logger.info("sendPush: no tokens for user", { uid });
    return;
  }

  const tokens = [];
  const tokenDocs = [];

  tokensSnap.forEach((doc) => {
    const t = doc.data().token;
    if (t) {
      tokens.push(t);
      tokenDocs.push(doc.ref);
    }
  });

  if (tokens.length === 0) return;

  const message = {
    notification: {
      title: title || "Campus Connect",
      body: body || "",
    },
    data: {
      ...dataPayload,
      // Android needs this to deliver even when the app is backgrounded
      // on some devices.
      channelId: "campus_connect_notifications",
    },
    tokens: tokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    logger.info("sendPush: FCM response", {
      successCount: response.successCount,
      failureCount: response.failureCount,
    });

    // Clean up tokens that FCM reports as invalid.
    response.responses.forEach((resp, i) => {
      if (!resp.success) {
        const code = resp.error?.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-argument" ||
          code === "messaging/invalid-registration-token"
        ) {
          logger.info("sendPush: removing stale token", {
            errorCode: code,
          });
          tokenDocs[i].delete().catch(() => {
            // Best-effort cleanup.
          });
        }
      }
    });
  } catch (e) {
    logger.error("sendPush: FCM send failed", { error: e.message });
  }
}

// ── Trigger 1: AI Match → L&F Notification ───────────────────────

/**
 * When an AI match document is created with `status: "proposed"`, this
 * function creates the corresponding `lfNotification` document using
 * the Admin SDK (which bypasses the client-side admin-only rule).
 *
 * This is the fix for the student-triggered AI-match path.  The Flutter
 * client calls `createNotification` which Firestore denies for
 * non-admins; the failure was silently swallowed.  Now the Cloud
 * Function handles it server-side.
 */
exports.onMatchCreated = functions.firestore.onDocumentCreated(
  "matches/{matchId}",
  async (event) => {
    const match = event.data?.data();
    if (!match || match.status !== "proposed") return;

    const studentId = match.lostOwnerStudentId;
    const lostReportId = match.lostReportId;
    const inventoryItemId = match.inventoryItemId;

    if (!studentId || !lostReportId) {
      logger.warn("onMatchCreated: missing required fields", {
        matchId: event.params.matchId,
      });
      return;
    }

    // Read linked document titles so the notification body is useful.
    let lostTitle = "";
    let invTitle = "";
    try {
      const [lostDoc, invDoc] = await Promise.all([
        admin.firestore().collection("items").doc(lostReportId).get(),
        admin.firestore().collection("inventory").doc(inventoryItemId).get(),
      ]);
      lostTitle = lostDoc.exists
        ? lostDoc.data()?.title?.toString() || ""
        : "";
      invTitle = invDoc.exists
        ? invDoc.data()?.title?.toString() || ""
        : "";
    } catch (e) {
      logger.warn("onMatchCreated: failed to read linked docs", {
        error: e.message,
      });
    }

    const body =
      invTitle && lostTitle
        ? `A "${invTitle}" handed in at the Inventory Office may match ` +
          `your lost "${lostTitle}". Please visit the office to verify ` +
          `ownership.`
        : "A possible match was found for your lost item. Review it under " +
          "My Lost Reports.";

    try {
      await admin.firestore().collection("lfNotifications").add({
        studentId: studentId,
        title: "Possible Match Found",
        body: body,
        type: "match",
        relatedReportId: lostReportId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info("onMatchCreated: notification created", {
        studentId,
        lostReportId,
      });
    } catch (e) {
      logger.error("onMatchCreated: failed to create notification", {
        error: e.message,
        studentId,
        lostReportId,
      });
    }
  }
);

// ── Trigger 2: L&F Notification → Push ──────────────────────────

exports.onLfNotificationCreated = functions.firestore.onDocumentCreated(
  "lfNotifications/{notificationId}",
  async (event) => {
    const notif = event.data?.data();
    if (!notif) return;

    const studentId = notif.studentId;
    const notificationId = event.params.notificationId;
    const relatedReportId = notif.relatedReportId || "";

    if (!studentId) {
      logger.warn("onLfNotificationCreated: missing studentId", {
        notificationId,
      });
      return;
    }

    // Resolve the recipient.
    const uid = await resolveUid(studentId);
    if (!uid) return;

    // Honour notification preferences.
    const allowed = await checkPreference(uid, "lostFoundMatches");
    if (!allowed) {
      logger.info("onLfNotificationCreated: preference disabled", {
        uid,
        studentId,
      });
      return;
    }

    await sendPush(uid, notif.title, notif.body, {
      type: "lfNotification",
      notificationId: notificationId,
      relatedReportId: relatedReportId,
    });
  }
);

// ── Trigger 3: Locker Notification → Push ───────────────────────

exports.onLockerNotificationCreated = functions.firestore.onDocumentCreated(
  "lockerNotifications/{notificationId}",
  async (event) => {
    const notif = event.data?.data();
    if (!notif) return;

    const studentId = notif.studentId;
    const notificationId = event.params.notificationId;

    if (!studentId) {
      logger.warn("onLockerNotificationCreated: missing studentId", {
        notificationId,
      });
      return;
    }

    const uid = await resolveUid(studentId);
    if (!uid) return;

    const allowed = await checkPreference(uid, "lockerReminders");
    if (!allowed) {
      logger.info("onLockerNotificationCreated: preference disabled", {
        uid,
        studentId,
      });
      return;
    }

    await sendPush(uid, notif.title, notif.body, {
      type: "lockerNotification",
      notificationId: notificationId,
      lockerId: notif.lockerId || "",
    });
  }
);
