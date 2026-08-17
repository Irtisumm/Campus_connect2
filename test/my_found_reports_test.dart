import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/models/item.dart';
import 'package:campus_connect/screens/lost_found/lost_found_screens.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/lost_found_service.dart';

Item _found({
  String id = 'f1',
  ItemStatus status = ItemStatus.awaitingHandover,
  DateTime? updatedAt,
}) {
  return Item(
    id: id,
    type: ItemType.found,
    title: 'Black umbrella',
    category: 'Accessories',
    description: 'Black umbrella found near the library',
    whereLost: 'Library',
    whenLost: DateTime(2026, 8, 16),
    reportedByUid: 'student-uid',
    reportedByStudentId: 'S001',
    status: status,
    updatedAt: updatedAt,
  );
}

/// A [LostFoundService] that never touches Firestore — it returns a fixed list
/// so the screen can be rendered with deterministic data in widget tests.
class _FakeLostFoundService extends LostFoundService {
  final List<Item> items;
  _FakeLostFoundService(this.items);

  @override
  Stream<List<Item>> watchMyFoundItems(String uid) => Stream.value(items);
}

void main() {
  group('FoundReportStudentView status mapping', () {
    test('awaiting statuses map to Awaiting', () {
      for (final status in [
        ItemStatus.active,
        ItemStatus.awaitingHandover,
        ItemStatus.matchedPending,
      ]) {
        final r = _found(status: status);
        expect(r.isFoundClosed, isFalse, reason: '$status');
        expect(r.foundStudentStatus, 'Awaiting', reason: '$status');
      }
    });

    test('post-handover statuses map to Closed', () {
      for (final status in [
        ItemStatus.inInventory,
        ItemStatus.resolved,
        ItemStatus.returned,
        ItemStatus.closed,
      ]) {
        final r = _found(status: status);
        expect(r.isFoundClosed, isTrue, reason: '$status');
        expect(r.foundStudentStatus, 'Closed', reason: '$status');
      }
    });
  });

  group('MyFoundReportsScreen', () {
    Future<void> pump(WidgetTester tester, List<Item> items) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>(
              create: (_) => AppState(lostFoundService: _FakeLostFoundService(items)),
            ),
          ],
          child: const MaterialApp(home: MyFoundReportsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows only Awaiting and Closed sections with counts',
        (tester) async {
      await pump(tester, [
        _found(id: 'a1'),
        _found(id: 'a2'),
        _found(id: 'c1', status: ItemStatus.inInventory,
            updatedAt: DateTime(2026, 8, 16)),
      ]);

      // Two segments, with dynamic counts, and no third option.
      expect(find.text('Awaiting (2)'), findsOneWidget);
      expect(find.text('Closed (1)'), findsOneWidget);

      // The full internal wording is never surfaced to students.
      expect(find.textContaining('Awaiting Handover'), findsNothing);
      expect(find.textContaining('In Inventory'), findsNothing);
    });

    testWidgets('defaults to Awaiting and shows only awaiting items',
        (tester) async {
      await pump(tester, [
        _found(id: 'a1'),
        _found(id: 'c1', status: ItemStatus.returned,
            updatedAt: DateTime(2026, 8, 16)),
      ]);

      // Awaiting item is visible with an "AWAITING" badge; the closed item is
      // not shown in the default section.
      expect(find.text('Black umbrella found near the library'), findsOneWidget);
      expect(find.text('AWAITING'), findsOneWidget);
      expect(find.text('CLOSED'), findsNothing);

      // The handover reminder is shown above the awaiting list.
      expect(
        find.textContaining('Lost & Found Office (Block A, Level 1)'),
        findsOneWidget,
      );
    });

    testWidgets('Closed section shows closed items with handover date',
        (tester) async {
      await pump(tester, [
        _found(id: 'a1'),
        _found(id: 'c1', status: ItemStatus.inInventory,
            updatedAt: DateTime(2026, 8, 16)),
      ]);

      await tester.tap(find.text('Closed (1)'));
      await tester.pumpAndSettle();

      expect(find.text('CLOSED'), findsOneWidget);
      expect(find.text('AWAITING'), findsNothing);
      expect(find.textContaining('Handover completed on 16 Aug 2026'),
          findsOneWidget);
    });

    testWidgets('shows the correct empty states', (tester) async {
      await pump(tester, []);

      expect(find.text('No items awaiting handover.'), findsOneWidget);

      await tester.tap(find.text('Closed (0)'));
      await tester.pumpAndSettle();

      expect(find.text('No closed found reports yet.'), findsOneWidget);
    });
  });
}
