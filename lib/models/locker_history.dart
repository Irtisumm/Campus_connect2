import 'package:cloud_firestore/cloud_firestore.dart';

/// One audit-trail entry in a locker's history.
///
/// Lives in the `lockers/{lockerId}/history` subcollection — one document per
/// event — so it reads under the parent locker's read rule and needs no rules
/// of its own.
///
/// Moved out of `lib/data/mock_data.dart` unchanged apart from the added
/// [LockerHistory.fromMap] / [LockerHistory.toMap] serialisation.
///
/// `timestamp` stays an ISO-8601 string on the Dart side so the existing
/// screens keep formatting it exactly as before; the Firestore document stores
/// a real [Timestamp], converted both ways here.
class LockerHistory {
  final String action;
  final String staffId;
  final String timestamp;
  final String? reason;

  const LockerHistory({
    required this.action,
    required this.staffId,
    required this.timestamp,
    this.reason,
  });

  /// Builds a [LockerHistory] from a Firestore document map.
  factory LockerHistory.fromMap(Map<String, dynamic> data) {
    return LockerHistory(
      action: data['action']?.toString() ?? '',
      staffId: data['staffId']?.toString() ?? '',
      timestamp: _asIso(data['timestamp']),
      reason: data['reason']?.toString(),
    );
  }

  /// The payload written when the document is first created.
  Map<String, dynamic> toMap() {
    return {
      'action': action,
      'staffId': staffId,
      'timestamp': _toTimestamp(timestamp),
      'reason': reason,
    };
  }

  LockerHistory copyWith({
    String? action,
    String? staffId,
    String? timestamp,
    Object? reason = _sentinel,
  }) {
    return LockerHistory(
      action: action ?? this.action,
      staffId: staffId ?? this.staffId,
      timestamp: timestamp ?? this.timestamp,
      reason: identical(reason, _sentinel) ? this.reason : reason as String?,
    );
  }

  static const Object _sentinel = Object();

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
