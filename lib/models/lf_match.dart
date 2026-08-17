import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of a match, stored in `matches/{id}.status`.
///
/// Matches can be created manually by an admin (`source: 'manual'`) or
/// automatically by the AI matching pipeline (`source: 'ai'`). Both enter
/// as `Proposed` and follow the same approval/rejection lifecycle.
///
/// `Proposed` — draft not yet approved; `Approved` — confirmed possible-match
/// shown to the lost report's owner; `Completed` — set by the return
/// transaction once the item is physically back with its owner; `Rejected` —
/// admin dismisses a proposed match (the linked inventory item is released
/// back to `In Inventory`).
enum MatchStatus {
  proposed('Proposed'),
  approved('Approved'),
  completed('Completed'),
  rejected('Rejected');

  const MatchStatus(this.wireValue);
  final String wireValue;

  static MatchStatus fromWire(Object? value,
      {MatchStatus fallback = MatchStatus.proposed}) {
    final raw = value?.toString();
    for (final status in MatchStatus.values) {
      if (status.wireValue == raw) return status;
    }
    return fallback;
  }
}

/// Who/what created this match.
enum MatchSource {
  manual('manual'),
  ai('ai');

  const MatchSource(this.wireValue);
  final String wireValue;

  static MatchSource fromWire(Object? value,
      {MatchSource fallback = MatchSource.manual}) {
    final raw = value?.toString();
    for (final s in MatchSource.values) {
      if (s.wireValue == raw) return s;
    }
    return fallback;
  }
}

/// Evidence features for AI match transparency.
class MatchEvidence {
  final List<String> matchingFeatures;
  final List<String> conflictingFeatures;

  const MatchEvidence({
    this.matchingFeatures = const [],
    this.conflictingFeatures = const [],
  });

  Map<String, dynamic> toMap() => {
        'matchingFeatures': matchingFeatures,
        'conflictingFeatures': conflictingFeatures,
      };

  factory MatchEvidence.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const MatchEvidence();
    return MatchEvidence(
      matchingFeatures:
          List<String>.from(data['matchingFeatures'] ?? const []),
      conflictingFeatures:
          List<String>.from(data['conflictingFeatures'] ?? const []),
    );
  }
}

/// A document from the Firestore `matches` collection.
///
/// Links one inventory item to one lost report. Only the lost report's owner
/// may read it (besides admins) — the student detail screen renders a safe
/// summary (item title/category/status), never finder identity or contact
/// details.
class LfMatch {
  /// Firestore document ID. Empty on an object that has not been written yet.
  final String id;

  final String lostReportId;
  final String inventoryItemId;

  /// Firebase Authentication UID of the lost report's owner — the intended
  /// recipient of the match notification and the return QR.
  final String lostOwnerUid;

  /// Campus Student ID of the owner (e.g. `S001`), denormalised for display
  /// and for the notification recipient key.
  final String lostOwnerStudentId;

  /// Firebase Authentication UID of the finder who handed in the inventory item.
  /// Used by the Firestore create rule to allow the finder (Flow B caller) to
  /// create AI-proposed matches without owning the lost report.
  final String finderUid;

  final MatchStatus status;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // ── AI match fields (nullable — absent on manual matches) ──────────

  /// `'ai'` or `'manual'`. Defaults to `'manual'` for backward compatibility.
  final MatchSource source;

  /// Weighted 0-100 overall score computed by the Worker.
  final int? overallScore;

  /// 0-100 per-factor scores from the AI model.
  final int? visualScore;
  final int? titleScore;
  final int? descriptionScore;
  final int? categoryScore;
  final int? locationScore;
  final int? timeScore;

  /// AI confidence in its own assessment (0-100).
  final int? confidence;

  /// One-sentence AI explanation of the strongest evidence.
  final String? reason;

  /// Structured evidence features (matchingFeatures, conflictingFeatures).
  final MatchEvidence? evidence;

  // ── Derived ────────────────────────────────────────────────────────

  /// Deterministic pair key for duplicate detection: `${lostReportId}_${inventoryItemId}`.
  String get pairKey => '${lostReportId}_$inventoryItemId';

  /// Whether this match was created by the AI pipeline.
  bool get isAiMatch => source == MatchSource.ai;

