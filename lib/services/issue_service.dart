import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/auth_result.dart';
import '../models/issue.dart';

/// Firestore access for the Issues `issues` collection.
///
/// Mirrors [LostFoundService] exactly: screens talk to this class and never to
/// Firestore directly, and every [FirebaseException] is translated into an
/// [AuthFailure] here so no Firebase type — and no raw Firebase error string —
/// ever reaches the widget tree.
class IssueService {
  static const String collectionPath = 'issues';

  final FirebaseFirestore? _dbOrNull;

  IssueService({FirebaseFirestore? firestore}) : _dbOrNull = _resolve(firestore);

  static FirebaseFirestore? _resolve(FirebaseFirestore? injected) {
    try {
      return injected ?? FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable => _dbOrNull != null;

  CollectionReference<Map<String, dynamic>> get _issues =>
      _dbOrNull!.collection(collectionPath);

  /// Writes a new issue and returns it with its Firestore ID.
  ///
  /// Throws an [AuthFailure] with a user-safe message when the database is
  /// unreachable, the write is rejected, or the network is down.
  Future<Issue> createIssue(Issue issue) async {
    _assertAvailable();
    try {
      final doc = await _issues.add(issue.toMap());
      return issue.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Overwrites an existing issue. Ownership and identity fields are enforced
  /// by the security rules, not here.
  Future<void> updateIssue(Issue issue) async {
    _assertAvailable();
    try {
      await _issues.doc(issue.id).update(issue.toMap());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Moves an issue to a new status, stamping `updatedDate`.
  Future<void> updateIssueStatus(String id, String status) async {
    _assertAvailable();
    try {
      await _issues.doc(id).update({
        'status': status,
        'updatedDate': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Hard-deletes an issue. Kept for parity with the CRUD surface; the current
  /// rules deny deletes from the client.
  Future<void> deleteIssue(String id) async {
    _assertAvailable();
    try {
      await _issues.doc(id).delete();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Fetches a single issue by its Firestore document ID, or `null` when it
  /// does not exist.
  Future<Issue?> getIssue(String id) async {
    _assertAvailable();
    try {
      final doc = await _issues.doc(id).get();
      return doc.exists ? Issue.fromMap(doc.id, doc.data()!) : null;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Live feed of the signed-in student's own issues, newest first.
  Stream<List<Issue>> watchMyIssues(String studentId) =>
      _watch(studentId: studentId);

  /// Live feed of every issue across all students, for the admin list.
  ///
  /// No `studentId` filter — an admin sees everyone's issues. The `issues`
  /// read rule admits this via `isAdmin()`.
  Stream<List<Issue>> watchAllIssues() => _watch();

  /// Live view of a single issue by its Firestore document ID, for the detail
  /// screens. Emits `null` when the document does not exist.
  Stream<Issue?> watchIssue(String id) {
    if (!isAvailable || id.isEmpty) return Stream.value(null);
    return _issues
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? Issue.fromMap(doc.id, doc.data()!) : null)
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Live feed of an issue's status-transition history, oldest first.
  ///
  /// History lives in the `issues/{id}/history` subcollection — one document
  /// per transition — so it reads under the parent issue's read rule and needs
  /// no rules of its own. Emits an empty list when the issue has no history or
  /// the database is unavailable, matching the screen's "no timeline" state.
  Stream<List<IssueHistory>> watchIssueHistory(String id) {
    if (!isAvailable || id.isEmpty) return Stream.value(const <IssueHistory>[]);
    return _issues
        .doc(id)
        .collection('history')
        .snapshots()
        .map((snap) {
          final entries = snap.docs
              .map((doc) => IssueHistory.fromMap(doc.data()))
              .toList();
          entries.sort((a, b) => a.date.compareTo(b.date));
          return entries;
        })
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// The single query core behind the `watchMy*` / `watchAll*` feeds.
  ///
  /// The `studentId` filter is not optional for a *student* caller: Firestore
  /// rules are not filters, so the read rule is evaluated against every
  /// document the query would return and rejects the whole query if any
  /// document fails. An admin's unfiltered query passes via `isAdmin()`.
  /// Passing `studentId: null` selects the admin shape.
  Stream<List<Issue>> _watch({String? studentId}) {
    if (!isAvailable) return Stream.value(const <Issue>[]);
    if (studentId != null && studentId.isEmpty) {
      return Stream.value(const <Issue>[]);
    }

    Query<Map<String, dynamic>> query = _issues;
    if (studentId != null) {
      query = query.where('studentId', isEqualTo: studentId);
    }

    return query
        .snapshots()
        .map(_sortedNewestFirst)
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Maps a snapshot to a list sorted newest-first by `createdDate`.
  ///
  /// Client-side so no composite Firestore index is required.
  static List<Issue> _sortedNewestFirst(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final issues = snapshot.docs
        .map((doc) => Issue.fromMap(doc.id, doc.data()))
        .toList();
    issues.sort((a, b) => b.createdDate.compareTo(a.createdDate));
    return issues;
  }

  void _assertAvailable() {
    if (!isAvailable) {
      throw const AuthFailure('The database is unavailable. Please restart the app.');
    }
  }
}
