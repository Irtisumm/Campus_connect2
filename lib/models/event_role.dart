import 'firestore_codecs.dart';

/// A crew assignment for one event — a document in `eventRoles`.
///
/// Roles are how a host delegates: an assigned student gains the listed
/// [permissions] on that one event without becoming an admin. The Manage
/// Event screen reads this collection to decide whether the signed-in user may
/// scan tickets or edit the event, so it is deliberately a separate document
/// rather than an array on the event — the host must be able to add and remove
/// crew without rewriting (and being allowed to rewrite) the event itself.
class EventRole {
  final String id;
  final String eventId;
  final String studentId;
  final String studentName;

  /// 'Organizer', 'Staff' or 'Volunteer'.
  final String role;

  /// 'scan_qr', 'manage_participants', 'edit_event'.
  final List<String> permissions;

  const EventRole({
    required this.id,
    required this.eventId,
    required this.studentId,
    required this.studentName,
    required this.role,
    this.permissions = const [],
  });

  /// Builds an [EventRole] from a Firestore document map.
  ///
  /// [id] is the Firestore document key — pass it explicitly when reading a
  /// snapshot (`EventRole.fromMap(doc.id, doc.data())`).
  factory EventRole.fromMap(String id, Map<String, dynamic> data) {
    return EventRole(
      id: id,
      eventId: asString(data['eventId']),
      studentId: asString(data['studentId']),
      studentName: asString(data['studentName']),
      role: asString(data['role']).isEmpty ? 'Volunteer' : asString(data['role']),
      permissions: asStringList(data['permissions']),
    );
  }

  /// The payload written to the document.
  ///
  /// [id] is deliberately absent — the Firestore document key is the identity.
  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'studentId': studentId,
      'studentName': studentName,
      'role': role,
      'permissions': permissions,
    };
  }

  EventRole copyWith({
    String? id,
    String? eventId,
    String? studentId,
    String? studentName,
    String? role,
    List<String>? permissions,
  }) {
    return EventRole(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
    );
  }
}
