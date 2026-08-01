import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/auth_result.dart';
import '../models/user_profile.dart';

/// Firestore CRUD for the `users` collection.
///
/// Owns everything about a user *document*; owns nothing about credentials.
/// Every Firestore error is translated into [AuthFailure] so `cloud_firestore`
/// types never escape this file.
class UserService {
  static const String collectionPath = 'users';

  final FirebaseFirestore? _dbOrNull;

  UserService({FirebaseFirestore? firestore}) : _dbOrNull = _resolve(firestore);

  static FirebaseFirestore? _resolve(FirebaseFirestore? injected) {
    try {
      return injected ?? FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable => _dbOrNull != null;

  CollectionReference<Map<String, dynamic>> get _users =>
      _dbOrNull!.collection(collectionPath);

  /// Resolves whatever the user typed into the login field to the address
  /// Firebase Authentication knows the account by.
  ///
  /// The login screen asks for a Student ID, but Firebase signs in with an
  /// email — this is the bridge. It always returns `authEmail`, never the
  /// editable display `email`, so a profile edit can never lock an account out.
  Future<String?> resolveAuthEmail(String identifier) async {
    _assertAvailable();
    final raw = identifier.trim();
    if (raw.isEmpty) return null;

    try {
      if (raw.contains('@')) {
        // Could be the auth address or a display address that has since been
        // edited. Look it up; fall back to treating it as the auth address.
        final match = await _findOne('email', raw) ?? await _findOne('authEmail', raw);
        return match?.authEmail ?? raw;
      }

      // Campus ID. IDs are stored uppercase, but try the raw form too so a
      // document written by hand in mixed case still resolves.
      for (final candidate in {raw.toUpperCase(), raw}) {
        final match = await _findOne('studentId', candidate);
        if (match != null && match.authEmail.isNotEmpty) return match.authEmail;
      }
      return null;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  Future<UserProfile?> fetchProfile(String uid) async {
    _assertAvailable();
    try {
      final doc = await _users.doc(uid).get();
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return UserProfile.fromMap(uid, data);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Writes the initial document. Throws [AuthFailure] on failure so the
  /// caller can roll the Firebase Auth account back.
  Future<void> createProfile(UserProfile profile) async {
    _assertAvailable();
    try {
      await _users.doc(profile.uid).set(profile.toCreateMap());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Updates the editable contact fields only.
  ///
  /// `authEmail`, `role`, `status`, `uid` and `studentId` are deliberately
  /// absent — they are immutable from the client and the security rules
  /// reject any attempt to change them.
  Future<UserProfile> updateContactDetails({
    required UserProfile current,
    required String fullName,
    required String email,
    required String faculty,
    required String phone,
  }) async {
    _assertAvailable();
    final updated = current.copyWith(
      fullName: fullName.trim(),
      email: email.trim(),
      faculty: faculty.trim(),
      phone: phone.trim(),
    );
    try {
      await _users.doc(current.uid).update({
        'fullName': updated.fullName,
        'email': updated.email,
        'faculty': updated.faculty,
        'phone': updated.phone,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return updated;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  Future<bool> isStudentIdTaken(String studentId) async {
    _assertAvailable();
    final id = studentId.trim().toUpperCase();
    if (id.isEmpty) return false;
    try {
      return await _findOne('studentId', id) != null;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Single-document lookup. The `limit(1)` matters: the security rules only
  /// permit an anonymous `list` when the query asks for one document.
  Future<UserProfile?> _findOne(String field, String value) async {
    final snapshot = await _users.where(field, isEqualTo: value).limit(1).get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return UserProfile.fromMap(doc.id, doc.data());
  }

  void _assertAvailable() {
    if (!isAvailable) {
      throw const AuthFailure('The database is unavailable. Please restart the app.');
    }
  }
}
