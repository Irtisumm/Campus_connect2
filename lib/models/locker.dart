import 'package:cloud_firestore/cloud_firestore.dart';

/// A document from the Firestore `lockers` collection.
///
/// Moved out of `lib/data/mock_data.dart` and made Firestore-ready via
/// [Locker.fromMap] / [Locker.toMap]. Every field the mock model exposed is
/// preserved — only serialisation was added, nothing was renamed or dropped.
///
/// `startDate` / `endDate` stay as ISO-8601 date strings on the Dart side so
/// the existing screens keep formatting them exactly as before; the Firestore
/// documents store real [Timestamp]s, converted both ways here.
///
/// SECURITY — digital lock codes are deliberately NOT part of this model.
/// `lockers/{lockerId}` is readable by every signed-in user, so storing the
/// unlock code here exposed every student's code to every other student. The
/// code now lives only on the owner-scoped `lockerBookings/{bookingId}`
/// document ([LockerBooking.digitalCode]), which is the single source of
/// truth. Legacy locker documents may still carry a `digitalCode` field — it
/// is never read here and never written back.
class Locker {
  /// Firestore document ID — also the human locker code (e.g. `LK-A01`).
  final String id;
  final String location;
  final String status;

  /// Campus-issued Student ID of the current renter (e.g. `S001`). Null when
  /// the locker is not rented.
  final String? studentId;
  final String? endDate;
  final String? startDate;
  final int? daysLeft;

  /// 'key' or 'digital'.
  final String lockType;

  /// RM10/month.
  final double monthlyRent;

  /// RM100 deposit.
  final double deposit;
  final bool depositRefunded;

  const Locker({
    required this.id,
    required this.location,
    required this.status,
    this.studentId,
    this.endDate,
    this.daysLeft,
    this.startDate,
    this.lockType = 'key',
    this.monthlyRent = 10.0,
    this.deposit = 100.0,
    this.depositRefunded = false,
  });

  /// Builds a [Locker] from a Firestore document map.
  ///
  /// [id] is the Firestore document key — pass it explicitly when reading a
  /// snapshot (`Locker.fromMap(doc.id, doc.data())`).
  ///
  /// `data['digitalCode']` is intentionally ignored: legacy documents may
  /// still hold the field, but the booking is the only source of truth.
  factory Locker.fromMap(String id, Map<String, dynamic> data) {
    return Locker(
      id: id,
      location: data['location']?.toString() ?? '',
      status: data['status']?.toString() ?? 'Available',
      studentId: data['studentId']?.toString(),
      startDate: _asIsoOrNull(data['startDate']),
      endDate: _asIsoOrNull(data['endDate']),
      daysLeft: (data['daysLeft'] as num?)?.toInt(),
      lockType: data['lockType']?.toString() ?? 'key',
      monthlyRent: (data['monthlyRent'] as num?)?.toDouble() ?? 10.0,
      deposit: (data['deposit'] as num?)?.toDouble() ?? 100.0,
      depositRefunded: data['depositRefunded'] == true,
    );
  }

  /// The payload written when the document is created or replaced.
  ///
  /// [id] is deliberately absent — the Firestore document key is the identity.
  /// Dates are stored as [Timestamp]s so range queries and ordering work.
  /// `digitalCode` is deliberately absent — it is never written to a locker.
  Map<String, dynamic> toMap() {
    return {
      'location': location,
      'status': status,
      'studentId': studentId,
      'startDate': _toTimestampOrNull(startDate),
      'endDate': _toTimestampOrNull(endDate),
      'daysLeft': daysLeft,
      'lockType': lockType,
      'monthlyRent': monthlyRent,
      'deposit': deposit,
      'depositRefunded': depositRefunded,
    };
  }

  Locker copyWith({
    String? id,
    String? location,
    String? status,
    Object? studentId = _sentinel,
    Object? startDate = _sentinel,
    Object? endDate = _sentinel,
    Object? daysLeft = _sentinel,
    String? lockType,
    double? monthlyRent,
    double? deposit,
    bool? depositRefunded,
  }) {
    return Locker(
      id: id ?? this.id,
      location: location ?? this.location,
      status: status ?? this.status,
      studentId: identical(studentId, _sentinel) ? this.studentId : studentId as String?,
      startDate: identical(startDate, _sentinel) ? this.startDate : startDate as String?,
      endDate: identical(endDate, _sentinel) ? this.endDate : endDate as String?,
      daysLeft: identical(daysLeft, _sentinel) ? this.daysLeft : daysLeft as int?,
      lockType: lockType ?? this.lockType,
      monthlyRent: monthlyRent ?? this.monthlyRent,
      deposit: deposit ?? this.deposit,
      depositRefunded: depositRefunded ?? this.depositRefunded,
    );
  }

  static const Object _sentinel = Object();

  /// Firestore stores [Timestamp]s; the Dart side keeps ISO-8601 date strings.
  static String? _asIsoOrNull(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String().split('T').first;
    if (value is DateTime) return value.toIso8601String().split('T').first;
    if (value is String) return value;
    return null;
  }

  static Object? _toTimestampOrNull(String? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : Timestamp.fromDate(parsed);
  }
}
