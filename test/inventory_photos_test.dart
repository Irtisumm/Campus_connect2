import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/models/inventory_item.dart';
import 'package:campus_connect/models/item.dart';
import 'package:campus_connect/models/lf_match.dart';
import 'package:campus_connect/screens/lost_found/lost_found_screens.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/lf_workflow_service.dart';
import 'package:campus_connect/services/lost_found_service.dart';

InventoryItem _item({
  List<String> imageUrls = const [],
  String title = 'White Air Pod',
  String description = 'Found in the library',
}) {
  return InventoryItem(
    id: 'inv1',
    foundReportId: 'r1',
    finderUid: 'uidA',
    finderStudentId: 'S003',
    title: title,
    category: 'Other',
    description: description,
    imageUrls: imageUrls,
    status: InventoryStatus.inInventory,
    handedOverAt: DateTime(2026, 8, 18),
  );
}

class _FakeLostFoundService extends LostFoundService {
  @override
  Stream<List<Item>> watchAllItems() => Stream.value(const []);
}

class _FakeLfWorkflowService extends LfWorkflowService {
  final InventoryItem item;
  _FakeLfWorkflowService(this.item);

  @override
  Stream<InventoryItem?> watchInventoryItem(String id) => Stream.value(item);

  @override
  Stream<List<LfMatch>> watchAllMatches() => Stream.value(const []);
}

void main() {
  Future<void> pumpInventoryDetail(
    WidgetTester tester,
    InventoryItem item,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>(
            create: (_) => AppState(
              lostFoundService: _FakeLostFoundService(),
              lfWorkflowService: _FakeLfWorkflowService(item),
            ),
          ),
        ],
        child: MaterialApp(
          home: AdminInventoryDetailScreen(id: item.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Inventory photo gallery', () {
    testWidgets('no photos shows "No image available"', (tester) async {
      await pumpInventoryDetail(tester, _item(imageUrls: []));

      expect(find.text('No image available'), findsOneWidget);
      expect(find.text('Photos'), findsNothing);
    });

    testWidgets('one photo shows Photos label and gallery', (tester) async {
      await pumpInventoryDetail(tester,
          _item(imageUrls: ['https://example.com/photo1.jpg']));

      expect(find.text('Photos'), findsOneWidget);
      // Image.network will error in tests (no network), so the placeholder
      // icon should be visible.
      expect(find.byIcon(Icons.image_rounded), findsWidgets);
    });

    testWidgets('multiple photos show gallery without overflow',
        (tester) async {
      await pumpInventoryDetail(tester, _item(imageUrls: [
        'https://example.com/photo1.jpg',
        'https://example.com/photo2.jpg',
        'https://example.com/photo3.jpg',
      ]));

      expect(find.text('Photos'), findsOneWidget);
      // No RenderFlex overflow exception.
      expect(tester.takeException(), isNull);
    });

    testWidgets('long item title does not overflow', (tester) async {
      await pumpInventoryDetail(
        tester,
        _item(
          title: 'I found a white color air pod with a very long title '
              'that should wrap correctly without any horizontal overflow',
          description: 'I found a white color air pod with a very long '
              'description that should wrap correctly without any horizontal '
              'overflow on the physical phone screen',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('I found a white color air pod'), findsWidgets);
    });

    testWidgets('waiting for collection status badge renders',
        (tester) async {
      final item = _item();
      // Replace with waitingForCollection status.
      final waitingItem = InventoryItem(
        id: item.id,
        foundReportId: item.foundReportId,
        finderUid: item.finderUid,
        finderStudentId: item.finderStudentId,
        title: item.title,
        category: item.category,
        description: item.description,
        imageUrls: item.imageUrls,
        status: InventoryStatus.waitingForCollection,
        handedOverAt: item.handedOverAt,
      );
      await pumpInventoryDetail(tester, waitingItem);

      // StatusBadge renders uppercase.
      expect(find.text('WAITING FOR COLLECTION'), findsOneWidget);
    });
  });
}
