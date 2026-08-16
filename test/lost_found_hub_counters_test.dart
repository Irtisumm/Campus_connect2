import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/models/item.dart';
import 'package:campus_connect/screens/lost_found/lost_found_screens.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/data_service.dart';
import 'package:campus_connect/services/lost_found_service.dart';

Item _found(String id, ItemStatus status) => Item(
      id: id,
      type: ItemType.found,
      title: 'Found $id',
      category: 'Accessories',
      description: 'Found item $id',
      whereLost: 'Library',
      whenLost: DateTime(2026, 8, 16),
      reportedByUid: 'student-uid',
      reportedByStudentId: 'S001',
      status: status,
    );

Item _lost(String id, ItemStatus status) => Item(
      id: id,
      type: ItemType.lost,
      title: 'Lost $id',
      category: 'Bottle',
      description: 'Lost item $id',
      whereLost: 'Canteen',
      whenLost: DateTime(2026, 8, 16),
      reportedByUid: 'student-uid',
      reportedByStudentId: 'S001',
      status: status,
    );

/// A [LostFoundService] that never touches Firestore — it returns a fixed list
/// so the hub's combined summary counts can be asserted deterministically.
class _FakeLostFoundService extends LostFoundService {
  final List<Item> items;
  _FakeLostFoundService(this.items);

  @override
  Stream<List<Item>> watchMyAllItems(String uid) => Stream.value(items);
}

void main() {
  Future<void> pump(WidgetTester tester, List<Item> items) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DataService()),
          ChangeNotifierProvider(
            create: (_) =>
                AppState(lostFoundService: _FakeLostFoundService(items)),
          ),
        ],
        child: const MaterialApp(home: LostFoundHubScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no reports shows zero counters', (tester) async {
    await pump(tester, []);
    expect(find.text('0 Found Reports', findRichText: true), findsOneWidget);
    expect(find.text('0 Total Active', findRichText: true), findsOneWidget);
  });

  testWidgets('Found Reports counts only active found reports',
      (tester) async {
    // Two active found reports plus three found reports in non-active states
    // (closed, in inventory, returned) — only the two active ones count.
    await pump(tester, [
      _found('f1', ItemStatus.active),
      _found('f2', ItemStatus.active),
      _found('f3', ItemStatus.closed),
      _found('f4', ItemStatus.inInventory),
      _found('f5', ItemStatus.returned),
    ]);

    expect(find.text('2 Found Reports', findRichText: true), findsOneWidget);
    expect(find.text('2 Total Active', findRichText: true), findsOneWidget);
  });

  testWidgets('closing reports decrements the counters', (tester) async {
    // Three submitted, two closed → one active remains.
    await pump(tester, [
      _found('f1', ItemStatus.active),
      _found('f2', ItemStatus.closed),
      _found('f3', ItemStatus.closed),
    ]);

    expect(find.text('1 Found Reports', findRichText: true), findsOneWidget);
    expect(find.text('1 Total Active', findRichText: true), findsOneWidget);
  });

  testWidgets('lost reports do not inflate the Found Reports counter',
      (tester) async {
    await pump(tester, [
      _found('f1', ItemStatus.active),
      _lost('l1', ItemStatus.active),
      _lost('l2', ItemStatus.active),
    ]);

    // Found Reports = 1 (only the active found report); Total Active = 3.
    expect(find.text('1 Found Reports', findRichText: true), findsOneWidget);
    expect(find.text('3 Total Active', findRichText: true), findsOneWidget);
  });
}
