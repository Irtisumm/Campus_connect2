import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of an admin-reviewed manual match, stored in
/// `matches/{id}.status`.
///
/// `Proposed` is a draft the admin has not approved yet; `Approved` is the
/// confirmed possible-match shown to the lost report's owner; `Completed` is
/// set by the return transaction once the item is physically back with its
/// owner.
enum MatchStatus {
  proposed('Proposed'),
  approved('Approved'),
  completed('Completed');

  const MatchStatus(this.wireValue);
  final String wireValue;

  static MatchStatus fromWire(Object? value,
      {MatchStatus fallback = MatchStatus.proposed}) {
    final raw = value?.toString();
    for (final status in MatchStatus.values) {
      if (status.wireValue == raw) return status;
    }
    return fallback;
  }
}

/// A document from the Firestore `matches` collection.
///
/// Links one inventory item to one lost report. Only the lost report's owner
/// may read it (besides admins) — the student detail screen renders a safe
/// summary (item title/category/status), never finder identity or contact
/// details.
class LfMatch {
  /// Firestore document ID. Empty on an object that has not been written yet.
  final String id;

  final String lostReportId;
  final String inventoryItemId;

  /// Firebase Authentication UID of the lost report's owner — the intended
  /// recipient of the match notification and the return QR.
  final String lostOwnerUid;

  /// Campus Student ID of the owner (e.g. `S001`), denormalised for display
  /// and for the notification recipient key.
  final String lostOwnerStudentId;

  final MatchStatus status;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const LfMatch({
    this.id = '',
    required this.lostReportId,
    required this.inventoryItemId,
    required this.lostOwnerUid,
    required this.lostOwnerStudentId,
    this.status = MatchStatus.proposed,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  LfMatch copyWith({
    String? id,
    MatchStatus? status,
    String? notes,
    DateTime? updatedAt,
  }) {
    return LfMatch(
      id: id ?? this.id,
      lostReportId: lostReportId,
      inventoryItemId: inventoryItemId,
      lostOwnerUid: lostOwnerUid,
      lostOwnerStudentId: lostOwnerStudentId,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'lostReportId': lostReportId,
      'inventoryItemId': inventoryItemId,
      'lostOwnerUid': lostOwnerUid,
      'lostOwnerStudentId': lostOwnerStudentId,
      'status': status.wireValue,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Admin-only edits. The linked records and the owner are immutable.
  Map<String, dynamic> toUpdateMap() {
    return {
      'status': status.wireValue,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory LfMatch.fromMap(String id, Map<String, dynamic> data) {
    return LfMatch(
      id: id,
      lostReportId: data['lostReportId']?.toString() ?? '',
      inventoryItemId: data['inventoryItemId']?.toString() ?? '',
      lostOwnerUid: data['lostOwnerUid']?.toString() ?? '',
      lostOwnerStudentId: data['lostOwnerStudentId']?.toString() ?? '',
      status: MatchStatus.fromWire(data['status']),
      notes: data['notes']?.toString() ?? '',
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
