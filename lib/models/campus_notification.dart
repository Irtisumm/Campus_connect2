/// The canonical notification model for Campus Connect.
///
/// This is the **unified model** that all feature modules should use when
/// emitting a notification.  The [NotificationService] writes to the
/// appropriate Firestore collection based on the [source] field — feature
/// code never needs to know which collection backs a given notification.
///
/// ## Identifier conventions
///
/// | Field            | Example           | Purpose                       |
/// |------------------|-------------------|-------------------------------|
/// | [recipientUid]   | `abc123…` (28 ch) | Firebase Auth UID — used for  |
/// |                  |                   | OneSignal external user ID,   |
/// |                  |                   | Firestore `items.reportedByUid`|
/// | [studentId]      | `S001`            | Campus-issued Student ID —    |
/// |                  |                   | Firestore notification query   |
/// |                  |                   | key and rule ownership anchor  |
///
/// **Never interchange these two identifiers.**  They serve different layers
/// and a mix-up silently delivers push to nobody (OneSignal returns
/// `recipients: 0` with HTTP 200).
///
/// ## Deduplication
///
/// The [dedupeKey] is a deterministic string:
///
///     ${source}.${type}.${relatedEntityId}.${recipientUid}
///
/// Two emissions with the same dedupe key produce exactly one Firestore
/// notification + at most one push.
class CampusNotification {
  /// Firestore document ID. Empty before the initial write; populated by
  /// [NotificationService.emit] after the document is created.
  final String id;

  /// The application module that produced this notification.
  final NotificationSource source;

  /// Discriminator within the source module, e.g. `'match'`,
  /// `'approved'`, `'termination'`, `'event_approved'`.
  final String type;

  /// Campus-issued Student ID of the recipient (e.g. `S001`).
  ///
  /// This is the Firestore query key for `lfNotifications` and
  /// `lockerNotifications`, and the rule ownership anchor
  /// (`ownsLfNotification`, `ownsLockerNotification`).
  final String studentId;

  /// Firebase Auth UID of the recipient (28-char string).
  ///
  /// Used for OneSignal external user ID targeting.  Also used to read
  /// the recipient's Firestore user profile during admin-triggered
  /// preference checks.
  final String recipientUid;

  /// Short headline shown in the notification row.
  final String title;

  /// Full body text shown in the notification detail.
  final String body;

  /// Domain entity this notification refers to, e.g. a Lost Report ID
  /// (`items/itemA1`), a Locker ID (`LK-A01`), an Event ID, or an
  /// Issue ID.  Used to construct the deep-link route.
  final String? relatedEntityId;

  /// The GoRouter route fragment to navigate to when the notification
  /// is tapped.  Built from [source] + [relatedEntityId], e.g.
  /// `/lost-found/lost/itemA1` or `/lockers/LK-A01`.
  final String relatedScreen;

  /// Whether the recipient has marked this notification read.
  final bool read;

  /// When the notification document was created in Firestore.
  final DateTime? createdAt;

  /// The key in [UserProfile.notificationPrefs] that controls whether
  /// this notification generates a push.  One of:
  /// `'lostFoundMatches'`, `'lockerReminders'`, `'eventUpdates'`,
  /// `'issueStatus'`.
  final String preferenceCategory;

  /// A deterministic string that prevents duplicate processing:
  ///
  ///     ${source}.${type}.${relatedEntityId}.${recipientUid}
  ///
  /// Two emissions with the same key produce at most one Firestore
  /// document + one push.
  final String dedupeKey;

  /// The delivery state of the OneSignal push for this notification.
  final PushStatus pushStatus;

  /// True when this row is an *admin work-queue* item (from the
  /// `adminNotifications` collection, adapted for an admin viewer).  The
  /// unified NotificationsScreen uses this to route mark-read calls to the
  /// admin queue instead of a student collection.  Student rows are false.
  final bool adminWorkItem;

  const CampusNotification({
    this.id = '',
    required this.source,
    required this.type,
    required this.studentId,
    required this.recipientUid,
    required this.title,
    required this.body,
    this.relatedEntityId,
    this.relatedScreen = '',
    this.read = false,
    this.createdAt,
    this.preferenceCategory = 'lostFoundMatches',
    this.dedupeKey = '',
    this.pushStatus = PushStatus.notAttempted,
    this.adminWorkItem = false,
  });

  /// Builds a deterministic deduplication key from the notification's
  /// source, type, related entity, and recipient UID.
  ///
  /// Two calls with the same arguments produce the same key; the caller
  /// should check a short-lived in-memory set before emitting.
  static String buildDedupeKey({
    required NotificationSource source,
    required String type,
    required String? relatedEntityId,
    required String recipientUid,
  }) {
    return '${source.name}.$type.${relatedEntityId ?? ''}.$recipientUid';
  }

  /// Returns a copy with the given fields replaced.
  CampusNotification copyWith({
    String? id,
    NotificationSource? source,
    String? type,
    String? studentId,
    String? recipientUid,
    String? title,
    String? body,
    String? relatedEntityId,
    String? relatedScreen,
    bool? read,
    DateTime? createdAt,
    String? preferenceCategory,
    String? dedupeKey,
    PushStatus? pushStatus,
    bool? adminWorkItem,
  }) {
    return CampusNotification(
      id: id ?? this.id,
      source: source ?? this.source,
      type: type ?? this.type,
      studentId: studentId ?? this.studentId,
      recipientUid: recipientUid ?? this.recipientUid,
      title: title ?? this.title,
      body: body ?? this.body,
      relatedEntityId: relatedEntityId ?? this.relatedEntityId,
      relatedScreen: relatedScreen ?? this.relatedScreen,
      read: read ?? this.read,
      createdAt: createdAt ?? this.createdAt,
      preferenceCategory: preferenceCategory ?? this.preferenceCategory,
      dedupeKey: dedupeKey ?? this.dedupeKey,
      pushStatus: pushStatus ?? this.pushStatus,
      adminWorkItem: adminWorkItem ?? this.adminWorkItem,
    );
  }
}

/// The application module that produced a notification.
///
/// The [NotificationService] uses this to determine which Firestore
/// collection to write to and which [UserProfile.notificationPrefs]
/// key to consult.
enum NotificationSource {
  /// Lost & Found notifications (writes to `lfNotifications`).
  /// Preference key: `lostFoundMatches`.
  lostFound,

  /// Locker notifications (writes to `lockerNotifications`).
  /// Preference key: `lockerReminders`.
  locker,

  /// Event & Activities notifications (future).
  /// Preference key: `eventUpdates`.
  event,

  /// Issue Reporting notifications (future).
  /// Preference key: `issueStatus`.
  issue,

  /// Account, system, and announcement notifications (future).
  /// No preference key — always in-app; push only for critical alerts.
  system,
}

/// The delivery state of the OneSignal push for a notification.
///
/// Transitions: notAttempted → attempted → accepted → (noRecipient | delivered)
/// A failed push stays at [attempted] so the reliability layer can retry.
enum PushStatus {
  /// No push dispatch has been requested yet.
  notAttempted,

  /// A push was requested from the Worker but no response has been
  /// received (or the response was unparseable).
  attempted,

  /// The Worker accepted the request and OneSignal returned
  /// `recipients > 0`.
  delivered,

  /// The Worker returned success but `recipients == 0` — the target
  /// user has no active OneSignal subscription on any device.
  noRecipient,

  /// The Worker call failed (network error, 5xx, auth failure), or
  /// OneSignal returned an API error.
  failed,
}
