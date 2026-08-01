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
      throw const AuthFailure('Please sign in again before submitting a report.');
    }

    try {
      final doc = await _items.add(item.toCreateMap());
      return item.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Live feed of the caller's own lost reports, newest first.
  Stream<List<Item>> watchMyLostItems(String uid) =>
      _watchMine(uid, ItemType.lost);

  /// Live feed of the caller's own found reports, newest first.
  ///
  /// Identical to [watchMyLostItems] apart from the `type` filter — both read
  /// the same `items` collection, so a found report is just a document whose
  /// `type` is `found`.
  Stream<List<Item>> watchMyFoundItems(String uid) =>
      _watchMine(uid, ItemType.found);

  /// Live feed of the caller's own lost AND found reports, for the Lost &
  /// Found hub's combined summary counts.
  ///
  /// One query (no `type` filter) instead of merging two, so the hub sees a
  /// single consistent snapshot rather than two streams that emit
  /// independently. The caller splits the result into lost/found by
  /// [Item.isLost] / [Item.isFound] if it needs the breakdown — the hub's
  /// status chips do exactly that.
  Stream<List<Item>> watchMyAllItems(String uid) {
    // An unavailable database or a signed-out caller yields an empty list
    // rather than an error, matching [watchMyLostItems] / [watchMyFoundItems].
    if (!isAvailable || uid.isEmpty) return Stream.value(const <Item>[]);
    // No `type` filter, so this is a different query shape from `_watchMine`;
    // the body is otherwise identical, so it calls the same private core.
    return _watchAll(uid);
  }

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
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// The shared query behind both `watchMy*` feeds.
  ///
  /// The `reportedByUid` filter is not optional. Firestore rules are not
  /// filters — the `items` read rule is evaluated against every document the
  /// query would return and rejects the whole query if any document fails, so
  /// an unfiltered query is denied outright for a non-admin caller.
  ///
  /// Soft-deleted reports are excluded here rather than in the UI, so no screen
  /// has to remember to check [Item.isDeleted].
  Stream<List<Item>> _watchMine(String uid, ItemType type) {
    // An unavailable database or a signed-out caller yields an empty list
    // rather than an error: the screen shows its normal empty state instead of
    // a failure the user can do nothing about.
    if (!isAvailable || uid.isEmpty) return Stream.value(const <Item>[]);

    return _items
        .where('reportedByUid', isEqualTo: uid)
        .where('type', isEqualTo: type.wireValue)
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) => Item.fromMap(doc.id, doc.data()))
              .toList();
          // Sorted client-side so no composite Firestore index is required.
          items.sort((a, b) {
            final aDate = a.createdAt;
            final bDate = b.createdAt;
            if (aDate == null && bDate == null) return 0;
            if (aDate == null) return 1;
            if (bDate == null) return -1;
            return bDate.compareTo(aDate);
          });
          return items;
        })
        // Stream errors bypass try/catch, so they are translated here. Without
        // this a raw FirebaseException would surface in `snapshot.error` and
        // land in the widget tree.
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// The combined-query core behind [watchMyAllItems].
  ///
  /// Same contract as [_watchMine] minus the `type` filter, so the hub gets one
  /// snapshot covering both report kinds in one read rather than merging two
  /// streams that emit on independent schedules.
  Stream<List<Item>> _watchAll(String uid) {
    // An unavailable database or a signed-out caller yields an empty list
    // rather than an error: the hub shows its normal empty state instead of a
    // failure it can do nothing about.
    if (!isAvailable || uid.isEmpty) return Stream.value(const <Item>[]);

    return _items
        .where('reportedByUid', isEqualTo: uid)
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) => Item.fromMap(doc.id, doc.data()))
              .toList();
          // Sorted client-side so no composite Firestore index is required.
          items.sort((a, b) {
            final aDate = a.createdAt;
            final bDate = b.createdAt;
            if (aDate == null && bDate == null) return 0;
            if (aDate == null) return 1;
            if (bDate == null) return -1;
            return bDate.compareTo(aDate);
          });
          return items;
        })
        // Stream errors bypass try/catch, so they are translated here. Without
        // this a raw FirebaseException would surface in `snapshot.error` and
        // land in the widget tree.
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  void _assertAvailable() {
    if (!isAvailable) {
      throw const AuthFailure('The database is unavailable. Please restart the app.');
    }
  }
}
