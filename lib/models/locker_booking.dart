import 'package:cloud_firestore/cloud_firestore.dart';

/// A document from the Firestore `lockerBookings` collection.
///
/// Moved out of `lib/data/mock_data.dart` and made Firestore-ready via
/// [LockerBooking.fromMap] / [LockerBooking.toMap]. Every field the mock
/// model exposed is preserved — only serialisation was added, nothing was
/// renamed or dropped.
///
/// `startDate` / `endDate` / `keyCollectionDate` / `keyReturnDate` stay as
/// ISO-8601 strings on the Dart side so the existing screens keep formatting
/// them exactly as before; the Firestore documents store real [Timestamp]s,
/// converted both ways here.
class LockerBooking {
  /// Firestore document ID. Empty on an object that has not been written yet.
  final String id;
  final String lockerId;
  final String location;
  final String startDate;
  final String endDate;
  final String status;
  final int daysLeft;

  /// 2–12 months.
  final int durationMonths;
  final double monthlyRent;
  final double deposit;

  /// Total rental cost for the full period (monthlyRent × durationMonths).
  final double rentalCost;

  /// Deposit + total rental cost — the full amount paid upfront.
  final double totalPaid;

  /// QR code for key collection.
  final String? keyCollectionQR;
  final bool keyCollected;
  final String? keyCollectionDate;

  /// QR code for key return.
  final String? keyReturnQR;
  final bool keyReturned;
  final String? keyReturnDate;

  /// null, 'Requested', 'Pending Return', 'Returned', 'Completed'.
  final String? releaseStatus;

  /// ISO-8601 date the booking reached its terminal `Completed` state. Null
  /// until the booking is completed; set via a server timestamp at completion.
  final String? completedDate;

  /// Whether the security deposit was refunded at completion. True on a normal
  /// release; false when the agreement was terminated (deposit forfeited).
  final bool depositRefunded;

  /// Campus-issued Student ID of the renter (e.g. `S001`). Populated once
  /// bookings are written to Firestore — the mock rows carried no owner.
  final String? studentId;

  /// Unlock code for digital locks. Generated at booking time and stored on
  /// the student-owned booking so the student can read it immediately; the
  /// admin's first locker operation copies it onto the locker document.
  final String? digitalCode;

  /// Firestore document ID of the `payments` record for this booking. Set
  /// after the demo payment gateway succeeds, before the booking doc is
  /// created. Lets the admin detail screen pull the payment receipt without
  /// an extra query.
  final String? paymentId;

  /// Human-readable receipt number copied from the [Payment] record so it is
  /// visible on the booking without a join.
  final String? receiptNumber;

  const LockerBooking({
    required this.id,
    required this.lockerId,
    required this.location,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.daysLeft,
    this.durationMonths = 6,
    this.monthlyRent = 10.0,
    this.deposit = 100.0,
    this.rentalCost = 60.0,
    this.totalPaid = 160.0,
    this.keyCollectionQR,
    this.keyCollected = false,
    this.keyCollectionDate,
    this.keyReturnQR,
    this.keyReturned = false,
    this.keyReturnDate,
    this.releaseStatus,
    this.completedDate,
    this.depositRefunded = false,
    this.studentId,
    this.digitalCode,
    this.paymentId,
    this.receiptNumber,
  });

  /// Builds a [LockerBooking] from a Firestore document map.
  ///
  /// [id] is the Firestore document key — pass it explicitly when reading a
  /// snapshot (`LockerBooking.fromMap(doc.id, doc.data())`).
  factory LockerBooking.fromMap(String id, Map<String, dynamic> data) {
    return LockerBooking(
      id: id,
      lockerId: data['lockerId']?.toString() ?? '',
      location: data['location']?.toString() ?? '',
      startDate: _asIso(data['startDate']),
      endDate: _asIso(data['endDate']),
      status: data['status']?.toString() ?? 'Pending Pickup',
      daysLeft: (data['daysLeft'] as num?)?.toInt() ?? 0,
      durationMonths: (data['durationMonths'] as num?)?.toInt() ?? 6,
      monthlyRent: (data['monthlyRent'] as num?)?.toDouble() ?? 10.0,
      deposit: (data['deposit'] as num?)?.toDouble() ?? 100.0,
      rentalCost: (data['rentalCost'] as num?)?.toDouble() ??
          ((data['monthlyRent'] as num?)?.toDouble() ?? 10.0) *
          ((data['durationMonths'] as num?)?.toInt() ?? 6),
      totalPaid: (data['totalPaid'] as num?)?.toDouble() ?? 160.0,
      keyCollectionQR: data['keyCollectionQR']?.toString(),
      keyCollected: data['keyCollected'] == true,
      keyCollectionDate: _asIsoOrNull(data['keyCollectionDate']),
      keyReturnQR: data['keyReturnQR']?.toString(),
      keyReturned: data['keyReturned'] == true,
      keyReturnDate: _asIsoOrNull(data['keyReturnDate']),
      releaseStatus: data['releaseStatus']?.toString(),
      completedDate: _asIsoOrNull(data['completedDate']),
      depositRefunded: data['depositRefunded'] == true,
      studentId: data['studentId']?.toString(),
      digitalCode: data['digitalCode']?.toString(),
      paymentId: data['paymentId']?.toString(),
      receiptNumber: data['receiptNumber']?.toString(),
    );
  }

