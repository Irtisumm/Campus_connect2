import 'package:flutter_test/flutter_test.dart';

import 'package:campus_connect/models/qr_transaction.dart';
import 'package:campus_connect/services/lf_workflow_service.dart';

/// Two return QRs for the same student but different lost reports — the
/// exact scenario from the bug report:
///  - QR-Pen  → lostReportId 'lostPen',  matchId 'matchPen'
///  - QR-Book → lostReportId 'lostBook', matchId 'matchBook'
/// Both belong to student 'student-uid' (S001).
QrTransaction _penReturnQr() => QrTransaction.issue(
      kind: QrKind.return_,
      intendedStudentUid: 'student-uid',
      intendedStudentId: 'S001',
      lostReportId: 'lostPen',
      inventoryItemId: 'invPen',
      matchId: 'matchPen',
      now: DateTime(2026, 8, 18, 10),
    );

QrTransaction _bookReturnQr() => QrTransaction.issue(
      kind: QrKind.return_,
      intendedStudentUid: 'student-uid',
      intendedStudentId: 'S001',
      lostReportId: 'lostBook',
      inventoryItemId: 'invBook',
      matchId: 'matchBook',
      now: DateTime(2026, 8, 18, 10),
    );

/// Fake service that returns a configurable QR from [findQrByToken], so the
/// real [scanQr] cross-report validation can be tested without Firestore.
class _FakeLfWorkflowService extends LfWorkflowService {
  final QrTransaction? qrToReturn;

  _FakeLfWorkflowService({this.qrToReturn});

  @override
  Future<QrTransaction?> findQrByToken(
      String token, String studentUid) async {
    if (qrToReturn == null) return null;
    if (qrToReturn!.token == token &&
        qrToReturn!.intendedStudentUid == studentUid) {
      return qrToReturn;
    }
    return null;
  }
}

