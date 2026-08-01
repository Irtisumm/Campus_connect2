import 'package:cloud_firestore/cloud_firestore.dart';

/// Role stored in `users/{uid}.role`.
///
/// [wireValue] is what actually lives in Firestore — the enum is the only
/// thing the Dart side should ever compare against.
enum UserRole {
  student('student'),
  admin('admin');

  const UserRole(this.wireValue);
  final String wireValue;

  static UserRole fromWire(Object? value, {UserRole fallback = UserRole.student}) {
    final raw = value?.toString();
    for (final role in UserRole.values) {
      if (role.wireValue == raw) return role;
    }
    return fallback;
  }
}

/// Account lifecycle stored in `users/{uid}.status`.
///
/// A freshly registered student sits at [pending] until an administrator
/// approves them from the Student Registrations screen.
enum AccountStatus {
  pending('Pending'),
  active('Active'),
  rejected('Rejected');

  const AccountStatus(this.wireValue);
  final String wireValue;

  /// The Admin Registrations screen has always said "Approved" where
  /// Firestore stores "Active". Translate at the boundary rather than
  /// changing the screen's vocabulary.
  String get displayLabel => this == AccountStatus.active ? 'Approved' : wireValue;

  static AccountStatus fromWire(Object? value, {AccountStatus fallback = AccountStatus.pending}) {
    final raw = value?.toString();
    for (final status in AccountStatus.values) {
      if (status.wireValue == raw) return status;
    }
    return fallback;
  }
}

/// A document from the Firestore `users` collection.
///
/// Field names follow the Firestore schema. The legacy getters [userId],
/// [name] and [programme] are kept so the existing screens compile untouched.
class UserProfile {
  final String uid;
  final String studentId;
  final String fullName;

  /// The address Firebase Authentication knows this account by.
  ///
  /// Written once at registration and **never** changed afterwards — sign-in
  /// resolves a campus ID to this field, so letting it drift would lock the
  /// account out. [email] is the editable, display-only address.
  final String authEmail;

  /// Display / contact address, editable from the Profile screen.
  final String email;

  final String faculty;
  final UserRole role;
  final AccountStatus status;
  final String phone;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    required this.uid,
    required this.studentId,
    required this.fullName,
    required this.authEmail,
    required this.email,
    required this.faculty,
    required this.role,
    required this.status,
    this.phone = '',
    this.createdAt,
    this.updatedAt,
  });

  // ── Backwards-compatible aliases (used across the existing screens) ──
  String get userId => studentId.isNotEmpty ? studentId : uid;
  String get name => fullName;
  String get programme => faculty;

  bool get isAdmin => role == UserRole.admin;
  bool get isActive => status == AccountStatus.active;
  bool get isPending => status == AccountStatus.pending;
  bool get isRejected => status == AccountStatus.rejected;

  UserProfile copyWith({
    String? fullName,
    String? email,
    String? faculty,
    String? phone,
    AccountStatus? status,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid,
      studentId: studentId,
      fullName: fullName ?? this.fullName,
      // authEmail is deliberately absent — it is immutable by design.
      authEmail: authEmail,
      email: email ?? this.email,
      faculty: faculty ?? this.faculty,
      role: role,
      status: status ?? this.status,
      phone: phone ?? this.phone,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// The payload written when the document is first created.
  /// Never contains a password — that lives only in Firebase Authentication.
  Map<String, dynamic> toCreateMap() {
    return {
      'uid': uid,
      'studentId': studentId,
      'fullName': fullName,
      'authEmail': authEmail,
      'email': email,
      'faculty': faculty,
      'role': role.wireValue,
      'status': status.wireValue,
      'phone': phone,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    final role = UserRole.fromWire(data['role']);
    final email = data['email']?.toString() ?? '';
    return UserProfile(
      uid: data['uid']?.toString() ?? uid,
      studentId: data['studentId']?.toString() ?? '',
      fullName: data['fullName']?.toString() ?? '',
      // Documents written before authEmail existed fall back to `email`.
      authEmail: data['authEmail']?.toString() ?? email,
      email: email,
      faculty: data['faculty']?.toString() ?? '',
      role: role,
      // Admin documents created by hand often omit `status`; treat them as
      // active so an administrator is never locked out by a missing field.
      status: AccountStatus.fromWire(
        data['status'],
        fallback: role == UserRole.admin ? AccountStatus.active : AccountStatus.pending,
      ),
      phone: data['phone']?.toString() ?? '',
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
