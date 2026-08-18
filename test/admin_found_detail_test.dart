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
import 'package:campus_connect/widgets/common.dart';

Item _found({
  String id = 'f1',
  ItemStatus status = ItemStatus.active,
  String title = 'Hp laptop',
  String description = 'Hp laptop',
  String reportedByName = 'Test Student',
  String reportedByStudentId = 'S100',
  String category = 'Laptop',
  String whereLost = 'Block B',
  List<String> imageUrls = const [],
}) {
  return Item(
    id: id,
    type: ItemType.found,
    title: title,
    category: category,
    description: description,
    whereLost: whereLost,
    whenLost: DateTime(2026, 8, 16),
    reportedByUid: 'student-uid',
    reportedByStudentId: reportedByStudentId,
    reportedByName: reportedByName,
    imageUrls: imageUrls,
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
  final List<QrTransaction> myQrs;
  _FakeLfWorkflowService({this.myQrs = const []});

  final List<String> rejectedReports = [];

  @override
  Stream<List<QrTransaction>> watchHandoverQrForReport(String foundReportId) =>
      Stream.value(const []);

  @override
  Stream<List<QrTransaction>> watchMyActiveQr(String uid, QrKind kind) =>
      Stream.value(myQrs);

  @override
  Stream<List<LfMatch>> watchAllMatches() => Stream.value(const []);

  @override
  Stream<List<LfMatch>> watchMatchesForOwner(String uid) =>
      Stream.value(const []);

  @override
  Future<void> rejectActiveMatchesForReport(String lostReportId) async {
    rejectedReports.add(lostReportId);
  }

  @override
  Future<QrScanOutcome> scanQr({
    required String token,
    required String studentUid,
    String? lostReportId,
    DateTime? now,
  }) async {
    if (myQrs.isEmpty) return const QrScanOutcome.invalid();
    return QrScanOutcome.success(myQrs.first);
  }
}

void main() {
  Future<void> pumpAdminFoundDetail(
      WidgetTester tester, Item item, _FakeLostFoundService lost) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>(
            create: (_) => AppState(
              lostFoundService: lost,
              lfWorkflowService: _FakeLfWorkflowService(),
            ),
          ),
        ],
        child: MaterialApp(home: AdminFoundDetailScreen(id: item.id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AdminFoundDetailScreen', () {
    testWidgets('uses a fixed title and keeps the raw ID only as a secondary row',
        (tester) async {
      await pumpAdminFoundDetail(tester, _found(), _FakeLostFoundService(_found()));

      expect(find.text('Found Item Details'), findsOneWidget);
      expect(find.text('Report ID: f1'), findsOneWidget);
    });

    testWidgets('title-cases the header and shows the ordered info rows',
        (tester) async {
      await pumpAdminFoundDetail(tester, _found(), _FakeLostFoundService(_found()));

      // Header is title-cased, not the raw lowercase input.
      expect(find.text('Hp Laptop'), findsOneWidget);
      expect(find.text('Hp laptop'), findsNothing);

      // Ordered left-label / right-value rows.
      expect(find.text('Reported by'), findsOneWidget);
      expect(find.text('Test Student'), findsOneWidget);
      expect(find.text('Student ID'), findsOneWidget);
      expect(find.text('S100'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('Where Found'), findsOneWidget);
      expect(find.text('Block B'), findsOneWidget);
      expect(find.text('When Found'), findsOneWidget);
      expect(find.text('16 Aug 2026'), findsOneWidget);

      // The reporter name is never labelled "Finder ID" and the raw UID is
      // never surfaced as a name.
      expect(find.text('Finder ID'), findsNothing);
      expect(find.text('student-uid'), findsNothing);
    });

    testWidgets('omits the Description row when it duplicates the title',
        (tester) async {
      await pumpAdminFoundDetail(tester, _found(), _FakeLostFoundService(_found()));

      expect(find.text('Description'), findsNothing);
    });

    testWidgets('shows Description only when it adds information beyond the title',
        (tester) async {
      final item = _found(
          title: 'Hp laptop',
          description: 'Hp laptop with a cracked corner and a blue sticker');
      await pumpAdminFoundDetail(tester, item, _FakeLostFoundService(item));

      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Hp laptop with a cracked corner and a blue sticker'),
          findsOneWidget);
    });

    testWidgets('active report shows Generate Handover QR and Mark as Resolved, no Close Report',
        (tester) async {
      await pumpAdminFoundDetail(tester, _found(), _FakeLostFoundService(_found()));

      expect(find.text('Generate Handover QR'), findsOneWidget);
      expect(find.text('Mark as Resolved'), findsOneWidget);
      expect(find.text('Close Report'), findsNothing);
    });

    testWidgets('Mark as Resolved is an outline button, not a gradient',
        (tester) async {
      await pumpAdminFoundDetail(tester, _found(), _FakeLostFoundService(_found()));

      expect(find.widgetWithText(OutlineBtn, 'Mark as Resolved'), findsOneWidget);
      expect(find.widgetWithText(GradientButton, 'Mark as Resolved'), findsNothing);
    });

    testWidgets('Mark as Resolved countdown enables then resolves on tap',
        (tester) async {
      final lost = _FakeLostFoundService(_found());
      await pumpAdminFoundDetail(tester, _found(), lost);

      await tester.tap(find.text('Mark as Resolved'));
      await tester.pump();

      expect(find.text('Mark as Resolved (3)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Mark as Resolved (2)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Mark as Resolved (1)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      // Enabled but the timer never resolves on its own.
      expect(find.widgetWithText(TextButton, 'Mark as Resolved'), findsOneWidget);
      expect(lost.statusWithReasonCalls, isEmpty);

      await tester.tap(find.widgetWithText(TextButton, 'Mark as Resolved'));
      await tester.pumpAndSettle();

      expect(lost.statusWithReasonCalls, [
        ('f1', ItemStatus.closed, AppState.closeReasonAdminResolved),
      ]);
    });

    testWidgets('closed report renders read-only with no actions',
        (tester) async {
      final item = _found(status: ItemStatus.closed);
      await pumpAdminFoundDetail(tester, item, _FakeLostFoundService(item));

      expect(find.text('Generate Handover QR'), findsNothing);
      expect(find.text('Mark as Resolved'), findsNothing);
      expect(find.text('Close Report'), findsNothing);
      expect(find.text('This report has been closed.'), findsOneWidget);
    });
  });

  group('FoundDetailScreen handover scan success', () {
    Future<void> pumpFoundDetailWithIssuedQr(
        WidgetTester tester, Item item, QrTransaction qr) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>(
              create: (_) => AppState(
                lostFoundService: _FakeLostFoundService(item),
                lfWorkflowService: _FakeLfWorkflowService(myQrs: [qr]),
              ),
            ),
          ],
          child: MaterialApp(home: FoundDetailScreen(id: item.id)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a verified handover scan shows the Thank You dialog',
        (tester) async {
      final item = _found();
      final qr = QrTransaction(
        id: 'qr1',
        kind: QrKind.handover,
        token: 'abc123',
        intendedStudentUid: 'student-uid',
        intendedStudentId: 'S100',
        foundReportId: item.id,
        status: QrStatus.issued,
        issuedAt: DateTime(2026, 8, 16),
        expiresAt: DateTime(2026, 8, 16, 0, 10),
      );

      await pumpFoundDetailWithIssuedQr(tester, item, qr);

      // The scan section is visible while a code is Issued.
      expect(find.text('Input Key'), findsOneWidget);

      await tester.ensureVisible(find.text('Input Key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Input Key'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abc123');

      await tester.ensureVisible(find.text('Verify Key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify Key'));
      await tester.pumpAndSettle();

      // Exact dialog content, no intermediate "Code verified." toast.
      expect(find.text('Thank You'), findsOneWidget);
      expect(
          find.text(
              'Thank you for handing over the item to the Lost & Found Office.'),
          findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });
  });
}
