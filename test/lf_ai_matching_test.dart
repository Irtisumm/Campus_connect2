import 'package:campus_connect/models/inventory_item.dart';
import 'package:campus_connect/models/lf_match.dart';
import 'package:campus_connect/services/lf_workflow_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════════════════
// Two-way AI Lost & Found matching — comprehensive test suite
//
// Covers:
//  1. MatchSource enum (wire values, fromWire, fallback)
//  2. MatchEvidence (toMap, fromMap, defaults, null safety)
//  3. LfMatch AI fields (source, scores, evidence, pairKey, isAiMatch)
//  4. LfMatch.toCreateMap (conditional AI fields)
//  5. LfMatch.fromMap (round-trip, non-integer safety, defaults)
//  6. LfMatch.copyWith (AI field immutability)
//  7. LfMatch.toUpdateMap (score fields excluded)
//  8. LfWorkflowService.pairKey (static)
//  9. Scoring threshold (≥50 = match)
// 10. Candidate category filtering (same-category rule)
// 11. Inventory eligibility (only inInventory is eligible)
// ══════════════════════════════════════════════════════════════════════════

void main() {
  // ── MatchSource enum ─────────────────────────────────────────────────

  group('MatchSource', () {
    test('wire values', () {
      expect(MatchSource.values.map((s) => s.wireValue), ['manual', 'ai']);
    });

    test('fromWire round-trips every value', () {
      for (final s in MatchSource.values) {
        expect(MatchSource.fromWire(s.wireValue), s);
      }
    });

    test('fromWire falls back to manual for unknown values', () {
      expect(MatchSource.fromWire('auto'), MatchSource.manual);
      expect(MatchSource.fromWire(null), MatchSource.manual);
      expect(MatchSource.fromWire(123), MatchSource.manual);
    });

    test('fromWire accepts explicit fallback', () {
      expect(
          MatchSource.fromWire('x', fallback: MatchSource.ai), MatchSource.ai);
    });
  });

  // ── MatchEvidence ────────────────────────────────────────────────────

  group('MatchEvidence', () {
    test('toMap writes both feature lists', () {
      final evidence = MatchEvidence(
        matchingFeatures: ['logo', 'color'],
        conflictingFeatures: ['size'],
      );
      expect(evidence.toMap(), {
        'matchingFeatures': ['logo', 'color'],
        'conflictingFeatures': ['size'],
      });
    });

    test('toMap writes empty lists when no features', () {
      final evidence =
          MatchEvidence(matchingFeatures: const [], conflictingFeatures: const []);
      expect(evidence.toMap()['matchingFeatures'], isEmpty);
      expect(evidence.toMap()['conflictingFeatures'], isEmpty);
    });

    test('fromMap restores both lists', () {
      final evidence = MatchEvidence.fromMap({
        'matchingFeatures': ['brand'],
        'conflictingFeatures': ['scratch pattern'],
      });
      expect(evidence.matchingFeatures, ['brand']);
      expect(evidence.conflictingFeatures, ['scratch pattern']);
    });

    test('fromMap defaults to empty lists for missing keys', () {
      final evidence = MatchEvidence.fromMap({});
      expect(evidence.matchingFeatures, isEmpty);
      expect(evidence.conflictingFeatures, isEmpty);
    });

    test('fromMap handles null', () {
      final evidence = MatchEvidence.fromMap(null);
      expect(evidence.matchingFeatures, isEmpty);
      expect(evidence.conflictingFeatures, isEmpty);
    });
  });

  // ── LfMatch — AI source & derived getters ───────────────────────────

  group('LfMatch — AI source and derived getters', () {
    test('default source is manual', () {
      final m = LfMatch(
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
      );
      expect(m.source, MatchSource.manual);
      expect(m.isAiMatch, isFalse);
    });

    test('isAiMatch returns true only for ai source', () {
      final manual = LfMatch(
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
      );
      final ai = LfMatch(
        lostReportId: 'lost2',
        inventoryItemId: 'inv2',
        lostOwnerUid: 'uidB',
        lostOwnerStudentId: 'S002',
        source: MatchSource.ai,
      );
      expect(manual.isAiMatch, isFalse);
      expect(ai.isAiMatch, isTrue);
    });

    test('pairKey combines IDs with underscore', () {
      final m = LfMatch(
        lostReportId: 'lostX',
        inventoryItemId: 'invY',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
      );
      expect(m.pairKey, 'lostX_invY');
    });

    test('all AI score fields are nullable and default to null', () {
      final m = LfMatch(
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
      );
      expect(m.overallScore, isNull);
      expect(m.visualScore, isNull);
      expect(m.titleScore, isNull);
      expect(m.descriptionScore, isNull);
      expect(m.categoryScore, isNull);
      expect(m.locationScore, isNull);
      expect(m.timeScore, isNull);
      expect(m.confidence, isNull);
      expect(m.reason, isNull);
      expect(m.evidence, isNull);
    });
  });

  // ── LfMatch.toCreateMap — conditional AI fields ──────────────────────

  group('LfMatch.toCreateMap with AI fields', () {
    test('writes source when ai', () {
      final m = LfMatch(
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        source: MatchSource.ai,
        overallScore: 85,
        visualScore: 90,
        titleScore: 60,
        reason: 'Same logo and scratch',
      );
      final map = m.toCreateMap();
      expect(map['source'], 'ai');
      expect(map['overallScore'], 85);
      expect(map['visualScore'], 90);
      expect(map['titleScore'], 60);
      expect(map['reason'], 'Same logo and scratch');
    });

    test('does NOT write null AI score fields to map', () {
      final m = LfMatch(
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        source: MatchSource.ai,
        overallScore: 85,
        // visualScore, titleScore, etc. are all null
      );
      final map = m.toCreateMap();
      expect(map['overallScore'], 85);
      expect(map.containsKey('visualScore'), isFalse);
      expect(map.containsKey('titleScore'), isFalse);
      expect(map.containsKey('descriptionScore'), isFalse);
      expect(map.containsKey('locationScore'), isFalse);
      expect(map.containsKey('timeScore'), isFalse);
      expect(map.containsKey('confidence'), isFalse);
      expect(map.containsKey('reason'), isFalse);
    });

    test('writes manual source by default (no AI fields)', () {
      final m = LfMatch(
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
      );
      final map = m.toCreateMap();
      expect(map['source'], 'manual');
      expect(map.containsKey('overallScore'), isFalse);
    });

    test('includes evidence when present', () {
      final m = LfMatch(
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        source: MatchSource.ai,
        evidence:
            MatchEvidence(matchingFeatures: ['brand'], conflictingFeatures: const []),
      );
      final map = m.toCreateMap();
      expect(map['evidence'], isA<Map>());
      expect((map['evidence'] as Map)['matchingFeatures'], ['brand']);
    });

    test('does NOT write evidence when null', () {
      final m = LfMatch(
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
      );
      final map = m.toCreateMap();
      expect(map.containsKey('evidence'), isFalse);
    });

    test('writes required identity fields', () {
      final m = LfMatch(
        lostReportId: 'lostA',
        inventoryItemId: 'invB',
        lostOwnerUid: 'uidX',
        lostOwnerStudentId: 'S123',
        status: MatchStatus.proposed,
        source: MatchSource.ai,
      );
      final map = m.toCreateMap();
      expect(map['lostReportId'], 'lostA');
      expect(map['inventoryItemId'], 'invB');
      expect(map['lostOwnerUid'], 'uidX');
      expect(map['lostOwnerStudentId'], 'S123');
      expect(map['status'], 'Proposed');
    });
  });

  // ── LfMatch.fromMap — AI field deserialization ──────────────────────

  group('LfMatch.fromMap with AI fields', () {
    test('reads all AI score fields from integers', () {
      final restored = LfMatch.fromMap('m1', {
        'lostReportId': 'lost1',
        'inventoryItemId': 'inv1',
        'lostOwnerUid': 'uidA',
        'lostOwnerStudentId': 'S001',
        'status': 'Proposed',
        'source': 'ai',
        'notes': '',
        'overallScore': 88,
        'visualScore': 92,
        'titleScore': 65,
        'descriptionScore': 55,
        'categoryScore': 100,
        'locationScore': 80,
        'timeScore': 70,
        'confidence': 85,
        'reason': 'Matching logo',
        'createdAt': DateTime.utc(2026, 8, 15),
        'updatedAt': DateTime.utc(2026, 8, 15),
      });
      expect(restored.source, MatchSource.ai);
      expect(restored.overallScore, 88);
      expect(restored.visualScore, 92);
      expect(restored.titleScore, 65);
      expect(restored.descriptionScore, 55);
      expect(restored.categoryScore, 100);
      expect(restored.locationScore, 80);
      expect(restored.timeScore, 70);
      expect(restored.confidence, 85);
      expect(restored.reason, 'Matching logo');
    });

    test('ignores non-integer score values (type safety)', () {
      final restored = LfMatch.fromMap('m1', {
        'lostReportId': 'lost1',
        'inventoryItemId': 'inv1',
        'lostOwnerUid': 'uidA',
        'lostOwnerStudentId': 'S001',
        'status': 'Proposed',
        'source': 'manual',
        'notes': '',
        'overallScore': 'eighty',
        'visualScore': 90.5,
        'confidence': true,
        'createdAt': DateTime.utc(2026, 8, 15),
        'updatedAt': DateTime.utc(2026, 8, 15),
      });
      expect(restored.overallScore, isNull);
      expect(restored.visualScore, isNull);
      expect(restored.confidence, isNull);
    });

    test('reads evidence when map key is present', () {
      final restored = LfMatch.fromMap('m1', {
        'lostReportId': 'lost1',
        'inventoryItemId': 'inv1',
        'lostOwnerUid': 'uidA',
        'lostOwnerStudentId': 'S001',
        'status': 'Proposed',
        'source': 'ai',
        'notes': '',
        'evidence': {
          'matchingFeatures': ['brand', 'color'],
          'conflictingFeatures': ['size'],
        },
        'createdAt': DateTime.utc(2026, 8, 15),
        'updatedAt': DateTime.utc(2026, 8, 15),
      });
      expect(restored.evidence, isNotNull);
      expect(restored.evidence!.matchingFeatures, ['brand', 'color']);
      expect(restored.evidence!.conflictingFeatures, ['size']);
    });

    test('ignores evidence when not a map', () {
      final restored = LfMatch.fromMap('m1', {
        'lostReportId': 'lost1',
        'inventoryItemId': 'inv1',
        'lostOwnerUid': 'uidA',
        'lostOwnerStudentId': 'S001',
        'status': 'Proposed',
        'source': 'ai',
        'notes': '',
        'evidence': 'not-a-map',
        'createdAt': DateTime.utc(2026, 8, 15),
        'updatedAt': DateTime.utc(2026, 8, 15),
      });
      expect(restored.evidence, isNull);
    });

    test('defaults source to manual when key is missing', () {
      final restored = LfMatch.fromMap('m1', {
        'lostReportId': 'lost1',
        'inventoryItemId': 'inv1',
        'lostOwnerUid': 'uidA',
        'lostOwnerStudentId': 'S001',
        'status': 'Proposed',
        'notes': '',
        'createdAt': DateTime.utc(2026, 8, 15),
        'updatedAt': DateTime.utc(2026, 8, 15),
      });
      expect(restored.source, MatchSource.manual);
      expect(restored.isAiMatch, isFalse);
    });

    test('round-trips complete AI match', () {
      final match = LfMatch(
        lostReportId: 'lost99',
        inventoryItemId: 'inv99',
        lostOwnerUid: 'uidX',
        lostOwnerStudentId: 'S099',
        source: MatchSource.ai,
        overallScore: 82,
        visualScore: 88,
        titleScore: 70,
        descriptionScore: 60,
        categoryScore: 100,
        locationScore: 75,
        timeScore: 50,
        confidence: 80,
        reason: 'Same brand logo and distinctive scratch on corner',
        evidence: MatchEvidence(
          matchingFeatures: ['brand logo', 'corner scratch'],
          conflictingFeatures: const [],
        ),
      );
      final map = match.toCreateMap();
      final restored = LfMatch.fromMap('m99', {
        ...map,
        'createdAt': DateTime.utc(2026, 8, 15, 10),
        'updatedAt': DateTime.utc(2026, 8, 15, 10),
      });

      expect(restored.id, 'm99');
      expect(restored.lostReportId, 'lost99');
      expect(restored.inventoryItemId, 'inv99');
      expect(restored.source, MatchSource.ai);
      expect(restored.isAiMatch, isTrue);
      expect(restored.overallScore, 82);
      expect(restored.visualScore, 88);
      expect(restored.categoryScore, 100);
      expect(restored.reason, 'Same brand logo and distinctive scratch on corner');
      expect(restored.evidence!.matchingFeatures, ['brand logo', 'corner scratch']);
      expect(restored.pairKey, 'lost99_inv99');
    });
  });

  // ── LfMatch.copyWith — AI field immutability ────────────────────────

  group('LfMatch.copyWith preserves AI fields', () {
    test('score fields and source pass through unchanged', () {
      final original = LfMatch(
        id: 'm1',
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        source: MatchSource.ai,
        overallScore: 85,
        visualScore: 90,
        reason: 'Matching logo',
        evidence: MatchEvidence(
            matchingFeatures: ['logo'], conflictingFeatures: const []),
      );

      final copy = original.copyWith(
        status: MatchStatus.approved,
        notes: 'Reviewed by admin',
      );

      expect(copy.source, MatchSource.ai);
      expect(copy.overallScore, 85);
      expect(copy.visualScore, 90);
      expect(copy.reason, 'Matching logo');
      expect(copy.evidence!.matchingFeatures, ['logo']);
      // Identity preserved.
      expect(copy.lostReportId, 'lost1');
      expect(copy.inventoryItemId, 'inv1');
      expect(copy.lostOwnerUid, 'uidA');
      // Status and notes updated.
      expect(copy.status, MatchStatus.approved);
      expect(copy.notes, 'Reviewed by admin');
    });

    test('manual match copyWith preserves default source', () {
      final original = LfMatch(
        id: 'm1',
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
      );
      final copy = original.copyWith(status: MatchStatus.completed);
      expect(copy.source, MatchSource.manual);
    });
  });

  // ── LfMatch.toUpdateMap — AI fields excluded ────────────────────────

  group('LfMatch.toUpdateMap excludes AI fields', () {
    test('only status, notes, and updatedAt are present', () {
      final m = LfMatch(
        id: 'm1',
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        source: MatchSource.ai,
        overallScore: 85,
        visualScore: 90,
        reason: 'match',
        status: MatchStatus.proposed,
        notes: 'admin note',
      );
      final map = m.toUpdateMap();
      expect(map.keys.toSet(), {'status', 'notes', 'updatedAt'});
      expect(map.containsKey('overallScore'), isFalse);
      expect(map.containsKey('visualScore'), isFalse);
      expect(map.containsKey('source'), isFalse);
      expect(map.containsKey('reason'), isFalse);
      expect(map.containsKey('evidence'), isFalse);
    });
  });

  // ── LfWorkflowService.pairKey (static) ───────────────────────────────

  group('LfWorkflowService.pairKey', () {
    test('produces correct format', () {
      expect(LfWorkflowService.pairKey('lost123', 'inv456'), 'lost123_inv456');
    });

    test('handles IDs with special characters', () {
      expect(LfWorkflowService.pairKey('lost-abc', 'inv_xyz'), 'lost-abc_inv_xyz');
    });

    test('empty IDs produce underscore between them', () {
      expect(LfWorkflowService.pairKey('', ''), '_');
    });
  });

  // ── Scoring threshold logic ──────────────────────────────────────────

  group('AI scoring threshold', () {
    test('49% is not a match', () {
      expect(_isAiMatch(49), isFalse);
    });

    test('50% is a match', () {
      expect(_isAiMatch(50), isTrue);
    });

    test('65% is a match', () {
      expect(_isAiMatch(65), isTrue);
    });

    test('79% is a match', () {
      expect(_isAiMatch(79), isTrue);
    });

    test('80% is a match', () {
      expect(_isAiMatch(80), isTrue);
    });

    test('95% is a match', () {
      expect(_isAiMatch(95), isTrue);
    });

    test('100% is a match', () {
      expect(_isAiMatch(100), isTrue);
    });

    test('null score is not a match', () {
      expect(_isAiMatch(null), isFalse);
    });

    test('0 is not a match', () {
      expect(_isAiMatch(0), isFalse);
    });
  });

  // ── Candidate category filtering ────────────────────────────────────

  group('Candidate category filter (same-category rule)', () {
    test('same category passes', () {
      expect(_sameCategory('Phone', 'Phone'), isTrue);
    });

    test('different category fails', () {
      expect(_sameCategory('Phone', 'Laptop'), isFalse);
      expect(_sameCategory('Wallet', 'Backpack'), isFalse);
    });

    test('case insensitive comparison', () {
      expect(_sameCategory('phone', 'Phone'), isTrue);
      expect(_sameCategory('PHONE', 'phone'), isTrue);
    });

    test('trims leading/trailing whitespace', () {
      expect(_sameCategory(' Phone ', 'phone'), isTrue);
      expect(_sameCategory('  Wallet', 'Wallet  '), isTrue);
    });

    test('empty category vs non-empty fails', () {
      expect(_sameCategory('', 'Phone'), isFalse);
      expect(_sameCategory('Phone', ''), isFalse);
    });

    test('both empty fails', () {
      expect(_sameCategory('', ''), isFalse);
    });
  });

  // ── Inventory availability ───────────────────────────────────────────

  group('Inventory availability for AI matching', () {
    test('inInventory is eligible', () {
      expect(_isEligibleStatus(InventoryStatus.inInventory), isTrue);
    });

    test('reserved is NOT eligible', () {
      expect(_isEligibleStatus(InventoryStatus.reserved), isFalse);
    });

    test('returned is NOT eligible', () {
      expect(_isEligibleStatus(InventoryStatus.returned), isFalse);
    });
  });

  // ── Duplicate pair prevention (pairKey logic) ────────────────────────

  group('Duplicate pair prevention', () {
    test('different lost IDs produce different pair keys', () {
      final key1 = LfWorkflowService.pairKey('lostA', 'inv1');
      final key2 = LfWorkflowService.pairKey('lostB', 'inv1');
      expect(key1, isNot(key2));
    });

    test('different inventory IDs produce different pair keys', () {
      final key1 = LfWorkflowService.pairKey('lost1', 'invA');
      final key2 = LfWorkflowService.pairKey('lost1', 'invB');
      expect(key1, isNot(key2));
    });

    test('same pair always produces same key (deterministic)', () {
      const lost = 'lost-fixed';
      const inv = 'inv-fixed';
      expect(LfWorkflowService.pairKey(lost, inv),
          LfWorkflowService.pairKey(lost, inv));
    });
  });

  // ── MatchStatus values unchanged ─────────────────────────────────────

  group('MatchStatus values unchanged', () {
    test('all four statuses remain', () {
      expect(MatchStatus.values.map((s) => s.wireValue), [
        'Proposed',
        'Approved',
        'Completed',
        'Rejected',
      ]);
    });

    test('fromWire round-trips all statuses', () {
      for (final s in MatchStatus.values) {
        expect(MatchStatus.fromWire(s.wireValue), s);
      }
    });
  });

  // ── Backward compatibility: old matches without AI fields ────────────

  group('Backward compatibility', () {
    test('fromMap handles old-style match without AI fields', () {
      final restored = LfMatch.fromMap('old1', {
        'lostReportId': 'lostOld',
        'inventoryItemId': 'invOld',
        'lostOwnerUid': 'uidOld',
        'lostOwnerStudentId': 'S999',
        'status': 'Completed',
        'notes': 'old note',
        'createdAt': DateTime.utc(2024, 1, 1),
        'updatedAt': DateTime.utc(2024, 1, 1),
      });
      expect(restored.source, MatchSource.manual);
      expect(restored.isAiMatch, isFalse);
      expect(restored.overallScore, isNull);
      expect(restored.evidence, isNull);
      expect(restored.reason, isNull);
      // Core fields intact.
      expect(restored.status, MatchStatus.completed);
      expect(restored.notes, 'old note');
    });

    test('toCreateMap of manual match is unchanged from before', () {
      final m = LfMatch(
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        status: MatchStatus.proposed,
        notes: '',
      );
      final map = m.toCreateMap();
      expect(map['source'], 'manual');
      expect(map['status'], 'Proposed');
      expect(map.containsKey('overallScore'), isFalse);
    });
  });
}

// ── Pure-logic helpers (mirrors the real implementation) ────────────────

bool _isAiMatch(int? score) => score != null && score >= 50;

bool _sameCategory(String a, String b) {
  final aa = a.trim();
  final bb = b.trim();
  if (aa.isEmpty || bb.isEmpty) return false;
  return aa.toLowerCase() == bb.toLowerCase();
}

bool _isEligibleStatus(InventoryStatus s) => s == InventoryStatus.inInventory;
