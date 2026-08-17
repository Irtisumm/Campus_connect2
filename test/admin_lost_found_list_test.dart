import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/models/item.dart';
import 'package:campus_connect/models/lf_match.dart';
import 'package:campus_connect/screens/lost_found/lost_found_screens.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/lf_workflow_service.dart';
import 'package:campus_connect/services/lost_found_service.dart';

Item _item({
  String id = 'r1',
  ItemType type = ItemType.lost,
  ItemStatus status = ItemStatus.active,
}) {
  return Item(
    id: id,
    type: type,
    title: 'Blue water bottle',
    category: 'Bottle',
    description: 'Blue water bottle',
    whereLost: 'Canteen',
    whenLost: DateTime(2026, 8, 16),
    reportedByUid: 'student-uid',
    reportedByStudentId: 'S001',
    status: status,
  );
}

LfMatch _match({String lostReportId = 'r1', MatchStatus status = MatchStatus.approved}) {
  return LfMatch(
    id: 'm1',
    lostReportId: lostReportId,
    inventoryItemId: 'inv1',
    lostOwnerUid: 'student-uid',
    lostOwnerStudentId: 'S001',
    status: status,
  );
}

class _FakeLostFoundService extends LostFoundService {
  final List<Item> items;
  _FakeLostFoundService(this.items);

  @override
  Stream<List<Item>> watchAllLostItems() => Stream.value(
      items.where((i) => i.type == ItemType.lost).toList());

  @override
  Stream<List<Item>> watchAllFoundItems() => Stream.value(
      items.where((i) => i.type == ItemType.found).toList());
}

class _FakeLfWorkflowService extends LfWorkflowService {
  final List<LfMatch> matches;
  _FakeLfWorkflowService(this.matches);

  @override
  Stream<List<LfMatch>> watchAllMatches() => Stream.value(matches);
}

Future<void> _pumpLost(WidgetTester tester, List<Item> items,
    [List<LfMatch> matches = const []]) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(
            lostFoundService: _FakeLostFoundService(items),
            lfWorkflowService: _FakeLfWorkflowService(matches),
          ),
        ),
      ],
      child: const MaterialApp(home: AdminLostListScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpFound(WidgetTester tester, List<Item> items) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(
            lostFoundService: _FakeLostFoundService(items),
            lfWorkflowService: _FakeLfWorkflowService(const []),
          ),
        ),
      ],
      child: const MaterialApp(home: AdminFoundListScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AdminLostListScreen 3-tab sections', () {
    testWidgets('buckets reports into Active / Notified / Closed',
        (tester) async {
      await _pumpLost(tester, [
        _item(id: 'active', status: ItemStatus.active),
        _item(id: 'notified', status: ItemStatus.active),
        _item(id: 'closed', status: ItemStatus.resolved),
      ], [
        _match(lostReportId: 'notified'),
      ]);

      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('Notified (1)'), findsOneWidget);
      expect(find.text('Closed (1)'), findsOneWidget);
    });

    testWidgets('a proposed (not approved) match keeps the report Active',
        (tester) async {
      await _pumpLost(tester, [
        _item(id: 'active', status: ItemStatus.active),
      ], [
        _match(lostReportId: 'active', status: MatchStatus.proposed),
      ]);

      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('Notified (0)'), findsOneWidget);
      expect(find.text('Closed (0)'), findsOneWidget);
    });

    testWidgets('switching to Notified shows the notified report',
        (tester) async {
      await _pumpLost(tester, [
        _item(id: 'active', status: ItemStatus.active),
        _item(id: 'notified', status: ItemStatus.active),
      ], [
        _match(lostReportId: 'notified'),
      ]);

      // Default Active shows only the active report.
      expect(find.text('Blue water bottle'), findsOneWidget);

      await tester.tap(find.text('Notified (1)'));
      await tester.pumpAndSettle();

      // The notified report is now visible (its card also shows "Blue water bottle").
      expect(find.text('Blue water bottle'), findsOneWidget);
    });
  });

  group('AdminFoundListScreen 2-tab sections', () {
    testWidgets('buckets found reports into Active / Closed',
        (tester) async {
      await _pumpFound(tester, [
        _item(id: 'f1', type: ItemType.found, status: ItemStatus.awaitingHandover),
        _item(id: 'f2', type: ItemType.found, status: ItemStatus.inInventory),
        _item(id: 'f3', type: ItemType.found, status: ItemStatus.resolved),
      ]);

      // Awaiting Handover is Active; In Inventory (handover completed) and
      // Resolved are Closed.
      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('Closed (2)'), findsOneWidget);
    });

    testWidgets('before handover the found report stays Active',
        (tester) async {
      await _pumpFound(tester, [
        _item(id: 'f1', type: ItemType.found, status: ItemStatus.awaitingHandover),
      ]);

      // Still waiting for the student to physically hand over the item.
      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('Closed (0)'), findsOneWidget);
    });

    testWidgets('after handover the report leaves Active and appears in Closed',
        (tester) async {
      await _pumpFound(tester, [
        _item(id: 'f1', type: ItemType.found, status: ItemStatus.inInventory),
      ]);

      // The handover-completed report is no longer in the Active section.
      expect(find.text('Active (0)'), findsOneWidget);
      expect(find.text('Closed (1)'), findsOneWidget);

      // And it is listed under Closed, not Active.
      await tester.tap(find.text('Closed (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Blue water bottle'), findsOneWidget);
    });
  });
}
