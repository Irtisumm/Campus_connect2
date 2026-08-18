import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Wraps the OneSignal Flutter SDK for push notification delivery on top of
/// the existing Firestore in-app notification system.
///
/// OneSignal is the **push delivery layer only**. Firestore remains the
/// authoritative notification store. Read/unread state, badge counts, and
/// notification history are all driven from Firestore — never from OneSignal.
///
/// ## Identity mapping
///
/// Firebase Auth UID  ←→  OneSignal external user ID
///
/// When a student logs in, their Firebase UID becomes the OneSignal
/// external user ID. On logout, the mapping is cleared so the next login
/// on the same device starts fresh.
class OneSignalService {
  OneSignalService();

  static const String appId = '031d61a8-0a3a-4de8-9d88-d3e739896da5';

  // ── Initialization ──────────────────────────────────────────────

  /// Call once at app startup, after Firebase is initialized.  Registers
  /// foreground-will-display and click listeners so the app can react to
  /// incoming pushes.
  ///
  /// [onClick] is called when the user taps a notification (background or
  /// terminated). The payload `additionalData` map is passed directly so
  /// the caller can mark the Firestore notification read and navigate.
  Future<void> initialize({
    void Function(Map<String, dynamic> data)? onClick,
  }) async {
    OneSignal.initialize(appId);

    // ── Foreground: show the system notification but don't duplicate ──
    // By default, OneSignal will display the notification in the
    // foreground on Android. We keep that behaviour — the system tray
    // notification is shown, and the Firestore unread badge already
    // reflects the new document. No second Firestore write happens here.
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      // Let OneSignal show the OS-level notification.  The app's in-app
      // badge is already updated by the live Firestore stream.
      event.notification.display();
    });

    // ── Background / terminated tap ──
    // When the user taps a notification while the app is backgrounded or
    // killed, `addClickListener` fires.  We extract the custom data payload
    // and hand it to the caller so it can mark the Firestore notification
    // read and deep-link.
    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      if (data != null && data.isNotEmpty) {
        onClick?.call(_stringifyMap(data));
      }
    });
  }

  // ── Identity ────────────────────────────────────────────────────

  /// Associates the OneSignal device subscription with the given
  /// Firebase Auth UID. Called after a successful login.
  ///
  /// Safe to call multiple times for the same user — OneSignal's `login`
  /// is idempotent per external ID.
  Future<void> setExternalUserId(String uid) async {
    if (uid.isEmpty) return;
    try {
      await OneSignal.login(uid);
      debugPrint('[OneSignal] login: $uid');
    } catch (e) {
      debugPrint('[OneSignal] login failed: $e');
    }
  }

  /// Removes the current external user ID mapping. Called at logout so
  /// the next user on this device starts with a clean subscription.
  Future<void> removeExternalUserId() async {
    try {
      await OneSignal.logout();
      debugPrint('[OneSignal] logout');
    } catch (e) {
      debugPrint('[OneSignal] logout failed: $e');
    }
  }

  // ── Permission ──────────────────────────────────────────────────

  /// Requests the `POST_NOTIFICATIONS` runtime permission on Android
  /// 13+. Returns `true` if permission is granted or already held.
  ///
  /// The app continues to work normally if permission is denied —
  /// Firestore in-app notifications are unaffected.
  Future<bool> requestPermission() async {
    try {
      final granted = await OneSignal.Notifications.requestPermission(true);
      debugPrint('[OneSignal] permission: $granted');
      return granted;
    } catch (e) {
      debugPrint('[OneSignal] permission request failed: $e');
      return false;
    }
  }

  /// Whether push permission has already been granted by this user on
  /// this device.
  Future<bool> get hasPermission async {
    try {
      return await OneSignal.Notifications.permission;
    } catch (_) {
      return false;
    }
  }

  // ── Payload parsing ─────────────────────────────────────────────

  /// Extracts the deeplink target from a tapped notification's
  /// `additionalData` payload. Returns `null` when the payload is
  /// missing or unrecognised.
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

  // ── Helpers ─────────────────────────────────────────────────────

  /// OneSignal's `additionalData` values may be typed as `dynamic`
  /// (often `Object` at runtime), so we canonicalise them to strings.
  static Map<String, dynamic> _stringifyMap(Map<dynamic, dynamic> map) {
    return map.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
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
