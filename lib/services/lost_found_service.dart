import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/auth_result.dart';
import '../models/item.dart';

/// Firestore access for the Lost & Found `items` collection.
///
/// Screens talk to this class and never to Firestore directly. Every
/// [FirebaseException] is translated into an [AuthFailure] here, so no Firebase
/// type — and no raw Firebase error string — ever reaches the widget tree.
class LostFoundService {
  static const String collectionPath = 'items';

  final FirebaseFirestore? _dbOrNull;

  LostFoundService({FirebaseFirestore? firestore})
      : _dbOrNull = _resolve(firestore);

  static FirebaseFirestore? _resolve(FirebaseFirestore? injected) {
    try {
      return injected ?? FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable => _dbOrNull != null;

  CollectionReference<Map<String, dynamic>> get _items =>
      _dbOrNull!.collection(collectionPath);

  /// Writes a new lost or found report and returns it with its Firestore ID.
  ///
  /// Throws an [AuthFailure] with a user-safe message when the database is
  /// unreachable, the write is rejected, or the network is down.
  Future<Item> createItem(Item item) async {
    _assertAvailable();

    if (item.reportedByUid.isEmpty) {
      throw const AuthFailure(
          'Please sign in again before submitting a report.');
    }

    try {
      final doc = await _items.add(item.toCreateMap());
      return item.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Updates an existing report's editable fields.
  ///
  /// Writes [item.toUpdateMap()] — only `title`, `category`, `description`,
  /// `whereLost`, `imageUrls`, `status`, `isDeleted`, and `updatedAt`. The
  /// caller must ensure `item.id` is the Firestore document ID of a report
  /// the caller owns (or is an admin).
  ///
  /// The Firestore rules independently enforce that `type`,
  /// `reportedByUid`, and `reportedByStudentId` are unchanged, and that the
  /// status transition is permitted for the caller's role.
  ///
  /// Throws [AuthFailure] with a user-safe message on failure.
  Future<Item> updateItem(Item item) async {
    _assertAvailable();

    if (item.id.isEmpty) {
      throw const AuthFailure('This report cannot be updated.');
    }

    try {
      await _items.doc(item.id).update(item.toUpdateMap());
      return item;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Changes a report's status.
  ///
  /// The client must enforce the transition policy before calling this:
  /// a student may only close an active report (Active → Closed); an admin
  /// may set any valid status. The refined Firestore rule enforces the same
  /// restriction independently — a student attempting Resolved or Matched -
  /// Pending is denied at the database level.
  ///
  /// Throws [AuthFailure] with a user-safe message on failure.
  Future<void> updateStatus(String id, ItemStatus newStatus) async {
    _assertAvailable();

    if (id.isEmpty) {
      throw const AuthFailure('This report cannot be updated.');
    }

    try {
      await _items.doc(id).update({
        'status': newStatus.wireValue,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Soft-deletes a report by setting `isDeleted: true`.
  ///
  /// The document remains in Firestore (for admin history and any future
  /// match recovery) but is excluded from all `watch*` feeds, which filter
  /// by `isDeleted == false`.
  ///
  /// Throws [AuthFailure] with a user-safe message on failure.
  Future<void> softDelete(String id) async {
    _assertAvailable();

    if (id.isEmpty) {
      throw const AuthFailure('This report cannot be removed.');
    }

    try {
      await _items.doc(id).update({
        'isDeleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Live feed of the caller's own lost reports, newest first.
  Stream<List<Item>> watchMyLostItems(String uid) =>
      _watch(uid: uid, type: ItemType.lost);

  /// Live feed of the caller's own found reports, newest first.
  ///
  /// Identical to [watchMyLostItems] apart from the `type` filter — both read
  /// the same `items` collection, so a found report is just a document whose
  /// `type` is `found`.
  Stream<List<Item>> watchMyFoundItems(String uid) =>
      _watch(uid: uid, type: ItemType.found);

  /// Live feed of the caller's own lost AND found reports, for the Lost &
  /// Found hub's combined summary counts.
  ///
  /// One query (no `type` filter) instead of merging two, so the hub sees a
  /// single consistent snapshot rather than two streams that emit
  /// independently. The caller splits the result into lost/found by
  /// [Item.isLost] / [Item.isFound] if it needs the breakdown.
  Stream<List<Item>> watchMyAllItems(String uid) => _watch(uid: uid);

  /// Live feed of every lost report across all students, for the admin lists.
  ///
  /// No `reportedByUid` filter — unlike the `watchMy*` feeds, an admin sees
  /// everyone's reports. The `items` read rule admits this via `isAdmin()`
  /// (rules are not filters: the rule is evaluated against each returned
  /// document, and `isAdmin()` passes them all).
  Stream<List<Item>> watchAllLostItems() => _watch(type: ItemType.lost);

  /// Live feed of every found report across all students, for the admin lists.
  ///
  /// Same contract as [watchAllLostItems] with `type` `found`.
  Stream<List<Item>> watchAllFoundItems() => _watch(type: ItemType.found);

  /// Live feed of every lost AND found report across all students, for the
  /// admin dashboard's combined summary counts.
  ///
  /// One query (no `type` filter) instead of merging two streams, mirroring
  /// [watchMyAllItems] on the admin side: the dashboard sees a single
  /// consistent snapshot and splits the result into lost/found by
  /// [Item.isLost] / [Item.isFound] when it needs the breakdown.
  Stream<List<Item>> watchAllItems() => _watch();

  /// Live feed behind the Notifications screen.
  ///
  /// There is no `notifications` collection: `firestore.rules` governs only
  /// `users` and `items`, and Firestore is default-deny, so one could be
  /// neither read nor written. The feed is therefore derived from the reports
  /// themselves — every report the caller may already see is one notification
  /// row, and any change to it (a status transition, an edit) re-emits the row
  /// live.
  ///
  /// Passing `uid` selects the student shape (own reports only); omitting it
  /// selects the admin shape, exactly as the list feeds do.
  Stream<List<Item>> watchNotificationItems({String? uid}) => _watch(uid: uid);

  /// Live view of a single report by its Firestore document ID, for the detail
  /// screens.
  ///
  /// Emits `null` when the document does not exist — the screen renders its
  /// "not found" state from that. A soft-deleted report still exists and is
  /// readable (the `items` read rule checks ownership, not `isDeleted`), so it
  /// is emitted as an [Item] with [Item.isDeleted] `true`; the screen renders
  /// its "deleted" state from that flag rather than treating it as missing.
  ///
  /// Like the `watchMy*` feeds, raw [FirebaseException]s are translated to
  /// [AuthFailure] here so a permission-denied or offline failure reaches the
  /// widget tree as a display-ready message — never a Firebase type.
  Stream<Item?> watchItem(String id) {
    // An unavailable database or an empty ID yields `null` (the "not found"
    // state) instead of an error: the detail screen can do nothing about either.
    if (!isAvailable || id.isEmpty) return Stream.value(null);

    return _items
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? Item.fromMap(doc.id, doc.data()!) : null)
        .handleError(
          (Object error) =>
              throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// The single query core behind every `watchMy*` / `watchAll*` feed.
  ///
  /// Both the student feeds (filtered by `reportedByUid`) and the admin feeds
  /// (no owner filter) run through here, so the mapping, client-side sort and
  /// error translation exist in exactly one place.
  ///
  /// The `reportedByUid` filter is not optional for a *student* caller:
  /// Firestore rules are not filters, so the `items` read rule is evaluated
  /// against every document the query would return and rejects the whole query
  /// if any document fails — an unfiltered-by-uid query is denied outright for
  /// a non-admin. An admin's unfiltered query passes via `isAdmin()`. Passing
  /// `uid: null` selects the admin shape.
  ///
  /// Soft-deleted reports are excluded here rather than in the UI, so no screen
  /// has to remember to check [Item.isDeleted].
  Stream<List<Item>> _watch({String? uid, ItemType? type}) {
    // An unavailable database, or a signed-out caller when filtering by uid,
    // yields an empty list rather than an error: the screen shows its normal
    // empty state instead of a failure the user can do nothing about.
    if (!isAvailable) return Stream.value(const <Item>[]);
    if (uid != null && uid.isEmpty) return Stream.value(const <Item>[]);

    Query<Map<String, dynamic>> query =
        _items.where('isDeleted', isEqualTo: false);
    if (uid != null) {
      query = query.where('reportedByUid', isEqualTo: uid);
    }
    if (type != null) {
      query = query.where('type', isEqualTo: type.wireValue);
    }

    return query
        .snapshots()
        .map(_sortedNewestFirst)
        // Stream errors bypass try/catch, so they are translated here. Without
        // this a raw FirebaseException would surface in `snapshot.error` and
        // land in the widget tree.
        .handleError(
          (Object error) =>
              throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Maps a snapshot to a list sorted newest-first by `createdAt`.
  ///
  /// Client-side so no composite Firestore index is required; null dates sort
  /// last so a report whose server timestamp has not resolved yet does not jump
  /// to the top of the list.
  static List<Item> _sortedNewestFirst(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final items =
        snapshot.docs.map((doc) => Item.fromMap(doc.id, doc.data())).toList();
    items.sort((a, b) {
      final aDate = a.createdAt;
      final bDate = b.createdAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return items;
  }

  void _assertAvailable() {
    if (!isAvailable) {
      throw const AuthFailure(
          'The database is unavailable. Please restart the app.');
    }
  }
}
