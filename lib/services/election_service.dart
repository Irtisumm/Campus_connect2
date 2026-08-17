import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/auth_result.dart';
import '../models/candidate.dart';
import '../models/election_meta.dart';

/// Firestore access for the Elections subsystem: the `electionCandidates`
/// and `electionMeta` collections.
///
/// Mirrors [EventService] / [LockerService] exactly: screens talk to
/// [AppState], [AppState] talks to this class, and nothing else touches
/// Firestore. Every [FirebaseException] is translated into an [AuthFailure]
/// here so no Firebase type — and no raw Firebase error string — ever reaches
/// the widget tree.
///
/// This class is deliberately thin. It knows how to read and write documents;
/// it does not decide *when* a candidate may be published. That composition
/// belongs in [AppState], exactly as it does for events.
class ElectionService {
  static const String candidatesPath = 'electionCandidates';
  static const String metaPath = 'electionMeta';

  /// The statuses a candidate moves through before it is published. These are
  /// the documents that appear in the admin review queue, mirroring
  /// [EventService.reviewStatuses].
  static const List<String> reviewStatuses = <String>[
    'Pending',
  ];

  final FirebaseFirestore? _dbOrNull;

  ElectionService({FirebaseFirestore? firestore})
      : _dbOrNull = _resolve(firestore);

