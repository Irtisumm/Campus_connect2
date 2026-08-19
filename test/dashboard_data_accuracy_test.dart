import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/screens/issues/issues_screens.dart';
import 'package:campus_connect/screens/lost_found/lost_found_screens.dart';
import 'package:campus_connect/services/admin_service.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/issue_service.dart';
import 'package:campus_connect/services/lost_found_service.dart';

Issue _issue(String id, String status, String category) => Issue(
      id: id,
      title: 'Issue $id',
      category: category,
      location: 'Block A',
      status: status,
      createdDate: '2026-08-18T09:00:00.000Z',
      updatedDate: '2026-08-18T09:00:00.000Z',
      description: 'Test issue',
      studentId: 'S001',
    );

class _FakeIssueService extends IssueService {
  final Stream<List<Issue>> _stream;

  _FakeIssueService(List<Issue> issues)
      : _stream = Stream<List<Issue>>.value(issues),
        super();

  _FakeIssueService.error(Object error)
      : _stream = Stream<List<Issue>>.error(error),
        super();

  @override
  Stream<List<Issue>> watchAllIssues() => _stream;
}

class _FakeLostFoundService extends LostFoundService {
  final List<Item> items;

  _FakeLostFoundService(this.items) : super();

  @override
  Stream<List<Item>> watchAllItems() => Stream.value(items);
}

class _FakeWorkflowService extends LfWorkflowService {
  final List<InventoryItem> inventory;
  final List<LfMatch> matches;

  _FakeWorkflowService(this.inventory, this.matches) : super();

  @override
  Stream<List<InventoryItem>> watchAllInventory() => Stream.value(inventory);

  @override
  Stream<List<LfMatch>> watchAllMatches() => Stream.value(matches);
}

class _FakeAdminService extends AdminService {
  _FakeAdminService() : super();

  @override
  Stream<List<UserProfile>> watchStudentRegistrations() =>
      Stream.value(const <UserProfile>[]);
}

Item _item(String id, ItemType type, ItemStatus status) => Item(
      id: id,
      type: type,
      title: id,
      category: 'Phone',
      description: id,
      whereLost: 'Library',
      reportedByUid: 'uid-$id',
      reportedByStudentId: 'S001',
      status: status,
    );

InventoryItem _inventory(String id, InventoryStatus status) => InventoryItem(
      id: id,
      foundReportId: 'found-$id',
      finderUid: 'uid-$id',
      finderStudentId: 'S001',
      title: id,
      category: 'Phone',
      description: id,
      status: status,
    );

void main() {
  test('Issue.fromMap does not turn a missing status into New', () {
    final issue = Issue.fromMap('broken', {
      'title': 'Missing status',
      'category': 'IT',
      'location': 'Library',
      'description': 'Malformed fixture',
    });

    expect(issue.status, isEmpty);
  });

  testWidgets('admin issue cards include every active pipeline state',
      (tester) async {
    final issues = [
      _issue('new', 'New', 'Facilities'),
      _issue('triaged', 'Triaged', 'Safety'),
      _issue('assigned', 'Assigned', 'IT'),
      _issue('progress', 'In Progress', 'Cleanliness'),
      _issue('resolved', 'Resolved', 'Other'),
      _issue('closed', 'Closed - Verified', 'Facilities'),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(issueService: _FakeIssueService(issues)),
        child: const MaterialApp(home: AdminIssuesDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
    // Triaged + Assigned + In Progress are all active work.
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('admin issue dashboard does not show zero while loading fails',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(
          issueService: _FakeIssueService.error(
            const AuthFailure('Issue feed unavailable'),
          ),
        ),
        child: const MaterialApp(home: AdminIssuesDashboardScreen()),
      ),
    );
    await tester.pump();

    // The three status cards and the five category rows all remain
    // explicitly unavailable; none is rendered as a false zero.
    expect(find.text('—'), findsNWidgets(8));
    expect(find.text('0'), findsNothing);
    expect(find.text('Issue feed unavailable'), findsOneWidget);
  });

  testWidgets('lost and found dashboard cards match realistic lifecycle data',
      (tester) async {
    final items = [
      _item('lost-active-1', ItemType.lost, ItemStatus.active),
      _item('lost-active-2', ItemType.lost, ItemStatus.matchedPending),
      _item('lost-closed', ItemType.lost, ItemStatus.closed),
      _item('lost-resolved', ItemType.lost, ItemStatus.resolved),
      _item('found-office', ItemType.found, ItemStatus.inInventory),
      _item('found-returned', ItemType.found, ItemStatus.returned),
      _item('found-closed', ItemType.found, ItemStatus.closed),
    ];
    final inventory = [
      ...List.generate(
        2,
        (i) => _inventory('office-$i', InventoryStatus.inInventory),
      ),
      _inventory('returned', InventoryStatus.returned),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(
          adminService: _FakeAdminService(),
          lostFoundService: _FakeLostFoundService(items),
          lfWorkflowService: _FakeWorkflowService(inventory, const []),
        ),
        child: const MaterialApp(home: AdminLFDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active Lost Items'), findsOneWidget);
    expect(find.text('Found Reports'), findsOneWidget);
    // The active-lost card and the inventory-office workflow row both equal 2.
    expect(find.text('2'), findsNWidgets(2));
    expect(find.text('0'), findsNWidgets(3));
    expect(find.text('Inventory Office'), findsOneWidget);
    expect(find.text('2 items in office'), findsOneWidget);
  });
}
