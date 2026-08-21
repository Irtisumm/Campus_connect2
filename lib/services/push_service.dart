import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device FCM token lifecycle, Android notification-channel creation,
/// runtime permission handling, and all message-payload routing.
///
/// Every method degrades gracefully when Firebase is unavailable (plain
/// widget tests) — push is an *additional* delivery mechanism; the Firestore
/// in-app notifications always remain available.
class PushService {
  PushService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    SharedPreferences? prefs,
  })  : _customMessaging = messaging,
        _customFirestore = firestore,
        _prefs = prefs;

  final FirebaseMessaging? _customMessaging;
  final FirebaseFirestore? _customFirestore;

  FirebaseMessaging get _messaging => _customMessaging ?? FirebaseMessaging.instance;
  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;
  SharedPreferences? _prefs;

  // Held so it can be cancelled at logout — otherwise a lingering
  // subscription from user A would try to update user A's deviceToken
  // document while user B is authenticated, triggering PERMISSION_DENIED.
  StreamSubscription<String>? _tokenRefreshSub;

  static const String _deviceIdKey = 'push_device_id';
  static const String _permissionAskedKey = 'push_permission_asked';

  // ── Device identity ──────────────────────────────────────────────

  /// A stable device identifier generated once and persisted in
  /// SharedPreferences.  Used as the Firestore token-document ID so that
  /// FCM token refreshes update the same document in-place rather than
  /// creating duplicates.
  Future<String> get deviceId async {
    final p = await _ensurePrefs();
    var id = p.getString(_deviceIdKey);
    if (id == null) {
      id = _newId();
      await p.setString(_deviceIdKey, id);
    }
    return id;
  }

  static String _newId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}'
        '-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<SharedPreferences> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Permission ──────────────────────────────────────────────────

  /// Requests the Android `POST_NOTIFICATIONS` runtime permission (Android
  /// 13+).  Called once after the first successful login; never blocks the
  /// app if denied.  The Firestore in-app notification system works
  /// regardless.
  Future<bool> requestPermissionIfNeeded() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        return true;
      }
      // Track that we asked so we don't pester on every login.
      final p = await _ensurePrefs();
      final alreadyAsked = p.getBool(_permissionAskedKey) ?? false;
      if (alreadyAsked) return false;
      await p.setBool(_permissionAskedKey, true);

      final result = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return result.authorizationStatus == AuthorizationStatus.authorized ||
          result.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  // ── Token lifecycle ──────────────────────────────────────────────

  /// Writes a `deviceTokens/{deviceId}` document for the authenticated
  /// user.  Safe to call on every login — it overwrites an existing row
  /// for the same device.
  Future<void> registerToken(String uid) async {
    if (uid.isEmpty) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      final dId = await deviceId;
      final now = FieldValue.serverTimestamp();
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('deviceTokens')
          .doc(dId)
          .set({
        'token': token,
        'platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown'),
        'createdAt': now,
        'updatedAt': now,
        'appVersion': '1.0.0',
      }, SetOptions(merge: true));
    } on FirebaseException {
      // Non-fatal — push delivery is best-effort.
    } catch (_) {
      // Firebase may be unavailable (tests); ignore.
    }
  }

  /// Listens for FCM token rotations.  When the token changes the
  /// existing device document is updated in-place so the Cloud Function
  /// always targets the active token.
  ///
  /// The subscription is cancelled at logout so a lingering listener from
  /// a previous session never tries to write with the wrong auth identity.
  void listenToTokenRefresh(String uid) {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
      if (uid.isEmpty || newToken.isEmpty) return;
      try {
        final dId = await deviceId;
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('deviceTokens')
            .doc(dId)
            .update({
          'token': newToken,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException {
        // Retry on next token rotation.
      } catch (_) {
        // Firebase unavailable.
      }
    });
  }

  /// Removes this device's token document and cancels the onTokenRefresh
  /// subscription. Called at logout so the logged-out device stops
  /// receiving private notifications and stale listeners don't leak.
  Future<void> unregisterToken(String uid) async {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    if (uid.isEmpty) return;
    try {
      final dId = await deviceId;
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('deviceTokens')
          .doc(dId)
          .delete();
    } on FirebaseException {
      // The token will be cleaned up when FCM reports it as invalid.
    } catch (_) {
      // Firebase unavailable.
    }
  }

  // ── Message routing ───────────────────────────────────────────────

  /// Called once at startup to wire up foreground, background-tap, and
  /// terminated-app-tap handlers.  Returns the initial message (if any)
  /// that launched the app so the caller can route after the widget tree
  /// is ready.
  Future<RemoteMessage?> initialize({
    required void Function(RemoteMessage message) onTap,
  }) async {
    // ── Terminated-app launch ──
    // Check whether this cold start came from a notification tap.
    final initial = await _messaging.getInitialMessage();

    // ── Background-to-foreground tap ──
    // App was in the background (not killed) — user tapped the tray.
    FirebaseMessaging.onMessageOpenedApp.listen(onTap);

    // ── Foreground delivery ──
    // App is open and visible.  Android OS does NOT create an automatic
    // tray notification for foreground messages, so we show a local one
    // via the FlutterLocalNotificationsPlugin (or, minimally, let the
    // app decide via the callback).  We do NOT bundle flutter_local_notifications
    // here — the existing Android channel + the notification payload's
    // `notification` block are sufficient for Android to display a heads-up
    // when the app is in the foreground on newer Firebase Messaging versions.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    return initial;
  }

  void _onForegroundMessage(RemoteMessage message) {
    // The notification payload (message.notification) is rendered by the
    // system on Android 14+ even in the foreground when the FCM payload
    // has both `notification` and `data` blocks.  No-op here — the
    // system handles display.  If needed, a local-notification plugin
    // could be wired in later.
    debugPrint(
      '[PUSH] Foreground message: id=${message.messageId} '
      'type=${message.data['type']}',
    );
  }

  // ── Payload parsing ───────────────────────────────────────────────

  /// Extracts the deeplink target from a tapped notification's data
  /// payload.  Returns null when the payload is missing or unrecognised.
  static NotificationTap? parseTap(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final notificationId = data['notificationId'] as String?;
    final reportId = data['relatedReportId'] as String?;

    if (notificationId == null || notificationId.isEmpty) return null;

    return NotificationTap(
      type: type ?? 'unknown',
      notificationId: notificationId,
      relatedReportId: reportId ?? '',
    );
  }
}

/// The structured data extracted from a notification tap.
class NotificationTap {
  final String type; // 'lfNotification' | 'lockerNotification'
  final String notificationId;
  final String relatedReportId;

  const NotificationTap({
    required this.type,
    required this.notificationId,
    required this.relatedReportId,
  });
}