  /// The payload written when the document is first created.
  ///
  /// [id] is deliberately absent — the Firestore document key is the identity.
  /// Dates are stored as [Timestamp]s so range queries and ordering work.
  Map<String, dynamic> toMap() {
    return {
      'lockerId': lockerId,
      'location': location,
      'startDate': _toTimestamp(startDate),
      'endDate': _toTimestamp(endDate),
      'status': status,
      'daysLeft': daysLeft,
      'durationMonths': durationMonths,
      'monthlyRent': monthlyRent,
      'deposit': deposit,
      'rentalCost': rentalCost,
      'totalPaid': totalPaid,
      'keyCollectionQR': keyCollectionQR,
      'keyCollected': keyCollected,
      'keyCollectionDate': _toTimestampOrNull(keyCollectionDate),
      'keyReturnQR': keyReturnQR,
      'keyReturned': keyReturned,
      'keyReturnDate': _toTimestampOrNull(keyReturnDate),
      'releaseStatus': releaseStatus,
      'completedDate': _toTimestampOrNull(completedDate),
      'depositRefunded': depositRefunded,
      'studentId': studentId,
      'digitalCode': digitalCode,
      'paymentId': paymentId,
      'receiptNumber': receiptNumber,
    };
  }

  LockerBooking copyWith({
    String? id,
    String? lockerId,
    String? location,
    String? startDate,
    String? endDate,
    String? status,
    int? daysLeft,
    int? durationMonths,
    double? monthlyRent,
    double? deposit,
    double? rentalCost,
    double? totalPaid,
    Object? keyCollectionQR = _sentinel,
    bool? keyCollected,
    Object? keyCollectionDate = _sentinel,
    Object? keyReturnQR = _sentinel,
    bool? keyReturned,
    Object? keyReturnDate = _sentinel,
    Object? releaseStatus = _sentinel,
    Object? completedDate = _sentinel,
    bool? depositRefunded,
    Object? studentId = _sentinel,
    Object? digitalCode = _sentinel,
    Object? paymentId = _sentinel,
    Object? receiptNumber = _sentinel,
  }) {
    return LockerBooking(
      id: id ?? this.id,
      lockerId: lockerId ?? this.lockerId,
      location: location ?? this.location,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      daysLeft: daysLeft ?? this.daysLeft,
      durationMonths: durationMonths ?? this.durationMonths,
      monthlyRent: monthlyRent ?? this.monthlyRent,
      deposit: deposit ?? this.deposit,
      rentalCost: rentalCost ?? this.rentalCost,
      totalPaid: totalPaid ?? this.totalPaid,
      keyCollectionQR: identical(keyCollectionQR, _sentinel) ? this.keyCollectionQR : keyCollectionQR as String?,
      keyCollected: keyCollected ?? this.keyCollected,
      keyCollectionDate: identical(keyCollectionDate, _sentinel) ? this.keyCollectionDate : keyCollectionDate as String?,
      keyReturnQR: identical(keyReturnQR, _sentinel) ? this.keyReturnQR : keyReturnQR as String?,
      keyReturned: keyReturned ?? this.keyReturned,
      keyReturnDate: identical(keyReturnDate, _sentinel) ? this.keyReturnDate : keyReturnDate as String?,
      releaseStatus: identical(releaseStatus, _sentinel) ? this.releaseStatus : releaseStatus as String?,
      completedDate: identical(completedDate, _sentinel) ? this.completedDate : completedDate as String?,
      depositRefunded: depositRefunded ?? this.depositRefunded,
      studentId: identical(studentId, _sentinel) ? this.studentId : studentId as String?,
      digitalCode: identical(digitalCode, _sentinel) ? this.digitalCode : digitalCode as String?,
      paymentId: identical(paymentId, _sentinel) ? this.paymentId : paymentId as String?,
      receiptNumber: identical(receiptNumber, _sentinel) ? this.receiptNumber : receiptNumber as String?,
    );
  }

  static const Object _sentinel = Object();

  /// Firestore stores [Timestamp]s; the Dart side keeps ISO-8601 date strings.
  static String _asIso(Object? value) {
    if (value is Timestamp) return value.toDate().toIso8601String().split('T').first;
    if (value is DateTime) return value.toIso8601String().split('T').first;
    if (value is String) return value;
    return DateTime.now().toIso8601String().split('T').first;
  }

  static String? _asIsoOrNull(Object? value) {
    if (value == null) return null;
    return _asIso(value);
  }

  static Object _toTimestamp(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(parsed);
  }

  static Object? _toTimestampOrNull(String? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : Timestamp.fromDate(parsed);
  }
}

/// Outcome of a booking creation attempt. Carries the created [LockerBooking]
/// on success, or a user-safe failure message that the caller can show
/// directly (e.g. "Locker already reserved.").
class LockerBookingResult {
  final LockerBooking? booking;
  final String? error;
  const LockerBookingResult.success(this.booking) : error = null;
  const LockerBookingResult.failure(this.error) : booking = null;
  bool get isSuccess => booking != null;
}
