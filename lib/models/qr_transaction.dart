import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Whether a QR transaction belongs to Workflow 2 (physical handover of a
/// found item) or Workflow 3 (return of a matched item to its owner).
enum QrKind {
  handover('handover'),
  return_('return');

  const QrKind(this.wireValue);
  final String wireValue;

  static QrKind fromWire(Object? value, {QrKind fallback = QrKind.handover}) {
    final raw = value?.toString();
    for (final kind in QrKind.values) {
      if (kind.wireValue == raw) return kind;
    }
    return fallback;
  }
}

/// Lifecycle of a QR transaction, stored in `qrTransactions/{id}.status`.
///
/// `Issued` (admin generated) → `Scanned` (intended student scanned/entered
/// the token) → `Confirmed` (admin confirmed the physical handover/return).
/// `Cancelled` is set by an admin on an unused code. Every transition is
/// enforced by the Firestore rules, which is what makes a token single-use.
enum QrStatus {
  issued('Issued'),
  scanned('Scanned'),
  confirmed('Confirmed'),
  cancelled('Cancelled');

  const QrStatus(this.wireValue);
  final String wireValue;

  static QrStatus fromWire(Object? value, {QrStatus fallback = QrStatus.issued}) {
    final raw = value?.toString();
    for (final status in QrStatus.values) {
      if (status.wireValue == raw) return status;
    }
    return fallback;
  }
}

/// A document from the Firestore `qrTransactions` collection.
///
/// One document per physical office transaction: the QR payload is [token]
/// (opaque, random, contains no personal data or write authority), and the
/// document itself is the transaction record. Both the Handover QR and the
/// Return QR use this same shape — [kind] discriminates.
class QrTransaction {
  /// Firestore document ID. Empty on an object that has not been written yet.
  final String id;

  final QrKind kind;

  /// The opaque payload encoded in the QR image. 32 random hex characters.
  final String token;

  /// The only student allowed to scan this code — their Firebase UID.
  final String intendedStudentUid;

  /// Campus Student ID of the intended student (e.g. `S001`), denormalised
  /// for display.
  final String intendedStudentId;

  /// Workflow 2: the found report being handed over.
  final String foundReportId;

  /// Workflow 3: the lost report the item returns against.
  final String lostReportId;

  /// Workflow 3: the inventory item going home.
  final String inventoryItemId;

  final QrStatus status;
  final DateTime? issuedAt;

  /// issuedAt + [validityWindow]. Enforced by rules on every write.
  final DateTime? expiresAt;

  final DateTime? scannedAt;
  final DateTime? confirmedAt;

  /// UID of the admin who confirmed the physical action.
  final String? confirmedByUid;

  const QrTransaction({
    this.id = '',
    required this.kind,
    required this.token,
    required this.intendedStudentUid,
    required this.intendedStudentId,
    this.foundReportId = '',
    this.lostReportId = '',
    this.inventoryItemId = '',
    this.status = QrStatus.issued,
    this.issuedAt,
    this.expiresAt,
    this.scannedAt,
    this.confirmedAt,
    this.confirmedByUid,
  });

  /// How long a code stays scannable. The spec asks for "a reasonable short
  /// expiry, such as 10 minutes"; the Firestore rules bound issuance to a
  /// 15-minute window to tolerate device clock skew.
  static const Duration validityWindow = Duration(minutes: 10);

  /// Mints a fresh [QrTransaction] for a student. `token` is generated with
  /// the platform CSPRNG, so it cannot be predicted.
  ///
  /// The document ID is left empty — the caller lets Firestore generate it,
  /// or derives one from the token itself.
  factory QrTransaction.issue({
    required QrKind kind,
    required String intendedStudentUid,
    required String intendedStudentId,
    String foundReportId = '',
    String lostReportId = '',
    String inventoryItemId = '',
    DateTime? now,
  }) {
    final issued = now ?? DateTime.now();
    return QrTransaction(
      kind: kind,
      token: generateToken(),
      intendedStudentUid: intendedStudentUid,
      intendedStudentId: intendedStudentId,
      foundReportId: foundReportId,
      lostReportId: lostReportId,
      inventoryItemId: inventoryItemId,
      status: QrStatus.issued,
      issuedAt: issued,
      expiresAt: issued.add(validityWindow),
    );
  }

  /// Generates a 32-character random hex token.
  static String generateToken() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// Whether the code has passed its expiry at [now].
  bool isExpiredAt(DateTime now) =>
      expiresAt == null || !now.isBefore(expiresAt!);

  bool get isHandover => kind == QrKind.handover;
  bool get isReturn => kind == QrKind.return_;

  Map<String, dynamic> toCreateMap() {
    return {
      'kind': kind.wireValue,
      'token': token,
      'intendedStudentUid': intendedStudentUid,
      'intendedStudentId': intendedStudentId,
      'foundReportId': foundReportId,
      'lostReportId': lostReportId,
      'inventoryItemId': inventoryItemId,
      'status': status.wireValue,
      'issuedAt': issuedAt == null ? null : Timestamp.fromDate(issuedAt!),
      'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
    };
  }

  /// The write a student performs when they scan the code. Only `status` and
  /// `scannedAt` may change — the rules reject anything else.
  Map<String, dynamic> toScanMap() {
    return {
      'status': QrStatus.scanned.wireValue,
      'scannedAt': FieldValue.serverTimestamp(),
    };
  }

  /// The write an admin performs to confirm the physical handover/return.
  Map<String, dynamic> toConfirmMap(String adminUid) {
    return {
      'status': QrStatus.confirmed.wireValue,
      'confirmedAt': FieldValue.serverTimestamp(),
      'confirmedByUid': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// The write a student performs when their handover scan completes the
  /// physical handover (Workflow 2). Unlike [toScanMap] (the return flow,
  /// where the code stops at `Scanned` and an admin confirms), a handover code
  /// jumps straight from `Issued` to `Confirmed` in the same transaction that
  /// closes the report and creates the inventory record. `confirmedByUid` is
  /// therefore the student's own UID here, not an admin's.
  Map<String, dynamic> toCompleteHandoverMap(String studentUid) {
    return {
      'status': QrStatus.confirmed.wireValue,
      'scannedAt': FieldValue.serverTimestamp(),
      'confirmedAt': FieldValue.serverTimestamp(),
      'confirmedByUid': studentUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// The write an admin performs to cancel an unused code.
  static Map<String, dynamic> cancelMap() {
    return {
      'status': QrStatus.cancelled.wireValue,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory QrTransaction.fromMap(String id, Map<String, dynamic> data) {
    return QrTransaction(
      id: id,
      kind: QrKind.fromWire(data['kind']),
      token: data['token']?.toString() ?? '',
      intendedStudentUid: data['intendedStudentUid']?.toString() ?? '',
      intendedStudentId: data['intendedStudentId']?.toString() ?? '',
      foundReportId: data['foundReportId']?.toString() ?? '',
      lostReportId: data['lostReportId']?.toString() ?? '',
      inventoryItemId: data['inventoryItemId']?.toString() ?? '',
      status: QrStatus.fromWire(data['status']),
      issuedAt: _asDate(data['issuedAt']),
      expiresAt: _asDate(data['expiresAt']),
      scannedAt: _asDate(data['scannedAt']),
      confirmedAt: _asDate(data['confirmedAt']),
      confirmedByUid: data['confirmedByUid']?.toString(),
    );
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
