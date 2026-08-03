import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../models/auth_result.dart';
import '../models/issue.dart';
import '../models/item.dart';
import '../models/user_profile.dart';
import 'admin_service.dart';
import 'auth_service.dart';
import 'issue_service.dart';
import 'lost_found_service.dart';
import 'user_service.dart';

// Re-exported so screens keep importing a single file for session types.
export '../models/app_notification.dart' show AppNotification;
export '../models/auth_result.dart' show AuthResult, AuthFailure;
export '../models/issue.dart' show Issue, IssueHistory;
export '../models/item.dart' show Item, ItemStatus, ItemType;
export '../models/user_profile.dart' show UserProfile, UserRole, AccountStatus;

/// App-wide session state and the orchestrator across the three services:
/// [AuthService] (credentials), [UserService] (profile documents) and
/// [AdminService] (approval).
///
/// This is the only object the widget tree talks to, and the only
/// `ChangeNotifier` in the auth stack — the Provider graph is unchanged.
/// No Firebase type crosses this boundary.
class AppState extends ChangeNotifier {
  final AuthService _auth;
  final UserService _users;
  final AdminService _admin;
  final LostFoundService _lostFound;
  final IssueService _issues;

  String? _firebaseUid;
  UserProfile? _profile;
  AccountCounts _counts = AccountCounts.empty;
  StreamSubscription<String?>? _authSub;

  AppState({
    AuthService? authService,
    UserService? userService,
    AdminService? adminService,
    LostFoundService? lostFoundService,
    IssueService? issueService,
  })  : _auth = authService ?? AuthService(),
        _users = userService ?? UserService(),
        _admin = adminService ?? AdminService(),
        _lostFound = lostFoundService ?? LostFoundService(),
        _issues = issueService ?? IssueService() {
    _firebaseUid = _auth.currentUid;
    // Firebase auth state can change without a UI action (token refresh,
    // cold-start session restore), so mirror it into the widget tree.
    _authSub = _auth.uidChanges().listen(_onUidChanged);
  }

  bool get _servicesReady =>
      _auth.isAvailable && _users.isAvailable && _admin.isAvailable;

  // ── Session ───────────────────────────────────────────────────────
  /// True only when a Firebase user is signed in, their profile has loaded,
  /// and the account is approved.
  bool get isAuthenticated => _firebaseUid != null && (_profile?.isActive ?? false);

  bool get isAdmin => _profile?.isAdmin ?? false;

  /// Campus-issued Student / Admin ID (e.g. `S001`). The rest of the app keys
  /// its records off this, so it is deliberately NOT the Firebase UID.
  String? get userId => _profile?.userId;

  /// Firebase Authentication UID — also the `users` document ID.
  String? get firebaseUid => _firebaseUid;

  String? get userName => _profile?.fullName;
  UserRole? get userRole => _profile?.role;
  AccountStatus? get userStatus => _profile?.status;
  UserProfile? get currentUserProfile => _profile;

  // ── USER ANALYTICS ────────────────────────────────────────────────
  int get totalAccounts => _counts.total;
  int get totalStudentAccounts => _counts.students;
  int get totalAdminAccounts => _counts.admins;

  /// Students still awaiting approval on the Student Registrations screen.
  int get pendingStudentAccounts => _counts.pendingStudents;

  Future<void> refreshAccountStats() async {
    final counts = await _admin.fetchAccountCounts();
    _counts = counts;
    notifyListeners();
  }

  Future<void> _onUidChanged(String? uid) async {
    _firebaseUid = uid;
    if (uid == null) {
      _profile = null;
      notifyListeners();
      return;
    }
    // Restore the profile after a cold start where Firebase kept the session.
    if (_profile == null || _profile!.uid != uid) {
      try {
        _profile = await _users.fetchProfile(uid);
      } on AuthFailure {
        _profile = null;
      }
    }
    notifyListeners();
  }

