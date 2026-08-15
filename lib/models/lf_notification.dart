import 'package:cloud_firestore/cloud_firestore.dart';

/// An in-app Lost & Found notification, stored in
/// `lfNotifications/{id}`.
///
/// The project has no push-messaging configuration, so this collection is
/// the notification system: admins create a row when they approve a match,
/// and the recipient student sees it in the L&F Notifications screen. The
/// recipient key is the campus Student ID (`studentId`), the same trust
/// anchor the locker notifications use.
class LfNotification {
  /// Firestore document ID. Empty on an object that has not been written yet.
  final String id;

  /// Campus Student ID of the recipient (e.g. `S001`).
  final String studentId;

  final String title;
  final String body;

  /// Discriminator for iconography; `match` is the only kind today.
  final String type;

  /// Related lost report (`items/{id}`), so the screen can deep-link.
  final String relatedReportId;

  final bool read;
  final DateTime? createdAt;

  const LfNotification({
    this.id = '',
    required this.studentId,
    required this.title,
    required this.body,
    this.type = 'match',
    this.relatedReportId = '',
    this.read = false,
    this.createdAt,
  });

  LfNotification copyWith({
    String? id,
    bool? read,
  }) {
    return LfNotification(
      id: id ?? this.id,
      studentId: studentId,
      title: title,
      body: body,
      type: type,
      relatedReportId: relatedReportId,
      read: read ?? this.read,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'studentId': studentId,
      'title': title,
      'body': body,
      'type': type,
      'relatedReportId': relatedReportId,
      'read': read,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// The only edit a student may make: marking their own notification read.
  static Map<String, dynamic> readMap() {
    return {'read': true};
  }

  factory LfNotification.fromMap(String id, Map<String, dynamic> data) {
    return LfNotification(
      id: id,
      studentId: data['studentId']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      type: data['type']?.toString() ?? 'match',
      relatedReportId: data['relatedReportId']?.toString() ?? '',
      read: data['read'] == true,
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
