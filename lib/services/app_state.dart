import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
import '../models/inventory_item.dart';
import '../models/item.dart';
import '../models/lf_match.dart';
import '../models/lf_notification.dart';
import '../models/locker.dart';
import '../models/locker_booking.dart';
import '../models/locker_history.dart';
import '../models/locker_issue.dart';
import '../models/locker_notification.dart';
import '../models/payment.dart';
import '../models/qr_transaction.dart';
import '../models/user_profile.dart';
import 'admin_service.dart';
import 'auth_service.dart';
import 'cloudinary_service.dart';
import 'election_service.dart';
import 'event_service.dart';
import 'issue_service.dart';
import 'lf_workflow_service.dart';
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
export '../models/inventory_item.dart' show InventoryItem, InventoryStatus;
export '../models/issue.dart' show Issue, IssueHistory;
export '../models/item.dart' show Item, ItemStatus, ItemType;
export '../models/lf_match.dart' show LfMatch, MatchStatus, MatchSource;
export '../models/lf_notification.dart' show LfNotification;
export '../models/locker.dart' show Locker;
export '../models/locker_booking.dart' show LockerBooking, LockerBookingResult;
export '../models/locker_history.dart' show LockerHistory;
export '../models/locker_issue.dart' show LockerIssue;
export '../models/locker_notification.dart' show LockerNotification;
export '../models/payment.dart' show Payment, PaymentResult;
export '../models/qr_transaction.dart' show QrTransaction, QrKind, QrStatus;
export '../models/user_profile.dart'
    show UserProfile, UserRole, AccountStatus, ProfileLoadStatus;
export 'cloudinary_service.dart'
    show CloudinaryUploadResult, CloudinaryException;