  // ── SIGN IN ───────────────────────────────────────────────────────
  /// [id] accepts a Student/Admin ID or an email address.
  Future<AuthResult> loginUser(String id, String password, bool isAdminLogin) async {
    if (!_servicesReady) return _unavailable;

    final identifier = id.trim();
    if (identifier.isEmpty || password.isEmpty) {
      return const AuthResult.failure('Please fill all fields');
    }

    try {
      final authEmail = await _users.resolveAuthEmail(identifier);
      if (authEmail == null) {
        return const AuthResult.failure('No account exists with this ID.');
      }

      final uid = await _auth.signIn(email: authEmail, password: password);
      final profile = await _users.fetchProfile(uid);

      if (profile == null) {
        await _auth.signOut();
        return const AuthResult.failure(
          'Your profile could not be found. Please contact the administrator.',
        );
      }

      final rejection = _gateFor(profile, requireAdmin: isAdminLogin);
      if (rejection != null) {
        await _auth.signOut();
        return AuthResult.failure(rejection);
      }

      _firebaseUid = uid;
      _profile = profile;
      notifyListeners();
      unawaited(refreshAccountStats());
      return AuthResult.success(profile: profile);
    } on AuthFailure catch (failure) {
      return AuthResult.failure(failure.message);
    }
  }

  /// Returns the reason this profile may not enter the app, or null if it may.
  String? _gateFor(UserProfile profile, {required bool requireAdmin}) {
    switch (profile.status) {
      case AccountStatus.pending:
        return 'Your account is waiting for administrator approval.';
      case AccountStatus.rejected:
        return 'Your registration was rejected.';
      case AccountStatus.active:
        break;
    }
    if (requireAdmin && !profile.isAdmin) {
      return 'This account does not have administrator access.';
    }
    if (!requireAdmin && profile.isAdmin) {
      return 'This is an administrator account. Use the admin login.';
    }
    return null;
  }

  // ── REGISTER ──────────────────────────────────────────────────────
  /// Creates the credential and the profile document as one atomic unit.
  ///
  /// Firestore has no cross-service transaction with Firebase Auth, so if the
  /// profile write fails the newly created credential is deleted — an account
  /// can never exist in Authentication without a matching `users` document.
  Future<AuthResult> registerStudent({
    required String studentId,
    required String fullName,
    required String email,
    required String faculty,
    required String password,
  }) async {
    if (!_servicesReady) return _unavailable;

    final normalisedId = studentId.trim().toUpperCase();
    final normalisedEmail = email.trim();

    try {
      if (await _users.isStudentIdTaken(normalisedId)) {
        return const AuthResult.failure('This Student ID is already registered.');
      }

      // Step 1 — credential. Firebase signs the new user in automatically.
      final uid = await _auth.createAccount(
        email: normalisedEmail,
        password: password,
      );

      final profile = UserProfile(
        uid: uid,
        studentId: normalisedId,
        fullName: fullName.trim(),
        // Immutable from here on; sign-in always resolves to this address.
        authEmail: normalisedEmail,
        email: normalisedEmail,
        faculty: faculty.trim(),
        role: UserRole.student,
        status: AccountStatus.pending,
      );

      // Step 2 — profile document, with rollback if it fails.
      try {
        await _users.createProfile(profile);
      } on AuthFailure catch (failure) {
        final rolledBack = await _auth.deleteCurrentAccount();
        if (!rolledBack) await _auth.signOut();
        _firebaseUid = null;
        _profile = null;
        notifyListeners();
        return AuthResult.failure(
          rolledBack
              ? 'Could not complete registration: ${failure.message} Please try again.'
              : 'Registration could not be completed. Please contact the '
                  'administrator before registering again.',
        );
      }

      await _auth.updateDisplayName(profile.fullName);

      // A pending account must not hold a live session.
      await _auth.signOut();
      _firebaseUid = null;
      _profile = null;
      notifyListeners();

      return AuthResult.success(
        profile: profile,
        message: 'Your account is waiting for administrator approval.',
      );
    } on AuthFailure catch (failure) {
      return AuthResult.failure(failure.message);
    }
  }

  // ── SIGN OUT / RESET ──────────────────────────────────────────────
  Future<void> logout() async {
    try {
      await _auth.signOut();
    } on AuthFailure {
      // Clearing local state matters more than a clean remote sign-out.
    }
    await _auth.clearRememberedIdentifier();
    _firebaseUid = null;
    _profile = null;
    notifyListeners();
  }

