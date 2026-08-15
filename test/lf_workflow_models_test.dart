import 'package:campus_connect/models/app_notification.dart';
import 'package:campus_connect/models/inventory_item.dart';
import 'package:campus_connect/models/item.dart';
import 'package:campus_connect/models/lf_match.dart';
import 'package:campus_connect/models/lf_notification.dart';
import 'package:campus_connect/models/qr_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ItemStatus (extended lifecycle)', () {
    test('round-trips every wire value', () {
      for (final status in ItemStatus.values) {
        expect(ItemStatus.fromWire(status.wireValue), status);
      }
    });

    test('falls back to active for unknown values', () {
      expect(ItemStatus.fromWire('In Inventory (typo)'), ItemStatus.active);
    });

    test('lists all seven lifecycle values', () {
      expect(ItemStatus.values.map((s) => s.wireValue), [
        'Active',
        'Awaiting Handover',
        'Matched - Pending',
        'In Inventory',
        'Resolved',
        'Returned',
        'Closed',
      ]);
    });
  });

  group('InventoryItem', () {
    test('round-trips through create map', () {
      final item = InventoryItem(
        id: 'inv1',
        foundReportId: 'r1',
        finderUid: 'uidA',
        finderStudentId: 'S001',
        title: 'Phone',
        category: 'Phone',
        description: 'Black phone',
        imageUrls: const ['https://res.cloudinary.com/xijxwdly/test.jpg'],
        handedOverAt: DateTime.utc(2026, 8, 15, 10),
      );
      final map = item.toCreateMap();
      // Server timestamps are not plain values.
      expect(map['status'], 'In Inventory');
      expect(map['foundReportId'], 'r1');
      final restored = InventoryItem.fromMap(
          'inv1',
          {
            ...map,
            'createdAt': DateTime.utc(2026, 8, 15, 10, 30),
            'updatedAt': DateTime.utc(2026, 8, 15, 10, 30),
          });
      expect(restored.finderUid, 'uidA');
      expect(restored.status, InventoryStatus.inInventory);
      expect(restored.imageUrls, ['https://res.cloudinary.com/xijxwdly/test.jpg']);
      expect(restored.handedOverAt!.toUtc(), DateTime.utc(2026, 8, 15, 10));
    });

    test('update map carries only the editable fields', () {
      final map = InventoryItem(
        id: 'inv1',
        foundReportId: 'r1',
        finderUid: 'uidA',
        finderStudentId: 'S001',
        title: 'Phone',
        category: 'Phone',
        description: 'desc',
        status: InventoryStatus.returned,
        matchedLostReportId: 'lost1',
        returnedAt: DateTime.utc(2026, 8, 15, 11),
      ).toUpdateMap();
      expect(map.keys.toSet(),
          {'status', 'matchedLostReportId', 'returnedAt', 'updatedAt'});
      expect(map['status'], 'Returned');
      expect(map['matchedLostReportId'], 'lost1');
    });
  });

  group('LfMatch', () {
    test('round-trips through create map', () {
      final match = LfMatch(
        id: 'm1',
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        status: MatchStatus.proposed,
        notes: 'Looks similar',
      );
      final map = match.toCreateMap();
      expect(map['status'], 'Proposed');
      final restored = LfMatch.fromMap('m1', {
        ...map,
        'createdAt': DateTime.utc(2026, 8, 15),
        'updatedAt': DateTime.utc(2026, 8, 15),
      });
      expect(restored.lostOwnerUid, 'uidA');
      expect(restored.status, MatchStatus.proposed);
    });

    test('status wire values', () {
      expect(MatchStatus.values.map((s) => s.wireValue),
          ['Proposed', 'Approved', 'Completed']);
    });
  });

  group('QrTransaction', () {
    test('issue mints an opaque 32-hex token with a 10-minute expiry', () {
      final now = DateTime.utc(2026, 8, 15, 12);
      final txn = QrTransaction.issue(
        kind: QrKind.handover,
        intendedStudentUid: 'uidA',
        intendedStudentId: 'S001',
        foundReportId: 'r1',
        now: now,
      );
      expect(txn.token, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(txn.status, QrStatus.issued);
      expect(txn.expiresAt, now.add(const Duration(minutes: 10)));
      expect(txn.isExpiredAt(now), isFalse);
      expect(txn.isExpiredAt(now.add(const Duration(minutes: 10))), isTrue);
      expect(txn.isExpiredAt(now.add(const Duration(minutes: 9))), isFalse);
    });

    test('tokens are not predictable between issues', () {
      final a = QrTransaction.issue(
              kind: QrKind.handover,
              intendedStudentUid: 'uidA',
              intendedStudentId: 'S001')
          .token;
      final b = QrTransaction.issue(
              kind: QrKind.handover,
              intendedStudentUid: 'uidA',
              intendedStudentId: 'S001')
          .token;
      expect(a, isNot(b));
    });

    test('round-trips through create map', () {
      final txn = QrTransaction.issue(
        kind: QrKind.return_,
        intendedStudentUid: 'uidA',
        intendedStudentId: 'S001',
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        now: DateTime.utc(2026, 8, 15, 12),
      );
      final restored = QrTransaction.fromMap('t1', txn.toCreateMap());
      expect(restored.kind, QrKind.return_);
      expect(restored.token, txn.token);
      expect(restored.expiresAt!.toUtc(), txn.expiresAt!.toUtc());
    });

    test('scan map changes only status and scannedAt', () {
      final map = QrTransaction.issue(
              kind: QrKind.handover,
              intendedStudentUid: 'uidA',
              intendedStudentId: 'S001')
          .toScanMap();
      expect(map.keys.toSet(), {'status', 'scannedAt'});
      expect(map['status'], 'Scanned');
    });

    test('kind wire values', () {
      expect(QrKind.values.map((k) => k.wireValue), ['handover', 'return']);
    });
  });

  group('LfNotification', () {
    test('round-trips through create map', () {
      final notification = LfNotification(
        studentId: 'S001',
        title: 'Possible match found',
        body: 'Visit the office',
        relatedReportId: 'lost1',
      );
      final map = notification.toCreateMap();
      expect(map['studentId'], 'S001');
      expect(map['read'], false);
      final restored = LfNotification.fromMap('n1', {
        ...map,
        'createdAt': DateTime.utc(2026, 8, 15),
      });
      expect(restored.title, 'Possible match found');
      expect(restored.read, isFalse);
    });

    test('readMap flips only the read flag', () {
      expect(LfNotification.readMap(), {'read': true});
    });
  });

  group('AppNotification text for new statuses', () {
    Item itemWith(ItemStatus status) => Item(
          id: 'r1',
          type: status == ItemStatus.awaitingHandover ||
                  status == ItemStatus.inInventory ||
                  status == ItemStatus.returned
              ? ItemType.found
              : ItemType.lost,
          title: 'Phone',
          category: 'Phone',
          description: 'desc',
          whereLost: 'Block A',
          reportedByUid: 'uidA',
          reportedByStudentId: 'S001',
          status: status,
        );

    test('awaiting handover row tells the student to visit the office', () {
      final row = AppNotification.forOwner(itemWith(ItemStatus.awaitingHandover));
      expect(row.text, contains('Inventory Office'));
    });

    test('inventory and returned rows render', () {
      expect(AppNotification.forOwner(itemWith(ItemStatus.inInventory)).text,
          contains('in inventory'));
      expect(AppNotification.forOwner(itemWith(ItemStatus.returned)).text,
          contains('returned'));
    });
  });
}
