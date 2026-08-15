import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../models/auth_result.dart';
import '../models/candidate.dart';
import '../models/election_meta.dart';
import '../models/event.dart';
import '../models/event_action_result.dart';
import '../models/event_joining.dart';
import '../models/event_message.dart';
import '../models/event_role.dart';
import '../models/issue.dart';
import '../models/item.dart';
import '../models/locker.dart';
import '../models/locker_booking.dart';
import '../models/locker_history.dart';
import '../models/locker_issue.dart';
import '../models/locker_notification.dart';
import '../models/payment.dart';
import '../models/user_profile.dart';
import 'admin_service.dart';
import 'auth_service.dart';
import 'cloudinary_service.dart';
import 'election_service.dart';
import 'event_service.dart';
import 'issue_service.dart';
import 'locker_service.dart';
import 'locker_pricing.dart';
import 'lost_found_service.dart';
import 'payment_service.dart';
import 'user_service.dart';

// Re-exported so screens keep importing a single file for session types.
export '../models/app_notification.dart' show AppNotification;
export '../models/auth_result.dart' show AuthResult, AuthFailure;
export '../models/candidate.dart' show Candidate;
export '../models/election_meta.dart' show ElectionMeta, ElectionTimelineEntry;
export '../models/event.dart' show Event;
export '../models/event_joining.dart' show EventJoining;
export '../models/event_message.dart' show EventMessage;
export '../models/event_role.dart' show EventRole;
export '../models/issue.dart' show Issue, IssueHistory;
export '../models/item.dart' show Item, ItemStatus, ItemType;
export '../models/locker.dart' show Locker;
export '../models/locker_booking.dart' show LockerBooking, LockerBookingResult;
export '../models/locker_history.dart' show LockerHistory;
export '../models/locker_issue.dart' show LockerIssue;
export '../models/locker_notification.dart' show LockerNotification;
export '../models/payment.dart' show Payment, PaymentResult;
export '../models/user_profile.dart'
    show UserProfile, UserRole, AccountStatus, ProfileLoadStatus;
