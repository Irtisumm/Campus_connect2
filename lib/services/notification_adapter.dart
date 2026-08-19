import '../models/admin_notification.dart';
import '../models/campus_notification.dart';
import '../models/lf_notification.dart';
import '../models/locker_notification.dart';
import 'notification_service.dart' show defaultScreenForSource, preferenceCategoryForSource;

/// Converts an [LfNotification] to a [CampusNotification] for unified UI
/// rendering.  The resulting object is suitable for display and navigation;
/// it should NOT be passed to [NotificationService.emit] (use the original
/// [LfNotification] path instead).
CampusNotification adaptLfNotification(
    LfNotification lf, String recipientUid) {
  return CampusNotification(
    id: lf.id,
    source: NotificationSource.lostFound,
    type: lf.type,
    studentId: lf.studentId,
    recipientUid: recipientUid,
    title: lf.title,
    body: lf.body,
    relatedEntityId:
        lf.relatedReportId.isNotEmpty ? lf.relatedReportId : null,
    relatedScreen: defaultScreenForSource(
        NotificationSource.lostFound, lf.relatedReportId),
    read: lf.read,
    createdAt: lf.createdAt,
    preferenceCategory:
        preferenceCategoryForSource(NotificationSource.lostFound),
  );
}

/// Converts a [LockerNotification] to a [CampusNotification] for unified UI
/// rendering.  The resulting object is suitable for display and navigation;
/// it should NOT be passed to [NotificationService.emit] (use the original
/// [LockerNotification] path instead).
CampusNotification adaptLockerNotification(
    LockerNotification lock, String recipientUid) {
  // Parse the ISO-8601 createdAt string (locker stores strings, not
  // Timestamps, on the Dart side).
  final DateTime? parsedCreatedAt = DateTime.tryParse(lock.createdAt);

  return CampusNotification(
    id: lock.id,
    source: NotificationSource.locker,
    type: lock.type,
    studentId: lock.studentId,
    recipientUid: recipientUid,
    title: lock.title,
    body: lock.body,
    relatedEntityId: lock.lockerId.isNotEmpty ? lock.lockerId : null,
    relatedScreen: defaultScreenForSource(
        NotificationSource.locker, lock.lockerId),
    read: lock.read,
    createdAt: parsedCreatedAt,
    preferenceCategory:
        preferenceCategoryForSource(NotificationSource.locker),
  );
}

/// Converts an [AdminNotification] into a [CampusNotification] for the
/// unified NotificationsScreen, viewed by the admin identified by
/// [currentAdminUid].
///
/// `read` is computed per-viewer from `readBy` (one admin acknowledging an
/// item must not hide it from another), and `adminWorkItem` is set so the
/// screen routes mark-read calls to the admin queue rather than a student
/// collection.  The stored [AdminNotification.relatedScreen] is used as-is
/// when present; otherwise the source default applies.
CampusNotification adaptAdminNotification(
    AdminNotification admin, String currentAdminUid) {
  final relatedScreen = admin.relatedScreen.isNotEmpty
      ? admin.relatedScreen
      : defaultScreenForSource(admin.source, admin.relatedEntityId);

  return CampusNotification(
    id: admin.id,
    source: admin.source,
    type: admin.type,
    // The actor who triggered the item — the screen surfaces this as the
    // "from" identity; it is not a push recipient.
    studentId: admin.studentId,
    recipientUid: currentAdminUid,
    title: admin.title,
    body: admin.body,
    relatedEntityId:
        admin.relatedEntityId.isNotEmpty ? admin.relatedEntityId : null,
    relatedScreen: relatedScreen,
    read: admin.readBy.contains(currentAdminUid),
    createdAt: admin.createdAt,
    preferenceCategory: preferenceCategoryForSource(admin.source),
    adminWorkItem: true,
  );
}
