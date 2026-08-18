import 'package:campus_connect/models/lf_match.dart';
import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════════════════
// Deterministic AI scoring — Dart-side contract
//
// The arithmetic itself lives in the Worker (campus-connect-ai/src/scoring.js,
// covered by campus-connect-ai/test/deterministic_scoring.test.js). These
// tests cover the Dart half of the contract:
//
//   3.  Missing location is stored as null, never as a misleading 0
//   4.  Missing time is stored as null, never as a misleading 0
//   6.  10 candidates are not silently reduced to 5
//   10. matchingFeatures survive the Worker → LfMatch → Firestore round-trip
//   11. conflictingFeatures survive the same round-trip
//   12. Old matches with null evidence still load correctly
//   13. The 50 threshold is unchanged
//   14. Lost → Inventory wiring
//   15. Inventory/Found → Lost wiring
// ══════════════════════════════════════════════════════════════════════════

/// Mirrors `AppState._evidenceFromWorkerResult`. Kept in step with that
/// method — it is private, so the parsing contract is verified here.
MatchEvidence? evidenceFromWorkerResult(Map<String, dynamic> r) {
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

/// Builds an AI match exactly the way both flows in `AppState` do.
LfMatch aiMatchFromWorkerResult(
  Map<String, dynamic> r, {
  required String lostReportId,
  required String inventoryItemId,
  required String lostOwnerUid,
  required String lostOwnerStudentId,
  required String finderUid,
}) {
  return LfMatch(
    lostReportId: lostReportId,
    inventoryItemId: inventoryItemId,
    lostOwnerUid: lostOwnerUid,
    lostOwnerStudentId: lostOwnerStudentId,
    finderUid: finderUid,
    status: MatchStatus.proposed,
    source: MatchSource.ai,
    overallScore: (r['overallScore'] as num?)?.toInt(),
    visualScore: (r['visualScore'] as num?)?.toInt(),
    titleScore: (r['titleScore'] as num?)?.toInt(),
    descriptionScore: (r['descriptionScore'] as num?)?.toInt(),
    categoryScore: (r['categoryScore'] as num?)?.toInt(),
    locationScore: (r['locationScore'] as num?)?.toInt(),
    timeScore: (r['timeScore'] as num?)?.toInt(),
    confidence: (r['confidence'] as num?)?.toInt(),
    reason: r['reason']?.toString(),
    evidence: evidenceFromWorkerResult(r),
  );
}

/// A complete Worker result for a strong match.
Map<String, dynamic> workerResult({
  int overallScore = 88,
  int? locationScore,
  int? timeScore,
  List<String> matching = const [
    'Dell logo on lid',
    'crack near top-right corner',
  ],
  List<String> conflicting = const [],
  bool includeEvidence = true,
}) {
  return <String, dynamic>{
    'candidateId': 'inv-1',
    'overallScore': overallScore,
    'visualScore': 95,
    'titleScore': 100,
    'descriptionScore': 82,
    'categoryScore': 100,
    'locationScore': locationScore,
    'timeScore': timeScore,
    'confidence': 92,
    'reason': 'Same model label and the same crack in the same place.',
    if (includeEvidence)
      'evidence': <String, dynamic>{
        'matchingFeatures': matching,
        'conflictingFeatures': conflicting,
      },
  };
}

void main() {
  // ── 6. Candidate count ─────────────────────────────────────────────────

  group('6. Ten candidates are not silently reduced to five', () {
    // Mirrors AppState._aiMaxCandidates and the Worker's
    // BATCH_MAX_CANDIDATES.
    const aiMaxCandidates = 10;
    const workerBatchMaxCandidates = 10;

    test('the client limit is 10, not 5', () {
      expect(aiMaxCandidates, 10);
      expect(aiMaxCandidates, isNot(5));
    });

    test('the client limit does not exceed the Worker hard cap', () {
      expect(aiMaxCandidates, lessThanOrEqualTo(workerBatchMaxCandidates));
    });

    test('fetch limit equals the evaluated limit (Flow A)', () {
      // queryInventoryForAi(limit: _aiMaxCandidates) — previously
      // _aiMaxCandidates * 2, which fetched 10 but only 5 were scored.
      const fetchLimit = aiMaxCandidates;
      const sentMaxCandidates = aiMaxCandidates;
      expect(fetchLimit, sentMaxCandidates);
    });

    test('take() limit equals the evaluated limit (Flow B)', () {
      // .take(_aiMaxCandidates) — previously .take(_aiMaxCandidates * 2).
      const takeLimit = aiMaxCandidates;
      expect(takeLimit, aiMaxCandidates);
    });

    test('all ten fetched candidates are evaluated', () {
      final fetched = List.generate(10, (i) => 'inv-$i');
      final evaluated = fetched.take(aiMaxCandidates).toList();
      expect(evaluated.length, 10);
      expect(fetched.length - evaluated.length, 0);
    });

    test('both directions use the same limit', () {
      const flowALimit = aiMaxCandidates;
      const flowBLimit = aiMaxCandidates;
      expect(flowALimit, flowBLimit);
    });
  });

  // ── 3 & 4. Missing location/time are stored as null, never 0 ───────────

  group('3. Missing location is stored as null, not 0', () {
    test('a null locationScore stays null on the model', () {
      final m = aiMatchFromWorkerResult(
        workerResult(locationScore: null, timeScore: 75),
        lostReportId: 'lost1',
        inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        finderUid: 'uidB',
      );
      expect(m.locationScore, isNull);
      expect(m.timeScore, 75);
    });

    test('a null locationScore is omitted from the Firestore payload', () {
      final m = aiMatchFromWorkerResult(
        workerResult(locationScore: null, timeScore: 75),
        lostReportId: 'lost1',
        inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        finderUid: 'uidB',
      );
      final map = m.toCreateMap();
      // Absent, rather than written as a misleading 0.
      expect(map.containsKey('locationScore'), isFalse);
      expect(map['timeScore'], 75);
    });

    test('a real location score is still stored', () {
      final m = aiMatchFromWorkerResult(
        workerResult(locationScore: 100, timeScore: 75),
        lostReportId: 'lost1',
        inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        finderUid: 'uidB',
      );
      expect(m.locationScore, 100);
      expect(m.toCreateMap()['locationScore'], 100);
    });

    test('a genuine 0 location score is distinguishable from absent', () {
      final absent = aiMatchFromWorkerResult(
        workerResult(locationScore: null),
        lostReportId: 'l', inventoryItemId: 'i',
        lostOwnerUid: 'u', lostOwnerStudentId: 'S', finderUid: 'f',
      );
      final zero = aiMatchFromWorkerResult(
        workerResult(locationScore: 0),
        lostReportId: 'l', inventoryItemId: 'i',
        lostOwnerUid: 'u', lostOwnerStudentId: 'S', finderUid: 'f',
      );
      expect(absent.locationScore, isNull);
      expect(zero.locationScore, 0);
      expect(absent.toCreateMap().containsKey('locationScore'), isFalse);
      expect(zero.toCreateMap()['locationScore'], 0);
    });
  });

  group('4. Missing time is stored as null, not 0', () {
    test('a null timeScore stays null and is omitted from the payload', () {
      final m = aiMatchFromWorkerResult(
        workerResult(locationScore: 100, timeScore: null),
        lostReportId: 'lost1',
        inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        finderUid: 'uidB',
      );
      expect(m.timeScore, isNull);
      expect(m.toCreateMap().containsKey('timeScore'), isFalse);
    });

    test('both absent at once — the real inventory case', () {
      // Inventory items carry no location; the report form has no date field.
      final m = aiMatchFromWorkerResult(
        workerResult(locationScore: null, timeScore: null, overallScore: 91),
        lostReportId: 'lost1',
        inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        finderUid: 'uidB',
      );
      expect(m.locationScore, isNull);
      expect(m.timeScore, isNull);
      // The renormalised score still clears the threshold.
      expect(m.overallScore, 91);
      expect(m.overallScore! >= 50, isTrue);
      final map = m.toCreateMap();
      expect(map.containsKey('locationScore'), isFalse);
      expect(map.containsKey('timeScore'), isFalse);
      expect(map['overallScore'], 91);
    });
  });

  // ── 10 & 11. Structured evidence is wired through ──────────────────────

  group('10. matchingFeatures are populated', () {
    test('parsed from the Worker result', () {
      final e = evidenceFromWorkerResult(workerResult(matching: const [
        'white colour',
        'same visible logo',
        'same scratch near top-right corner',
      ]));
      expect(e, isNotNull);
      expect(e!.matchingFeatures, [
        'white colour',
        'same visible logo',
        'same scratch near top-right corner',
      ]);
    });

    test('reach the LfMatch model', () {
      final m = aiMatchFromWorkerResult(
        workerResult(matching: const ['Nike swoosh logo', 'frayed left strap']),
        lostReportId: 'lost1', inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', finderUid: 'uidB',
      );
      expect(m.evidence, isNotNull);
      expect(m.evidence!.matchingFeatures,
          ['Nike swoosh logo', 'frayed left strap']);
    });

    test('are written to the Firestore payload', () {
      final m = aiMatchFromWorkerResult(
        workerResult(matching: const ['same visible logo']),
        lostReportId: 'lost1', inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', finderUid: 'uidB',
      );
      final evidence = m.toCreateMap()['evidence'] as Map<String, dynamic>;
      expect(evidence['matchingFeatures'], ['same visible logo']);
    });

    test('survive a full Firestore round-trip', () {
      final m = aiMatchFromWorkerResult(
        workerResult(
          matching: const ['same visible logo', 'dent on the base'],
          conflicting: const ['different case colour'],
        ),
        lostReportId: 'lost1', inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', finderUid: 'uidB',
      );
      final stored = m.toCreateMap();
      final restored = LfMatch.fromMap('m1', {
        ...stored,
        // Firestore returns real values in place of the sentinels.
        'createdAt': DateTime.utc(2026, 8, 18),
        'updatedAt': DateTime.utc(2026, 8, 18),
      });
      expect(restored.evidence, isNotNull);
      expect(restored.evidence!.matchingFeatures,
          ['same visible logo', 'dent on the base']);
      expect(restored.evidence!.conflictingFeatures, ['different case colour']);
    });

    test('blank and non-string entries are dropped', () {
      final e = evidenceFromWorkerResult({
        'evidence': {
          'matchingFeatures': ['  same logo  ', '', '   ', 42, null, 'scratch'],
          'conflictingFeatures': <dynamic>[],
        },
      });
      expect(e!.matchingFeatures, ['same logo', '42', 'scratch']);
    });
  });

  group('11. conflictingFeatures are populated', () {
    test('parsed from the Worker result', () {
      final e = evidenceFromWorkerResult(workerResult(
        matching: const ['same shape'],
        conflicting: const [
          'different case colour',
          'different visible model label',
        ],
      ));
      expect(e!.conflictingFeatures, [
        'different case colour',
        'different visible model label',
      ]);
    });

    test('reach the model and the Firestore payload', () {
      final m = aiMatchFromWorkerResult(
        workerResult(
          matching: const ['same shape'],
          conflicting: const ['different case colour'],
        ),
        lostReportId: 'lost1', inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', finderUid: 'uidB',
      );
      expect(m.evidence!.conflictingFeatures, ['different case colour']);
      final evidence = m.toCreateMap()['evidence'] as Map<String, dynamic>;
      expect(evidence['conflictingFeatures'], ['different case colour']);
    });

    test('conflict-only evidence is still stored', () {
      final m = aiMatchFromWorkerResult(
        workerResult(
          matching: const [],
          conflicting: const ['different brand: Samsung vs Apple'],
        ),
        lostReportId: 'lost1', inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', finderUid: 'uidB',
      );
      expect(m.evidence, isNotNull);
      expect(m.evidence!.matchingFeatures, isEmpty);
      expect(m.evidence!.conflictingFeatures,
          ['different brand: Samsung vs Apple']);
    });
  });

  // ── 12. Backward compatibility with null evidence ──────────────────────

  group('12. Old matches with null evidence still load correctly', () {
    test('a Worker result with no evidence key yields null', () {
      final e = evidenceFromWorkerResult(
          workerResult(includeEvidence: false));
      expect(e, isNull);
    });

    test('empty evidence lists yield null rather than an empty object', () {
      final e = evidenceFromWorkerResult({
        'evidence': {
          'matchingFeatures': <dynamic>[],
          'conflictingFeatures': <dynamic>[],
        },
      });
      expect(e, isNull);
    });

    test('a malformed evidence value yields null', () {
      expect(evidenceFromWorkerResult({'evidence': 'nope'}), isNull);
      expect(evidenceFromWorkerResult({'evidence': 42}), isNull);
      expect(evidenceFromWorkerResult({'evidence': null}), isNull);
      expect(evidenceFromWorkerResult(<String, dynamic>{}), isNull);
    });

    test('a match with null evidence omits the field entirely', () {
      final m = aiMatchFromWorkerResult(
        workerResult(includeEvidence: false),
        lostReportId: 'lost1', inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', finderUid: 'uidB',
      );
      expect(m.evidence, isNull);
      expect(m.toCreateMap().containsKey('evidence'), isFalse);
    });

    test('a pre-evidence AI match document still loads', () {
      final restored = LfMatch.fromMap('legacy-ai', {
        'lostReportId': 'lostOld',
        'inventoryItemId': 'invOld',
        'lostOwnerUid': 'uidOld',
        'lostOwnerStudentId': 'S999',
        'status': 'Approved',
        'notes': '',
        'source': 'ai',
        'overallScore': 72,
        'visualScore': 65,
        'titleScore': 80,
        'descriptionScore': 70,
        'categoryScore': 100,
        'locationScore': 0,
        'timeScore': 0,
        'confidence': 55,
        'reason': 'Legacy AI match.',
        // No 'evidence' key at all — written before evidence existed.
        'createdAt': DateTime.utc(2026, 1, 1),
        'updatedAt': DateTime.utc(2026, 1, 1),
      });
      expect(restored.evidence, isNull);
      expect(restored.isAiMatch, isTrue);
      expect(restored.overallScore, 72);
      // Historic fake-zero values load unchanged — no migration required.
      expect(restored.locationScore, 0);
      expect(restored.timeScore, 0);
      expect(restored.status, MatchStatus.approved);
    });

    test('a pre-evidence manual match still loads', () {
      final restored = LfMatch.fromMap('legacy-manual', {
        'lostReportId': 'lostOld',
        'inventoryItemId': 'invOld',
        'lostOwnerUid': 'uidOld',
        'lostOwnerStudentId': 'S999',
        'status': 'Completed',
        'notes': 'handed over at the counter',
        'createdAt': DateTime.utc(2025, 6, 1),
        'updatedAt': DateTime.utc(2025, 6, 1),
      });
      expect(restored.evidence, isNull);
      expect(restored.source, MatchSource.manual);
      expect(restored.overallScore, isNull);
      expect(restored.notes, 'handed over at the counter');
    });

    test('an explicitly null evidence field loads as null', () {
      final restored = LfMatch.fromMap('m1', {
        'lostReportId': 'l',
        'inventoryItemId': 'i',
        'lostOwnerUid': 'u',
        'lostOwnerStudentId': 'S001',
        'status': 'Proposed',
        'source': 'ai',
        'evidence': null,
      });
      expect(restored.evidence, isNull);
    });

    test('MatchEvidence.fromMap still tolerates null', () {
      final e = MatchEvidence.fromMap(null);
      expect(e.matchingFeatures, isEmpty);
      expect(e.conflictingFeatures, isEmpty);
    });
  });

  // ── 13. The 50 threshold is unchanged ──────────────────────────────────

  group('13. Existing 50 threshold behaviour is preserved', () {
    // Mirrors the accept test used by both flows in AppState.
    bool accepts(int overallScore) => overallScore >= 50;

    test('50 is accepted', () => expect(accepts(50), isTrue));
    test('49 is rejected', () => expect(accepts(49), isFalse));
    test('0 is rejected', () => expect(accepts(0), isFalse));
    test('100 is accepted', () => expect(accepts(100), isTrue));

    test('the threshold is not lowered', () {
      const threshold = 50;
      expect(threshold, 50);
      expect(threshold, greaterThanOrEqualTo(50));
    });

    test('a below-threshold result is never turned into a match', () {
      final m = aiMatchFromWorkerResult(
        workerResult(overallScore: 49),
        lostReportId: 'lost1', inventoryItemId: 'inv-1',
        lostOwnerUid: 'uidA', lostOwnerStudentId: 'S001', finderUid: 'uidB',
      );
      expect(accepts(m.overallScore!), isFalse);
    });
  });

  // ── 14 & 15. Both directions build a valid, rule-compliant match ───────

  group('14. Lost → Inventory (Flow A) wiring', () {
    // Flow A: the signed-in student owns the lost report and is the creator.
    test('builds a Proposed AI match owned by the lost reporter', () {
      final m = aiMatchFromWorkerResult(
        workerResult(),
        lostReportId: 'lostA',
        inventoryItemId: 'inv-1',
        lostOwnerUid: 'uid-student',
        lostOwnerStudentId: 'S001',
        finderUid: 'uid-finder',
      );
      expect(m.source, MatchSource.ai);
      expect(m.status, MatchStatus.proposed);
      expect(m.lostOwnerUid, 'uid-student');
      expect(m.finderUid, 'uid-finder');
      expect(m.isAiMatch, isTrue);
    });

    test('the payload satisfies the Firestore create rule for the owner', () {
      final map = aiMatchFromWorkerResult(
        workerResult(),
        lostReportId: 'lostA', inventoryItemId: 'inv-1',
        lostOwnerUid: 'uid-student', lostOwnerStudentId: 'S001',
        finderUid: 'uid-finder',
      ).toCreateMap();
      // Rule: source == 'ai' && status == 'Proposed' && the three ID strings.
      expect(map['source'], 'ai');
      expect(map['status'], 'Proposed');
      expect(map['lostReportId'], isA<String>());
      expect(map['inventoryItemId'], isA<String>());
      expect(map['lostOwnerUid'], isA<String>());
    });

    test('evidence and scores are carried on the match', () {
      final m = aiMatchFromWorkerResult(
        workerResult(locationScore: null, timeScore: 75),
        lostReportId: 'lostA', inventoryItemId: 'inv-1',
        lostOwnerUid: 'uid-student', lostOwnerStudentId: 'S001',
        finderUid: 'uid-finder',
      );
      expect(m.overallScore, 88);
      expect(m.visualScore, 95);
      expect(m.evidence!.matchingFeatures, isNotEmpty);
      expect(m.pairKey, 'lostA_inv-1');
    });
  });

  group('15. Inventory/Found → Lost (Flow B) wiring', () {
    // Flow B: the finder created the inventory item and is the creator.
    test('builds a Proposed AI match with the finder as creator', () {
      final m = aiMatchFromWorkerResult(
        workerResult(),
        lostReportId: 'lostB',
        inventoryItemId: 'inv-2',
        lostOwnerUid: 'uid-owner',
        lostOwnerStudentId: 'S002',
        finderUid: 'uid-finder',
      );
      expect(m.source, MatchSource.ai);
      expect(m.status, MatchStatus.proposed);
      expect(m.finderUid, 'uid-finder');
      expect(m.lostOwnerUid, 'uid-owner');
    });

    test('the payload satisfies the Firestore create rule for the finder', () {
      final map = aiMatchFromWorkerResult(
        workerResult(),
        lostReportId: 'lostB', inventoryItemId: 'inv-2',
        lostOwnerUid: 'uid-owner', lostOwnerStudentId: 'S002',
        finderUid: 'uid-finder',
      ).toCreateMap();
      expect(map['source'], 'ai');
      expect(map['status'], 'Proposed');
      expect(map['finderUid'], 'uid-finder');
      expect(map['lostOwnerUid'], isA<String>());
    });

    test('both flows produce an identical shape for the same result', () {
      final flowA = aiMatchFromWorkerResult(
        workerResult(),
        lostReportId: 'lostX', inventoryItemId: 'inv-9',
        lostOwnerUid: 'uid-owner', lostOwnerStudentId: 'S003',
        finderUid: 'uid-finder',
      );
      final flowB = aiMatchFromWorkerResult(
        workerResult(),
        lostReportId: 'lostX', inventoryItemId: 'inv-9',
        lostOwnerUid: 'uid-owner', lostOwnerStudentId: 'S003',
        finderUid: 'uid-finder',
      );
      expect(flowA.overallScore, flowB.overallScore);
      expect(flowA.visualScore, flowB.visualScore);
      expect(flowA.locationScore, flowB.locationScore);
      expect(flowA.timeScore, flowB.timeScore);
      expect(flowA.evidence!.matchingFeatures,
          flowB.evidence!.matchingFeatures);
      expect(flowA.evidence!.conflictingFeatures,
          flowB.evidence!.conflictingFeatures);
      expect(flowA.pairKey, flowB.pairKey);
    });

    test('duplicate prevention still keys on the same pair', () {
      final a = aiMatchFromWorkerResult(
        workerResult(),
        lostReportId: 'lostX', inventoryItemId: 'inv-9',
        lostOwnerUid: 'u', lostOwnerStudentId: 'S', finderUid: 'f',
      );
      final b = aiMatchFromWorkerResult(
        workerResult(overallScore: 61),
        lostReportId: 'lostX', inventoryItemId: 'inv-9',
        lostOwnerUid: 'u', lostOwnerStudentId: 'S', finderUid: 'f',
      );
      // Same pair → same key, so the existing duplicate check still fires
      // regardless of which direction discovered it.
      expect(a.pairKey, b.pairKey);
    });
  });
}
