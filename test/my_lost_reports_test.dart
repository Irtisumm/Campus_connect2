import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/models/item.dart';
import 'package:campus_connect/models/lf_match.dart';
import 'package:campus_connect/screens/lost_found/lost_found_screens.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/lf_workflow_service.dart';
import 'package:campus_connect/services/lost_found_service.dart';

Item _lost({
  String id = 'l1',
  ItemStatus status = ItemStatus.active,
  DateTime? updatedAt,
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
    status: status,
    updatedAt: updatedAt,
  );
}

LfMatch _match({
  String id = 'm1',
  String lostReportId = 'l1',
  MatchStatus status = MatchStatus.approved,
}) {
  return LfMatch(
    id: id,
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
  Stream<List<Item>> watchMyLostItems(String uid) => Stream.value(items);
}

class _FakeLfWorkflowService extends LfWorkflowService {
  final List<LfMatch> matches;
  _FakeLfWorkflowService(this.matches);

  @override
  Stream<List<LfMatch>> watchMatchesForOwner(String uid) =>
      Stream.value(matches);
}

void main() {
  group('LostReportStudentView status mapping', () {
    test('closed statuses map to Closed', () {
      for (final status in [
        ItemStatus.resolved,
        ItemStatus.returned,
        ItemStatus.closed,
      ]) {
        expect(_lost(status: status).isLostClosed, isTrue, reason: '$status');
      }
    });

    test('open statuses are not closed', () {
      for (final status in [
        ItemStatus.active,
        ItemStatus.matchedPending,
        ItemStatus.awaitingHandover,
        ItemStatus.inInventory,
      ]) {
        expect(_lost(status: status).isLostClosed, isFalse, reason: '$status');
      }
    });
  });

  group('MyLostReportsScreen', () {
    Future<void> pump(WidgetTester tester, List<Item> items,
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
          child: const MaterialApp(home: MyLostReportsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows exactly three sections with counts, default Active',
        (tester) async {
      await pump(tester, [_lost(id: 'l1')]);

      expect(find.text('Possible Matches (0)'), findsOneWidget);
      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('Closed (0)'), findsOneWidget);

      // No raw internal status names leak to the student.
      expect(find.textContaining('Resolved'), findsNothing);
      expect(find.textContaining('Matched - Pending'), findsNothing);
    });

    testWidgets('new report with no match appears in Active',
        (tester) async {
      await pump(tester, [_lost(id: 'l1')]);

      // Default section is Active, so the report card and its badge show.
      expect(find.text('Blue water bottle'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('POSSIBLE MATCH'), findsNothing);
      expect(find.text('CLOSED'), findsNothing);
    });

    testWidgets('an approved match moves the report to Possible Matches',
        (tester) async {
      await pump(tester, [_lost(id: 'l1')], [_match(lostReportId: 'l1')]);

      expect(find.text('Possible Matches (1)'), findsOneWidget);
      expect(find.text('Active (0)'), findsOneWidget);

      // Active is the default, so the matched report is not shown there.
      expect(find.text('Blue water bottle'), findsNothing);

      // Switch to Possible Matches.
      await tester.tap(find.text('Possible Matches (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Blue water bottle'), findsOneWidget);
      expect(find.text('POSSIBLE MATCH'), findsOneWidget);
      expect(find.text('1 possible match'), findsOneWidget);
    });

    testWidgets('a proposed (draft) match also counts as unresolved',
        (tester) async {
      await pump(tester, [_lost(id: 'l1')],
          [_match(lostReportId: 'l1', status: MatchStatus.proposed)]);

      expect(find.text('Possible Matches (1)'), findsOneWidget);
      expect(find.text('Active (0)'), findsOneWidget);
    });

    testWidgets('multiple candidates show the report once with a plural count',
        (tester) async {
      await pump(tester, [_lost(id: 'l1')], [
        _match(id: 'm1', lostReportId: 'l1'),
        _match(id: 'm2', lostReportId: 'l1'),
      ]);

      expect(find.text('Possible Matches (1)'), findsOneWidget);

      await tester.tap(find.text('Possible Matches (1)'));
      await tester.pumpAndSettle();

      // One card, not two.
      expect(find.text('Blue water bottle'), findsOneWidget);
      expect(find.text('2 possible matches'), findsOneWidget);
    });

    testWidgets('a resolved report appears in Closed with a return date',
        (tester) async {
      await pump(tester, [
        _lost(id: 'l1', status: ItemStatus.resolved,
            updatedAt: DateTime(2026, 8, 16)),
      ]);

      expect(find.text('Closed (1)'), findsOneWidget);
      expect(find.text('Active (0)'), findsOneWidget);

      await tester.tap(find.text('Closed (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Blue water bottle'), findsOneWidget);
      expect(find.text('CLOSED'), findsOneWidget);
      expect(find.textContaining('Item returned on 16 Aug 2026'),
          findsOneWidget);
    });

    testWidgets('shows the correct empty states per section', (tester) async {
      await pump(tester, []);

      // Active is default.
      expect(find.text('No active lost reports.'), findsOneWidget);

      await tester.tap(find.text('Possible Matches (0)'));
      await tester.pumpAndSettle();
      expect(find.text('No possible matches yet.'), findsOneWidget);

      await tester.tap(find.text('Closed (0)'));
      await tester.pumpAndSettle();
      expect(find.text('No closed lost reports yet.'), findsOneWidget);
    });
  });
}
