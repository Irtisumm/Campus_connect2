import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/models/item.dart';
import 'package:campus_connect/models/lf_match.dart';
import 'package:campus_connect/models/qr_transaction.dart';
import 'package:campus_connect/screens/lost_found/lost_found_screens.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/lf_workflow_service.dart';
import 'package:campus_connect/services/lost_found_service.dart';

Item _lost({ItemStatus status = ItemStatus.active}) {
  return Item(
    id: 'l1',
    type: ItemType.lost,
    title: 'Blue water bottle',
    category: 'Bottle',
    description: 'Blue water bottle lost near the canteen',
    whereLost: 'Canteen',
    whenLost: DateTime(2026, 8, 16),
    reportedByUid: 'student-uid',
    reportedByStudentId: 'S001',
    reportedByName: 'Alice Smith',
    status: status,
  );
}

LfMatch _approvedMatch() => LfMatch(
      id: 'm1',
      lostReportId: 'l1',
      inventoryItemId: 'inv1',
      lostOwnerUid: 'student-uid',
      lostOwnerStudentId: 'S001',
      status: MatchStatus.approved,
      notes: 'Test match',
    );

LfMatch _proposedMatch() => LfMatch(
      id: 'm2',
      lostReportId: 'l1',
      inventoryItemId: 'inv2',
      lostOwnerUid: 'student-uid',
      lostOwnerStudentId: 'S001',
      status: MatchStatus.proposed,
      notes: 'Proposed match',
    );

QrTransaction _scannedReturnQr() => QrTransaction(
      id: 'qr1',
      kind: QrKind.return_,
      token: 'abc123',
      intendedStudentUid: 'student-uid',
      intendedStudentId: 'S001',
      foundReportId: '',
      lostReportId: 'l1',
      inventoryItemId: 'inv1',
      status: QrStatus.scanned,
      issuedAt: DateTime(2026, 8, 16, 10),
      expiresAt: DateTime(2026, 8, 16, 10, 10),
    );

class _FakeLostFoundService extends LostFoundService {
  final Item item;
  _FakeLostFoundService(this.item);

  @override
  Stream<Item?> watchItem(String id) => Stream.value(item);
}

class _FakeLfWorkflowService extends LfWorkflowService {
  final List<LfMatch> matches;
  final List<QrTransaction> qrs;

  _FakeLfWorkflowService({this.matches = const [], this.qrs = const []});

  @override
  Stream<List<LfMatch>> watchMatchesForOwner(String uid) =>
      Stream.value(matches);

  @override
  Stream<List<LfMatch>> watchAllMatches() => Stream.value(matches);

  @override
  Stream<List<QrTransaction>> watchMyActiveQr(String uid, QrKind kind) =>
      Stream.value(qrs);

  @override
  Future<void> rejectActiveMatchesForReport(String lostReportId) async {}
}

void main() {
  Future<void> pumpLostDetail(
    WidgetTester tester,
    Item item, {
    List<LfMatch> matches = const [],
    List<QrTransaction> qrs = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>(
            create: (_) => AppState(
              lostFoundService: _FakeLostFoundService(item),
              lfWorkflowService: _FakeLfWorkflowService(
                  matches: matches, qrs: qrs),
            ),
          ),
        ],
        child: MaterialApp(home: LostDetailScreen(id: item.id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Approved collection workflow — close request gating', () {
    testWidgets(
        'active report with no approved match shows Request to Close',
        (tester) async {
      await pumpLostDetail(tester, _lost(),
          matches: [_proposedMatch()]);

      expect(find.text('Request to Close'), findsOneWidget);
    });

    testWidgets(
        'active report with approved match hides Request to Close',
        (tester) async {
      await pumpLostDetail(tester, _lost(),
          matches: [_approvedMatch()]);

      expect(find.text('Request to Close'), findsNothing);
    });

    testWidgets(
        'approved match with scanned QR shows Collection confirmed banner',
        (tester) async {
      await pumpLostDetail(tester, _lost(),
          matches: [_approvedMatch()], qrs: [_scannedReturnQr()]);

      expect(find.textContaining('Collection confirmed'), findsOneWidget);
      expect(find.textContaining('waiting for Admin handover'), findsOneWidget);
      expect(find.text('Request to Close'), findsNothing);
    });

    testWidgets(
        'approved match without scanned QR shows visit Inventory Office notice',
        (tester) async {
      await pumpLostDetail(tester, _lost(),
          matches: [_approvedMatch()]);

      expect(find.textContaining('visit the Inventory Office'), findsOneWidget);
      expect(find.text('Request to Close'), findsNothing);
    });

    testWidgets(
        'unrelated report without match keeps normal close request',
        (tester) async {
      // A different report — no matches for it at all.
      final other = Item(
        id: 'l2',
        type: ItemType.lost,
        title: 'Black wallet',
        category: 'Wallet',
        description: 'Lost wallet',
        whereLost: 'Library',
        whenLost: DateTime(2026, 8, 16),
        reportedByUid: 'student-uid',
        reportedByStudentId: 'S001',
        reportedByName: 'Bob Jones',
        status: ItemStatus.active,
      );
      // Matches are for l1, not l2 — so l2 has no approved match.
      await pumpLostDetail(tester, other, matches: [_approvedMatch()]);

      expect(find.text('Request to Close'), findsOneWidget);
    });
  });
}
