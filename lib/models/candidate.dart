import 'firestore_codecs.dart';

/// A candidate standing in the Student Council Elections, stored as one
/// document in the `electionCandidates` collection.
///
/// Mirrors [Event] / [Locker]: the mock model in `lib/data/mock_data.dart`
/// was promoted to a Firestore-ready model via [Candidate.fromMap] /
/// [Candidate.toMap]. Every field the mock model exposed is preserved — only
/// serialisation was added, nothing was renamed or dropped.
///
/// The document is world-readable to signed-in users once published (see
/// `firestore.rules`), exactly like a published `events` document. Writes are
/// admin-only: candidates are published by the Elections Admin, not by
/// students.
class Candidate {
  /// Firestore document ID — also the human candidate code (e.g. `C-001`).
  final String id;
  final String name;
  final String programme;
  final String position;
  final String manifesto;

  /// 'Pending' or 'Published'. Admin-only transitions are enforced by the
  /// security rules, mirroring the `events` status lifecycle.
  final String status;

  const Candidate({
    required this.id,
    required this.name,
    required this.programme,
    required this.position,
    required this.manifesto,
    this.status = 'Published',
  });

  /// Builds a [Candidate] from a Firestore document map.
  ///
  /// [id] is the Firestore document key — pass it explicitly when reading a
  /// snapshot (`Candidate.fromMap(doc.id, doc.data())`).
  factory Candidate.fromMap(String id, Map<String, dynamic> data) {
    return Candidate(
      id: id,
      name: asString(data['name']),
      programme: asString(data['programme']),
      position: asString(data['position']),
      manifesto: asString(data['manifesto']),
      status: asString(data['status']).isEmpty
          ? 'Published'
          : asString(data['status']),
    );
  }

  /// The payload written when the document is created or replaced.
  ///
  /// [id] is deliberately absent — the Firestore document key is the identity.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'programme': programme,
      'position': position,
      'manifesto': manifesto,
      'status': status,
    };
  }

  Candidate copyWith({
    String? id,
    String? name,
    String? programme,
    String? position,
    String? manifesto,
    String? status,
  }) {
    return Candidate(
      id: id ?? this.id,
      name: name ?? this.name,
      programme: programme ?? this.programme,
      position: position ?? this.position,
      manifesto: manifesto ?? this.manifesto,
      status: status ?? this.status,
    );
  }
}