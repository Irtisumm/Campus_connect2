import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/auth_result.dart';
import '../models/locker.dart';
import '../models/locker_booking.dart';
import '../models/locker_history.dart';
import '../models/locker_issue.dart';
import '../models/locker_notification.dart';

/// Firestore access for the Lockers subsystem: the `lockers`,
/// `lockerBookings` and `lockerIssues` collections plus the
/// `lockers/{id}/history` subcollection.
///
/// Mirrors [IssueService] exactly: screens talk to this class and never to
/// Firestore directly, and every [FirebaseException] is translated into an
/// [AuthFailure] here so no Firebase type — and no raw Firebase error string —
/// ever reaches the widget tree.
class LockerService {
  static const String lockersPath = 'lockers';
  static const String bookingsPath = 'lockerBookings';
  static const String issuesPath = 'lockerIssues';
  static const String notificationsPath = 'lockerNotifications';
  static const String historySubPath = 'history';

  final FirebaseFirestore? _dbOrNull;

  LockerService({FirebaseFirestore? firestore}) : _dbOrNull = _resolve(firestore);

  static FirebaseFirestore? _resolve(FirebaseFirestore? injected) {
    try {
      return injected ?? FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable => _dbOrNull != null;

  CollectionReference<Map<String, dynamic>> get _lockers =>
      _dbOrNull!.collection(lockersPath);

  CollectionReference<Map<String, dynamic>> get _bookings =>
      _dbOrNull!.collection(bookingsPath);

  CollectionReference<Map<String, dynamic>> get _issues =>
      _dbOrNull!.collection(issuesPath);

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _dbOrNull!.collection(notificationsPath);

  // ── LOCKERS ─────────────────────────────────────────────────────

  /// Live feed of every locker, for the browse screen (students) and the
  /// admin list/dashboard screens.
  ///
  /// The `lockers` read rule admits any signed-in user, so no ownership
  /// filter is applied here. Sorted client-side by locker ID so no composite
  /// Firestore index is required.
  Stream<List<Locker>> watchLockers() {
    if (!isAvailable) return Stream.value(const <Locker>[]);
    return _lockers
        .snapshots()
        .map((snap) {
          final lockers = snap.docs
              .map((doc) => Locker.fromMap(doc.id, doc.data()))
              .toList();
          lockers.sort((a, b) => a.id.compareTo(b.id));
          return lockers;
        })
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Live view of a single locker by its document ID (e.g. `LK-A01`), for the
  /// booking and admin detail screens. Emits `null` when it does not exist.
  Stream<Locker?> watchLocker(String id) {
    if (!isAvailable || id.isEmpty) return Stream.value(null);
    return _lockers
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? Locker.fromMap(doc.id, doc.data()!) : null)
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Fetches a single locker by its document ID, or `null` when it does not
  /// exist.
  Future<Locker?> getLocker(String id) async {
    _assertAvailable();
    try {
      final doc = await _lockers.doc(id).get();
      return doc.exists ? Locker.fromMap(doc.id, doc.data()!) : null;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Updates a locker document. Status transitions and renter assignment are
  /// enforced by the security rules, not here.
  Future<void> updateLocker(Locker locker) async {
    _assertAvailable();
    try {
      await _lockers.doc(locker.id).update(locker.toMap());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── BOOKINGS ────────────────────────────────────────────────────

  /// Live feed of the signed-in student's own bookings, newest first.
  ///
  /// The `studentId` filter is not optional for a *student* caller: Firestore
  /// rules are not filters, so the read rule is evaluated against every
  /// document the query would return and rejects the whole query if any
  /// document fails. An admin's unfiltered query passes via `isAdmin()`.
  Stream<List<LockerBooking>> watchMyBookings(String studentId) =>
      _watchBookings(studentId: studentId);

  /// Live feed of every booking across all students, for the admin screens.
  Stream<List<LockerBooking>> watchAllBookings() => _watchBookings();

  /// Live view of a single booking by its Firestore document ID. Emits `null`
  /// when the document does not exist.
  Stream<LockerBooking?> watchBooking(String id) {
    if (!isAvailable || id.isEmpty) return Stream.value(null);
    return _bookings
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? LockerBooking.fromMap(doc.id, doc.data()!) : null)
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// The single query core behind the `watchMy*` / `watchAll*` booking feeds.
  Stream<List<LockerBooking>> _watchBookings({String? studentId}) {
    if (!isAvailable) return Stream.value(const <LockerBooking>[]);
    if (studentId != null && studentId.isEmpty) {
      return Stream.value(const <LockerBooking>[]);
    }

    Query<Map<String, dynamic>> query = _bookings;
    if (studentId != null) {
      query = query.where('studentId', isEqualTo: studentId);
    }

    return query
        .snapshots()
        .map(_sortedBookingsNewestFirst)
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Maps a snapshot to a list sorted newest-first by `startDate`.
  ///
  /// Client-side so no composite Firestore index is required.
  static List<LockerBooking> _sortedBookingsNewestFirst(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final bookings = snapshot.docs
        .map((doc) => LockerBooking.fromMap(doc.id, doc.data()))
        .toList();
    bookings.sort((a, b) => b.startDate.compareTo(a.startDate));
    return bookings;
  }

  /// Writes a new booking and returns it with its Firestore ID.
  ///
  /// Throws an [AuthFailure] with a user-safe message when the database is
  /// unreachable, the write is rejected, or the network is down.
  Future<LockerBooking> createBooking(LockerBooking booking) async {
    _assertAvailable();
    try {
      final doc = await _bookings.add(booking.toMap());
      return booking.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Returns `true` if the given locker already has an active (non-Completed,
  /// non-Rejected) booking — i.e. a booking whose `status` is anything other
  /// than `Completed` or `Rejected`. Used to prevent two students from booking
  /// the same locker while it is still `Available` pending admin confirmation.
  ///
  /// The query is `where('lockerId', '==', lockerId).where('status',
  /// '!=', 'Completed')`. Under the deployed security rules a *student*
  /// caller cannot list other students' bookings (`ownsBooking()` is not a
  /// filter), so this query is expected to be denied for students with
  /// `permission-denied`; the caller treats that denial as "unable to
  /// verify" and proceeds, relying on the booking-create rule as the final
  /// guard. An *admin* caller can run it. A composite index on
  /// `(lockerId, status)` is not required for a single inequality.
  Future<bool> hasActiveBookingForLocker(String lockerId) async {
    _assertAvailable();
    try {
      final snap = await _bookings
          .where('lockerId', isEqualTo: lockerId)
          .where('status', isNotEqualTo: 'Completed')
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Overwrites an existing booking. Ownership and identity fields are
  /// enforced by the security rules, not here.
  Future<void> updateBooking(LockerBooking booking) async {
    _assertAvailable();
    try {
      await _bookings.doc(booking.id).update(booking.toMap());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Partial update of a booking document — used for status/QR transitions
  /// where only a few fields change.
  Future<void> patchBooking(String id, Map<String, dynamic> fields) async {
    _assertAvailable();
    try {
      await _bookings.doc(id).update(fields);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Atomically completes a booking lifecycle: marks the booking Completed,
  /// frees the locker, and appends the audit-trail entry in a single
  /// [WriteBatch], so all writes succeed or fail together.
  ///
  /// The booking is NEVER deleted — `allow delete: if false` in the security
  /// rules forbids it and history must be preserved. Instead the booking
  /// document is updated to its terminal `Completed` state.
  ///
  /// [bookingFields] carries the partial booking update (status, releaseStatus,
  /// depositRefunded, completedDate). [locker] is the freed locker (status
  /// 'Available', renter fields cleared). [history] is the audit-trail entry.
  Future<void> completeBookingWithLocker(
    String bookingId,
    Map<String, dynamic> bookingFields,
    Locker locker,
    LockerHistory history,
  ) async {
    _assertAvailable();
    try {
      final historyRef =
          _lockers.doc(locker.id).collection(historySubPath).doc();
      final batch = _dbOrNull!.batch()
        ..update(_bookings.doc(bookingId), bookingFields)
        ..update(_lockers.doc(locker.id), locker.toMap())
        ..set(historyRef, history.toMap());
      await batch.commit();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Fetches a single booking by its Firestore document ID, or `null` when it
  /// does not exist.
  Future<LockerBooking?> getBooking(String id) async {
    _assertAvailable();
    try {
      final doc = await _bookings.doc(id).get();
      return doc.exists ? LockerBooking.fromMap(doc.id, doc.data()!) : null;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── LOCKER ISSUES ───────────────────────────────────────────────

  /// Live feed of the signed-in student's own locker issue reports, newest
  /// first.
  Stream<List<LockerIssue>> watchMyLockerIssues(String studentId) =>
      _watchIssues(studentId: studentId);

  /// Live feed of every locker issue across all students, for the admin
  /// screens.
  Stream<List<LockerIssue>> watchAllLockerIssues() => _watchIssues();

  Stream<List<LockerIssue>> _watchIssues({String? studentId}) {
    if (!isAvailable) return Stream.value(const <LockerIssue>[]);
    if (studentId != null && studentId.isEmpty) {
      return Stream.value(const <LockerIssue>[]);
    }

    Query<Map<String, dynamic>> query = _issues;
    if (studentId != null) {
      query = query.where('studentId', isEqualTo: studentId);
    }

    return query
        .snapshots()
        .map((snap) {
          final issues = snap.docs
              .map((doc) => LockerIssue.fromMap(doc.id, doc.data()))
              .toList();
          issues.sort((a, b) => b.reportedDate.compareTo(a.reportedDate));
          return issues;
        })
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Writes a new locker issue report and returns it with its Firestore ID.
  Future<LockerIssue> createLockerIssue(LockerIssue issue) async {
    _assertAvailable();
    try {
      final doc = await _issues.add(issue.toMap());
      return issue.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Moves a locker issue to a new status ('Under Review', 'Resolved') and
  /// optionally attaches an admin note in the same write.
  Future<void> updateLockerIssueStatus(String id, String status, {String? adminNotes}) async {
    _assertAvailable();
    try {
      final updates = <String, dynamic>{'status': status};
      if (adminNotes != null && adminNotes.isNotEmpty) {
        updates['adminNotes'] = adminNotes;
      }
      await _issues.doc(id).update(updates);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── HISTORY (subcollection lockers/{id}/history) ────────────────

  /// Live feed of a locker's audit-trail history, oldest first, for the admin
  /// detail screen's timeline. Emits an empty list when there is no history.
  Stream<List<LockerHistory>> watchLockerHistory(String lockerId) {
    if (!isAvailable || lockerId.isEmpty) {
      return Stream.value(const <LockerHistory>[]);
    }
    return _lockers
        .doc(lockerId)
        .collection(historySubPath)
        .snapshots()
        .map((snap) {
          final entries = snap.docs
              .map((doc) => LockerHistory.fromMap(doc.data()))
              .toList();
          entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          return entries;
        })
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Appends one entry to a locker's audit-trail history.
  Future<void> addLockerHistory(String lockerId, LockerHistory entry) async {
    _assertAvailable();
    try {
      await _lockers.doc(lockerId).collection(historySubPath).add(entry.toMap());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }
  /// Atomically reserves a locker for an existing booking and appends the
  /// audit-trail entry in a single [WriteBatch], so both writes succeed or
  /// fail together.
  ///
  /// This is the FIRST admin-controlled locker operation for a booking: the
  /// student creates the `lockerBookings` document only (students may never
  /// write `lockers` or `lockers/{id}/history`), and the inventory is not
  /// touched until the admin generates the collection QR. At that point this
  /// method flips the locker to `Pending Pickup`, stamps the renter and
  /// dates, and records the audit entry — all admin-only writes.
  ///
  /// [locker] is the reserved locker (status 'Pending Pickup', renter fields
  /// populated). It carries no unlock code — for a digital lock the code lives
  /// on the owner-scoped booking document only. [history] is the audit-trail
  /// entry.
  Future<void> reserveLockerForBooking(
    Locker locker,
    LockerHistory history,
  ) async {
    _assertAvailable();
    try {
      final historyRef =
          _lockers.doc(locker.id).collection(historySubPath).doc();
      final batch = _dbOrNull!.batch()
        ..update(_lockers.doc(locker.id), locker.toMap())
        ..set(historyRef, history.toMap());
      await batch.commit();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── NOTIFICATIONS (lockerNotifications collection) ──────────────

  /// Live feed of the signed-in student's own locker notifications, newest
  /// first.
  Stream<List<LockerNotification>> watchMyLockerNotifications(String studentId) {
    if (!isAvailable || studentId.isEmpty) {
      return Stream.value(const <LockerNotification>[]);
    }
    return _notifications
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snap) {
          final notifications = snap.docs
              .map((doc) => LockerNotification.fromMap(doc.id, doc.data()))
              .toList();
          notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return notifications;
        })
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Live feed of every locker notification, for the admin screens.
  Stream<List<LockerNotification>> watchAllLockerNotifications() {
    if (!isAvailable) return Stream.value(const <LockerNotification>[]);
    return _notifications
        .snapshots()
        .map((snap) {
          final notifications = snap.docs
              .map((doc) => LockerNotification.fromMap(doc.id, doc.data()))
              .toList();
          notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return notifications;
        })
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Creates a locker notification document. Returns it with its Firestore ID.
  Future<LockerNotification> createLockerNotification(LockerNotification notification) async {
    _assertAvailable();
    try {
      final doc = await _notifications.add(notification.toMap());
      return notification.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Marks a notification as read.
  Future<void> markNotificationRead(String id) async {
    _assertAvailable();
    try {
      await _notifications.doc(id).update({'read': true});
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Marks every unread notification owned by [studentId] as read in a single
  /// batch. The Firestore rules allow only the owner to update, so the batch
  /// contains only the caller's own documents.
  Future<void> markAllRead(String studentId) async {
    _assertAvailable();
    if (studentId.isEmpty) return;
    try {
      final snap = await _notifications
          .where('studentId', isEqualTo: studentId)
          .where('read', isEqualTo: false)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _dbOrNull!.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  void _assertAvailable() {
    if (!isAvailable) {
      throw const AuthFailure('The database is unavailable. Please restart the app.');
    }
  }
}