  Future<AuthResult> switchRole(String id, String password, bool toAdmin) =>
      loginUser(id, password, toAdmin);

  Future<AuthResult> sendPasswordReset(String identifier) async {
    if (!_servicesReady) return _unavailable;
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) {
      return const AuthResult.failure('Enter your Student ID or email first.');
    }
    try {
      final authEmail = await _users.resolveAuthEmail(trimmed);
      if (authEmail == null) {
        return const AuthResult.failure('No account exists with this ID.');
      }
      await _auth.sendPasswordResetEmail(authEmail);
      return AuthResult.success(message: 'Password reset link sent to $authEmail');
    } on AuthFailure catch (failure) {
      return AuthResult.failure(failure.message);
    }
  }

  // ── LOST & FOUND ──────────────────────────────────────────────────
  /// Live feed of the signed-in student's own lost reports, newest first.
  ///
  /// The screen never has to know the Firebase UID — it is read from the
  /// session here, so the UI keeps its single dependency on [AppState].
  /// Signed out yields an empty list, matching the screen's empty state.
  Stream<List<Item>> watchMyLostReports() =>
      _lostFound.watchMyLostItems(_firebaseUid ?? '');

  /// Live feed of the signed-in student's own found reports, newest first.
  ///
  /// Same contract as [watchMyLostReports] — the screen supplies no UID and
  /// signing out yields an empty list.
  Stream<List<Item>> watchMyFoundReports() =>
      _lostFound.watchMyFoundItems(_firebaseUid ?? '');

  /// Live view of a single report (lost or found) by its Firestore document ID.
  ///
  /// The detail screens call this with only the ID from the route — they never
  /// touch the service or Firestore, and they never see a Firebase type: the
  /// stream emits the [Item], `null` for "not found", or throws an
  /// [AuthFailure] for permission/offline failures.
  Stream<Item?> watchReport(String id) => _lostFound.watchItem(id);

  /// Live feed of the signed-in student's own lost AND found reports, for the
  /// Lost & Found hub's combined summary counts.
  ///
  /// One query instead of merging two streams — the hub splits the result into
  /// lost/found by [Item.isLost] / [Item.isFound] when it needs the breakdown.
  Stream<List<Item>> watchMyAllReports() =>
      _lostFound.watchMyAllItems(_firebaseUid ?? '');

  /// Live feed of every lost report across all students, for the admin list
  /// screen. No UID — an admin sees everyone's reports.
  Stream<List<Item>> watchAdminLostReports() =>
      _lostFound.watchAllLostItems();

  /// Live feed of every found report across all students, for the admin list
  /// screen. Same contract as [watchAdminLostReports] with `type` `found`.
  Stream<List<Item>> watchAdminFoundReports() =>
      _lostFound.watchAllFoundItems();

  /// Live feed of every lost AND found report across all students, for the
  /// admin dashboard's combined summary counts. One query instead of merging
  /// two streams — the dashboard splits the result into lost/found by
  /// [Item.isLost] / [Item.isFound] when it needs the breakdown.
  Stream<List<Item>> watchAdminAllReports() =>
      _lostFound.watchAllItems();

  /// Live feed behind the Notifications screen, newest first.
  ///
  /// Notifications are derived from the reports themselves rather than read
  /// from a `notifications` collection — `firestore.rules` governs only
  /// `users` and `items`, and Firestore is default-deny, so no such collection
  /// can exist yet. Each report the caller may already see becomes one row,
  /// and because the query is a live snapshot a status change re-emits its row
  /// without a refresh.
  ///
  /// The screen supplies no UID and no role: the admin/student split is
  /// resolved here, so an admin sees every report attributed to its reporter
  /// and a student sees only their own. Signed out yields an empty list,
  /// matching the screen's empty state.
  Stream<List<AppNotification>> watchNotifications() {
    final admin = isAdmin;
    return _lostFound
        .watchNotificationItems(uid: admin ? null : (_firebaseUid ?? ''))
        .map((items) => items
            .map((item) => admin
                ? AppNotification.forAdmin(item)
                : AppNotification.forOwner(item))
            .toList(growable: false));
  }

  // ── ISSUES ────────────────────────────────────────────────────────
  /// Live feed of the signed-in student's own issues, newest first.
  ///
  /// The screen never supplies an ID — the campus Student ID is read from the
  /// session here, so the UI keeps its single dependency on [AppState].
  /// Signed out yields an empty list, matching the screen's empty state.
  Stream<List<Issue>> watchMyIssues() =>
      _issues.watchMyIssues(userId ?? '');

  /// Live feed of every issue across all students, for the admin list screen.
  /// No ID — an admin sees everyone's issues.
  Stream<List<Issue>> watchAllIssues() => _issues.watchAllIssues();

  /// Live view of a single issue by its Firestore document ID. Emits the
  /// [Issue], `null` for "not found", or throws an [AuthFailure].
  Stream<Issue?> watchIssue(String id) => _issues.watchIssue(id);

  /// Live feed of an issue's status-transition history, oldest first, for the
  /// detail screen's timeline. Emits an empty list when there is no history.
  Stream<List<IssueHistory>> watchIssueHistory(String id) =>
      _issues.watchIssueHistory(id);

  /// Submits a new issue on behalf of the signed-in student, stamping the
  /// campus Student ID from the session. Returns the issue with its
  /// Firestore ID, or `null` on failure.
  Future<Issue?> createIssue({
    required String title,
    required String category,
    required String location,
    required String description,
    List<String> imagePaths = const [],
  }) async {
    final now = DateTime.now().toIso8601String();
    final issue = Issue(
      id: '',
      title: title,
      category: category,
      location: location,
      status: 'New',
      createdDate: now,
      updatedDate: now,
      description: description,
      studentId: userId,
      imagePaths: imagePaths,
    );
    try {
      return await _issues.createIssue(issue);
    } on AuthFailure {
      return null;
    }
  }

  /// Moves an issue to a new status. Returns `true` on success.
  Future<bool> updateIssueStatus(String id, String status) async {
    try {
      await _issues.updateIssueStatus(id, status);
      return true;
    } on AuthFailure {
      return false;
    }
  }

  // ── REGISTRATION APPROVAL (admin) ─────────────────────────────────
  Stream<List<UserProfile>> watchStudentRegistrations() =>
      _admin.watchStudentRegistrations();

  Future<bool> approveRegistration(String uid) =>
      _setStatus(uid, AccountStatus.active);

  Future<bool> rejectRegistration(String uid) =>
      _setStatus(uid, AccountStatus.rejected);

  Future<bool> _setStatus(String uid, AccountStatus status) async {
    try {
      await _admin.setAccountStatus(uid, status);
      if (_profile?.uid == uid) {
        _profile = _profile!.copyWith(status: status);
      }
      notifyListeners();
      unawaited(refreshAccountStats());
      return true;
    } on AuthFailure {
      return false;
    }
  }

  Future<bool> isStudentIdTaken(String studentId) async {
    try {
      return await _users.isStudentIdTaken(studentId);
    } on AuthFailure {
      return false;
    }
  }

  // ── REMEMBER ME (identifier only — never the password) ────────────
  Future<void> saveRememberedIdentifier(String id) =>
      _auth.saveRememberedIdentifier(id);

  Future<String?> loadRememberedIdentifier() => _auth.loadRememberedIdentifier();

  Future<void> clearRememberedIdentifier() => _auth.clearRememberedIdentifier();

  // ── PROFILE ───────────────────────────────────────────────────────
  Future<bool> updateCurrentUserProfile({
    required String name,
    required String email,
    required String programme,
    required String phone,
  }) async {
    final current = _profile;
    if (current == null || !_servicesReady) return false;
    try {
      _profile = await _users.updateContactDetails(
        current: current,
        fullName: name,
        email: email,
        faculty: programme,
        phone: phone,
      );
      notifyListeners();
      return true;
    } on AuthFailure {
      return false;
    }
  }

  static const AuthResult _unavailable =
      AuthResult.failure('Authentication is unavailable. Please restart the app.');

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