export 'cloudinary_service.dart' show CloudinaryUploadResult, CloudinaryException;

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
  final LockerService _lockers;
  final PaymentService _payments;
  final EventService _eventsService;
  final ElectionService _electionsService;
  final CloudinaryService _cloudinary;

  String? _firebaseUid;
  UserProfile? _profile;
  ProfileLoadStatus _profileStatus = ProfileLoadStatus.idle;
  AccountCounts _counts = AccountCounts.empty;
  StreamSubscription<String?>? _authSub;

  AppState({
    AuthService? authService,
    UserService? userService,
    AdminService? adminService,
    LostFoundService? lostFoundService,
    IssueService? issueService,
    LockerService? lockerService,
    PaymentService? paymentService,
    EventService? eventService,
    ElectionService? electionService,
    CloudinaryService? cloudinaryService,
  })  : _auth = authService ?? AuthService(),
        _users = userService ?? UserService(),
        _admin = adminService ?? AdminService(),
        _lostFound = lostFoundService ?? LostFoundService(),
        _issues = issueService ?? IssueService(),
        _lockers = lockerService ?? LockerService(),
        _payments = paymentService ?? PaymentService(),
        _eventsService = eventService ?? EventService(),
        _electionsService = electionService ?? ElectionService(),
        _cloudinary = cloudinaryService ??
            CloudinaryService(
              cloudName: 'xijxwdly',
              uploadPreset: 'campus_connect_events',
              folder: 'events',
            ) {
    _firebaseUid = _auth.currentUid;
    // Firebase auth state can change without a UI action (token refresh,
    // cold-start session restore), so mirror it into the widget tree.
    _authSub = _auth.uidChanges().listen(_onUidChanged);
  }

  /// Test-only constructor that seeds a known profile (and optional load
  /// status) so the Profile screen can be rendered with deterministic data
  /// in widget tests. Firebase is not initialised in tests, so the default
  /// constructor would otherwise leave the profile null and the screen in its
  /// empty state. Never used in production.
  @visibleForTesting
  factory AppState.forTesting({
    UserProfile? profile,
    ProfileLoadStatus status = ProfileLoadStatus.idle,
  }) {
    final state = AppState();
    // A signed-in-but-unloaded user (loading/missing/error) still has a uid.
    state._firebaseUid =
        profile?.uid ?? (status == ProfileLoadStatus.idle ? null : 'test-uid');
    state._profile = profile;
    state._profileStatus =
        profile == null ? status : ProfileLoadStatus.ready;
    return state;
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

  /// Where the current profile load stands, so the Profile screen can show a
  /// loading or retry state instead of hard-coded fallback data.
  ProfileLoadStatus get profileLoadStatus => _profileStatus;

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
      _profileStatus = ProfileLoadStatus.idle;
      notifyListeners();
      return;
    }
    // Restore the profile after a cold start or Firebase session restore.
    if (_profile == null || _profile!.uid != uid) {
      _profileStatus = ProfileLoadStatus.loading;
      notifyListeners();
      try {
        _profile = await _users.fetchProfile(uid);
        _profileStatus = _profile == null
            ? ProfileLoadStatus.missing
            : ProfileLoadStatus.ready;
      } on AuthFailure {
        _profile = null;
        _profileStatus = ProfileLoadStatus.error;
      }
    }
    // Apply the same gate checks as loginUser so a restored session
    // cannot bypass role or account-status validation.
    if (_profile != null) {
      final rejection = _gateFor(_profile!, requireAdmin: _profile!.isAdmin);
      if (rejection != null) {
        try {
          await _auth.signOut();
        } on AuthFailure { /* clear local state regardless */ }
        _firebaseUid = null;
        _profile = null;
        _profileStatus = ProfileLoadStatus.idle;
      } else if (_profile!.isAdmin) {
        // Only admins can fetch account stats — the queries count all users
        // and are denied by Firestore rules for students.
        unawaited(refreshAccountStats());
      }
    }
    notifyListeners();
  }

  /// Re-fetches the current user's profile. Used by the Profile screen's
  /// retry affordance when a load failed or the document was missing.
  Future<void> retryLoadProfile() async {
    final uid = _firebaseUid;
    if (uid == null || !_servicesReady) {
      _profileStatus = ProfileLoadStatus.idle;
      notifyListeners();
      return;
    }
    _profileStatus = ProfileLoadStatus.loading;
    notifyListeners();
    try {
      _profile = await _users.fetchProfile(uid);
      _profileStatus = _profile == null
          ? ProfileLoadStatus.missing
          : ProfileLoadStatus.ready;
    } on AuthFailure {
      _profile = null;
      _profileStatus = ProfileLoadStatus.error;
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
      _profileStatus = ProfileLoadStatus.ready;
      notifyListeners();
      // Only fetch account stats for admins — the queries count all users
      // and are denied by Firestore rules for students.
      if (profile.isAdmin) {
        unawaited(refreshAccountStats());
      }
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
    _profileStatus = ProfileLoadStatus.idle;
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

  /// Hard-deletes an issue. Returns `true` on success.
  ///
  /// Kept for parity with the admin detail screen's delete button; the current
  /// Firestore rules deny client deletes, so this will return `false` until
  /// the rules are relaxed.
  Future<bool> deleteIssue(String id) async {
    try {
      await _issues.deleteIssue(id);
      return true;
    } on AuthFailure {
      return false;
    }
  }

  // ── LOCKERS ───────────────────────────────────────────────────────
  /// Live feed of every locker, for the browse screen (students) and the
  /// admin list/dashboard screens.
  Stream<List<Locker>> watchLockers() => _lockers.watchLockers();

  /// Live view of a single locker by its document ID (e.g. `LK-A01`), for the
  /// booking and admin detail screens. Emits `null` when it does not exist.
  Stream<Locker?> watchLocker(String id) => _lockers.watchLocker(id);

  /// Live feed of the signed-in student's own locker bookings, newest first.
  ///
  /// The screen never supplies an ID — the campus Student ID is read from the
  /// session here, so the UI keeps its single dependency on [AppState].
  /// Signed out yields an empty list, matching the screen's empty state.
  Stream<List<LockerBooking>> watchMyLockerBookings() =>
      _lockers.watchMyBookings(userId ?? '');

  /// Live feed of every locker booking across all students, for the admin
  /// screens. No ID — an admin sees everyone's bookings.
  Stream<List<LockerBooking>> watchAllLockerBookings() =>
      _lockers.watchAllBookings();

  /// Live view of a single locker booking by its Firestore document ID.
  /// Emits the [LockerBooking], `null` for "not found", or throws an
  /// [AuthFailure].
  Stream<LockerBooking?> watchLockerBooking(String id) =>
      _lockers.watchBooking(id);

  /// Live feed of a locker's audit-trail history, oldest first, for the admin
  /// detail screen's timeline. Emits an empty list when there is no history.
  Stream<List<LockerHistory>> watchLockerHistory(String lockerId) =>
      _lockers.watchLockerHistory(lockerId);

  /// Live feed of the signed-in student's own locker issue reports, newest
  /// first.
  Stream<List<LockerIssue>> watchMyLockerIssues() =>
      _lockers.watchMyLockerIssues(userId ?? '');

  /// Live feed of every locker issue across all students, for the admin
  /// screens.
  Stream<List<LockerIssue>> watchAllLockerIssues() =>
      _lockers.watchAllLockerIssues();

  /// Live feed of the signed-in student's own locker notifications, newest
  /// first.
  Stream<List<LockerNotification>> watchMyLockerNotifications() =>
      _lockers.watchMyLockerNotifications(userId ?? '');

  /// Marks a locker notification as read. Returns `true` on success.
  Future<bool> markLockerNotificationRead(String notificationId) async {
    try {
      await _lockers.markNotificationRead(notificationId);
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Creates a locker notification for a student. Admin-only — called by the
  /// terminate, release, block, and force-release flows. Best-effort: a
  /// failure is logged but does not block the calling action.
  Future<void> _sendLockerNotification({
    required String studentId,
    required String lockerId,
    required String title,
    required String body,
    required String type,
  }) async {
    if (studentId.isEmpty) return;
    try {
      await _lockers.createLockerNotification(LockerNotification(
        id: '',
        studentId: studentId,
        lockerId: lockerId,
        title: title,
        body: body,
        type: type,
        createdAt: DateTime.now().toIso8601String(),
      ));
    } on AuthFailure {
      // Best-effort: the primary action (terminate/release/block) already
      // succeeded; a notification failure should not roll it back.
      debugPrint('Failed to send locker notification: $title');
    }
  }

  /// Live feed of the signed-in student's own payments, newest first.
  Stream<List<Payment>> watchMyPayments() =>
      _payments.watchMyPayments(userId ?? '');

  /// Live feed of every payment across all students, for the admin screens.
  Stream<List<Payment>> watchAllPayments() => _payments.watchAllPayments();

  /// Fetches the payment record linked to a booking, if any.
  Future<Payment?> getPaymentForBooking(String bookingId) =>
      _payments.getPaymentForBooking(bookingId);

  /// Books a locker on behalf of the signed-in student, stamping the campus
  /// Student ID from the session. Returns the booking with its Firestore ID,
  /// or `null` on failure.
  ///
  /// The accompanying locker status update and history entry are written by
  /// the caller (or a future batched-write helper); this creates the booking
  /// document only.
  Future<LockerBooking?> bookLocker(String lockerId, {
    required String location,
    required int durationMonths,
  }) async {
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month + durationMonths, now.day);
    final daysLeft = endDate.difference(now).inDays;
    // Use default pricing when the Locker object isn't available.
    final pricing = const LockerPricing(deposit: 100.0, monthlyRent: 10.0, durationMonths: 6)
        .copyWithDurationMonths(durationMonths);

    final booking = LockerBooking(
      id: '',
      lockerId: lockerId,
      location: location,
      startDate: now.toIso8601String().split('T').first,
      endDate: endDate.toIso8601String().split('T').first,
      status: 'Pending Pickup',
      daysLeft: daysLeft,
      durationMonths: pricing.durationMonths,
      monthlyRent: pricing.monthlyRent,
      deposit: pricing.deposit,
      rentalCost: pricing.totalRentalCost,
      totalPaid: pricing.amountDueToday,
      studentId: userId,
    );
    try {
      return await _lockers.createBooking(booking);
    } on AuthFailure {
      return null;
    }
  }

  /// Reports a locker issue on behalf of the signed-in student, stamping the
  /// campus Student ID from the session. Returns the issue with its Firestore
  /// ID, or `null` on failure.
  Future<LockerIssue?> reportLockerIssue(
    String lockerId,
    String description,
    int photoCount, {
    String category = '',
  }) async {
    final issue = LockerIssue(
      id: '',
      lockerId: lockerId,
      studentId: userId ?? '',
      category: category,
      description: description,
      status: 'Reported',
      photoCount: photoCount,
      reportedDate: DateTime.now().toIso8601String(),
    );
    try {
      final created = await _lockers.createLockerIssue(issue);
      // Record the report in the locker's audit-trail history.
      await _lockers.addLockerHistory(lockerId, LockerHistory(
        action: 'Student reported locker issue',
        staffId: userId ?? '',
        timestamp: DateTime.now().toIso8601String(),
        reason: category.isNotEmpty ? '$category: $description' : description,
      ));
      return created;
    } on AuthFailure {
      return null;
    }
  }

  /// Moves a locker issue to a new status ('Under Review' or 'Resolved') and
  /// appends an audit-trail entry to the locker's history. Returns `true` on
  /// success.
  Future<bool> updateLockerIssueStatus(
    LockerIssue issue,
    String newStatus, {
    String? adminNotes,
  }) async {
    try {
      await _lockers.updateLockerIssueStatus(issue.id, newStatus, adminNotes: adminNotes);
      final action = newStatus == 'Under Review'
          ? 'Issue moved to Under Review'
          : newStatus == 'Resolved'
              ? 'Issue resolved'
              : 'Issue status updated';
      await _lockers.addLockerHistory(issue.lockerId, LockerHistory(
        action: action,
        staffId: userId ?? 'admin',
        timestamp: DateTime.now().toIso8601String(),
        reason: adminNotes?.isNotEmpty == true ? adminNotes : null,
      ));
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Appends one entry to a locker's audit-trail history. Returns `true` on
  /// success.
  Future<bool> addLockerHistory(String lockerId, LockerHistory entry) async {
    try {
      await _lockers.addLockerHistory(lockerId, entry);
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Partial update of a locker booking document — used for QR/status
  /// transitions where only a few fields change. Returns `true` on success.
  Future<bool> patchLockerBooking(String id, Map<String, dynamic> fields) async {
    try {
      await _lockers.patchBooking(id, fields);
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Overwrites an existing locker document. Returns `true` on success.
  Future<bool> updateLocker(Locker locker) async {
    try {
      await _lockers.updateLocker(locker);
      return true;
    } on AuthFailure {
      return false;
    }
  }

  // ── LOCKER STUDENT FLOWS ────────────────────────────────────────
  // These orchestrate the multi-document transitions the mock DataService
  // performed in memory: booking update + locker update + history entry.
  // They are written sequentially (Firestore has no cross-collection
  // transaction from the client here); a failure mid-flow leaves the earlier
  // writes in place, matching the mock's behaviour closely enough for the
  // student flows. All return `false` on any failure.

  /// Extends a locker booking by [additionalMonths]. Mirrors the mock rule:
  /// only allowed when 30 or fewer days remain. Updates the booking, the
  /// locker's end date, and appends a history entry. Returns `true` on
  /// success.
  Future<bool> requestLockerExtension(
    LockerBooking booking,
    int additionalMonths,
  ) async {
    if (additionalMonths <= 0 || booking.daysLeft > 30) return false;
    final end = DateTime.tryParse(booking.endDate);
    if (end == null) return false;

    final newEnd = DateTime(end.year, end.month + additionalMonths, end.day);
    final today = DateTime.now();
    final newDaysLeft =
        newEnd.difference(DateTime(today.year, today.month, today.day)).inDays;
    final pricing = LockerPricing.fromBooking(booking);
    final additionalCost = pricing.extensionCost(additionalMonths);
    final newEndStr = newEnd.toIso8601String().split('T').first;

    try {
      await _lockers.patchBooking(booking.id, {
        'endDate': Timestamp.fromDate(newEnd),
        'daysLeft': newDaysLeft,
        'durationMonths': booking.durationMonths + additionalMonths,
        'totalPaid': booking.totalPaid + additionalCost,
      });

      final locker = await _lockers.getLocker(booking.lockerId);
      if (locker != null) {
        await _lockers.updateLocker(locker.copyWith(
          endDate: newEndStr,
          daysLeft: newDaysLeft,
        ));
      }

      await _lockers.addLockerHistory(
        booking.lockerId,
        LockerHistory(
          action: 'Rental extended',
          staffId: 'system',
          timestamp: DateTime.now().toIso8601String(),
          reason:
              'Extended by $additionalMonths month(s). Additional payment: RM${additionalCost.toStringAsFixed(0)}',
        ),
      );
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Starts the release flow for a booking: booking status →
  /// 'Release Requested', releaseStatus → 'Requested', plus a history entry
  /// and a student notification. Mirrors the mock guard: no-op when a release
  /// is already in flight.
  Future<bool> requestLockerRelease(LockerBooking booking) async {
    if (booking.releaseStatus != null && booking.releaseStatus != 'Completed') {
      return false;
    }
    try {
      await _lockers.patchBooking(booking.id, {
        'status': 'Release Requested',
        'releaseStatus': 'Requested',
      });
      await _lockers.addLockerHistory(
        booking.lockerId,
        LockerHistory(
          action: 'Release requested',
          staffId: 'system',
          timestamp: DateTime.now().toIso8601String(),
          reason: 'Student requested locker release',
        ),
      );
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Verifies a key-collection QR scan. On a match the booking becomes
  /// 'Active' with `keyCollected` stamped. The locker status update and
  /// history entry are admin-only operations (Firestore rules deny student
  /// writes to `lockers` and `lockers/{id}/history`), so they are skipped
  /// here — the admin will see the booking flip to 'Active' and can update
  /// the locker inventory from their screen.
  ///
  /// Returns `false` for an invalid code, an already-collected key, or any
  /// failure — the screen's toast wording is unchanged either way.
  Future<bool> scanKeyCollectionQR(LockerBooking booking, String qrCode) async {
    if (booking.keyCollectionQR != qrCode || booking.keyCollected) return false;
    try {
      await _lockers.patchBooking(booking.id, {
        'status': 'Active',
        'keyCollected': true,
        'keyCollectionDate': Timestamp.now(),
      });
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Verifies a key-return QR scan. Mirrors the mock guards: only valid in
  /// 'Pending Return' with a matching, unused code. On a match the booking
  /// records the return and releaseStatus → 'Returned'. The locker history
  /// entry is an admin-only operation (Firestore rules deny student writes to
  /// `lockers/{id}/history`), so it is skipped here. A student notification
  /// is sent confirming the key return.
  Future<bool> scanKeyReturnQR(LockerBooking booking, String qrCode) async {
    if (booking.releaseStatus != 'Pending Return') return false;
    if (booking.keyReturnQR != qrCode || booking.keyReturned) return false;
    try {
      await _lockers.patchBooking(booking.id, {
        'keyReturned': true,
        'keyReturnDate': Timestamp.now(),
        'releaseStatus': 'Returned',
      });
      // Notify the student that the key return was verified.
      if (booking.studentId != null && booking.studentId!.isNotEmpty) {
        await _sendLockerNotification(
          studentId: booking.studentId!,
          lockerId: booking.lockerId,
          title: 'Key Returned',
          body: 'Your key return for locker ${booking.lockerId} has been verified. '
              'Please wait for the admin to finalize your release and process your deposit refund.',
          type: 'key_returned',
        );
      }
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Runs the demo payment gateway for a locker booking and returns the
  /// [PaymentResult]. The payment document is written to the `payments`
  /// collection on success. The booking is NOT created here — the caller
  /// passes the resulting [Payment] to [completeLockerBooking] to create the
  /// booking with status 'Waiting Approval'.
  ///
  /// [cardNumber] and [cardCvv] are used for the demo gateway simulation only;
  /// the full card number and CVV are NEVER stored. Only the last 4 digits
  /// appear on the [Payment] document.
  Future<PaymentResult> processLockerPayment({
    required String cardNumber,
    required String cardCvv,
    required Locker locker,
    required int durationMonths,
  }) async {
    final pricing = LockerPricing.fromLocker(locker, durationMonths);
    try {
      return await _payments.processPayment(
        cardNumber: cardNumber,
        cardCvv: cardCvv,
        amount: pricing.amountDueToday,
        deposit: pricing.deposit,
        monthlyRent: pricing.monthlyRent,
        durationMonths: pricing.durationMonths,
        lockerId: locker.id,
        studentId: userId ?? '',
        bookingId: '', // booking doesn't exist yet; linked after creation
      );
    } on AuthFailure catch (e) {
      debugPrint('processLockerPayment AuthFailure: ${e.message}');
      return PaymentResult.failure('Payment failed: ${e.message}');
    } catch (e) {
      debugPrint('processLockerPayment unexpected error: $e');
      return const PaymentResult.failure('Payment failed. Please try again.');
    }
  }

  /// Creates the student's booking request as a single `lockerBookings`
  /// document with status 'Waiting Approval' and returns it (with its
  /// Firestore ID) on success, or a [LockerBookingResult.failure] carrying a
  /// user-safe message.
  ///
  /// This is called AFTER the demo payment gateway succeeds. The [payment]
  /// record's ID and receipt number are stamped onto the booking so the admin
  /// can review the payment without an extra query.
  ///
  /// Students may ONLY write their own `lockerBookings` document — the
  /// Firestore security rules forbid them from touching `lockers` or
  /// `lockers/{id}/history`. The locker is therefore NOT updated here: it
  /// stays `Available` until the admin approves the booking, which reserves
  /// it and appends the audit-trail entry. For digital locks the unlock code
  /// is generated now and stored on the student-owned booking so the student
  /// can read it once approved. The booking is the single source of truth for
  /// the code — it is never copied onto the world-readable locker document.
  ///
  /// The booking's dates, duration, payment, deposit and rent are computed
  /// here so the later admin approval uses the same values.
  ///
  /// Before creating the booking, a conflict check runs: if an active
  /// (non-Completed, non-Rejected) booking already exists for this locker the
  /// request is rejected with "Locker already reserved." and no document is
  /// written.
  Future<LockerBookingResult> completeLockerBooking(
    Locker locker,
    int durationMonths, {
    Payment? payment,
  }) async {
    // Conflict guard: prevent two students from booking the same locker
    // while it is still `Available` pending admin confirmation. The query
    // excludes `Completed` bookings so a returned locker can be rebooked.
    try {
      final taken = await _lockers.hasActiveBookingForLocker(locker.id);
      if (taken) {
        return const LockerBookingResult.failure('Locker already reserved.');
      }
    } on AuthFailure {
      // The cross-student query is denied for students under the deployed
      // rules (ownsBooking() is not a filter). Treat the denial as "unable
      // to verify" and fall through to the booking create, which remains the
      // authoritative guard. Do not block the booking on the check failing.
    }

    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month + durationMonths, now.day);
    final daysLeft = endDate.difference(now).inDays;
    final pricing = LockerPricing.fromLocker(locker, durationMonths);
    // totalPaid stores the full amount charged today (deposit + total
    // rental cost), matching the Payment record.
    final totalPaid = pricing.amountDueToday;
    final rentalCost = pricing.totalRentalCost;
    // Digital-lock code lives ONLY on the student-owned booking. The
    // `lockers` collection is readable by every signed-in user, so the code
    // is never written there — `booking.digitalCode` is the source of truth.
    final digitalCode =
        locker.lockType == 'digital' ? '${Random().nextInt(9000) + 1000}' : null;

    final booking = LockerBooking(
      id: '',
      lockerId: locker.id,
      location: locker.location,
      startDate: now.toIso8601String().split('T').first,
      endDate: endDate.toIso8601String().split('T').first,
      status: 'Waiting Approval',
      daysLeft: daysLeft,
      durationMonths: pricing.durationMonths,
      monthlyRent: pricing.monthlyRent,
      deposit: pricing.deposit,
      rentalCost: rentalCost,
      totalPaid: totalPaid,
      studentId: userId,
      digitalCode: digitalCode,
      paymentId: payment?.id,
      receiptNumber: payment?.receiptNumber,
    );

    try {
      // Student-safe write: booking document only. No locker/history writes.
      final created = await _lockers.createBooking(booking);
      // If a payment was processed, link it back to the booking now that we
      // have the booking ID. This is a best-effort admin/student update —
      // the payment doc's `bookingId` field helps the admin cross-reference.
      if (payment != null && payment.id.isNotEmpty && _payments.isAvailable) {
        try {
          await _lockers.patchBooking(created.id, {
            'paymentId': payment.id,
            'receiptNumber': payment.receiptNumber,
          });
        } on AuthFailure {
          // Non-fatal: the booking is created; the payment link is cosmetic.
        }
      }
      return LockerBookingResult.success(created.copyWith(
        paymentId: payment?.id,
        receiptNumber: payment?.receiptNumber,
      ));
    } on AuthFailure {
      return const LockerBookingResult.failure(
          'Booking failed. Please try again.');
    }
  }

  // ── LOCKER ADMIN FLOWS ──────────────────────────────────────────
  // Admin counterparts to the student flows above. They replace the mock
  // DataService mutations and operate on Firestore so the admin panel reads
  // and writes the same data the student module uses. Each mirrors the
  // corresponding mock method's field changes and history entry, and returns
  // `false` (or `null`) on any failure.

  /// Approves a 'Waiting Approval' booking. This is the admin's first locker
  /// operation for a booking that went through the payment gateway.
  ///
  /// For **digital locks**: the locker is reserved and the digital code is
  /// activated immediately — the booking moves to 'Active' (no key pickup
  /// step) and the locker moves to 'Active'. The digital code is NEVER copied
  /// onto the locker document: `lockers/{lockerId}` is world-readable to
  /// signed-in users, so the owner-scoped booking stays the only place the
  /// code is stored.
  ///
  /// For **key locks**: the locker is reserved and the booking moves to
  /// 'Pending Pickup' — the admin then generates the key collection QR as a
  /// separate step (the existing `generateKeyCollectionQR` flow). The locker
  /// moves to 'Pending Pickup' with renter fields populated.
  ///
  /// In both cases the audit-trail entry is appended atomically with the
  /// locker update. Returns `true` on success, `false` on failure or when the
  /// booking is not in 'Waiting Approval' state.
  Future<bool> approveLockerBooking(
    LockerBooking booking,
    Locker locker,
  ) async {
    if (booking.status != 'Waiting Approval') return false;
    final isDigital = locker.lockType == 'digital';
    final history = LockerHistory(
      action: isDigital
          ? 'Booking approved - Digital locker activated'
          : 'Booking approved - Locker reserved for key pickup',
      staffId: 'ADMIN',
      timestamp: DateTime.now().toIso8601String(),
      reason: isDigital
          ? 'Booking approved. Digital code issued to student booking. Status: Active.'
          : 'Booking approved. Locker reserved. Student to collect key.',
    );
    try {
      if (isDigital) {
        // Digital: booking → Active, locker → Active. The unlock code stays
        // on the booking only (never written to the locker document).
        await _lockers.patchBooking(booking.id, {'status': 'Active'});
        final reserved = locker.copyWith(
          status: 'Active',
          studentId: booking.studentId,
          startDate: booking.startDate,
          endDate: booking.endDate,
          daysLeft: booking.daysLeft,
        );
        await _lockers.reserveLockerForBooking(reserved, history);
      } else {
        // Key: booking → Pending Pickup, locker → Pending Pickup.
        // The admin will generate the collection QR next.
        await _lockers.patchBooking(booking.id, {'status': 'Pending Pickup'});
        final reserved = locker.copyWith(
          status: 'Pending Pickup',
          studentId: booking.studentId,
          startDate: booking.startDate,
          endDate: booking.endDate,
          daysLeft: booking.daysLeft,
        );
        await _lockers.reserveLockerForBooking(reserved, history);
      }
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Rejects a 'Waiting Approval' booking. The booking moves to 'Rejected'
  /// (terminal) and the linked payment moves to 'Refund Pending'. The locker
  /// is NOT touched (it was never reserved). Returns `true` on success,
  /// `false` on failure or when the booking is not in 'Waiting Approval'
  /// state.
  Future<bool> rejectLockerBooking(
    LockerBooking booking, {
    String? reason,
  }) async {
    if (booking.status != 'Waiting Approval') return false;
    try {
      await _lockers.patchBooking(booking.id, {
        'status': 'Rejected',
      });
      await _lockers.addLockerHistory(
        booking.lockerId,
        LockerHistory(
          action: 'Booking rejected',
          staffId: 'ADMIN',
          timestamp: DateTime.now().toIso8601String(),
          reason: reason ?? 'Booking rejected by admin. Refund pending.',
        ),
      );
      // Mark the linked payment as refund pending (best-effort).
      if (booking.paymentId != null && booking.paymentId!.isNotEmpty) {
        try {
          await _payments.updatePaymentStatus(
              booking.paymentId!, 'Refund Pending');
        } on AuthFailure {
          // Non-fatal: the booking is rejected; the payment status update is
          // cosmetic and can be reconciled later.
        }
      }
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Generates the one-time key-collection QR for a booking and stamps it on
  /// the booking document. Returns the code, or `null` on failure.
  ///
  /// This is the FIRST admin-controlled locker operation for a booking. The
  /// student created only the `lockerBookings` document (students may never
  /// write `lockers` or `lockers/{id}/history`), so the locker is still
  /// `Available` until this runs. Here the admin generates the QR, reserves
  /// the locker (`Pending Pickup`, renter fields populated) and appends the
  /// audit-trail entry. The booking patch and the locker reservation are both
  /// admin-only writes; the locker update + history entry go through one
  /// atomic batch. No digital code is ever written to the locker document.
  ///
  /// Regeneration is allowed only while the key has not been collected; once
  /// the QR has been scanned (`keyCollected`) the request is refused so a used
  /// QR is never overwritten. Re-reserving an already-reserved locker is a
  /// harmless idempotent update (same field values), so regeneration is safe.
  Future<String?> generateKeyCollectionQR(
    LockerBooking booking,
    Locker locker,
  ) async {
    if (booking.keyCollected) return null;
    final code =
        'KEY-COL-${booking.id}-${Random().nextInt(999999).toString().padLeft(6, '0')}';
    final history = LockerHistory(
      action: 'Key collection QR generated',
      staffId: 'ADMIN',
      timestamp: DateTime.now().toIso8601String(),
      reason: 'QR code ready for student to scan. Locker reserved.',
    );
    try {
      // Stamp the QR onto the booking (admin may update any booking).
      await _lockers.patchBooking(booking.id, {'keyCollectionQR': code});
      // Reserve the locker + audit entry atomically. The booking's dates and
      // renter (set at booking time) are the source of truth. The digital
      // code is never copied onto the locker — it stays on the booking.
      final reserved = locker.copyWith(
        status: 'Pending Pickup',
        studentId: booking.studentId,
        startDate: booking.startDate,
        endDate: booking.endDate,
        daysLeft: booking.daysLeft,
      );
      await _lockers.reserveLockerForBooking(reserved, history);
      return code;
    } on AuthFailure {
      return null;
    }
  }

  /// Confirms a digital-lock booking: the admin's first (and only) locker
  /// operation for a digital rental. Digital locks have no physical key and
  /// therefore no collection-QR step, so this action reserves the locker
  /// (`Pending Pickup`, renter fields populated) and appends the audit-trail
  /// entry — all admin-only writes in one atomic batch.
  ///
  /// The digital code was generated at booking time and stored on the
  /// owner-scoped booking; it is deliberately NOT copied onto the locker
  /// document, which any signed-in user can read. This step only makes the
  /// reservation visible on the locker and the inventory counts. Returns
  /// `true` on success, `false` on failure.
  Future<bool> confirmDigitalLockerBooking(
    LockerBooking booking,
    Locker locker,
  ) async {
    final history = LockerHistory(
      action: 'Digital booking confirmed',
      staffId: 'ADMIN',
      timestamp: DateTime.now().toIso8601String(),
      reason: 'Locker reserved. Digital code issued to student booking.',
    );
    try {
      final reserved = locker.copyWith(
        status: 'Pending Pickup',
        studentId: booking.studentId,
        startDate: booking.startDate,
        endDate: booking.endDate,
        daysLeft: booking.daysLeft,
      );
      await _lockers.reserveLockerForBooking(reserved, history);
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Generates (or regenerates) the one-time key-return QR for a booking.
  ///
  /// Valid while the release is in 'Requested' or 'Pending Return' and the key
  /// has not yet been returned. Each call stamps a brand-new code onto the
  /// booking, overwriting `keyReturnQR` so any previously issued code
  /// immediately becomes invalid (the student scan guard compares against the
  /// current stored code). First generation moves releaseStatus from
  /// 'Requested' to 'Pending Return'; regeneration keeps it at
  /// 'Pending Return'. Returns the new code, or `null` on failure / when the
  /// key has already been returned (a used QR is never overwritten).
  Future<String?> generateKeyReturnQR(LockerBooking booking) async {
    if (booking.keyReturned) return null;
    if (booking.releaseStatus != 'Requested' &&
        booking.releaseStatus != 'Approved' &&
        booking.releaseStatus != 'Pending Return') {
      return null;
    }
    final isRegeneration = booking.keyReturnQR != null;
    final code =
        'KEY-RET-${booking.id}-${Random().nextInt(999999).toString().padLeft(6, '0')}';
    try {
      await _lockers.patchBooking(booking.id, {
        'keyReturnQR': code,
        'keyReturned': false,
        'releaseStatus': 'Pending Return',
      });
      await _lockers.addLockerHistory(
        booking.lockerId,
        LockerHistory(
          action: isRegeneration
              ? 'Return QR regenerated'
              : 'Return QR generated',
          staffId: 'ADMIN',
          timestamp: DateTime.now().toIso8601String(),
          reason: isRegeneration
              ? 'New return QR generated. Previous QR invalidated.'
              : 'QR code ready for student to scan',
        ),
      );
      // Notify the student that the return QR is ready.
      if (booking.studentId != null && booking.studentId!.isNotEmpty) {
        await _sendLockerNotification(
          studentId: booking.studentId!,
          lockerId: booking.lockerId,
          title: 'Return QR Generated',
          body: 'Your key return QR for locker ${booking.lockerId} is ready. '
              'Please scan it in My Locker after handing over your key at the admin office.',
          type: 'return_qr',
        );
      }
      return code;
    } on AuthFailure {
      return null;
    }
  }

  /// Approves a release **request** — the intermediate step for KEY lockers.
  ///
  /// For key lockers the release flow is: Requested → Approved → (generate
  /// return QR) → Pending Return → (student scans) → Returned → (admin
  /// completes) → Completed. This method moves releaseStatus from 'Requested'
  /// to 'Approved', records the history entry, and notifies the student. The
  /// admin then generates the return QR as a separate step.
  ///
  /// For digital lockers this intermediate step is NOT needed — the admin
  /// goes straight to [approveLockerRelease] which completes the release.
  /// Returns `false` when the guard fails or on any write failure.
  Future<bool> approveLockerReleaseRequest(Locker locker, LockerBooking booking) async {
    if (booking.releaseStatus != 'Requested') return false;
    try {
      await _lockers.patchBooking(booking.id, {
        'releaseStatus': 'Approved',
      });
      await _lockers.addLockerHistory(
        booking.lockerId,
        LockerHistory(
          action: 'Release request approved',
          staffId: 'ADMIN',
          timestamp: DateTime.now().toIso8601String(),
          reason: 'Admin approved the release request. Return QR can now be generated.',
        ),
      );
      // Notify the student that their release request was approved.
      if (booking.studentId != null && booking.studentId!.isNotEmpty) {
        await _sendLockerNotification(
          studentId: booking.studentId!,
          lockerId: booking.lockerId,
          title: 'Release Approved',
          body: 'Your release request for locker ${booking.lockerId} has been approved. '
              'Please visit the admin office to return your key and scan the return QR.',
          type: 'release',
        );
      }
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Approves a release: frees the locker (deposit refunded), completes the
  /// booking, and writes the history entry. This is the FINAL step — for key
  /// locks it requires the key to have been returned (releaseStatus ==
  /// 'Returned'); for digital locks it can be done from 'Requested'. Returns
  /// `false` when the guard fails or on any write failure.
  ///
  /// The booking is NEVER deleted — it transitions to its terminal `Completed`
  /// state and is preserved permanently. The booking update, locker update and
  /// history entry are committed atomically in a single [WriteBatch], so the
  /// approval either succeeds completely or fails completely (no partial
  /// update where the locker is freed but the booking is left active).
  Future<bool> approveLockerRelease(Locker locker, LockerBooking booking) async {
    final requiresKeyReturn = locker.lockType == 'key';
    if (requiresKeyReturn &&
        (booking.releaseStatus != 'Returned' || !booking.keyReturned)) {
      return false;
    }
    if (!requiresKeyReturn &&
        booking.releaseStatus != 'Requested' &&
        booking.releaseStatus != 'Returned') {
      return false;
    }
    final freedLocker = locker.copyWith(
      status: 'Available',
      studentId: null,
      startDate: null,
      endDate: null,
      daysLeft: null,
      depositRefunded: true,
    );
    final bookingFields = <String, dynamic>{
      'status': 'Completed',
      'releaseStatus': 'Completed',
      'depositRefunded': true,
      'completedDate': FieldValue.serverTimestamp(),
    };
    // Digital releases get their own audit trail ('Digital release approved',
    // 'Locker code revoked', 'Deposit refunded'), because revoking the access
    // code is the material event and needs to be visible on its own line.
    // The key-locker path is left exactly as it was.
    final isDigital = locker.lockType == 'digital';
    final history = LockerHistory(
      action: isDigital
          ? 'Digital release approved'
          : 'Locker released - Booking completed - Deposit refunded',
      staffId: 'ADMIN',
      timestamp: DateTime.now().toIso8601String(),
      reason: isDigital
          ? 'Admin approved the digital locker release. No key return required.'
          : 'Release approved. Deposit: RM${booking.deposit.toStringAsFixed(0)} refunded.',
    );
    try {
      await _lockers.completeBookingWithLocker(
        booking.id,
        bookingFields,
        freedLocker,
        history,
      );
      if (isDigital) {
        await _lockers.addLockerHistory(
          locker.id,
          LockerHistory(
            action: 'Locker code revoked',
            staffId: 'ADMIN',
            timestamp: DateTime.now().toIso8601String(),
            reason: 'Digital access code invalidated on release approval.',
          ),
        );
        await _lockers.addLockerHistory(
          locker.id,
          LockerHistory(
            action: 'Deposit refunded',
            staffId: 'ADMIN',
            timestamp: DateTime.now().toIso8601String(),
            reason: 'Deposit: RM${booking.deposit.toStringAsFixed(0)} refunded.',
          ),
        );
      }

      // Notify the student: deposit refunded + agreement completed.
      if (booking.studentId != null && booking.studentId!.isNotEmpty) {
        await _sendLockerNotification(
          studentId: booking.studentId!,
          lockerId: booking.lockerId,
          title: 'Deposit Refunded',
          body: 'Your security deposit of RM${booking.deposit.toStringAsFixed(0)} '
              'for locker ${booking.lockerId} has been refunded.',
          type: 'deposit_refunded',
        );
        await _sendLockerNotification(
          studentId: booking.studentId!,
          lockerId: booking.lockerId,
          title: 'Locker Agreement Completed',
          body: 'Your locker agreement for ${booking.lockerId} has been completed. '
              'Thank you for using Campus Connect locker services.',
          type: 'completed',
        );
      }
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Terminates a locker agreement: frees the locker, completes any booking,
  /// and forfeits the deposit. The [reason] is recorded in the locker history
  /// and included in the student notification. Returns `false` on any write
  /// failure.
  ///
  /// The booking is never deleted — it is moved to `Completed` atomically with
  /// the locker update and history entry in a single [WriteBatch].
  Future<bool> terminateLocker(Locker locker, LockerBooking? booking, {String? reason}) async {
    final reasonText = reason ?? 'Admin terminated locker agreement. Deposit forfeited.';
    final freedLocker = locker.copyWith(
      status: 'Available',
      studentId: null,
      startDate: null,
      endDate: null,
      daysLeft: null,
      depositRefunded: false,
    );
    final history = LockerHistory(
      action: 'Agreement terminated',
      staffId: 'ADMIN',
      timestamp: DateTime.now().toIso8601String(),
      reason: reasonText,
    );
    try {
      if (booking != null) {
        await _lockers.completeBookingWithLocker(
          booking.id,
          <String, dynamic>{
            'status': 'Completed',
            'releaseStatus': 'Completed',
            'depositRefunded': false,
            'completedDate': FieldValue.serverTimestamp(),
          },
          freedLocker,
          history,
        );
      } else {
        await _lockers.updateLocker(freedLocker);
        await _lockers.addLockerHistory(locker.id, history);
      }
      // Notify the student about the termination.
      final studentId = booking?.studentId ?? locker.studentId;
      if (studentId != null && studentId.isNotEmpty) {
        await _sendLockerNotification(
          studentId: studentId,
          lockerId: locker.id,
          title: 'Locker Agreement Terminated',
          body: 'Your locker agreement for ${locker.id} has been terminated by the administrator. '
              'Reason: $reasonText. Your deposit has been forfeited. '
              'If you have questions, please contact the admin office.',
          type: 'termination',
        );
      }
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Blocks a locker (maintenance/issues), completing any booking. The
  /// [reason] is recorded in the locker history and included in the student
  /// notification if the locker was occupied. Returns `false` on any write
  /// failure.
  ///
  /// The booking is never deleted — it is moved to `Completed` atomically with
  /// the locker update and history entry in a single [WriteBatch].
  Future<bool> blockLocker(Locker locker, LockerBooking? booking, {String? reason}) async {
    final reasonText = reason ?? 'Admin blocked locker';
    final blockedLocker = locker.copyWith(
      status: 'Blocked',
      studentId: null,
      startDate: null,
      endDate: null,
      daysLeft: null,
    );
    final history = LockerHistory(
      action: 'Locker blocked',
      staffId: 'ADMIN',
      timestamp: DateTime.now().toIso8601String(),
      reason: reasonText,
    );
    try {
      if (booking != null) {
        await _lockers.completeBookingWithLocker(
          booking.id,
          <String, dynamic>{
            'status': 'Completed',
            'releaseStatus': 'Completed',
            'completedDate': FieldValue.serverTimestamp(),
          },
          blockedLocker,
          history,
        );
      } else {
        await _lockers.updateLocker(blockedLocker);
        await _lockers.addLockerHistory(locker.id, history);
      }
      // Notify the student if the locker was occupied.
      final studentId = booking?.studentId ?? locker.studentId;
      if (studentId != null && studentId.isNotEmpty) {
        await _sendLockerNotification(
          studentId: studentId,
          lockerId: locker.id,
          title: 'Locker Blocked',
          body: 'Your locker ${locker.id} has been blocked by the administrator. '
              'Reason: $reasonText. Please contact the admin office for more information.',
          type: 'block',
        );
      }
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Unblocks a previously blocked locker, making it available again. Unlike
  /// [releaseLockerAdmin], this does NOT complete any booking — the locker
  /// was already freed when it was blocked. It simply flips the status from
  /// 'Blocked' to 'Available' and records the reason in history.
  ///
  /// A notification is sent to the student ONLY if the locker still has an
  /// active studentId (edge case where the locker was blocked without
  /// completing the booking). Returns `false` on any write failure or if the
  /// locker is not currently blocked.
  Future<bool> unblockLocker(Locker locker, {String? reason}) async {
    // Validation guard: can only unblock a blocked locker.
    if (locker.status != 'Blocked') {
      return false;
    }
    final reasonText = reason ?? 'Admin unblocked locker. Made available.';
    final unblockedLocker = locker.copyWith(
      status: 'Available',
    );
    final history = LockerHistory(
      action: 'Locker unblocked',
      staffId: 'ADMIN',
      timestamp: DateTime.now().toIso8601String(),
      reason: reasonText,
    );
    try {
      await _lockers.updateLocker(unblockedLocker);
      await _lockers.addLockerHistory(locker.id, history);
      // Notify the student if the locker still has a tenant (edge case).
      final studentId = locker.studentId;
      if (studentId != null && studentId.isNotEmpty) {
        await _sendLockerNotification(
          studentId: studentId,
          lockerId: locker.id,
          title: 'Locker Available Again',
          body: 'Your locker ${locker.id} has been reopened and is available again. '
              'Reason: $reasonText. You may resume using it.',
          type: 'unblock',
        );
      }
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Force-releases a blocked or occupied locker back to available, completing
  /// any booking. The [reason] is recorded in the locker history and included
  /// in the student notification. Returns `false` on any write failure.
  ///
  /// The booking is never deleted — it is moved to `Completed` atomically with
  /// the locker update and history entry in a single [WriteBatch].
  Future<bool> releaseLockerAdmin(Locker locker, LockerBooking? booking, {String? reason}) async {
    final reasonText = reason ?? 'Admin force-released locker. Made available.';
    final freedLocker = locker.copyWith(
      status: 'Available',
      studentId: null,
      startDate: null,
      endDate: null,
      daysLeft: null,
    );
    final history = LockerHistory(
      action: 'Locker force-released',
      staffId: 'ADMIN',
      timestamp: DateTime.now().toIso8601String(),
      reason: reasonText,
    );
    try {
      if (booking != null) {
        await _lockers.completeBookingWithLocker(
          booking.id,
          <String, dynamic>{
            'status': 'Completed',
            'releaseStatus': 'Completed',
            'completedDate': FieldValue.serverTimestamp(),
          },
          freedLocker,
          history,
        );
      } else {
        await _lockers.updateLocker(freedLocker);
        await _lockers.addLockerHistory(locker.id, history);
      }
      // Notify the student if the locker was occupied.
      final studentId = booking?.studentId ?? locker.studentId;
      if (studentId != null && studentId.isNotEmpty) {
        await _sendLockerNotification(
          studentId: studentId,
          lockerId: locker.id,
          title: 'Locker Force-Released',
          body: 'Your locker ${locker.id} has been force-released by the administrator. '
              'Reason: $reasonText. Please contact the admin office for more information.',
          type: 'force_release',
        );
      }
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Sends a notice to a locker's tenant by logging it to the locker's
  /// history. Returns `false` on any write failure.
  Future<bool> sendLockerNotice(Locker locker, String message) async {
    try {
      await _lockers.addLockerHistory(
        locker.id,
        LockerHistory(
          action: 'Notice sent to student',
          staffId: 'ADMIN',
          timestamp: DateTime.now().toIso8601String(),
          reason: message,
        ),
      );
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

  /// Changes the signed-in student's password. The returned record carries a
  /// user-safe message; `success && message == null` is not a state — on
  /// success `message` confirms the change.
  Future<({bool success, String? message})> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!_servicesReady) {
      return (success: false, message: 'Please sign in again to continue.');
    }
    try {
      await _auth.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return (success: true, message: 'Password changed successfully.');
    } on AuthFailure catch (failure) {
      return (success: false, message: failure.message);
    }
  }

  /// Persists the signed-in student's notification toggles and refreshes the
  /// cached profile so the Profile screen reflects the saved state.
  Future<bool> updateNotificationPrefs(Map<String, bool> prefs) async {
    final current = _profile;
    if (current == null || !_servicesReady) return false;
    try {
      await _users.updateNotificationPrefs(uid: current.uid, prefs: prefs);
      _profile = current.copyWith(notificationPrefs: prefs);
      notifyListeners();
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Persists the signed-in student's preferred language and refreshes the
  /// cached profile.
  Future<bool> updatePreferredLanguage(String language) async {
    final current = _profile;
    if (current == null || !_servicesReady) return false;
    try {
      await _users.updatePreferredLanguage(uid: current.uid, language: language);
      _profile = current.copyWith(preferredLanguage: language);
      notifyListeners();
      return true;
    } on AuthFailure {
      return false;
    }
  }

  // ── EVENTS ──────────────────────────────────────────────────────
  //
  // The Firestore-backed replacement for the Event half of the mock
  // DataService. Same architecture as the Lockers section above: reads are
  // streams straight from the service, writes are futures that return a plain
  // bool or model so no Firebase type — and no AuthFailure — reaches a screen.
  //
  // The screens still call DataService today; Phase 2C points them here. Until
  // then this section is the seam, not yet the path.

  /// Published events, for the student browse screen.
  Stream<List<Event>> watchPublishedEvents() =>
      _eventsService.watchPublishedEvents();

  /// Every event the signed-in student submitted, in any status — My Events.
  Stream<List<Event>> watchMyEvents() =>
      _eventsService.watchEventsForHost(userId ?? '');

  /// The admin review queue: submissions not yet published.
  Stream<List<Event>> watchPendingEvents() => _eventsService.watchPendingEvents();

  /// Every event, for the admin dashboard.
  Stream<List<Event>> watchAllEvents() => _eventsService.watchEvents();

  /// A single event, for the detail and manage screens.
  Stream<Event?> watchEvent(String id) => _eventsService.watchEvent(id);

  /// Every joining request for one event — the host's participant list.
  Stream<List<EventJoining>> watchEventJoinings(String eventId) =>
      _eventsService.watchJoiningsForEvent(eventId);

  /// The signed-in student's own registrations, across every event.
  Stream<List<EventJoining>> watchMyJoinings() =>
      _eventsService.watchMyJoinings(userId ?? '');

  /// The crew assigned to one event.
  Stream<List<EventRole>> watchEventRoles(String eventId) =>
      _eventsService.watchRolesForEvent(eventId);

  /// The signed-in student's registration for one event, or `null` if they
  /// have not joined. Backs the "Join" vs "View Ticket" decision.
  Future<EventJoining?> joiningFor(String eventId) async {
    try {
      return await _eventsService.getJoiningForStudent(eventId, userId ?? '');
    } on AuthFailure {
      return null;
    }
  }

  /// Submits a new event in the signed-in student's name. Returns the created
  /// event, or `null` if the write failed.
  ///
  /// A submission is always born 'Pending' with an empty roster — the security
  /// rules reject anything else, so the status is set here rather than trusted
  /// from the caller.
  Future<Event?> createEvent(Event draft) async {
    try {
      return await _eventsService.createEvent(draft.copyWith(
        status: 'Pending',
        hostStudentId: draft.hostStudentId ?? userId,
        submittedDate: draft.submittedDate ?? _today(),
        attendeeIds: const <String>[],
        pendingJoiningIds: const <String>[],
      ));
    } on AuthFailure {
      return null;
    }
  }

  /// Saves an edited event.
  Future<bool> updateEvent(Event event) => _eventWrite(
        () => _eventsService.updateEvent(event),
      );

  /// Withdraws a submission that has not been published.
  Future<bool> deleteEvent(String id) =>
      _eventWrite(() => _eventsService.deleteEvent(id));

  /// Resubmits a revised event, moving it back into the review queue and
  /// counting the revision — the mock's `resubmitEvent`, unchanged.
  Future<bool> resubmitEvent(Event event) => _eventWrite(
        () => _eventsService.updateEvent(event.copyWith(
          status: 'Pending',
          revisionCount: event.revisionCount + 1,
          submittedDate: _today(),
        )),
      );

  Future<bool> approveEvent(String id) =>
      _eventWrite(() => _eventsService.approveEvent(id));

  Future<bool> rejectEvent(String id, String reason) =>
      _eventWrite(() => _eventsService.rejectEvent(id, reason));

  Future<bool> setEventUnderReview(String id) =>
      _eventWrite(() => _eventsService.setEventUnderReview(id));

  Future<bool> requestEventRevision(String id, String notes) =>
      _eventWrite(() => _eventsService.requestEventRevision(id, notes));

  Future<bool> markEventCompleted(String id) =>
      _eventWrite(() => _eventsService.markEventCompleted(id));

  /// Posts a message to the admin ↔ host thread on an event.
  Future<bool> addEventMessage(String eventId, String message,
      {String? attachmentName}) {
    return _eventWrite(() => _eventsService.addEventMessage(
          eventId,
          EventMessage(
            id: 'MSG-${DateTime.now().millisecondsSinceEpoch}',
            senderId: userId ?? '',
            senderRole: isAdmin ? 'admin' : 'student',
            message: message,
            timestamp: DateTime.now().toIso8601String(),
            attachmentName: attachmentName,
          ),
        ));
  }

  /// Joins an event in the signed-in student's name.
  ///
  /// An open, free event is approved on the spot and gets its ticket
  /// immediately; anything gated (club membership or payment) starts 'Pending'
  /// and waits for the host. This is the mock's `requestJoinEvent` /
  /// `quickJoinEvent` split, preserved exactly — the difference was never a
  /// separate code path, only a different starting state.
  ///
  /// Returns `null` if the student is not signed in, has already registered
  /// for this event, or the write failed. The joining creation and the event
  /// roster update are committed in a single [WriteBatch] so they can never
  /// disagree.
  Future<EventJoining?> joinEvent(
    Event event, {
    required String name,
    required String courseName,
    String? clubId,
  }) async {
    final studentId = userId;
    if (studentId == null) return null;

    // ── Duplicate prevention ──────────────────────────────────────
    // A student may only have one joining per event. If they already have a
    // Pending, Approved or Rejected registration, return null so the caller
    // can show "already registered" instead of creating a second document.
    final existing = await joiningFor(event.id);
    if (existing != null) return null;

    // ── Capacity guard ───────────────────────────────────────────
    // If the event has a participant cap and is already full, refuse the join
    // before touching Firestore. The service layer re-checks on the write
    // itself, but this early bail lets the UI show "Event Full" without a
    // round-trip.
    if (event.isFull) return null;

    final gated = event.isPaid || event.clubIdRequired || event.isPrivate;
    try {
      return await _eventsService.createJoiningAndRegister(
        EventJoining(
          id: '',
          eventId: event.id,
          studentId: studentId,
          name: name,
          courseName: courseName,
          clubId: clubId,
          status: gated ? 'Pending' : 'Approved',
          paymentStatus: event.isPaid ? 'Pending' : null,
          qrTicketCode: gated ? null : _ticketCode(),
          joinedDate: _today(),
        ),
        autoApproved: !gated,
      );
    } on AuthFailure {
      return null;
    }
  }

  /// Marks a paid registration as settled once the demo gateway succeeds.
  Future<bool> completeJoiningPayment(String joiningId) => _eventWrite(
        () => _eventsService.patchJoining(joiningId, {'paymentStatus': 'Completed'}),
      );

  /// Host decision: admit the student and issue their ticket. The joining and
  /// the event's roster move together in one batch.
  ///
  /// For paid events the joining's `paymentStatus` must be `'Completed'`
  /// before the host may approve — a participant who has not paid cannot be
  /// admitted. Returns [EventActionResult.failure] with the message
  /// "Payment has not been completed." when that rule is violated.
  Future<EventActionResult> approveJoining(EventJoining joining) async {
    // ── Payment verification ─────────────────────────────────────
    // Only a paid event can have an unpaid joining. A free event has a `null`
    // paymentStatus, so this guard is a no-op for the free workflow.
    if (joining.paymentStatus != null &&
        joining.paymentStatus != 'Completed') {
      return const EventActionResult.failure(
          'Payment has not been completed.');
    }

    final ok = await _eventWrite(
      () => _eventsService.decideJoining(
        joining.id,
        joining.eventId,
        {'status': 'Approved', 'qrTicketCode': joining.qrTicketCode ?? _ticketCode()},
        approved: true,
        studentId: joining.studentId,
      ),
    );
    return ok
        ? const EventActionResult.success()
        : const EventActionResult.failure('Failed to approve participant.');
  }

  /// Host decision: turn the student away. No ticket is issued.
  Future<bool> rejectJoining(EventJoining joining) => _eventWrite(
        () => _eventsService.decideJoining(
          joining.id,
          joining.eventId,
          {'status': 'Rejected'},
          approved: false,
          studentId: joining.studentId,
        ),
      );

  /// Flips attendance for one participant — the manual override on the
  /// participant list.
  Future<bool> setAttendance(String joiningId, bool attended) => _eventWrite(
        () => _eventsService.patchJoining(joiningId, {'hasAttended': attended}),
      );

  /// Scans a ticket: marks the holder present and reports whether the code was
  /// recognised. An unknown code is a failure with "Invalid or unapproved QR
  /// code.", and a code that has already been scanned is a failure with
  /// "Attendance has already been recorded." — the attendance is never written
  /// twice.
  Future<EventActionResult> verifyTicket(
      String eventId, String ticketCode) async {
    try {
      final joining =
          await _eventsService.findJoiningByTicketCode(eventId, ticketCode);
      if (joining == null) {
        return const EventActionResult.failure(
            'Invalid or unapproved QR code.');
      }
      // ── Duplicate scan guard ───────────────────────────────────
      // If attendance was already recorded, do NOT write again. The host sees
      // a specific message instead of a silent second check-in.
      if (joining.hasAttended) {
        return const EventActionResult.failure(
            'Attendance has already been recorded.');
      }
      await _eventsService.patchJoining(joining.id, {'hasAttended': true});
      notifyListeners();
      return const EventActionResult.success('Entry verified! Participant checked in.');
    } on AuthFailure {
      return const EventActionResult.failure(
          'Failed to verify ticket. Please try again.');
    }
  }

  /// Assigns a crew role on an event.
  ///
  /// Only a student with an **Approved** joining for the event may receive a
  /// role. Returns [EventActionResult.failure] with "Only approved participants
  /// can be assigned event roles." when the student is not an approved
  /// participant.
  Future<EventActionResult> assignEventRole({
    required String eventId,
    required String studentId,
    required String studentName,
    required String role,
    List<String> permissions = const <String>[],
  }) async {
    // ── Participation validation ────────────────────────────────
    // The student must have an Approved joining for this event before they can
    // be assigned a crew role.
    final joining = await _eventsService.getJoiningForStudent(eventId, studentId);
    if (joining == null || joining.status != 'Approved') {
      return const EventActionResult.failure(
          'Only approved participants can be assigned event roles.');
    }

    final ok = await _eventWrite(() => _eventsService.assignRole(EventRole(
          id: '',
          eventId: eventId,
          studentId: studentId,
          studentName: studentName,
          role: role,
          permissions: permissions,
        )));
    return ok
        ? const EventActionResult.success()
        : const EventActionResult.failure('Failed to assign role.');
  }

  /// Revokes a crew role.
  Future<bool> removeEventRole(String roleId) =>
      _eventWrite(() => _eventsService.removeRole(roleId));

  // ── COVER IMAGE ─────────────────────────────────────────────────

  /// Opens the device gallery and returns the selected image file,
  /// or `null` if the user cancels.
  Future<File?> pickEventCoverImage() => _cloudinary.pickImageFromGallery();

  /// Uploads a cover image to Cloudinary and returns the result
  /// containing the secure URL and public ID.
  ///
  /// Throws [CloudinaryException] on failure — callers should catch it
  /// and show an appropriate message.
  Future<CloudinaryUploadResult> uploadEventCoverToCloudinary(
    File imageFile, {
    void Function(int sent, int total)? onProgress,
  }) =>
      _cloudinary.uploadImage(imageFile, onProgress: onProgress);

  /// Best-effort removal of a cover image from Cloudinary.
  Future<void> deleteEventCoverImage(String publicId) async {
    await _cloudinary.deleteImage(publicId);
  }

  /// Every event mutation ends the same way: the write succeeds, or it fails
  /// with an [AuthFailure] the screen has no use for. Collapsing that into a
  /// bool here keeps the try/catch out of twelve call sites.
  Future<bool> _eventWrite(Future<void> Function() write) async {
    try {
      await write();
      notifyListeners();
      return true;
    } on AuthFailure {
      return false;
    }
  }

  // ── ELECTIONS ────────────────────────────────────────────────────
  //
  // Same shape as the Events section above: reads are streams straight from
  // the service, writes are futures that return a plain bool or model so no
  // Firebase type — and no AuthFailure — reaches a screen.

  /// Published candidates, for the student elections info screen.
  Stream<List<Candidate>> watchPublishedCandidates() =>
      _electionsService.watchPublishedCandidates();

  /// Every candidate, for the admin dashboard.
  Stream<List<Candidate>> watchAllCandidates() =>
      _electionsService.watchAllCandidates();

  /// A single candidate, for the admin detail screen.
  Stream<Candidate?> watchCandidate(String id) =>
      _electionsService.watchCandidate(id);

  /// The single published election configuration document, for the student
  /// elections info screen. Emits `null` when nothing is published yet.
  Stream<ElectionMeta?> watchPublishedElectionMeta() =>
      _electionsService.watchPublishedElectionMeta();

  /// The election configuration document regardless of status, for the admin
  /// manage screen.
  Stream<ElectionMeta?> watchElectionMeta(String id) =>
      _electionsService.watchElectionMeta(id);

  /// Every election configuration document, for the admin management and
  /// archive screens.
  Stream<List<ElectionMeta>> watchAllElectionMeta() =>
      _electionsService.watchAllElectionMeta();

  /// Creates a new candidate. Admin-only — enforced by the security rules.
  Future<bool> createCandidate(Candidate candidate) =>
      _electionWrite(() => _electionsService.createCandidate(candidate));

  /// Overwrites an existing candidate. Admin-only.
  Future<bool> updateCandidate(Candidate candidate) =>
      _electionWrite(() => _electionsService.updateCandidate(candidate));

  /// Publishes a candidate by moving its status to 'Published'.
  Future<bool> publishCandidate(String id) =>
      _electionWrite(() => _electionsService.patchCandidate(id, {'status': 'Published'}));

  /// Unpublishes a candidate by moving its status back to 'Pending'.
  Future<bool> unpublishCandidate(String id) =>
      _electionWrite(() => _electionsService.patchCandidate(id, {'status': 'Pending'}));

  /// Permanently removes a candidate. Admin-only.
  Future<bool> deleteCandidate(String id) =>
      _electionWrite(() => _electionsService.deleteCandidate(id));

  /// Creates a new election configuration document. Admin-only.
  Future<bool> createElectionMeta(ElectionMeta meta) =>
      _electionWrite(() => _electionsService.createElectionMeta(meta));

  /// Overwrites the election configuration. Admin-only.
  Future<bool> updateElectionMeta(ElectionMeta meta) =>
      _electionWrite(() => _electionsService.updateElectionMeta(meta));

  /// Publishes the election configuration by moving its status to
  /// 'Published'.
  Future<bool> publishElectionMeta(String id) =>
      _electionWrite(() => _electionsService.patchElectionMeta(id, {'status': 'Published'}));

  /// Moves an election into the Admin Archive. The status it held is
  /// preserved so it can be restored, and the archiving admin is taken from
  /// the signed-in profile so no caller passes identity around.
  Future<bool> archiveElectionMeta(String id, {required String previousStatus}) =>
      _electionWrite(() => _electionsService.archiveElectionMeta(
            id,
            previousStatus: previousStatus,
            archivedBy: _profile?.studentId ?? 'admin',
            archivedAt: DateTime.now().toIso8601String(),
          ));

  /// Restores an archived election to its pre-archive status.
  Future<bool> restoreElectionMeta(String id, {required String previousStatus}) =>
      _electionWrite(() =>
          _electionsService.restoreElectionMeta(id, previousStatus: previousStatus));

  /// Unused by the UI: elections are archived, not deleted. The security
  /// rules deny hard deletes for `electionMeta`.
  Future<bool> deleteElectionMeta(String id) =>
      _electionWrite(() => _electionsService.deleteElectionMeta(id));

  /// Every election mutation ends the same way as an event mutation: the
  /// write succeeds, or it fails with an [AuthFailure] the screen has no use
  /// for. Collapsing that into a bool here keeps the try/catch out of every
  /// call site.
  Future<bool> _electionWrite(Future<void> Function() write) async {
    try {
      await write();
      notifyListeners();
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Tickets are short, human-readable and unique enough for a campus event.
  static String _ticketCode() {
    final rand = Random();
    return 'TKT-${List.generate(6, (_) => rand.nextInt(10)).join()}';
  }

  static String _today() => DateTime.now().toIso8601String().split('T').first;

  static const AuthResult _unavailable =
      AuthResult.failure('Authentication is unavailable. Please restart the app.');

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
