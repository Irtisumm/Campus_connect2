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

Item _lost({
  String id = 'l1',
  ItemStatus status = ItemStatus.active,
  String reportedByName = 'Alice Smith',
}) {
  return Item(
    id: id,
    type: ItemType.lost,
    title: 'Blue water bottle',
    category: 'Bottle',
    description: 'Blue water bottle lost near the canteen',
    whereLost: 'Canteen',
    whenLost: DateTime(2026, 8, 16),
    reportedByUid: 'student-uid',
    reportedByStudentId: 'S001',
    reportedByName: reportedByName,
    status: status,
  );
}

class _FakeLostFoundService extends LostFoundService {
  final Item? item;
  _FakeLostFoundService(this.item);

  final List<(String, ItemStatus, String)> statusWithReasonCalls = [];

  @override
  Stream<Item?> watchItem(String id) => Stream.value(item);

  @override
  Future<void> updateStatusWithReason(
      String id, ItemStatus newStatus, String reason) async {
    statusWithReasonCalls.add((id, newStatus, reason));
  }
}

class _FakeLfWorkflowService extends LfWorkflowService {
  final List<String> rejectedReports = [];

  @override
  Stream<List<LfMatch>> watchMatchesForOwner(String uid) =>
      Stream.value(const []);

  @override
  Stream<List<LfMatch>> watchAllMatches() => Stream.value(const []);

  @override
  Stream<List<QrTransaction>> watchMyActiveQr(String uid, QrKind kind) =>
      Stream.value(const []);

  @override
  Future<void> rejectActiveMatchesForReport(String lostReportId) async {
    rejectedReports.add(lostReportId);
  }
}

void main() {
  Future<void> pumpLostDetail(WidgetTester tester, Item item,
      {_FakeLostFoundService? lost}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>(
            create: (_) => AppState(
              lostFoundService: lost ?? _FakeLostFoundService(item),
              lfWorkflowService: _FakeLfWorkflowService(),
            ),
          ),
        ],
        child: MaterialApp(home: LostDetailScreen(id: item.id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpAdminLostDetail(WidgetTester tester, Item item,
      {_FakeLostFoundService? lost}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>(
            create: (_) => AppState(
              lostFoundService: lost ?? _FakeLostFoundService(item),
              lfWorkflowService: _FakeLfWorkflowService(),
            ),
          ),
        ],
        child: MaterialApp(home: AdminLostDetailScreen(id: item.id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('LostDetailScreen close-request', () {
    testWidgets('an active report offers Request to Close', (tester) async {
      await pumpLostDetail(tester, _lost(status: ItemStatus.active));

      expect(find.text('Request to Close'), findsOneWidget);
      expect(find.textContaining('Closure Requested'), findsNothing);
    });

    testWidgets('a requested-close report shows Closure Requested and no button',
        (tester) async {
      await pumpLostDetail(tester, _lost(status: ItemStatus.requestedClose));

      // The non-actionable state replaces the button — a duplicate request is
      // impossible because there is nothing left to tap.
      expect(find.textContaining('Closure Requested'), findsOneWidget);
      expect(find.text('Request to Close'), findsNothing);
    });
  });

  group('AdminLostDetailScreen', () {
    testWidgets('renders the reporter name and Req for Close status',
        (tester) async {
      await pumpAdminLostDetail(
          tester, _lost(status: ItemStatus.requestedClose));

      // StatusBadge renders uppercase.
      expect(find.text('REQ FOR CLOSE'), findsOneWidget);
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('S001'), findsOneWidget); // Student ID stays separate.
    });

    testWidgets('Close button opens a 3-second countdown that never auto-closes',
        (tester) async {
      final lost = _FakeLostFoundService(_lost(status: ItemStatus.requestedClose));
      await pumpAdminLostDetail(tester, _lost(status: ItemStatus.requestedClose),
          lost: lost);

      await tester.tap(find.text('Close'));
      await tester.pump();

      // Countdown starts at 3 and the confirm button is disabled.
      expect(find.text('Close (3)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Close (2)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Close (1)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      // The button is now enabled, but the dialog is still open — the timer
      // never closes the report on its own.
      expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
      expect(find.text('Close Report'), findsOneWidget);
      expect(lost.statusWithReasonCalls, isEmpty);

      // The admin must tap the enabled button to actually close it.
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      expect(lost.statusWithReasonCalls, [
        ('l1', ItemStatus.closed, AppState.closeReasonStudentRequestApproved),
      ]);
    });

    testWidgets('Cancel dismisses the countdown without closing the report',
        (tester) async {
      final lost = _FakeLostFoundService(_lost(status: ItemStatus.requestedClose));
      await pumpAdminLostDetail(tester, _lost(status: ItemStatus.requestedClose),
          lost: lost);

      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(find.text('Close (3)'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Close Report'), findsNothing);
      expect(lost.statusWithReasonCalls, isEmpty);
    });
  });
}
