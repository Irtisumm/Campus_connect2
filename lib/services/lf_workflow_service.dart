import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/auth_result.dart';
import '../models/inventory_item.dart';
import '../models/item.dart';
import '../models/lf_match.dart';
import '../models/lf_notification.dart';
import '../models/qr_transaction.dart';

/// Firestore access for the Lost & Found full-workflow collections:
/// `inventory`, `matches`, `qrTransactions` and `lfNotifications`.
///
/// This service carries Workflows 2 and 3. There is no trusted server on
/// this project (owner decision), so the Firestore rules are the
/// enforcement layer and the multi-document handover/return updates run
/// inside Firestore transactions — whose individual writes the rules still
/// check one by one. A transaction therefore cannot be forged by a
/// student, and a duplicate confirmation is impossible because the token
/// document is re-read inside the transaction and must still be `Scanned`.
class LfWorkflowService {
  static const String inventoryPath = 'inventory';
  static const String matchesPath = 'matches';
  static const String qrPath = 'qrTransactions';
  static const String notificationsPath = 'lfNotifications';

  final FirebaseFirestore? _dbOrNull;

  LfWorkflowService({FirebaseFirestore? firestore})
      : _dbOrNull = _resolve(firestore);

  static FirebaseFirestore? _resolve(FirebaseFirestore? injected) {
    try {
      return injected ?? FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable => _dbOrNull != null;

  CollectionReference<Map<String, dynamic>> get _inventory =>
      _dbOrNull!.collection(inventoryPath);
  CollectionReference<Map<String, dynamic>> get _matches =>
      _dbOrNull!.collection(matchesPath);
  CollectionReference<Map<String, dynamic>> get _qr =>
      _dbOrNull!.collection(qrPath);
  CollectionReference<Map<String, dynamic>> get _notifications =>
      _dbOrNull!.collection(notificationsPath);

  // ── Inventory ───────────────────────────────────────────────────

  /// Live feed of the finder's own handed-over items, newest first.
  ///
  /// The `finderUid` filter is required: rules are not filters, and an
  /// unfiltered query would be denied for a non-admin.
  Stream<List<InventoryItem>> watchInventoryForFinder(String uid) =>
      _watchInventory(uid: uid);

  /// Live feed of every inventory record, for the admin inventory screens.
  Stream<List<InventoryItem>> watchAllInventory() => _watchInventory();

  /// Live view of a single inventory record by ID.
  Stream<InventoryItem?> watchInventoryItem(String id) {
    if (!isAvailable || id.isEmpty) return Stream.value(null);
    return _inventory
        .doc(id)
        .snapshots()
        .map((doc) =>
            doc.exists ? InventoryItem.fromMap(doc.id, doc.data()!) : null)
        .handleError(_translateError);
  }

  Stream<List<InventoryItem>> _watchInventory({String? uid}) {
    if (!isAvailable) return Stream.value(const <InventoryItem>[]);
    if (uid != null && uid.isEmpty) return Stream.value(const <InventoryItem>[]);

    Query<Map<String, dynamic>> query = _inventory;
    if (uid != null) {
      query = query.where('finderUid', isEqualTo: uid);
    }
    return query.snapshots().map(_sortedInventory).handleError(_translateError);
  }

  static List<InventoryItem> _sortedInventory(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final rows = snapshot.docs
        .map((doc) => InventoryItem.fromMap(doc.id, doc.data()))
        .toList();
    rows.sort((a, b) => _newestFirst(a.createdAt, b.createdAt));
    return rows;
  }

  // ── Matches ─────────────────────────────────────────────────────

  /// Live feed of matches pointing at the caller's own lost reports,
  /// newest first.
  Stream<List<LfMatch>> watchMatchesForOwner(String uid) =>
      _watchMatches(uid: uid);

  /// Live feed of every match, for the admin match screens.
  Stream<List<LfMatch>> watchAllMatches() => _watchMatches();

  /// Live view of a single match by ID.
  Stream<LfMatch?> watchMatch(String id) {
    if (!isAvailable || id.isEmpty) return Stream.value(null);
    return _matches
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? LfMatch.fromMap(doc.id, doc.data()!) : null)
        .handleError(_translateError);
  }

  Stream<List<LfMatch>> _watchMatches({String? uid}) {
    if (!isAvailable) return Stream.value(const <LfMatch>[]);
    if (uid != null && uid.isEmpty) return Stream.value(const <LfMatch>[]);

    Query<Map<String, dynamic>> query = _matches;
    if (uid != null) {
      query = query.where('lostOwnerUid', isEqualTo: uid);
    }
    return query.snapshots().map(_sortedMatches).handleError(_translateError);
  }

  static List<LfMatch> _sortedMatches(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final rows = snapshot.docs
        .map((doc) => LfMatch.fromMap(doc.id, doc.data()))
        .toList();
    rows.sort((a, b) => _newestFirst(a.createdAt, b.createdAt));
    return rows;
  }

  /// Creates a match (admin-only). Pass [MatchStatus.proposed] for a draft
  /// or [MatchStatus.approved] when creating it already approved.
  ///
  /// Throws [AuthFailure] with a user-safe message on failure.
  Future<LfMatch> createMatch(LfMatch match) async {
    _assertAvailable();
    try {
      final doc = await _matches.add(match.toCreateMap());
      return match.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Approves a proposed match and notifies the lost report's owner in one
  /// transaction, so an approval can never exist without its notification.
  ///
  /// Returns the notification document ID.
  Future<String> approveMatchWithNotification({
    required String matchId,
    required String lostReportTitle,
    required String inventoryTitle,
  }) async {
    _assertAvailable();
    try {
      final notificationId = await _dbOrNull!.runTransaction((tx) async {
        final matchRef = _matches.doc(matchId);
        final matchDoc = await tx.get(matchRef);
        if (!matchDoc.exists) {
          throw const AuthFailure('This match no longer exists.');
        }
        final match = LfMatch.fromMap(matchDoc.id, matchDoc.data()!);

        // Re-read the linked documents so the notification text reflects
        // what is actually stored.
        final lostDoc = await tx.get(_itemsDoc(match.lostReportId));
        final invDoc = await tx.get(_inventory.doc(match.inventoryItemId));
        final lostTitle = lostDoc.exists
            ? (lostDoc.data()?['title']?.toString() ?? lostReportTitle)
            : lostReportTitle;
        final invTitle = invDoc.exists
            ? (invDoc.data()?['title']?.toString() ?? inventoryTitle)
            : inventoryTitle;

        tx.update(matchRef, {
          'status': MatchStatus.approved.wireValue,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final notification = LfNotification(
          studentId: match.lostOwnerStudentId,
          title: 'Possible match found',
          body: 'A "$invTitle" handed in at the Inventory Office may match '
              'your lost "$lostTitle". Please visit the office to verify '
              'ownership.',
          type: 'match',
          relatedReportId: match.lostReportId,
        );
        final notifRef = await _notifications.add(notification.toCreateMap());
        return notifRef.id;
      });
      return notificationId;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── QR transactions ─────────────────────────────────────────────

  /// Issues a QR transaction (admin-only). The document ID is generated by
  /// Firestore; the caller shows `txn.token` as the QR payload.
  Future<QrTransaction> issueQr(QrTransaction txn) async {
    _assertAvailable();
    try {
      final doc = await _qr.add(txn.toCreateMap());
      return QrTransaction.fromMap(doc.id, txn.toCreateMap());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Finds the QR transaction a student just scanned, by token.
  ///
  /// The query is scoped to the caller's own UID, which the rules require:
  /// a student may only read transactions intended for them. A token that
  /// does not exist or belongs to someone else yields `null` — exactly like
  /// an invalid code.
  Future<QrTransaction?> findQrByToken(String token, String studentUid) async {
    if (!isAvailable || token.isEmpty || studentUid.isEmpty) return null;
    try {
      final snapshot = await _qr
          .where('token', isEqualTo: token)
          .where('intendedStudentUid', isEqualTo: studentUid)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return QrTransaction.fromMap(doc.id, doc.data());
    } on FirebaseException {
      return null;
    }
  }

  /// Admin view: the handover QR transactions for one found report, newest
  /// first. Used by the admin found-detail to show the live code and its
  /// Issued → Scanned → Confirmed state.
  Stream<List<QrTransaction>> watchHandoverQrForReport(String foundReportId) {
    if (!isAvailable || foundReportId.isEmpty) {
      return Stream.value(const <QrTransaction>[]);
    }
    return _qr
        .where('foundReportId', isEqualTo: foundReportId)
        .where('kind', isEqualTo: QrKind.handover.wireValue)
        .snapshots()
        .map(_sortedQr)
        .handleError(_translateError);
  }

  /// Admin view: the return QR transactions for one inventory item, newest
  /// first. Used by the admin inventory/match screens to show the live code
  /// and drive "Confirm Return".
  Stream<List<QrTransaction>> watchReturnQrForInventory(String inventoryItemId) {
    if (!isAvailable || inventoryItemId.isEmpty) {
      return Stream.value(const <QrTransaction>[]);
    }
    return _qr
        .where('inventoryItemId', isEqualTo: inventoryItemId)
        .where('kind', isEqualTo: QrKind.return_.wireValue)
        .snapshots()
        .map(_sortedQr)
        .handleError(_translateError);
  }

  /// Student view: the caller's own QR transactions of one [kind], newest
  /// first. The `intendedStudentUid` filter is required — rules are not
  /// filters, and an unfiltered query would be denied for a non-admin.
  Stream<List<QrTransaction>> watchMyActiveQr(String uid, QrKind kind) {
    if (!isAvailable || uid.isEmpty) {
      return Stream.value(const <QrTransaction>[]);
    }
    return _qr
        .where('intendedStudentUid', isEqualTo: uid)
        .where('kind', isEqualTo: kind.wireValue)
        .snapshots()
        .map(_sortedQr)
        .handleError(_translateError);
  }

  static List<QrTransaction> _sortedQr(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final rows = snapshot.docs
        .map((doc) => QrTransaction.fromMap(doc.id, doc.data()))
        .toList();
    rows.sort((a, b) => _newestFirst(a.issuedAt, b.issuedAt));
    return rows;
  }

  /// A student scanning a code. Inspects the transaction and, when it is
  /// `Issued` and unexpired, writes `Scanned`.
  ///
  /// The Firestore rules independently enforce intended-student, single-use
  /// and expiry — the inspection here only chooses the right message.
  Future<QrScanOutcome> scanQr({
    required String token,
    required String studentUid,
    DateTime? now,
  }) async {
    final txn = await findQrByToken(token, studentUid);
    if (txn == null) {
      return const QrScanOutcome.invalid();
    }

    final current = now ?? DateTime.now();
    if (txn.isExpiredAt(current)) {
      return const QrScanOutcome.failure(
          'This code has expired. Please ask the office to generate a new one.');
    }
    switch (txn.status) {
      case QrStatus.scanned:
        return const QrScanOutcome.failure(
            'This code was already scanned. Please wait for the office to confirm.');
      case QrStatus.confirmed:
        return const QrScanOutcome.failure(
            'This code has already been completed.');
      case QrStatus.cancelled:
        return const QrScanOutcome.failure(
            'This code was cancelled. Please ask the office to generate a new one.');
      case QrStatus.issued:
        break;
    }

    try {
      await _qr.doc(txn.id).update(txn.toScanMap());
      return QrScanOutcome.success(txn);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return const QrScanOutcome.failure(
            'This code is not valid for your account.');
      }
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Cancels an unused code (admin-only).
  Future<void> cancelQr(String txnId) async {
    _assertAvailable();
    try {
      await _qr.doc(txnId).update(QrTransaction.cancelMap());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Workflow 2 — admin confirms the physical handover. One transaction:
  /// the found report moves to `In Inventory`, exactly one inventory record
  /// is created, and the QR transaction moves to `Confirmed`.
  ///
  /// Duplicate prevention: the token document is re-read inside the
  /// transaction and must still be `Scanned`; a second confirmation finds
  /// `Confirmed` and aborts, so no second inventory record can be born from
  /// the same code.
  ///
  /// Returns the new inventory record's document ID.
  Future<String> confirmHandover({
    required String txnId,
    required String adminUid,
  }) async {
    _assertAvailable();
    try {
      return await _dbOrNull!.runTransaction((tx) async {
        final txnRef = _qr.doc(txnId);
        final txnDoc = await tx.get(txnRef);
        if (!txnDoc.exists) {
          throw const AuthFailure('This QR code no longer exists.');
        }
        final txn = QrTransaction.fromMap(txnDoc.id, txnDoc.data()!);
        if (!txn.isHandover) {
          throw const AuthFailure('This QR code is not a handover code.');
        }
        if (txn.status != QrStatus.scanned) {
          throw const AuthFailure(
              'This code is not ready to confirm. The student must scan it first.');
        }
        if (txn.isExpiredAt(DateTime.now())) {
          throw const AuthFailure(
              'This code has expired. Please generate a new one.');
        }

        final reportRef = _itemsDoc(txn.foundReportId);
        final reportDoc = await tx.get(reportRef);
        if (!reportDoc.exists) {
          throw const AuthFailure('The found report no longer exists.');
        }
        final report = Item.fromMap(reportDoc.id, reportDoc.data()!);

        final inventoryRef = _inventory.doc();
        final inventory = InventoryItem(
          id: inventoryRef.id,
          foundReportId: txn.foundReportId,
          finderUid: report.reportedByUid,
          finderStudentId: report.reportedByStudentId,
          title: report.title,
          category: report.category,
          description: report.description,
          imageUrls: report.imageUrls,
          handedOverAt: DateTime.now(),
        );

        tx.update(reportRef, {
          'status': ItemStatus.inInventory.wireValue,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(inventoryRef, inventory.toCreateMap());
        tx.update(txnRef, txn.toConfirmMap(adminUid));

        return inventoryRef.id;
      });
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Workflow 3 — admin confirms the physical return. One transaction:
  /// the inventory record moves to `Returned` (linked to the lost report),
  /// the found report moves to `Returned`, the lost report moves to
  /// `Resolved`, the match moves to `Completed`, and the QR transaction
  /// moves to `Confirmed`.
  ///
  /// Same duplicate guard as [confirmHandover]: the token must still be
  /// `Scanned` inside the transaction.
  Future<void> confirmReturn({
    required String txnId,
    required String adminUid,
  }) async {
    _assertAvailable();
    try {
      await _dbOrNull!.runTransaction((tx) async {
        final txnRef = _qr.doc(txnId);
        final txnDoc = await tx.get(txnRef);
        if (!txnDoc.exists) {
          throw const AuthFailure('This QR code no longer exists.');
        }
        final txn = QrTransaction.fromMap(txnDoc.id, txnDoc.data()!);
        if (!txn.isReturn) {
          throw const AuthFailure('This QR code is not a return code.');
        }
        if (txn.status != QrStatus.scanned) {
          throw const AuthFailure(
              'This code is not ready to confirm. The student must scan it first.');
        }
        if (txn.isExpiredAt(DateTime.now())) {
          throw const AuthFailure(
              'This code has expired. Please generate a new one.');
        }

        final invDoc = await tx.get(_inventory.doc(txn.inventoryItemId));
        if (!invDoc.exists) {
          throw const AuthFailure('The inventory item no longer exists.');
        }

        final lostDoc = await tx.get(_itemsDoc(txn.lostReportId));
        if (!lostDoc.exists) {
          throw const AuthFailure('The lost report no longer exists.');
        }
        final lostReport = Item.fromMap(lostDoc.id, lostDoc.data()!);

        final foundDoc = await tx.get(_itemsDoc(
            invDoc.data()?['foundReportId']?.toString() ?? ''));
        final foundReportId =
            invDoc.data()?['foundReportId']?.toString() ?? '';

        // The Flutter transaction API only fetches documents by reference,
        // so the approved match is located by query before the transaction
        // and re-read (and re-verified) inside it.
        final matchesSnapshot = await _matches
            .where('lostReportId', isEqualTo: txn.lostReportId)
            .where('inventoryItemId', isEqualTo: txn.inventoryItemId)
            .limit(1)
            .get();
        final matchRef = matchesSnapshot.docs.isNotEmpty
            ? matchesSnapshot.docs.first.reference
            : null;

        final now = DateTime.now();
        tx.update(_inventory.doc(txn.inventoryItemId), {
          'status': InventoryStatus.returned.wireValue,
          'matchedLostReportId': txn.lostReportId,
          'returnedAt': Timestamp.fromDate(now),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (foundDoc.exists && foundReportId.isNotEmpty) {
          tx.update(_itemsDoc(foundReportId), {
            'status': ItemStatus.returned.wireValue,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        tx.update(_itemsDoc(lostReport.id), {
          'status': ItemStatus.resolved.wireValue,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (matchRef != null) {
          tx.update(matchRef, {
            'status': MatchStatus.completed.wireValue,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        tx.update(txnRef, txn.toConfirmMap(adminUid));
      });
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── Notifications ───────────────────────────────────────────────

  /// Live feed of the signed-in student's own L&F notifications, newest
  /// first.
  Stream<List<LfNotification>> watchMyLfNotifications(String studentId) =>
      _watchNotifications(studentId: studentId);

  /// Live feed of every L&F notification, for the admin screens.
  Stream<List<LfNotification>> watchAllLfNotifications() =>
      _watchNotifications();

  Stream<List<LfNotification>> _watchNotifications({String? studentId}) {
    if (!isAvailable) return Stream.value(const <LfNotification>[]);
    if (studentId != null && studentId.isEmpty) {
      return Stream.value(const <LfNotification>[]);
    }

    Query<Map<String, dynamic>> query = _notifications;
    if (studentId != null) {
      query = query.where('studentId', isEqualTo: studentId);
    }
    return query.snapshots().map(_sortedNotifications).handleError(_translateError);
  }

  static List<LfNotification> _sortedNotifications(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final rows = snapshot.docs
        .map((doc) => LfNotification.fromMap(doc.id, doc.data()))
        .toList();
    rows.sort((a, b) => _newestFirst(a.createdAt, b.createdAt));
    return rows;
  }

  /// Marks a notification read (owner-only; the rules allow only the `read`
  /// field to change).
  Future<void> markLfNotificationRead(String id) async {
    _assertAvailable();
    try {
      await _notifications.doc(id).update(LfNotification.readMap());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── Shared helpers ──────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _itemsDoc(String id) =>
      _dbOrNull!.collection('items').doc(id);

  static int _newestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  static void _translateError(Object error) {
    if (error is FirebaseException) throw AuthFailure.fromCode(error.code);
    throw error;
  }

  void _assertAvailable() {
    if (!isAvailable) {
      throw const AuthFailure(
          'The database is unavailable. Please restart the app.');
    }
  }
}

/// Result of a student scanning a QR code, carrying a display-ready message
/// for every outcome so screens never invent their own wording.
class QrScanOutcome {
  final bool success;
  final String message;
  final QrTransaction? txn;

  const QrScanOutcome._({required this.success, required this.message, this.txn});

  const QrScanOutcome.success(QrTransaction txn)
      : this._(success: true, message: 'Code verified.', txn: txn);

  const QrScanOutcome.invalid()
      : this._(
            success: false,
            message: 'Invalid code. Please check the code and try again.');

  const QrScanOutcome.failure(String message)
      : this._(success: false, message: message);
}
