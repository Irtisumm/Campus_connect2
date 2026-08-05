import 'package:cloud_firestore/cloud_firestore.dart';

/// A notification sent to a student about locker-related events.
///
/// Lives in the `lockerNotifications` Firestore collection. Created by admin
/// actions (terminate, release, block, force-release) and read by the student
/// on their My Locker screen.
///
/// `createdAt` stays an ISO-8601 string on the Dart side so the existing
/// screens keep formatting it exactly as before; the Firestore document stores
/// a real [Timestamp], converted both ways here.
class LockerNotification {
  /// Firestore document ID. Empty on an object that has not been written yet.
  final String id;

  /// Campus-issued Student ID of the recipient (e.g. `S001`).
  final String studentId;

  /// The locker this notification is about (e.g. `LK-A01`).
  final String lockerId;

  /// Short headline (e.g. "Locker Agreement Terminated").
  final String title;

  /// Full body text with details.
  final String body;

   /// Notification category: 'termination', 'release', 'block', 'unblock',
  /// 'force_release', 'return_qr', 'key_returned', 'deposit_refunded',
  /// 'completed'.
  final String type;

  /// When the notification was created.
  final String createdAt;

  /// Whether the student has marked this notification as read.
  final bool read;

  const LockerNotification({
    required this.id,
    required this.studentId,
    required this.lockerId,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.read = false,
  });

  /// Builds a [LockerNotification] from a Firestore document map.
  ///
  /// [id] is the Firestore document key — pass it explicitly when reading a
  /// snapshot (`LockerNotification.fromMap(doc.id, doc.data())`).
  factory LockerNotification.fromMap(String id, Map<String, dynamic> data) {
    return LockerNotification(
      id: id,
      studentId: data['studentId']?.toString() ?? '',
      lockerId: data['lockerId']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      type: data['type']?.toString() ?? 'general',
      createdAt: _asIso(data['createdAt']),
      read: data['read'] == true,
    );
  }

  /// The payload written when the document is first created.
  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'lockerId': lockerId,
      'title': title,
      'body': body,
      'type': type,
      'createdAt': _toTimestamp(createdAt),
      'read': read,
    };
  }

  LockerNotification copyWith({
    String? id,
    String? studentId,
    String? lockerId,
    String? title,
    String? body,
    String? type,
    String? createdAt,
    bool? read,
  }) {
    return LockerNotification(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      lockerId: lockerId ?? this.lockerId,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      read: read ?? this.read,
    );
  }

  /// Firestore stores [Timestamp]s; the Dart side keeps ISO-8601 strings.
  static String _asIso(Object? value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is String) return value;
    return DateTime.now().toIso8601String();
  }

  static Object _toTimestamp(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(parsed);
  }
}
