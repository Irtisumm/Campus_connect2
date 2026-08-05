import 'package:cloud_firestore/cloud_firestore.dart';

/// A document from the Firestore `lockerIssues` collection.
///
/// Moved out of `lib/data/mock_data.dart` and made Firestore-ready via
/// [LockerIssue.fromMap] / [LockerIssue.toMap]. Every field the mock model
/// exposed is preserved — only serialisation was added, nothing was renamed
/// or dropped.
///
/// `reportedDate` stays an ISO-8601 string on the Dart side so the existing
/// screens keep formatting it exactly as before; the Firestore document stores
/// a real [Timestamp], converted both ways here.
class LockerIssue {
  /// Firestore document ID. Empty on an object that has not been written yet.
  final String id;
  final String lockerId;

  /// Campus-issued Student ID of the reporter (e.g. `S001`).
  final String studentId;

  /// Short category label chosen by the student (e.g. 'Lock Damage',
  /// 'Door Stuck', 'Other').
  final String category;
  final String description;

  /// 'Reported', 'Under Review', 'Resolved'.
  final String status;
  final int photoCount;
  final String reportedDate;

  /// Optional note an admin can attach when moving the issue to
  /// 'Under Review' or 'Resolved'. Empty string when no note has been set.
  final String adminNotes;

  const LockerIssue({
    required this.id,
    required this.lockerId,
    required this.studentId,
    this.category = '',
    required this.description,
    required this.status,
    this.photoCount = 0,
    required this.reportedDate,
    this.adminNotes = '',
  });

  /// Builds a [LockerIssue] from a Firestore document map.
  ///
  /// [id] is the Firestore document key — pass it explicitly when reading a
  /// snapshot (`LockerIssue.fromMap(doc.id, doc.data())`).
  factory LockerIssue.fromMap(String id, Map<String, dynamic> data) {
    return LockerIssue(
      id: id,
      lockerId: data['lockerId']?.toString() ?? '',
      studentId: data['studentId']?.toString() ?? '',
      category: data['category']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      status: data['status']?.toString() ?? 'Reported',
      photoCount: (data['photoCount'] as num?)?.toInt() ?? 0,
      reportedDate: _asIso(data['reportedDate']),
      adminNotes: data['adminNotes']?.toString() ?? '',
    );
  }

  /// The payload written when the document is first created.
  ///
  /// [id] is deliberately absent — the Firestore document key is the identity.
  Map<String, dynamic> toMap() {
    return {
      'lockerId': lockerId,
      'studentId': studentId,
      'category': category,
      'description': description,
      'status': status,
      'photoCount': photoCount,
      'reportedDate': _toTimestamp(reportedDate),
      'adminNotes': adminNotes,
    };
  }

  LockerIssue copyWith({
    String? id,
    String? lockerId,
    String? studentId,
    String? category,
    String? description,
    String? status,
    int? photoCount,
    String? reportedDate,
    String? adminNotes,
  }) {
    return LockerIssue(
      id: id ?? this.id,
      lockerId: lockerId ?? this.lockerId,
      studentId: studentId ?? this.studentId,
      category: category ?? this.category,
      description: description ?? this.description,
      status: status ?? this.status,
      photoCount: photoCount ?? this.photoCount,
      reportedDate: reportedDate ?? this.reportedDate,
      adminNotes: adminNotes ?? this.adminNotes,
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
