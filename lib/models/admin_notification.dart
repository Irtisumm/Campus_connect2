import 'package:cloud_firestore/cloud_firestore.dart';

import 'campus_notification.dart';

/// An admin work-queue notification, stored in `adminNotifications/{id}`.
///
/// This is the single cross-module admin queue used by every module that
/// needs to tell administrators "action is required" (Lost & Found today;
/// Events, Issues, Lockers, System re-use the same collection in later
/// phases by writing their own [type] + [source] pairs with an extended
/// rules allowlist).
///
/// It is deliberately separate from the student-facing notification
/// collections:
///
///  * Students can only *create* documents that are self-attributed (their
///    own [studentId], an allowlisted "…_submitted" [type], and a
///    [relatedEntityId] they own) — enforced by `selfAttributedAdminNote()`
///    in the Firestore rules.  They can never read or update any document.
///  * Admins read every document and mark it read *for themselves* only,
///    via an array-union into [readBy].  One admin acknowledging an item
///    does not hide it from another admin.
///
/// [studentId] here is the *actor's* campus ID (who triggered the event),
/// not a recipient — recipients are all administrators.
class AdminNotification {
  /// Firestore document ID. Empty on an object that has not been written yet.
  final String id;

  /// The application module that produced this work item.  Reuses the
  /// canonical [NotificationSource] so future modules plug in unchanged.
  final NotificationSource source;

  /// Discriminator within [source].  Lost & Found (Phase 5A):
  /// `lost_report_submitted`, `found_report_submitted`,
  /// `close_request_submitted`.
  final String type;

  /// Campus Student ID of the *actor* who triggered the event (e.g.
  /// `S001`).  The rules pin this to the caller's own profile.
  final String studentId;

  final String title;
  final String body;

  /// Domain entity this work item refers to (e.g. an `items/{id}` report).
  final String relatedEntityId;

  /// Route opened when an admin taps this row, stored so the rules can
  /// validate it is a string and readers never reconstruct it.
  final String relatedScreen;

  /// Firebase Auth UIDs of the administrators who have acknowledged this
  /// item.  An admin sees the item as unread while their UID is absent.
  final List<String> readBy;

  final DateTime? createdAt;

  const AdminNotification({
    this.id = '',
    required this.source,
    required this.type,
    required this.studentId,
    required this.title,
    required this.body,
    required this.relatedEntityId,
    this.relatedScreen = '',
    this.readBy = const [],
    this.createdAt,
  });

  AdminNotification copyWith({String? id}) {
    return AdminNotification(
      id: id ?? this.id,
      source: source,
      type: type,
      studentId: studentId,
      title: title,
      body: body,
      relatedEntityId: relatedEntityId,
      relatedScreen: relatedScreen,
      readBy: readBy,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'source': source.name,
      'type': type,
      'studentId': studentId,
      'title': title,
      'body': body,
      'relatedEntityId': relatedEntityId,
      'relatedScreen': relatedScreen,
      'readBy': readBy,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// The only edit an admin may make: acknowledging the item for
  /// themselves.  Rules restrict updates to exactly this key set.
  static Map<String, dynamic> readForMap(String adminUid) {
    return {'readBy': FieldValue.arrayUnion([adminUid])};
  }

  factory AdminNotification.fromMap(String id, Map<String, dynamic> data) {
    return AdminNotification(
      id: id,
      source: NotificationSource.values.asNameMap()[data['source']?.toString()] ??
          NotificationSource.system,
      type: data['type']?.toString() ?? '',
      studentId: data['studentId']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      relatedEntityId: data['relatedEntityId']?.toString() ?? '',
      relatedScreen: data['relatedScreen']?.toString() ?? '',
      readBy: (data['readBy'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      createdAt: _asDate(data['createdAt']),
    );
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}