  static FirebaseFirestore? _resolve(FirebaseFirestore? injected) {
    try {
      return injected ?? FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable => _dbOrNull != null;

  CollectionReference<Map<String, dynamic>> get _candidates =>
      _dbOrNull!.collection(candidatesPath);

  CollectionReference<Map<String, dynamic>> get _meta =>
      _dbOrNull!.collection(metaPath);

  // ── CANDIDATES ──────────────────────────────────────────────────

  /// Live feed of published candidates, for the student elections info screen.
  /// This is the only candidate query a student may run, because a published
  /// candidate is public to signed-in users by design — mirroring
  /// [EventService.watchPublishedEvents].
  Stream<List<Candidate>> watchPublishedCandidates() =>
      _watchCandidates(statuses: const <String>['Published']);

  /// Live feed of every candidate, for the admin dashboard. Mirrors
  /// [EventService.watchEvents].
  Stream<List<Candidate>> watchAllCandidates() => _watchCandidates();

  /// Live view of a single candidate by its Firestore document ID. Emits
  /// `null` when the document does not exist.
  Stream<Candidate?> watchCandidate(String id) {
    if (!isAvailable || id.isEmpty) return Stream.value(null);
    return _candidates
        .doc(id)
        .snapshots()
        .map((doc) =>
            doc.exists ? Candidate.fromMap(doc.id, doc.data()!) : null)
        .handleError(
          (Object error) =>
              throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// The single query core behind every candidate feed.
  ///
  /// Sorting is client-side (by document id) so no composite Firestore index
  /// is required, matching [EventService._watchEvents].
  Stream<List<Candidate>> _watchCandidates({List<String>? statuses}) {
    if (!isAvailable) return Stream.value(const <Candidate>[]);

    Query<Map<String, dynamic>> query = _candidates;
    if (statuses != null) {
      query = query.where('status', whereIn: statuses);
    }

    return query
        .snapshots()
        .map((snap) {
          final candidates = snap.docs
              .map((doc) => Candidate.fromMap(doc.id, doc.data()))
              .toList();
          candidates.sort((a, b) => a.id.compareTo(b.id));
          return candidates;
        })
        .handleError(
          (Object error) =>
              throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Fetches a single candidate by its document ID, or `null` when it does
  /// not exist.
  Future<Candidate?> getCandidate(String id) async {
    _assertAvailable();
    try {
      final doc = await _candidates.doc(id).get();
      return doc.exists ? Candidate.fromMap(doc.id, doc.data()!) : null;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Writes a new candidate and returns it with its Firestore ID.
  Future<Candidate> createCandidate(Candidate candidate) async {
    _assertAvailable();
    try {
      final doc = await _candidates.add(candidate.toMap());
      return candidate.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Overwrites an existing candidate. Status transitions are enforced by
  /// the security rules, not here.
  Future<void> updateCandidate(Candidate candidate) async {
    _assertAvailable();
    try {
      await _candidates.doc(candidate.id).update(candidate.toMap());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Partial update of a candidate document — used for status transitions
  /// (publish / unpublish) where a full overwrite would be wasteful. Mirrors
  /// [EventService.patchEvent].
  Future<void> patchCandidate(String id, Map<String, dynamic> fields) async {
    _assertAvailable();
    try {
      await _candidates.doc(id).update(fields);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Permanently removes a candidate. Only an admin may do this — enforced by
  /// the security rules.
  Future<void> deleteCandidate(String id) async {
    _assertAvailable();
    try {
      await _candidates.doc(id).delete();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── ELECTION META ───────────────────────────────────────────────

  /// Live view of the single published election configuration document.
  ///
  /// There is one document per election cycle, keyed by a stable id (e.g.
  /// `election_2026`). The student screen watches this stream so the page
  /// updates live when the admin publishes new content.
  Stream<ElectionMeta?> watchPublishedElectionMeta() =>
      _watchElectionMeta(status: 'Published');

  /// Live view of the election configuration document regardless of status,
  /// for the admin manage screen.
  Stream<ElectionMeta?> watchElectionMeta(String id) {
    if (!isAvailable || id.isEmpty) return Stream.value(null);
    return _meta
        .doc(id)
        .snapshots()
        .map((doc) =>
            doc.exists ? ElectionMeta.fromMap(doc.id, doc.data()!) : null)
        .handleError(
          (Object error) =>
              throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Live feed of every election configuration document, for the admin
  /// management and archive screens. Active vs archived is decided by the
  /// caller via [ElectionMeta.isArchived], mirroring how
  /// [watchAllCandidates] leaves status filtering to its caller.
  Stream<List<ElectionMeta>> watchAllElectionMeta() {
    if (!isAvailable) return Stream.value(const <ElectionMeta>[]);
    return _meta
        .snapshots()
        .map((snap) {
          final metas = snap.docs
              .map((doc) => ElectionMeta.fromMap(doc.id, doc.data()))
              .toList();
          metas.sort((a, b) => a.id.compareTo(b.id));
          return metas;
        })
        .handleError(
          (Object error) =>
              throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  Stream<ElectionMeta?> _watchElectionMeta({required String status}) {
    if (!isAvailable) return Stream.value(null);
    return _meta
        .where('status', isEqualTo: status)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : ElectionMeta.fromMap(
                snap.docs.first.id, snap.docs.first.data()))
        .handleError(
          (Object error) =>
              throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Fetches the election configuration by its document ID, or `null` when
  /// it does not exist.
  Future<ElectionMeta?> getElectionMeta(String id) async {
    _assertAvailable();
    try {
      final doc = await _meta.doc(id).get();
      return doc.exists ? ElectionMeta.fromMap(doc.id, doc.data()!) : null;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Writes a new election configuration and returns it with its Firestore ID.
  Future<ElectionMeta> createElectionMeta(ElectionMeta meta) async {
    _assertAvailable();
    try {
      final stamped = meta.copyWith(createdAt: meta.createdAt ?? _todayIso());
      final doc = await _meta.add(stamped.toMap());
      return stamped.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Overwrites an existing election configuration. Status transitions are
  /// enforced by the security rules, not here.
  Future<void> updateElectionMeta(ElectionMeta meta) async {
    _assertAvailable();
    try {
      await _meta.doc(meta.id).update(meta.toMap());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Partial update of the election configuration document — used for status
  /// transitions (publish / unpublish).
  Future<void> patchElectionMeta(
      String id, Map<String, dynamic> fields) async {
    _assertAvailable();
    try {
      await _meta.doc(id).update(fields);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Moves an election into the Admin Archive by flipping its status to
  /// 'Archived'. The document is preserved — [watchAllElectionMeta] still
  /// emits it and the archive screen renders it from there.
  Future<void> archiveElectionMeta(
    String id, {
    required String previousStatus,
    required String archivedBy,
    required String archivedAt,
  }) =>
      patchElectionMeta(id, {
        'status': 'Archived',
        'previousStatus': previousStatus,
        'archivedBy': archivedBy,
        'archivedAt': archivedAt,
      });

  /// Restores an archived election to the status it held before archiving
  /// and clears the archive audit fields.
  Future<void> restoreElectionMeta(String id, {required String previousStatus}) =>
      patchElectionMeta(id, {
        'status': previousStatus,
        'previousStatus': null,
        'archivedBy': null,
        'archivedAt': null,
      });

  /// Unused by the UI: the security rules deny hard deletes so an election is
  /// archived via `status: 'Archived'` instead of being destroyed.
  Future<void> deleteElectionMeta(String id) async {
    _assertAvailable();
    try {
      await _meta.doc(id).delete();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  void _assertAvailable() {
    if (!isAvailable) {
      throw AuthFailure.fromCode('unavailable');
    }
  }

  static String _todayIso() =>
      DateTime.now().toIso8601String().split('T').first;
}