export 'lf_workflow_service.dart' show LfWorkflowService, QrScanOutcome;

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
  final LfWorkflowService _lfWorkflow;
  final IssueService _issues;
  final LockerService _lockers;
  final PaymentService _payments;
  final EventService _eventsService;
  final ElectionService _electionsService;
  final CloudinaryService _cloudinary;
  final CloudinaryService _lostFoundCloudinary;

  /// Fixed `closeReason` values written by the two authorized admin closure
  /// paths. Never sourced from client input — the Firestore rules accept only
  /// these two strings.
  static const String closeReasonStudentRequestApproved =
      'STUDENT_REQUEST_APPROVED';
  static const String closeReasonAdminResolved = 'ADMIN_RESOLVED';

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
    LfWorkflowService? lfWorkflowService,
    IssueService? issueService,
    LockerService? lockerService,
    PaymentService? paymentService,
    EventService? eventService,
    ElectionService? electionService,
    CloudinaryService? cloudinaryService,
    CloudinaryService? lostFoundCloudinaryService,
  })  : _auth = authService ?? AuthService(),
        _users = userService ?? UserService(),
        _admin = adminService ?? AdminService(),
        _lostFound = lostFoundService ?? LostFoundService(),
        _lfWorkflow = lfWorkflowService ?? LfWorkflowService(),
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
            ),
        _lostFoundCloudinary = lostFoundCloudinaryService ??
            CloudinaryService(
              cloudName: 'xijxwdly',
              uploadPreset: 'campus_connect_lost_found',
              folder: 'lost-found',
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
    state._profileStatus = profile == null ? status : ProfileLoadStatus.ready;
    return state;
  }

  bool get _servicesReady =>
      _auth.isAvailable && _users.isAvailable && _admin.isAvailable;

  // ── Session ───────────────────────────────────────────────────────
  /// True only when a Firebase user is signed in, their profile has loaded,
  /// and the account is approved.
  bool get isAuthenticated =>
      _firebaseUid != null && (_profile?.isActive ?? false);

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
        } on AuthFailure {/* clear local state regardless */}
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
  Future<AuthResult> loginUser(
      String id, String password, bool isAdminLogin) async {
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
        return const AuthResult.failure(
            'This Student ID is already registered.');
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
      return AuthResult.success(
          message: 'Password reset link sent to $authEmail');
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
  Stream<List<Item>> watchAdminLostReports() => _lostFound.watchAllLostItems();

  /// Live feed of every found report across all students, for the admin list
  /// screen. Same contract as [watchAdminLostReports] with `type` `found`.
  Stream<List<Item>> watchAdminFoundReports() =>
      _lostFound.watchAllFoundItems();

  /// Live feed of every lost AND found report across all students, for the
  /// admin dashboard's combined summary counts. One query instead of merging
  /// two streams — the dashboard splits the result into lost/found by
  /// [Item.isLost] / [Item.isFound] when it needs the breakdown.
  Stream<List<Item>> watchAdminAllReports() => _lostFound.watchAllItems();

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

  // ── LOST & FOUND — writes ────────────────────────────────────────

  /// Picks a single image from the gallery for a Lost & Found report.
  ///
  /// Returns `null` if the user cancels. Throws [CloudinaryException] on
  /// failure. Uses the dedicated L&F Cloudinary preset (`lost-found` folder).
  Future<File?> pickReportImageFromGallery() =>
      _lostFoundCloudinary.pickImageFromGallery();

  /// Picks a single image from the camera for a Lost & Found report.
  ///
  /// Returns `null` if the user cancels. Throws [CloudinaryException] on
  /// failure. Uses the dedicated L&F Cloudinary preset (`lost-found` folder).
  Future<File?> pickReportImageFromCamera() =>
      _lostFoundCloudinary.pickImageFromCamera();

  /// Uploads one or more report images to Cloudinary.
  ///
  /// Each image is uploaded sequentially (not in parallel) so the caller can
  /// show per-image progress. Returns the list of secure HTTPS URLs to store
  /// in `Item.imageUrls`. Throws [CloudinaryException] on the first failure;
  /// previously uploaded URLs are still available in the returned partial list
  /// if the caller catches the exception.
  Future<List<String>> uploadReportImages(
    List<File> images, {
    void Function(int done, int total)? onProgress,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < images.length; i++) {
      if (onProgress != null) onProgress(i, images.length);
      final result = await _lostFoundCloudinary.uploadImage(images[i]);
      urls.add(result.url);
    }
    if (onProgress != null) onProgress(images.length, images.length);
    return urls;
  }

  /// Creates a new report, uploading images first (if any).
  ///
  /// Both lost and found reports are born `Active` — the status is coerced
  /// here so no caller can create a report in the wrong state. A found report
  /// stays `Active` until the admin confirms the physical handover (moving it
  /// to `In Inventory`); the Firestore rules enforce the same birth status
  /// independently.
  ///
  /// `reportedByName` is captured here from the authenticated profile — never
  /// from form input — so a student cannot submit a false reporter name.
  ///
  /// Flow: validate → upload all images → write to Firestore. If any image
  /// upload fails, the report is NOT created — the caller receives the
  /// [CloudinaryException] and can retry or submit without photos. If the
  /// Firestore write fails after uploads succeed, the caller receives the
  /// [AuthFailure] and can retry the write (the Cloudinary assets are
  /// orphaned — see handoff orphan-handling section).
  Future<Item> createReport(Item item, {List<File>? images}) async {
    var report = Item(
      id: item.id,
      type: item.type,
      title: item.title,
      category: item.category,
      description: item.description,
      whereLost: item.whereLost,
      whenLost: item.whenLost,
      reportedByUid: item.reportedByUid,
      reportedByStudentId: item.reportedByStudentId,
      reportedByName: _profile?.fullName ?? '',
      imageUrls: item.imageUrls,
      status: ItemStatus.active,
      isDeleted: item.isDeleted,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    );
    if (images != null && images.isNotEmpty) {
      final urls = await uploadReportImages(images);
      report = report.copyWith(imageUrls: urls);
    }
    final created = await _lostFound.createItem(report);

    // Trigger AI matching for new lost reports (fire-and-forget).
    // Found reports do NOT trigger AI here — Flow B requires the separate
    // handover process (generate QR → scan → inventory item created).
    debugPrint('[AI MATCH DEBUG] createReport finished id=${created.id} '
        'type=${created.type.wireValue} isLost=${created.isLost} '
        'cat=${created.category} images=${created.imageUrls.length} '
        'workerBase=$_aiWorkerBase');
    if (created.isLost) {
      runAiMatchingForLostReport(created).then((count) {
        debugPrint(
            '[AI MATCH] LOST→INVENTORY anchor=${created.id} matched=$count '
            'cat=${created.category} images=${created.imageUrls.length}');
      }).catchError((e) {
        debugPrint(
            '[AI MATCH] LOST→INVENTORY anchor=${created.id} FAILED: $e');
      });
    } else {
      debugPrint('[AI MATCH DEBUG] createReport type=found — Flow B requires '
          'handover (QR scan or admin confirm) to create inventory + trigger AI');
    }

    return created;
  }

  /// Closes a report that is still in the student's hands (admin-only for
  /// found reports — the admin found-detail "Close Report" path).
  ///
  /// A student can no longer close a lost report directly: they request
  /// closure ([requestClose]) and an admin approves it ([approveCloseRequest]).
  /// The Firestore rules reject a student's lost Active → Closed transition.
  Future<void> closeReport(String id) =>
      _lostFound.updateStatus(id, ItemStatus.closed);

  /// Student request to close their own lost report.
  ///
  /// The only permitted transition is Active → Requested Close. The Firestore
  /// rules reject every other student transition (including a direct
  /// Active → Closed), and a duplicate request on an already-requested report
  /// is a no-op at the database level.
  Future<void> requestClose(String id) =>
      _lostFound.updateStatus(id, ItemStatus.requestedClose);

  /// Admin approves a student's closure request.
  ///
  /// The report must currently be `Requested Close`; it moves to `Closed` with
  /// `closeReason = STUDENT_REQUEST_APPROVED`. Any still-active match on the
  /// report is rejected so no dangling reservation survives. The reason is a
  /// server-fixed constant — never client input.
  Future<void> approveCloseRequest(String id) async {
    await _lostFound.updateStatusWithReason(
        id, ItemStatus.closed, closeReasonStudentRequestApproved);
    await _lfWorkflow.rejectActiveMatchesForReport(id);
  }

  /// Admin marks an eligible open report as resolved.
  ///
  /// Moves the report to `Closed` with `closeReason = ADMIN_RESOLVED` and
  /// rejects any still-active match. Replaces the old `Resolved` status path.
  Future<void> markAsResolved(String id) async {
    await _lostFound.updateStatusWithReason(
        id, ItemStatus.closed, closeReasonAdminResolved);
    await _lfWorkflow.rejectActiveMatchesForReport(id);
  }

  /// Resolves a reporter's display name for a legacy report that predates
  /// `reportedByName`. Returns null when the profile cannot be loaded.
  Future<String?> fetchReporterName(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final profile = await _users.fetchProfile(uid);
      return profile?.fullName;
    } on AuthFailure {
      return null;
    }
  }

  /// Updates an existing report, uploading new images first (if any).
  ///
  /// New image URLs are appended to the existing `imageUrls` list. The caller
  /// must pass an [Item] whose `id` is set and whose `reportedByUid` matches
  /// the signed-in user (or the caller is an admin).
  Future<Item> updateReport(Item item, {List<File>? newImages}) async {
    var report = item;
    if (newImages != null && newImages.isNotEmpty) {
      final urls = await uploadReportImages(newImages);
      report = item.copyWith(
        imageUrls: [...item.imageUrls, ...urls],
      );
    }
    return _lostFound.updateItem(report);
  }

  /// Sets a report's status to Matched - Pending (admin-only by policy).
  Future<void> matchReport(String id) =>
      _lostFound.updateStatus(id, ItemStatus.matchedPending);

  /// Soft-deletes a report (sets `isDeleted: true`).
  ///
  /// The document remains in Firestore but is excluded from all feeds. This
  /// is the "delete/cancel" path for students who want to remove their own
  /// report.
  Future<void> deleteReport(String id) => _lostFound.softDelete(id);

  // ── LOST & FOUND — Workflows 2 & 3 ──────────────────────────────
  //
  // Handover QR, inventory, manual match, return QR and match
  // notifications. There is no trusted server (owner decision), so the
  // Firestore rules enforce every role boundary and the confirm methods
  // below run inside Firestore transactions for atomicity.

  /// Live feed of the signed-in finder's own inventory items, newest first.
  Stream<List<InventoryItem>> watchMyInventoryItems() =>
      _lfWorkflow.watchInventoryForFinder(firebaseUid ?? '');

  /// Live feed of every inventory item, for the admin inventory screen.
  Stream<List<InventoryItem>> watchAllInventoryItems() =>
      _lfWorkflow.watchAllInventory();

  /// Live view of a single inventory item by ID.
  Stream<InventoryItem?> watchInventoryItem(String id) =>
      _lfWorkflow.watchInventoryItem(id);

  /// Live feed of matches pointing at the signed-in student's own lost
  /// reports, newest first. Only a safe summary is rendered from these.
  Stream<List<LfMatch>> watchMyMatches() =>
      _lfWorkflow.watchMatchesForOwner(firebaseUid ?? '');

  /// Live feed of every match, for the admin match screens.
  Stream<List<LfMatch>> watchAllMatches() => _lfWorkflow.watchAllMatches();

  /// Live feed of AI-proposed matches only, for the Admin "AI Suggested
  /// Matches" section.  Sorted by score descending, then newest first.
  Stream<List<LfMatch>> watchAiProposedMatches() =>
      _lfWorkflow.watchAiProposedMatches();

  Stream<List<LfMatch>> watchApprovedMatches() =>
      _lfWorkflow.watchApprovedMatches();

  /// Live view of a single match by ID.
  Stream<LfMatch?> watchMatch(String id) => _lfWorkflow.watchMatch(id);

  /// Admin view: the handover QR transactions for one found report, newest
  /// first (the live code + Issued/Scanned/Confirmed state).
  Stream<List<QrTransaction>> watchHandoverQrForReport(String foundReportId) =>
      _lfWorkflow.watchHandoverQrForReport(foundReportId);

  /// Admin view: the return QR transactions for one inventory item, newest
  /// first (the live code + Issued/Scanned/Confirmed state).
  Stream<List<QrTransaction>> watchReturnQrForInventory(
          String inventoryItemId) =>
      _lfWorkflow.watchReturnQrForInventory(inventoryItemId);

  /// Student view: the signed-in student's own QR transactions of one kind.
  Stream<List<QrTransaction>> watchMyActiveQr(QrKind kind) =>
      _lfWorkflow.watchMyActiveQr(firebaseUid ?? '', kind);

  /// Live feed of the signed-in student's own L&F notifications.
  Stream<List<LfNotification>> watchMyLfNotifications() =>
      _lfWorkflow.watchMyLfNotifications(userId ?? '');

  /// Live feed of every L&F notification, for the admin screens.
  Stream<List<LfNotification>> watchAllLfNotifications() =>
      _lfWorkflow.watchAllLfNotifications();

  /// Marks a notification read. Returns `true` on success.
  Future<bool> markLfNotificationRead(String id) async {
    try {
      await _lfWorkflow.markLfNotificationRead(id);
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Live count of unread Lost & Found notifications for the signed-in user —
  /// a student's own, or every notification for an admin. Drives the bell
  /// badge's unread dot, which clears only once every notification is read.
  Stream<int> watchUnreadLfNotifications() {
    final Stream<List<LfNotification>> stream = isAdmin
        ? _lfWorkflow.watchAllLfNotifications()
        : _lfWorkflow.watchMyLfNotifications(userId ?? '');
    return stream.map((list) => list.where((n) => !n.read).length);
  }

  /// Marks all of the signed-in user's own L&F notifications as read.
  /// Returns `true` on success.
  Future<bool> markAllLfNotificationsRead() async {
    try {
      await _lfWorkflow.markAllRead(userId ?? '');
      return true;
    } on AuthFailure {
      return false;
    }
  }

  /// Issues a Handover QR for a found report awaiting handover
  /// (admin-only). The returned transaction carries the [QrTransaction.token]
  /// to encode in the QR image.
  Future<QrTransaction> issueHandoverQr(Item foundReport) =>
      _lfWorkflow.issueQr(QrTransaction.issue(
        kind: QrKind.handover,
        intendedStudentUid: foundReport.reportedByUid,
        intendedStudentId: foundReport.reportedByStudentId,
        foundReportId: foundReport.id,
      ));

  /// Issues a Return QR for an approved match (admin-only). Bound to the
  /// match's ID, lost report, the inventory item, and the lost report's owner.
  Future<QrTransaction> issueReturnQr(LfMatch match) =>
      _lfWorkflow.issueQr(QrTransaction.issue(
        kind: QrKind.return_,
        intendedStudentUid: match.lostOwnerUid,
        intendedStudentId: match.lostOwnerStudentId,
        lostReportId: match.lostReportId,
        inventoryItemId: match.inventoryItemId,
        matchId: match.id,
      ));

  /// A student scanning a code. Returns a [QrScanOutcome] whose message is
  /// display-ready for every case: invalid, expired, already used, cancelled,
  /// wrong account, wrong item, or success.
  ///
  /// [lostReportId] is the ID of the lost report the student is scanning
  /// from. For return QRs, the QR's stored `lostReportId` must match — this
  /// prevents cross-report scanning when a student has multiple approved
  /// matches. Pass `null` for handover scans (Workflow 2).
  ///
  /// When a handover scan creates a new inventory record, AI matching (Flow B)
  /// is triggered fire-and-forget without blocking the scan result.
  Future<QrScanOutcome> scanQrCode(String token, {String? lostReportId}) async {
    debugPrint('[AI MATCH DEBUG] scanQrCode called token=$token '
        'lostReportId=$lostReportId');
    final outcome = await _lfWorkflow.scanQr(
        token: token,
        studentUid: firebaseUid ?? '',
        lostReportId: lostReportId);
    debugPrint('[AI MATCH DEBUG] scanQrCode result: success=${outcome.success} '
        'invId=${outcome.inventoryId}');
    if (outcome.success && outcome.inventoryId != null) {
      _lfWorkflow
          .watchInventoryItem(outcome.inventoryId!)
          .first
          .timeout(const Duration(seconds: 30))
          .then((invItem) {
        debugPrint('[AI MATCH DEBUG] scanQrCode watchInventoryItem fired '
            'invId=${outcome.inventoryId} invItemIsNull=${invItem == null} '
            'status=${invItem?.status}');
        if (invItem == null) {
          debugPrint(
              '[AI MATCH] INVENTORY→LOST inv=${outcome.inventoryId} NO ITEM EMITTED (abort)');
          return;
        }
        runAiMatchingForInventoryItem(invItem).then((count) {
          debugPrint(
              '[AI MATCH] INVENTORY→LOST anchor=${outcome.inventoryId} matched=$count '
              'cat=${invItem.category} images=${invItem.imageUrls.length}');
        }).catchError((e) {
          debugPrint(
              '[AI MATCH] INVENTORY→LOST anchor=${outcome.inventoryId} FAILED: $e');
        });
      }).catchError((e) {
        debugPrint(
            '[AI MATCH] INVENTORY→LOST inv=${outcome.inventoryId} WATCH/TIMEOUT FAILED: $e');
      });
    }
    return outcome;
  }

  /// Cancels an unused QR code (admin-only).
  Future<void> cancelQrCode(String txnId) => _lfWorkflow.cancelQr(txnId);

  /// Workflow 2 — admin confirms the physical handover. One transaction:
  /// report → In Inventory, one inventory record, QR → Confirmed. Returns
  /// the inventory record ID.
  ///
  /// After handover, triggers AI matching (Flow B) for the new inventory item.
  Future<String> confirmHandover(String txnId) async {
    final invId = await _lfWorkflow.confirmHandover(
        txnId: txnId, adminUid: firebaseUid ?? '');
    debugPrint('[AI MATCH DEBUG] confirmHandover txnId=$txnId invId=$invId');

    // Trigger AI matching for the new inventory item (fire-and-forget).
    if (invId.isNotEmpty) {
      _lfWorkflow
          .watchInventoryItem(invId)
          .first
          .timeout(const Duration(seconds: 30))
          .then((invItem) {
        debugPrint('[AI MATCH DEBUG] confirmHandover watchInventoryItem fired '
            'invId=$invId invItemIsNull=${invItem == null} '
            'status=${invItem?.status}');
        if (invItem == null) {
          debugPrint(
              '[AI MATCH] INVENTORY→LOST inv=$invId NO ITEM EMITTED (abort)');
          return;
        }
        runAiMatchingForInventoryItem(invItem).then((count) {
          debugPrint(
              '[AI MATCH] INVENTORY→LOST anchor=$invId matched=$count '
              'cat=${invItem.category} images=${invItem.imageUrls.length}');
        }).catchError((e) {
          debugPrint(
              '[AI MATCH] INVENTORY→LOST anchor=$invId FAILED: $e');
        });
      }).catchError((e) {
        debugPrint(
            '[AI MATCH] INVENTORY→LOST inv=$invId WATCH/TIMEOUT FAILED: $e');
      });
    }

    return invId;
  }

  /// Workflow 3 — admin confirms the physical return. One transaction:
  /// inventory → Returned, found report → Returned, lost report → Resolved,
  /// match → Completed, QR → Confirmed.
  Future<void> confirmReturn(String txnId) =>
      _lfWorkflow.confirmReturn(txnId: txnId, adminUid: firebaseUid ?? '');

  /// Creates a match (admin-only). Pass [MatchStatus.proposed] for a draft
  /// or [MatchStatus.approved] to create it already approved.
  Future<LfMatch> createMatch(LfMatch match) => _lfWorkflow.createMatch(match);

  /// Approves a match and delivers the owner's notification atomically.
  Future<String> approveMatchWithNotification(String matchId) =>
      _lfWorkflow.approveMatchWithNotification(
        matchId: matchId,
        lostReportTitle: '',
        inventoryTitle: '',
      );

  /// Reserves an inventory item while an admin links it to a lost report.
  Future<void> reserveInventoryItem(String inventoryItemId) =>
      _lfWorkflow.reserveInventoryItem(inventoryItemId);

  /// Releases a reserved inventory item back to `In Inventory`.
  Future<void> releaseInventoryItem(String inventoryItemId) =>
      _lfWorkflow.releaseInventoryItem(inventoryItemId);

  /// Rejects a match and releases its inventory item atomically.
  Future<void> rejectMatch(String matchId) => _lfWorkflow.rejectMatch(matchId);

  // ── AI Matching orchestration ──────────────────────────────────

  /// Base URL of the campus-connect-ai Cloudflare Worker.
  ///
  /// Override at build time for physical-device development:
  ///   flutter run --dart-define=AI_WORKER_URL=http://192.168.1.239:8787
  ///
  /// Defaults to localhost (works with emulator or local browser).
  /// Change the default for a deployed production Worker.
  static const String _aiWorkerBase = String.fromEnvironment(
    'AI_WORKER_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );

  /// Maximum number of candidates evaluated in one batch.
  ///
  /// This is the single source of truth for both directions: exactly this many
  /// candidates are fetched, sent, and evaluated. It must not exceed the
  /// Worker's own `BATCH_MAX_CANDIDATES` (10), which is the hard cap.
  ///
  /// Previously 5 was sent as `maxCandidates` while 10 were fetched, so the
  /// Worker silently dropped half of every candidate set.
  static const int _aiMaxCandidates = 10;

  /// Runs AI matching for a newly created **Lost Report** (Flow A).
  ///
  /// 1. Queries eligible Found Inventory items (same category).
  /// 2. Sends the lost report + candidates to the Worker batch endpoint.
  /// 3. Creates `LfMatch` records (source: 'ai') for every result ≥ 50%.
  /// 4. Creates notifications for the lost owner.
  ///
  /// Returns the number of AI matches created.
  Future<int> runAiMatchingForLostReport(Item lostReport) async {
    debugPrint('[AI MATCH DEBUG] runAiMatchingForLostReport ENTERED '
        'anchor=${lostReport.id} cat=${lostReport.category} '
        'images=${lostReport.imageUrls.length} '
        'dbAvailable=${_lfWorkflow.isAvailable} '
        'isLost=${lostReport.isLost} '
        'status=${lostReport.status.wireValue} '
        'closed=${_isLostClosed(lostReport)} '
        'workerBase=$_aiWorkerBase');
    if (!_lfWorkflow.isAvailable) {
      debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
          'SKIP: db unavailable');
      return 0;
    }
    if (!lostReport.isLost) {
      debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
          'SKIP: not a lost report');
      return 0;
    }
    if (_isLostClosed(lostReport)) {
      debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
          'SKIP: status=${lostReport.status.wireValue}');
      return 0;
    }

    // Anchor must have at least one image for visual comparison.
    if (lostReport.imageUrls.isEmpty) {
      debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
          'SKIP: no anchor image');
      return 0;
    }

    // 1. Find eligible inventory candidates (same category, In Inventory,
    //    must have at least one image). Uses a targeted status+category
    //    query so the student's client can read under the 'In Inventory' rule.
    // Fetch exactly as many as will be evaluated — no silent drop.
    final candidates = await _lfWorkflow.queryInventoryForAi(
      category: lostReport.category,
      limit: _aiMaxCandidates,
    );

    if (candidates.isEmpty) {
      debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
          'NO candidates cat=${lostReport.category}');
      return 0;
    }

    // 2. Build the batch request.
    final anchorItem = _itemToWorkerPayload(lostReport);
    final candidatePayloads =
        candidates.map((inv) => _inventoryToWorkerPayload(inv)).toList();

    final batchResults =
        await _callBatchEndpoint(anchorItem, candidatePayloads);
    if (batchResults == null) {
      debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
          'BATCH FAILED (endpoint returned null)');
      return 0;
    }

    // 3. Create match records for results ≥ 50%.
    int created = 0;
    for (final r in batchResults) {
      final candidateId = r['candidateId'] as String? ?? '';
      final resultIndex = batchResults.indexOf(r);
      final hasError = r['error'] != null;
      debugPrint('[AI MATCH DEBUG] stage=candidate-result '
          'candidateId=$candidateId resultIndex=$resultIndex '
          'resultPresent=true hasError=$hasError');
      if (hasError) {
        debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
            'cand=${r['candidateId']} worker_error SKIP');
        continue;
      }
      final overallScore = (r['overallScore'] as num?)?.toInt() ?? 0;
      final workerIsMatch = r['isMatch'] as bool?;
      final scoreAtLeast50 = overallScore >= 50;
      debugPrint('[AI MATCH DEBUG] stage=score candidateId=$candidateId '
          'overallScore=$overallScore rawIsMatch=$workerIsMatch');
      debugPrint('[AI MATCH DEBUG] stage=threshold candidateId=$candidateId '
          'scoreAtLeast50=$scoreAtLeast50 threshold=50');
      if (!scoreAtLeast50) {
        debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
            'cand=${r['candidateId']} score=$overallScore BELOW 50 (skip)');
        continue;
      }

      final invItem = candidates
          .cast<InventoryItem?>()
          .firstWhere((c) => c?.id == candidateId, orElse: () => null);
      if (invItem == null) {
        debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
            'cand=$candidateId NOT FOUND in candidate set (skip)');
        continue;
      }

      // Duplicate check.
      debugPrint('[AI MATCH DEBUG] stage=pair-duplicate-check '
          'candidateId=$candidateId started=true');
      if (await _lfWorkflow.pairAlreadyMatched(
          lostReport.id, invItem.id,
          lostOwnerUid: lostReport.reportedByUid)) {
        debugPrint('[AI MATCH DEBUG] stage=pair-duplicate-check '
            'candidateId=$candidateId alreadyMatched=true error=none');
        debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
            'cand=$candidateId SKIP: pairAlreadyMatched=true');
        continue;
      }
      debugPrint('[AI MATCH DEBUG] stage=pair-duplicate-check '
          'candidateId=$candidateId alreadyMatched=false error=none');

      // Eligibility check.
      debugPrint('[AI MATCH DEBUG] stage=inventory-availability '
          'candidateId=$candidateId started=true');
      if (!await _lfWorkflow.isInventoryAvailableForAiMatch(invItem.id)) {
        debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
            'cand=$candidateId SKIP: inventory unavailable');
        continue;
      }
      debugPrint('[AI MATCH DEBUG] stage=inventory-availability '
          'candidateId=$candidateId available=true error=none');

      final match = LfMatch(
        lostReportId: lostReport.id,
        inventoryItemId: invItem.id,
        lostOwnerUid: lostReport.reportedByUid,
        lostOwnerStudentId: lostReport.reportedByStudentId,
        finderUid: invItem.finderUid,
        status: MatchStatus.proposed,
        source: MatchSource.ai,
        overallScore: overallScore,
        visualScore: (r['visualScore'] as num?)?.toInt(),
        titleScore: (r['titleScore'] as num?)?.toInt(),
        descriptionScore: (r['descriptionScore'] as num?)?.toInt(),
        categoryScore: (r['categoryScore'] as num?)?.toInt(),
        // locationScore/timeScore are null when the data was unavailable —
        // the Worker omits them rather than sending a misleading 0.
        locationScore: (r['locationScore'] as num?)?.toInt(),
        timeScore: (r['timeScore'] as num?)?.toInt(),
        confidence: (r['confidence'] as num?)?.toInt(),
        reason: r['reason']?.toString(),
        evidence: _evidenceFromWorkerResult(r),
      );

      final createdMatch = await _lfWorkflow.createAiMatchIfAvailable(match);
      if (createdMatch != null) {
        created++;
        debugPrint('[AI MATCH] LOST→INVENTORY MATCH CREATED '
            'anchor=${lostReport.id} cand=$candidateId '
            'score=$overallScore id=${createdMatch.id} '
            'evidence=${match.evidence?.matchingFeatures.length ?? 0}m/'
            '${match.evidence?.conflictingFeatures.length ?? 0}c');
        // Create notification for the lost owner (fire-and-forget).
        _createAiMatchNotification(createdMatch).catchError((_) => 0);
      } else {
        debugPrint('[AI MATCH] LOST→INVENTORY anchor=${lostReport.id} '
            'cand=$candidateId CREATE_REJECTED (null)');
      }
    }

    return created;
  }

  /// Runs AI matching for a newly created **Found Inventory item** (Flow B).
  ///
  /// 1. Queries active/unresolved Lost Reports (same category).
  /// 2. Sends each lost report as anchor + this inventory item as candidate.
  /// 3. Creates `LfMatch` records for results ≥ 50%.
  Future<int> runAiMatchingForInventoryItem(InventoryItem invItem) async {
    debugPrint('[AI MATCH DEBUG] runAiMatchingForInventoryItem ENTERED '
        'invId=${invItem.id} status=${invItem.status} '
        'cat=${invItem.category} images=${invItem.imageUrls.length}');
    if (!_lfWorkflow.isAvailable) {
      debugPrint('[AI MATCH] INVENTORY→LOST anchor=${invItem.id} '
          'SKIP: db unavailable');
      return 0;
    }
    if (invItem.status != InventoryStatus.inInventory) {
      debugPrint('[AI MATCH] INVENTORY→LOST anchor=${invItem.id} '
          'SKIP: status=${invItem.status}');
      return 0;
    }

    // Anchor must have at least one image for visual comparison.
    if (invItem.imageUrls.isEmpty) {
      debugPrint('[AI MATCH] INVENTORY→LOST anchor=${invItem.id} '
          'SKIP: no anchor image');
      return 0;
    }

    // 1. Find eligible lost reports (same category, not closed, must have
    //    at least one image). Takes exactly the number that will be
    //    evaluated, matching Flow A — no silent drop in either direction.
    final lostReports = await _lostFound.watchAllLostItems().first;
    final candidates = lostReports
        .where((r) =>
            !_isLostClosed(r) &&
            r.category == invItem.category &&
            r.imageUrls.isNotEmpty)
        .take(_aiMaxCandidates)
        .toList();

    if (candidates.isEmpty) {
      debugPrint('[AI MATCH] INVENTORY→LOST anchor=${invItem.id} '
          'NO candidates cat=${invItem.category}');
      return 0;
    }

    // 2. For each lost report, compare against this inventory item.
    int created = 0;
    for (final lostReport in candidates) {
      // Duplicate check.
      if (await _lfWorkflow.pairAlreadyMatched(
          lostReport.id, invItem.id,
          lostOwnerUid: lostReport.reportedByUid)) {
        debugPrint('[AI MATCH] INVENTORY→LOST anchor=${invItem.id} '
            'cand=${lostReport.id} SKIP: pairAlreadyMatched=true');
        continue;
      }

      // Eligibility check.
      if (!await _lfWorkflow.isInventoryAvailableForAiMatch(invItem.id)) {
        debugPrint('[AI MATCH] INVENTORY→LOST anchor=${invItem.id} '
            'ABORT: inventory item became unavailable');
        break; // item became unavailable — stop
      }

      final anchorItem = _itemToWorkerPayload(lostReport);
      final candidatePayloads = [_inventoryToWorkerPayload(invItem)];

      final batchResults =
          await _callBatchEndpoint(anchorItem, candidatePayloads);
      if (batchResults == null || batchResults.isEmpty) {
        debugPrint('[AI MATCH] INVENTORY→LOST anchor=${invItem.id} '
            'cand=${lostReport.id} BATCH FAILED/EMPTY (skip)');
        continue;
      }

      final r = batchResults.first;
      if (r['error'] != null) {
        debugPrint('[AI MATCH] INVENTORY→LOST anchor=${invItem.id} '
            'cand=${lostReport.id} worker_error SKIP');
        continue;
      }
      final overallScore = (r['overallScore'] as num?)?.toInt() ?? 0;
      if (overallScore < 50) {
        debugPrint('[AI MATCH] INVENTORY→LOST anchor=${invItem.id} '
            'cand=${lostReport.id} score=$overallScore BELOW 50 (skip)');
        continue;
      }

      final match = LfMatch(
        lostReportId: lostReport.id,
        inventoryItemId: invItem.id,
        lostOwnerUid: lostReport.reportedByUid,
        lostOwnerStudentId: lostReport.reportedByStudentId,
        finderUid: invItem.finderUid,
        status: MatchStatus.proposed,
        source: MatchSource.ai,
        overallScore: overallScore,
        visualScore: (r['visualScore'] as num?)?.toInt(),
        titleScore: (r['titleScore'] as num?)?.toInt(),
        descriptionScore: (r['descriptionScore'] as num?)?.toInt(),
        categoryScore: (r['categoryScore'] as num?)?.toInt(),
        // locationScore/timeScore are null when the data was unavailable —
        // the Worker omits them rather than sending a misleading 0.
        locationScore: (r['locationScore'] as num?)?.toInt(),
        timeScore: (r['timeScore'] as num?)?.toInt(),
        confidence: (r['confidence'] as num?)?.toInt(),
        reason: r['reason']?.toString(),
        evidence: _evidenceFromWorkerResult(r),
      );

      final createdMatch = await _lfWorkflow.createAiMatchIfAvailable(match);
      if (createdMatch != null) {
        created++;
        debugPrint('[AI MATCH] INVENTORY→LOST MATCH CREATED '
            'anchor=${invItem.id} cand=${lostReport.id} '
            'score=$overallScore id=${createdMatch.id} '
            'evidence=${match.evidence?.matchingFeatures.length ?? 0}m/'
            '${match.evidence?.conflictingFeatures.length ?? 0}c');
        _createAiMatchNotification(createdMatch).catchError((_) => 0);
      } else {
        debugPrint('[AI MATCH] INVENTORY→LOST anchor=${invItem.id} '
            'cand=${lostReport.id} CREATE_REJECTED (null)');
      }
    }

    debugPrint('[AI MATCH DEBUG] runAiMatchingForInventoryItem EXITED '
        'invId=${invItem.id} created=$created');
    return created;
  }

  // ── Private AI helpers ──────────────────────────────────────────

  Map<String, dynamic> _itemToWorkerPayload(Item item) => {
        'title': item.title,
        'description': item.description,
        'category': item.category,
        'location': item.whereLost,
        'dateTime': item.whenLost?.toIso8601String() ?? '',
        'imageUrls': item.imageUrls,
      };

  Map<String, dynamic> _inventoryToWorkerPayload(InventoryItem inv) => {
        'id': inv.id,
        'title': inv.title,
        'description': inv.description,
        'category': inv.category,
        // Inventory items carry no location field. The empty string is the
        // honest "not recorded" signal: the Worker drops the location weight
        // from the denominator instead of scoring it 0, so this no longer
        // caps every inventory comparison at 90.
        'location': '',
        'dateTime': inv.createdAt?.toIso8601String() ?? '',
        'imageUrls': inv.imageUrls,
      };

  /// Builds a [MatchEvidence] from one Worker result entry.
  ///
  /// The Worker always returns `evidence` as
  /// `{ matchingFeatures: [...], conflictingFeatures: [...] }` with both keys
  /// present (possibly empty). Returns null when the payload carries no
  /// evidence at all, so `LfMatch.evidence` stays null and `toCreateMap()`
  /// omits the field — exactly as it did before evidence existed. Old matches
  /// with a null evidence field therefore keep loading unchanged.
  static MatchEvidence? _evidenceFromWorkerResult(Map<String, dynamic> r) {
    final raw = r['evidence'];
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);

    List<String> readList(String key) {
      final value = map[key];
      if (value is! List) return const <String>[];
      return value
          .whereType<Object>()
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }

    final matching = readList('matchingFeatures');
    final conflicting = readList('conflictingFeatures');
    if (matching.isEmpty && conflicting.isEmpty) return null;
    return MatchEvidence(
      matchingFeatures: matching,
      conflictingFeatures: conflicting,
    );
  }

  /// Calls POST /ai/batch-match on the Worker. Returns the results list
  /// or null on failure.
  Future<List<Map<String, dynamic>>?> _callBatchEndpoint(
      Map<String, dynamic> anchorItem,
      List<Map<String, dynamic>> candidateItems) async {
    try {
      final uri = Uri.parse('$_aiWorkerBase/ai/batch-match');
      final host = uri.authority; // host:port only — no path, no secrets
      debugPrint('[AI MATCH DEBUG] Worker URL = $_aiWorkerBase  '
          'host=$host  candidates=${candidateItems.length}');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'anchorItem': anchorItem,
              'candidateItems': candidateItems,
              'maxCandidates': _aiMaxCandidates,
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        debugPrint('[AI MATCH] batch-match HTTP ${response.statusCode} '
            'on $host (returning null)');
        return null;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final resultList = body['results'] as List<dynamic>?;
      debugPrint('[AI MATCH DEBUG] stage=worker-response-received '
          'httpStatus=200 resultCount=${resultList?.length ?? 0} '
          'parseResult=success');
      if (body['success'] != true) {
        debugPrint('[AI MATCH] batch-match success=false on $host');
        return null;
      }
      return resultList?.cast<Map<String, dynamic>>();
    } catch (e) {
      final host = Uri.tryParse(_aiWorkerBase)?.authority ?? 'unknown';
      debugPrint('[AI MATCH] batch-match EXCEPTION on $host: '
          '${e.runtimeType} — ${e.toString().split('\n').first}');
      return null;
    }
  }

  /// Creates an lfNotification for the lost owner when an AI match is found.
  Future<void> _createAiMatchNotification(LfMatch match) async {
    try {
      final notification = LfNotification(
        studentId: match.lostOwnerStudentId,
        title: 'Possible Match Found',
        body: 'An AI-powered match was found for your lost item. '
            'Review it under My Lost Reports → Possible Matches.',
        type: 'match',
        relatedReportId: match.lostReportId,
      );
      await _lfWorkflow.createNotification(notification);
      debugPrint('[AI MATCH] NOTIFICATION CREATED '
          'match=${match.lostReportId}_${match.inventoryItemId} '
          'owner=${match.lostOwnerStudentId}');
    } catch (e) {
      debugPrint('[AI MATCH] NOTIFICATION FAILED '
          'match=${match.lostReportId}_${match.inventoryItemId} '
          'owner=${match.lostOwnerStudentId}: $e');
    }
  }

  bool _isLostClosed(Item item) {
    return item.status == ItemStatus.resolved ||
        item.status == ItemStatus.returned ||
        item.status == ItemStatus.closed;
  }

  /// Live feed of the signed-in student's own issues, newest first.
  ///
  /// The screen never supplies an ID — the campus Student ID is read from the
  /// session here, so the UI keeps its single dependency on [AppState].
  /// Signed out yields an empty list, matching the screen's empty state.
  Stream<List<Issue>> watchMyIssues() => _issues.watchMyIssues(userId ?? '');

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

  /// Live feed of every locker notification, for the admin screens.
  Stream<List<LockerNotification>> watchAllLockerNotifications() =>
      _lockers.watchAllLockerNotifications();

  /// Live count of unread locker notifications for the signed-in user —
  /// a student's own, or every notification for an admin. Contributes to the
  /// bell badge alongside [watchUnreadLfNotifications].
  Stream<int> watchUnreadLockerNotifications() {
    final Stream<List<LockerNotification>> stream = isAdmin
        ? _lockers.watchAllLockerNotifications()
        : _lockers.watchMyLockerNotifications(userId ?? '');
    return stream.map((list) => list.where((n) => !n.read).length);
  }

  /// Marks all of the signed-in user's own locker notifications as read.
  /// Returns `true` on success.
  Future<bool> markAllLockerNotificationsRead() async {
    try {
      await _lockers.markAllRead(userId ?? '');
      return true;
    } on AuthFailure {
      return false;
    }
  }

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
  Future<LockerBooking?> bookLocker(
    String lockerId, {
    required String location,
    required int durationMonths,
  }) async {
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month + durationMonths, now.day);
    final daysLeft = endDate.difference(now).inDays;
    // Use default pricing when the Locker object isn't available.
    final pricing = const LockerPricing(
            deposit: 100.0, monthlyRent: 10.0, durationMonths: 6)
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
      await _lockers.addLockerHistory(
          lockerId,
          LockerHistory(
            action: 'Student reported locker issue',
            staffId: userId ?? '',
            timestamp: DateTime.now().toIso8601String(),
            reason:
                category.isNotEmpty ? '$category: $description' : description,
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
      await _lockers.updateLockerIssueStatus(issue.id, newStatus,
          adminNotes: adminNotes);
      final action = newStatus == 'Under Review'
          ? 'Issue moved to Under Review'
          : newStatus == 'Resolved'
              ? 'Issue resolved'
              : 'Issue status updated';
      await _lockers.addLockerHistory(
          issue.lockerId,
          LockerHistory(
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
  Future<bool> patchLockerBooking(
      String id, Map<String, dynamic> fields) async {
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
          body:
              'Your key return for locker ${booking.lockerId} has been verified. '
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
    final digitalCode = locker.lockType == 'digital'
        ? '${Random().nextInt(9000) + 1000}'
        : null;

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
          action:
              isRegeneration ? 'Return QR regenerated' : 'Return QR generated',
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
  Future<bool> approveLockerReleaseRequest(
      Locker locker, LockerBooking booking) async {
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
          reason:
              'Admin approved the release request. Return QR can now be generated.',
        ),
      );
      // Notify the student that their release request was approved.
      if (booking.studentId != null && booking.studentId!.isNotEmpty) {
        await _sendLockerNotification(
          studentId: booking.studentId!,
          lockerId: booking.lockerId,
          title: 'Release Approved',
          body:
              'Your release request for locker ${booking.lockerId} has been approved. '
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
  Future<bool> approveLockerRelease(
      Locker locker, LockerBooking booking) async {
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
            reason:
                'Deposit: RM${booking.deposit.toStringAsFixed(0)} refunded.',
          ),
        );
      }

      // Notify the student: deposit refunded + agreement completed.
      if (booking.studentId != null && booking.studentId!.isNotEmpty) {
        await _sendLockerNotification(
          studentId: booking.studentId!,
          lockerId: booking.lockerId,
          title: 'Deposit Refunded',
          body:
              'Your security deposit of RM${booking.deposit.toStringAsFixed(0)} '
              'for locker ${booking.lockerId} has been refunded.',
          type: 'deposit_refunded',
        );
        await _sendLockerNotification(
          studentId: booking.studentId!,
          lockerId: booking.lockerId,
          title: 'Locker Agreement Completed',
          body:
              'Your locker agreement for ${booking.lockerId} has been completed. '
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
  Future<bool> terminateLocker(Locker locker, LockerBooking? booking,
      {String? reason}) async {
    final reasonText =
        reason ?? 'Admin terminated locker agreement. Deposit forfeited.';
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
          body:
              'Your locker agreement for ${locker.id} has been terminated by the administrator. '
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
  Future<bool> blockLocker(Locker locker, LockerBooking? booking,
      {String? reason}) async {
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
          body:
              'Your locker ${locker.id} has been blocked by the administrator. '
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
          body:
              'Your locker ${locker.id} has been reopened and is available again. '
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
  Future<bool> releaseLockerAdmin(Locker locker, LockerBooking? booking,
      {String? reason}) async {
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
          body:
              'Your locker ${locker.id} has been force-released by the administrator. '
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

  Future<String?> loadRememberedIdentifier() =>
      _auth.loadRememberedIdentifier();

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
      await _users.updatePreferredLanguage(
          uid: current.uid, language: language);
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
  Stream<List<Event>> watchPendingEvents() =>
      _eventsService.watchPendingEvents();

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
        () => _eventsService
            .patchJoining(joiningId, {'paymentStatus': 'Completed'}),
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
    if (joining.paymentStatus != null && joining.paymentStatus != 'Completed') {
      return const EventActionResult.failure('Payment has not been completed.');
    }

    final ok = await _eventWrite(
      () => _eventsService.decideJoining(
        joining.id,
        joining.eventId,
        {
          'status': 'Approved',
          'qrTicketCode': joining.qrTicketCode ?? _ticketCode()
        },
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
      return const EventActionResult.success(
          'Entry verified! Participant checked in.');
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
    final joining =
        await _eventsService.getJoiningForStudent(eventId, studentId);
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
  Future<bool> publishCandidate(String id) => _electionWrite(
      () => _electionsService.patchCandidate(id, {'status': 'Published'}));

  /// Unpublishes a candidate by moving its status back to 'Pending'.
  Future<bool> unpublishCandidate(String id) => _electionWrite(
      () => _electionsService.patchCandidate(id, {'status': 'Pending'}));

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
  Future<bool> publishElectionMeta(String id) => _electionWrite(
      () => _electionsService.patchElectionMeta(id, {'status': 'Published'}));

  /// Moves an election into the Admin Archive. The status it held is
  /// preserved so it can be restored, and the archiving admin is taken from
  /// the signed-in profile so no caller passes identity around.
  Future<bool> archiveElectionMeta(String id,
          {required String previousStatus}) =>
      _electionWrite(() => _electionsService.archiveElectionMeta(
            id,
            previousStatus: previousStatus,
            archivedBy: _profile?.studentId ?? 'admin',
            archivedAt: DateTime.now().toIso8601String(),
          ));

  /// Restores an archived election to its pre-archive status.
  Future<bool> restoreElectionMeta(String id,
          {required String previousStatus}) =>
      _electionWrite(() => _electionsService.restoreElectionMeta(id,
          previousStatus: previousStatus));

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

  static const AuthResult _unavailable = AuthResult.failure(
      'Authentication is unavailable. Please restart the app.');

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
