import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_result.dart';

/// Firebase Authentication only.
///
/// This service knows nothing about Firestore, profiles, roles or approval —
/// it creates, verifies and destroys credentials. Profile data lives in
/// [UserService]; approval lives in [AdminService]; the session is owned by
/// [AppState].
///
/// Every Firebase error is translated into [AuthFailure] so `firebase_auth`
/// types never escape this file.
class AuthService {
  // Remember Me — the login identifier only. Passwords are never persisted.
  static const String _rememberMeKey = 'remember_me';
  static const String _savedIdentifierKey = 'saved_user_id';
  static const String _legacyPasswordKey = 'saved_password';

  final FirebaseAuth? _authOrNull;

  AuthService({FirebaseAuth? auth}) : _authOrNull = _resolve(auth);

  /// Resolving the instance can throw when Firebase has not been initialised
  /// (a plain widget test). Degrade to unavailable instead of taking the app
  /// down; every entry point below checks [isAvailable].
  static FirebaseAuth? _resolve(FirebaseAuth? injected) {
    try {
      return injected ?? FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable => _authOrNull != null;
  FirebaseAuth get _auth => _authOrNull!;

  // ── Session primitives ──────────────────────────────────────────
  User? getCurrentUser() => isAvailable ? _auth.currentUser : null;

  Stream<User?> authStateChanges() =>
      isAvailable ? _auth.authStateChanges() : const Stream<User?>.empty();

  /// UID-only view of [authStateChanges], so callers never need to import
  /// `firebase_auth` just to observe the session.
  Stream<String?> uidChanges() => authStateChanges().map((user) => user?.uid);

  String? get currentUid => getCurrentUser()?.uid;

  // ── Credentials ─────────────────────────────────────────────────
  /// Returns the signed-in user's UID. Throws [AuthFailure] on any failure.
  Future<String> signIn({required String email, required String password}) async {
    _assertAvailable();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user?.uid;
      if (uid == null) {
        throw const AuthFailure('Sign in failed. Please try again.');
      }
      return uid;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Creates the account and returns its UID. Firebase signs the new user in
  /// automatically — the caller is responsible for signing back out.
  Future<String> createAccount({required String email, required String password}) async {
    _assertAvailable();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user?.uid;
      if (uid == null) {
        throw const AuthFailure('Registration failed. Please try again.');
      }
      return uid;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  Future<void> signOut() async {
    if (!isAvailable) return;
    try {
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    _assertAvailable();
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Deletes the currently signed-in account. Used to roll back a
  /// registration whose Firestore profile write failed, so no orphaned
  /// credential is left behind.
  ///
  /// Returns whether the account is gone. Never throws — the caller is
  /// already handling a failure when it calls this.
  Future<bool> deleteCurrentAccount() async {
    final user = _authOrNull?.currentUser;
    if (user == null) return false;
    try {
      await user.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cosmetic; failures are ignored so they can never fail a registration
  /// that has otherwise succeeded.
  Future<void> updateDisplayName(String name) async {
    final user = _authOrNull?.currentUser;
    if (user == null) return;
    try {
      await user.updateDisplayName(name);
    } catch (_) {
      // Not worth surfacing.
    }
  }

  // ── Remember Me (identifier only, never the password) ───────────
  Future<void> saveRememberedIdentifier(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedIdentifierKey, identifier.trim());
    await prefs.setBool(_rememberMeKey, true);
    // Drop anything written by the old mock implementation.
    await prefs.remove(_legacyPasswordKey);
  }

  Future<String?> loadRememberedIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    // Defensive cleanup: earlier builds stored the password in plain text.
    if (prefs.containsKey(_legacyPasswordKey)) {
      await prefs.remove(_legacyPasswordKey);
    }
    if (!(prefs.getBool(_rememberMeKey) ?? false)) return null;
    final id = prefs.getString(_savedIdentifierKey);
    return (id == null || id.isEmpty) ? null : id;
  }

  Future<void> clearRememberedIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedIdentifierKey);
    await prefs.remove(_legacyPasswordKey);
    await prefs.setBool(_rememberMeKey, false);
  }

  void _assertAvailable() {
    if (!isAvailable) {
      throw const AuthFailure('Authentication is unavailable. Please restart the app.');
    }
  }
}