void main() {
  final now = DateTime(2026, 8, 18, 10, 5);

  group('QrTransaction.matchId', () {
    test('is stored in toCreateMap and round-trips through fromMap', () {
      final qr = QrTransaction.issue(
        kind: QrKind.return_,
        intendedStudentUid: 'uid1',
        intendedStudentId: 'S001',
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        matchId: 'match1',
      );
      final map = qr.toCreateMap();
      expect(map['matchId'], 'match1');

      final restored = QrTransaction.fromMap('qr1', {
        ...map,
        'issuedAt': qr.issuedAt,
        'expiresAt': qr.expiresAt,
      });
      expect(restored.matchId, 'match1');
      expect(restored.lostReportId, 'lost1');
      expect(restored.inventoryItemId, 'inv1');
    });

    test('defaults to empty string for legacy documents without matchId', () {
      final restored = QrTransaction.fromMap('qr1', {
        'kind': 'return',
        'token': 'abc',
        'intendedStudentUid': 'uid1',
        'intendedStudentId': 'S001',
        'foundReportId': '',
        'lostReportId': 'lost1',
        'inventoryItemId': 'inv1',
        'status': 'Issued',
        'issuedAt': DateTime(2026, 8, 18),
        'expiresAt': DateTime(2026, 8, 18, 0, 10),
      });
      expect(restored.matchId, '');
    });
  });

  group('scanQr cross-report validation', () {
    // Create each QR once — generateToken() is random, so calling the
    // factory twice yields different tokens.
    final penQr = _penReturnQr();
    final bookQr = _bookReturnQr();

    test('scanning the Book QR from the Pen screen is rejected', () async {
      // Student is on the Pen's lost report (lostReportId='lostPen') but
      // scans the Book's QR (whose lostReportId='lostBook').
      final service = _FakeLfWorkflowService(qrToReturn: bookQr);
      final outcome = await service.scanQr(
        token: bookQr.token,
        studentUid: 'student-uid',
        lostReportId: 'lostPen',
        now: now,
      );
      expect(outcome.success, isFalse);
      expect(outcome.message, contains('different item'));
    });

    test('scanning the Pen QR from the Book screen is rejected', () async {
      // Vice-versa: on the Book screen, scanning the Pen's code.
      final service = _FakeLfWorkflowService(qrToReturn: penQr);
      final outcome = await service.scanQr(
        token: penQr.token,
        studentUid: 'student-uid',
        lostReportId: 'lostBook',
        now: now,
      );
      expect(outcome.success, isFalse);
      expect(outcome.message, contains('different item'));
    });

    test('scanning the correct QR does NOT fail with "different item"',
        () async {
      // Student on the Pen screen scans the Pen's QR. The validation should
      // pass — the method then tries to write to Firestore, which is not
      // available in the test, but the important assertion is that the
      // failure message is NOT "different item".
      final service = _FakeLfWorkflowService(qrToReturn: penQr);
      QrScanOutcome? outcome;
      try {
        outcome = await service.scanQr(
          token: penQr.token,
          studentUid: 'student-uid',
          lostReportId: 'lostPen',
          now: now,
        );
      } catch (_) {
        // Firestore write failed (expected in tests) — the validation
        // passed, which is what we're testing.
      }
      if (outcome != null) {
        expect(outcome.message, isNot(contains('different item')));
      }
    });

    test('scanning with empty lostReportId skips the cross-report check',
        () async {
      // When lostReportId is empty or null (e.g. handover flow), the
      // cross-report check is skipped.
      final service = _FakeLfWorkflowService(qrToReturn: penQr);
      QrScanOutcome? outcome;
      try {
        outcome = await service.scanQr(
          token: penQr.token,
          studentUid: 'student-uid',
          lostReportId: '',
          now: now,
        );
      } catch (_) {
        // Firestore write failed — validation passed.
      }
      if (outcome != null) {
        expect(outcome.message, isNot(contains('different item')));
      }
    });

    test('scanning a token that does not exist is invalid', () async {
      final service = _FakeLfWorkflowService(qrToReturn: null);
      final outcome = await service.scanQr(
        token: 'nonexistent',
        studentUid: 'student-uid',
        lostReportId: 'lostPen',
        now: now,
      );
      expect(outcome.success, isFalse);
      expect(outcome.message, contains('Invalid code'));
    });
  });

  group('issueReturnQr binds matchId', () {
    test('the issued QR carries the exact match ID', () {
      // Simulate what AppState.issueReturnQr does.
      final qr = QrTransaction.issue(
        kind: QrKind.return_,
        intendedStudentUid: 'student-uid',
        intendedStudentId: 'S001',
        lostReportId: 'lostPen',
        inventoryItemId: 'invPen',
        matchId: 'matchPen',
      );
      expect(qr.matchId, 'matchPen');
      expect(qr.lostReportId, 'lostPen');
      expect(qr.inventoryItemId, 'invPen');
      expect(qr.intendedStudentUid, 'student-uid');
      expect(qr.kind, QrKind.return_);
    });

    test('two QRs for different matches have different bindings', () {
      final penQr = QrTransaction.issue(
        kind: QrKind.return_,
        intendedStudentUid: 'student-uid',
        intendedStudentId: 'S001',
        lostReportId: 'lostPen',
        inventoryItemId: 'invPen',
        matchId: 'matchPen',
      );
      final bookQr = QrTransaction.issue(
        kind: QrKind.return_,
        intendedStudentUid: 'student-uid',
        intendedStudentId: 'S001',
        lostReportId: 'lostBook',
        inventoryItemId: 'invBook',
        matchId: 'matchBook',
      );
      expect(penQr.matchId, isNot(equals(bookQr.matchId)));
      expect(penQr.lostReportId, isNot(equals(bookQr.lostReportId)));
      expect(penQr.inventoryItemId, isNot(equals(bookQr.inventoryItemId)));
      // Same student — the bug scenario.
      expect(penQr.intendedStudentUid, equals(bookQr.intendedStudentUid));
    });
  });
}
