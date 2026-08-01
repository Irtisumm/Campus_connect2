import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/auth_result.dart';
import '../models/user_profile.dart';
import 'user_service.dart';

/// Account totals shown on the admin dashboard.
class AccountCounts {
  final int students;
  final int admins;

  /// Students still awaiting approval — drives the "N pending approval"
  /// subtitle on the admin dashboard.
  final int pendingStudents;

  const AccountCounts({
    required this.students,
    required this.admins,
    this.pendingStudents = 0,
  });

  static const AccountCounts empty = AccountCounts(students: 0, admins: 0);

  int get total => students + admins;
}

/// Administrator-side operations: reviewing registrations, approving or
/// rejecting them, and account analytics.
///
/// Reads the same `users` collection as [UserService] but is kept separate
/// because these are privileged operations gated by the security rules.
class AdminService {
  final FirebaseFirestore? _dbOrNull;

  AdminService({FirebaseFirestore? firestore}) : _dbOrNull = _resolve(firestore);

  static FirebaseFirestore? _resolve(FirebaseFirestore? injected) {
    try {
      return injected ?? FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable => _dbOrNull != null;

  CollectionReference<Map<String, dynamic>> get _users =>
      _dbOrNull!.collection(UserService.collectionPath);

  /// Live feed of every student document, newest first.
  Stream<List<UserProfile>> watchStudentRegistrations() {
    if (!isAvailable) return Stream.value(const <UserProfile>[]);

    return _users
        .where('role', isEqualTo: UserRole.student.wireValue)
        .snapshots()
        .map((snapshot) {
      final profiles = snapshot.docs
          .map((doc) => UserProfile.fromMap(doc.id, doc.data()))
          .toList();
      // Sorted client-side so no composite Firestore index is required.
      profiles.sort((a, b) {
        final aDate = a.createdAt;
        final bDate = b.createdAt;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
      return profiles;
    });
  }

  /// Moves an account between lifecycle states — this is what opens or closes
  /// the login gate for a student.
  Future<void> setAccountStatus(String uid, AccountStatus status) async {
    if (!isAvailable) {
      throw const AuthFailure('The database is unavailable. Please restart the app.');
    }
    try {
      await _users.doc(uid).update({
        'status': status.wireValue,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  Future<AccountCounts> fetchAccountCounts() async {
    if (!isAvailable) return AccountCounts.empty;
    try {
      final students = await _countByRole(UserRole.student);
      final admins = await _countByRole(UserRole.admin);
      final pending = await _countPendingStudents();
      return AccountCounts(
        students: students,
        admins: admins,
        pendingStudents: pending,
      );
    } on FirebaseException {
      // Counts are cosmetic — never fail a screen over them.
      return AccountCounts.empty;
    }
  }

  Future<int> _countByRole(UserRole role) async {
    final snapshot =
        await _users.where('role', isEqualTo: role.wireValue).count().get();
    return snapshot.count ?? 0;
  }

  /// Two equality filters are served by merging single-field indexes, so this
  /// needs no composite index.
  Future<int> _countPendingStudents() async {
    final snapshot = await _users
        .where('role', isEqualTo: UserRole.student.wireValue)
        .where('status', isEqualTo: AccountStatus.pending.wireValue)
        .count()
        .get();
    return snapshot.count ?? 0;
  }
}
