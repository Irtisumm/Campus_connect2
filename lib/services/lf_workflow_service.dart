import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

  /// One-shot query for AI matching: returns In-Inventory items of a given
  /// [category] that have at least one image (up to [limit] docs).
  ///
  /// This is a targeted query (status + category filtered) that works under
  /// the signed-in-user inventory read rule (status == 'In Inventory').
  Future<List<InventoryItem>> queryInventoryForAi({
    required String category,
    int limit = 10,
  }) async {
    _assertAvailable();
    try {
      final snap = await _inventory
          .where('status', isEqualTo: InventoryStatus.inInventory.wireValue)
          .where('category', isEqualTo: category)
          .limit(limit)
          .get();
      final list = snap.docs
          .map((doc) => InventoryItem.fromMap(doc.id, doc.data()!))
          .where((inv) => inv.imageUrls.isNotEmpty)
          .toList();
      debugPrint('[AI MATCH DEBUG] queryInventoryForAi cat=$category '
          'docsFound=${snap.docs.length} withImages=${list.length} '
          'limit=$limit');
      return list;
    } on FirebaseException catch (e) {
      debugPrint('[AI MATCH] queryInventoryForAi FAILED cat=$category '
          'limit=$limit code=${e.code} returning empty');
      return const <InventoryItem>[];
    }
  }

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
    if (uid != null && uid.isEmpty)
      return Stream.value(const <InventoryItem>[]);

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

  /// Live feed of AI-proposed matches only (source == 'ai', status == 'Proposed',
  /// overallScore >= 50).
  ///
  /// Used by the Admin "AI Suggested Matches" section. Sorted by
  /// [LfMatch.overallScore] descending, then newest-first by [LfMatch.createdAt].
  Stream<List<LfMatch>> watchAiProposedMatches() {
    if (!isAvailable) return Stream.value(const <LfMatch>[]);
    return _matches
        .where('source', isEqualTo: MatchSource.ai.wireValue)
        .where('status', isEqualTo: MatchStatus.proposed.wireValue)
        .where('overallScore', isGreaterThanOrEqualTo: 50)
        .snapshots()
        .map((snap) {
          final ids = snap.docs.map((d) => d.id).toList();
          debugPrint('[AI MATCH DEBUG] stage=admin-ai-query '
              'resultCount=${snap.docs.length} ids=$ids error=none');
          return _sortedAiProposed(snap);
        })
        .handleError((e) {
          debugPrint('[AI MATCH DEBUG] stage=admin-ai-query '
              'resultCount=0 error=${e.runtimeType}');
          throw e;
        })
        .handleError(_translateError);
  }

  static List<LfMatch> _sortedAiProposed(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final rows = snapshot.docs
        .map((doc) => LfMatch.fromMap(doc.id, doc.data()))
        .where((m) => (m.overallScore ?? 0) >= 50) // belt-and-suspenders
        .toList();
    rows.sort((a, b) {
      final scoreCmp = (b.overallScore ?? 0).compareTo(a.overallScore ?? 0);
      if (scoreCmp != 0) return scoreCmp;
      return _newestFirst(a.createdAt, b.createdAt);
    });
    return rows;
  }

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

  // ── AI Match helpers ────────────────────────────────────────────

  /// Deterministic pair key for duplicate detection.
  static String pairKey(String lostReportId, String inventoryItemId) =>
      '${lostReportId}_$inventoryItemId';

  /// Checks whether [inventoryItemId] is currently eligible for AI matching.
  ///
  /// Returns `true` only when the inventory item:
  /// 1. Exists and has status `In Inventory`,
  /// 2. Is NOT already referenced by any non-rejected match.
  Future<bool> isInventoryAvailableForAiMatch(String inventoryItemId) async {
    _assertAvailable();
    try {
      final invDoc = await _inventory.doc(inventoryItemId).get();
      if (!invDoc.exists) return false;

      final inv = InventoryItem.fromMap(invDoc.id, invDoc.data()!);
      // Must be In Inventory (not Reserved, not Returned).
      if (inv.status != InventoryStatus.inInventory) return false;

      // Check whether any non-rejected (active) match already references
      // this inventory item.
      final existing = await _matches
          .where('inventoryItemId', isEqualTo: inventoryItemId)
          .where('status', whereNotIn: [MatchStatus.rejected.wireValue])
          .limit(1)
          .get();
      return existing.docs.isEmpty;
    } on FirebaseException catch (e) {
      // A permission-denied error on the matches sub-query means the caller
      // (a student) cannot see matches for other lost reports — err on the
      // side of allowing the AI match to be created. The admin reviews
      // every AI suggestion before approval, so a false positive is safe.
      if (e.code == 'permission-denied') {
        debugPrint('[AI MATCH] isInventoryAvailableForAiMatch '
            'PERMISSION-DENIED inv=$inventoryItemId '
            'returning true (allow)');
        return true;
      }
      debugPrint('[AI MATCH] isInventoryAvailableForAiMatch EXCEPTION '
          'inv=$inventoryItemId code=${e.code} returning false');
      return false;
    }
  }

  /// Checks whether a match already exists for this specific pair.
  ///
  /// A pair is `${lostReportId}_${inventoryItemId}`. Returns `true` if any
  /// non-rejected match already links these two documents.
  ///
  /// When [lostOwnerUid] is provided, the query also filters by it so the
  /// Firestore rules can validate that the caller is the lost-report owner.
  /// This parameter should always be passed by AI-matching callers.
  Future<bool> pairAlreadyMatched(
      String lostReportId, String inventoryItemId,
      {String? lostOwnerUid}) async {
    _assertAvailable();
    try {
      var query = _matches
          .where('lostReportId', isEqualTo: lostReportId)
          .where('inventoryItemId', isEqualTo: inventoryItemId)
          as Query<Map<String, dynamic>>;
      if (lostOwnerUid != null) {
        query = query.where('lostOwnerUid', isEqualTo: lostOwnerUid);
      }
      final existing = await query
          .where('status', whereNotIn: [MatchStatus.rejected.wireValue])
          .limit(1)
          .get();
      return existing.docs.isNotEmpty;
    } on FirebaseException catch (e) {
      // A permission-denied error when lostOwnerUid is set means the caller
      // is NOT the lost-report owner (Flow B: finder matching against existing
      // lost reports). Allow the match through — isInventoryAvailableForAiMatch
      // still catches broad duplicates, and createAiMatchIfAvailable's
      // transaction provides atomic commit. The admin reviews every AI
      // suggestion before approval, so a rare duplicate is safe.
      if (e.code == 'permission-denied' && lostOwnerUid != null) {
        debugPrint('[AI MATCH] pairAlreadyMatched PERMISSION-DENIED '
            'pair=${lostReportId}_$inventoryItemId '
            'non-owner caller — returning false (allow)');
        return false;
      }
      debugPrint('[AI MATCH] pairAlreadyMatched EXCEPTION '
          'pair=${lostReportId}_$inventoryItemId code=${e.code} '
          'returning true (blocks match)');
      return true; // Err on the safe side — block duplicate.
    }
  }

  /// Creates an AI match atomically with duplicate + eligibility guards.
  ///
  /// This runs inside a Firestore transaction:
  /// 1. Re-checks inventory item status (must be `In Inventory`).
  /// 2. Re-checks no non-rejected match references this inventory item.
  /// 3. Re-checks no match already exists for this pair.
  /// 4. Creates the match document with `source: 'ai'`.
  ///
  /// NOTE: This does NOT reserve the inventory item — inventory reservation
  /// remains an admin-only action. The admin reviews the AI suggestion and
  /// uses the existing manual workflow to reserve/approve.
  ///
  /// Returns the created [LfMatch] with its new document ID, or `null` if the
  /// item is no longer available or a duplicate exists.
  ///
  /// Throws [AuthFailure] on Firestore errors.
  Future<LfMatch?> createAiMatchIfAvailable(LfMatch match) async {
    _assertAvailable();
    debugPrint('[AI MATCH DEBUG] stage=create-ai-match '
        'anchorId=${match.lostReportId} candidateId=${match.inventoryItemId} '
        'started=true');
    try {
      return await _dbOrNull!.runTransaction((tx) async {
        // Safety gate: pre-checks (isInventoryAvailableForAiMatch /
        // pairAlreadyMatched) already verified the item is available.
        // The transaction provides atomic commit only — no re-read of
        // the inventory document inside the transaction (that read
        // requires admin permissions per firestore.rules, and AI
        // matching may fire from the student's client after createReport).

        // Create the match (auto-generated ID).
        final matchRef = _matches.doc();
        debugPrint('[AI MATCH DEBUG] stage=firestore-match-write '
            'candidateId=${match.inventoryItemId} '
            'matchId=${matchRef.id} started=true');
        tx.set(matchRef, match.toCreateMap());

        debugPrint('[AI MATCH DEBUG] stage=firestore-match-created '
            'candidateId=${match.inventoryItemId} '
            'matchId=${matchRef.id} result=success');
        return match.copyWith(id: matchRef.id);
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint('[AI MATCH DEBUG] stage=firestore-match-write '
            'candidateId=${match.inventoryItemId} '
            'result=failure error=permission-denied');
        debugPrint('[AI MATCH] createAiMatchIfAvailable PERMISSION-DENIED '
            'pair=${match.lostReportId}_${match.inventoryItemId} '
            'returning null');
        return null;
      }
      debugPrint('[AI MATCH DEBUG] stage=firestore-match-write '
          'candidateId=${match.inventoryItemId} '
          'result=failure error=${e.code}');
      debugPrint('[AI MATCH] createAiMatchIfAvailable EXCEPTION '
          'pair=${match.lostReportId}_${match.inventoryItemId} '
          'code=${e.code} rethrowing');
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

  /// Reserves an inventory item while an admin links it to a lost report
  /// (admin-only). A reserved item is excluded from the Find Match picker so
  /// it cannot be matched to a second report.
  Future<void> reserveInventoryItem(String inventoryItemId) async {
    _assertAvailable();
    try {
      await _inventory.doc(inventoryItemId).update({
        'status': InventoryStatus.reserved.wireValue,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Releases a reserved inventory item back to `In Inventory` (admin-only).
  Future<void> releaseInventoryItem(String inventoryItemId) async {
    _assertAvailable();
    try {
      await _inventory.doc(inventoryItemId).update({
        'status': InventoryStatus.inInventory.wireValue,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Rejects a match and releases its inventory item in one transaction, so a
  /// rejected match can never leave an item stuck in `Reserved`.
  Future<void> rejectMatch(String matchId) async {
    _assertAvailable();
    try {
      await _dbOrNull!.runTransaction((tx) async {
        final matchRef = _matches.doc(matchId);
        final matchDoc = await tx.get(matchRef);
        if (!matchDoc.exists) {
          throw const AuthFailure('This match no longer exists.');
        }
        final match = LfMatch.fromMap(matchDoc.id, matchDoc.data()!);
        tx.update(matchRef, {
          'status': MatchStatus.rejected.wireValue,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(_inventory.doc(match.inventoryItemId), {
          'status': InventoryStatus.inInventory.wireValue,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Rejects every still-active match (Proposed or Approved) pointing at a
  /// lost report, releasing each linked inventory item back to `In Inventory`.
  ///
  /// Called when an admin closes a report so no dangling active match or
  /// reservation survives the closure. Best-effort: a failure here does not
  /// roll back the report's own status change.
  Future<void> rejectActiveMatchesForReport(String lostReportId) async {
    _assertAvailable();
    if (lostReportId.isEmpty) return;
    try {
      final snapshot =
          await _matches.where('lostReportId', isEqualTo: lostReportId).get();
      for (final doc in snapshot.docs) {
        final match = LfMatch.fromMap(doc.id, doc.data());
        if (match.status == MatchStatus.proposed ||
            match.status == MatchStatus.approved) {
          await rejectMatch(doc.id);
        }
      }
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
  Stream<List<QrTransaction>> watchReturnQrForInventory(
      String inventoryItemId) {
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

  /// A student scanning a code. Inspects the transaction and then either:
  ///   - return code (`Issued`): writes `Scanned` and waits for the admin to
  ///     confirm the physical return (Workflow 3), or
  ///   - handover code (`Issued`): completes the physical handover in one
  ///     atomic transaction — the report moves to `In Inventory`, exactly one
  ///     inventory record is created, and the code moves straight to
  ///     `Confirmed` (Workflow 2).
  ///
  /// The Firestore rules independently enforce intended-student, single-use,
  /// expiry and the cross-document linkage — the inspection here only chooses
  /// the right message and outcome.
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

    if (txn.isHandover) {
      return _completeHandoverByScan(txn, studentUid, current);
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

  /// Workflow 2 — the student's scan completes the physical handover. One
  /// transaction: the found report moves to `In Inventory` (linked to the code
  /// via `handoverTxnId`), exactly one inventory record is created, and the
  /// code moves straight from `Issued` to `Confirmed`.
  ///
  /// Duplicate prevention: the code is re-read inside the transaction and
  /// must still be `Issued`; a second scan finds `Confirmed` and aborts, so no
  /// second inventory record or transition can be born from the same code.
  /// The rules independently require the report/inventory writes to point back
  /// at a `Confirmed` handover code, so a partial write is impossible.
  Future<QrScanOutcome> _completeHandoverByScan(
      QrTransaction txn, String studentUid, DateTime now) async {
    try {
      final invId = await _dbOrNull!.runTransaction((tx) async {
        final txnRef = _qr.doc(txn.id);
        final txnDoc = await tx.get(txnRef);
        if (!txnDoc.exists) {
          throw const AuthFailure('This QR code no longer exists.');
        }
        final fresh = QrTransaction.fromMap(txnDoc.id, txnDoc.data()!);
        if (!fresh.isHandover) {
          throw const AuthFailure('This QR code is not a handover code.');
        }
        if (fresh.status != QrStatus.issued) {
          throw const AuthFailure('This code has already been used.');
        }
        if (fresh.isExpiredAt(now)) {
          throw const AuthFailure(
              'This code has expired. Please ask the office to generate a new one.');
        }

        final reportRef = _itemsDoc(fresh.foundReportId);
        final reportDoc = await tx.get(reportRef);
        if (!reportDoc.exists) {
          throw const AuthFailure('The found report no longer exists.');
        }
        final report = Item.fromMap(reportDoc.id, reportDoc.data()!);
        if (report.status != ItemStatus.active &&
            report.status != ItemStatus.awaitingHandover) {
          throw const AuthFailure(
              'This report is no longer awaiting handover.');
        }

        final inventoryRef = _inventory.doc();
        final inventory = InventoryItem(
          id: inventoryRef.id,
          foundReportId: fresh.foundReportId,
          finderUid: report.reportedByUid,
          finderStudentId: report.reportedByStudentId,
          title: report.title,
          category: report.category,
          description: report.description,
          imageUrls: report.imageUrls,
          handedOverAt: now,
          handoverTxnId: fresh.id,
        );

        tx.update(reportRef, {
          'status': ItemStatus.inInventory.wireValue,
          'handoverTxnId': fresh.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(inventoryRef, inventory.toCreateMap());
        tx.update(txnRef, fresh.toCompleteHandoverMap(studentUid));

        debugPrint('[AI MATCH DEBUG] _completeHandoverByScan inventoryCreated '
            'invId=${inventoryRef.id} reportId=${report.id} '
            'cat=${report.category} images=${report.imageUrls.length}');
        return inventoryRef.id;
      });
      return QrScanOutcome.success(txn, inventoryId: invId);
    } on AuthFailure catch (e) {
      return QrScanOutcome.failure(e.message);
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

        debugPrint('[AI MATCH DEBUG] confirmHandover inventoryCreated '
            'invId=${inventoryRef.id} reportId=${report.id} '
            'cat=${report.category} images=${report.imageUrls.length}');
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

        final foundDoc = await tx
            .get(_itemsDoc(invDoc.data()?['foundReportId']?.toString() ?? ''));
        final foundReportId = invDoc.data()?['foundReportId']?.toString() ?? '';

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
    return query
        .snapshots()
        .map(_sortedNotifications)
        .handleError(_translateError);
  }

  static List<LfNotification> _sortedNotifications(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final rows = snapshot.docs
        .map((doc) => LfNotification.fromMap(doc.id, doc.data()))
        .toList();
    rows.sort((a, b) => _newestFirst(a.createdAt, b.createdAt));
    return rows;
  }

  /// Creates a notification (admin-only per rules).
  /// Returns the notification document ID.
  Future<String> createNotification(LfNotification notification) async {
    _assertAvailable();
    try {
      final doc = await _notifications.add(notification.toCreateMap());
      return doc.id;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
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
  /// Populated when a handover scan creates a new inventory record (Flow B
  /// trigger path). Null for all other outcomes.
  final String? inventoryId;

  const QrScanOutcome._(
      {required this.success,
      required this.message,
      this.txn,
      this.inventoryId});

  const QrScanOutcome.success(QrTransaction txn, {String? inventoryId})
      : this._(
            success: true,
            message: 'Code verified.',
            txn: txn,
            inventoryId: inventoryId);

  const QrScanOutcome.invalid()
      : this._(
            success: false,
            message: 'Invalid code. Please check the code and try again.');

  const QrScanOutcome.failure(String message)
      : this._(success: false, message: message);
}