  const LfMatch({
    this.id = '',
    required this.lostReportId,
    required this.inventoryItemId,
    required this.lostOwnerUid,
    required this.lostOwnerStudentId,
    this.finderUid = '',
    this.status = MatchStatus.proposed,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
    this.source = MatchSource.manual,
    this.overallScore,
    this.visualScore,
    this.titleScore,
    this.descriptionScore,
    this.categoryScore,
    this.locationScore,
    this.timeScore,
    this.confidence,
    this.reason,
    this.evidence,
  });

  LfMatch copyWith({
    String? id,
    MatchStatus? status,
    String? notes,
    DateTime? updatedAt,
    // AI fields are pass-through (set once at creation, never edited by client).
  }) {
    return LfMatch(
      id: id ?? this.id,
      lostReportId: lostReportId,
      inventoryItemId: inventoryItemId,
      lostOwnerUid: lostOwnerUid,
      lostOwnerStudentId: lostOwnerStudentId,
      finderUid: finderUid,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source,
      overallScore: overallScore,
      visualScore: visualScore,
      titleScore: titleScore,
      descriptionScore: descriptionScore,
      categoryScore: categoryScore,
      locationScore: locationScore,
      timeScore: timeScore,
      confidence: confidence,
      reason: reason,
      evidence: evidence,
    );
  }

  Map<String, dynamic> toCreateMap() {
    final map = <String, dynamic>{
      'lostReportId': lostReportId,
      'inventoryItemId': inventoryItemId,
      'lostOwnerUid': lostOwnerUid,
      'lostOwnerStudentId': lostOwnerStudentId,
      'finderUid': finderUid,
      'status': status.wireValue,
      'notes': notes,
      'source': source.wireValue,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // AI score fields — only write if present (manual matches omit them).
    if (overallScore != null) map['overallScore'] = overallScore;
    if (visualScore != null) map['visualScore'] = visualScore;
    if (titleScore != null) map['titleScore'] = titleScore;
    if (descriptionScore != null) map['descriptionScore'] = descriptionScore;
    if (categoryScore != null) map['categoryScore'] = categoryScore;
    if (locationScore != null) map['locationScore'] = locationScore;
    if (timeScore != null) map['timeScore'] = timeScore;
    if (confidence != null) map['confidence'] = confidence;
    if (reason != null) map['reason'] = reason;
    if (evidence != null) map['evidence'] = evidence!.toMap();

    return map;
  }

  /// Admin-only edits. The linked records, owner, source, and AI scores are
  /// immutable after creation.
  Map<String, dynamic> toUpdateMap() {
    return {
      'status': status.wireValue,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory LfMatch.fromMap(String id, Map<String, dynamic> data) {
    return LfMatch(
      id: id,
      lostReportId: data['lostReportId']?.toString() ?? '',
      inventoryItemId: data['inventoryItemId']?.toString() ?? '',
      lostOwnerUid: data['lostOwnerUid']?.toString() ?? '',
      lostOwnerStudentId: data['lostOwnerStudentId']?.toString() ?? '',
      finderUid: data['finderUid']?.toString() ?? '',
      status: MatchStatus.fromWire(data['status']),
      notes: data['notes']?.toString() ?? '',
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
      source: MatchSource.fromWire(data['source'],
          fallback: MatchSource.manual),
      overallScore: data['overallScore'] is int
          ? data['overallScore'] as int
          : null,
      visualScore:
          data['visualScore'] is int ? data['visualScore'] as int : null,
      titleScore:
          data['titleScore'] is int ? data['titleScore'] as int : null,
      descriptionScore: data['descriptionScore'] is int
          ? data['descriptionScore'] as int
          : null,
      categoryScore: data['categoryScore'] is int
          ? data['categoryScore'] as int
          : null,
      locationScore: data['locationScore'] is int
          ? data['locationScore'] as int
          : null,
      timeScore:
          data['timeScore'] is int ? data['timeScore'] as int : null,
      confidence:
          data['confidence'] is int ? data['confidence'] as int : null,
      reason: data['reason']?.toString(),
      evidence: data['evidence'] is Map
          ? MatchEvidence.fromMap(
              Map<String, dynamic>.from(data['evidence'] as Map))
          : null,
    );
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
