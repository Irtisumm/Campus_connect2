import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/screens/events/admin_election_archive_screen.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/election_service.dart';

/// A fake [ElectionService] that never touches Firestore. Every overridden
/// method returns before the real (null) database is dereferenced, so
/// constructing it via the default `super()` is safe in the test environment.
class _FakeElectionService extends ElectionService {
  _FakeElectionService(this._metas);

  final List<ElectionMeta> _metas;
  final List<String> restoredIds = <String>[];

  @override
  Stream<List<ElectionMeta>> watchAllElectionMeta() =>
      Stream<List<ElectionMeta>>.value(List<ElectionMeta>.of(_metas));

  @override
  Future<void> restoreElectionMeta(String id,
      {required String previousStatus}) {
    restoredIds.add(id);
    return Future<void>.value();
  }
}

ElectionMeta _meta({
  required String id,
  required String title,
  String status = 'Published',
  String? previousStatus,
  String? archivedAt,
  String? archivedBy,
  String? createdAt,
  String aboutBody = 'About body',
}) =>
    ElectionMeta(
      id: id,
      title: title,
      allPositionsLabel: 'All Positions',
      noticeTitle: 'Notice',
      noticeBody: 'Notice body',
      aboutTitle: 'About',
      aboutBody: aboutBody,
      timelineTitle: 'Timeline',
      upcomingLabel: 'Upcoming',
      positionsTitle: 'Positions',
      howToVoteTitle: 'How to Vote',
      pollingLocation: 'Main Hall',
      pollingDate: '2026-05-01',
      pollingTime: '09:00',
      positions: const <String>['President'],
      timeline: const <ElectionTimelineEntry>[
        ElectionTimelineEntry(
          date: '2026-04-01',
          description: 'Nominations open',
          tone: 'muted',
        ),
      ],
      voteSteps: const <String>['Step one'],
      status: status,
      previousStatus: previousStatus,
      archivedAt: archivedAt,
      archivedBy: archivedBy,
      createdAt: createdAt,
    );

Widget _buildApp(_FakeElectionService fake) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(electionService: fake),
        ),
      ],
      child: const MaterialApp(home: AdminElectionArchiveScreen()),
    );

void main() {
  testWidgets('lists only archived elections and restores on tap',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final fake = _FakeElectionService(<ElectionMeta>[
      _meta(
        id: 'election_2025',
        title: 'Election 2025',
        status: 'Archived',
        previousStatus: 'Published',
        archivedAt: '2026-08-01T10:00:00',
        archivedBy: 'ADMIN001',
        createdAt: '2026-01-10',
        aboutBody: 'An old election aboutBody text',
      ),
      _meta(id: 'election_2026', title: 'Election 2026', status: 'Published'),
    ]);

    await tester.pumpWidget(_buildApp(fake));
    await tester.pump();
    await tester.pump();

    // The archived election is rendered with its audit details.
    expect(find.text('Election 2025'), findsOneWidget);
    expect(find.text('An old election aboutBody text'), findsOneWidget);
    expect(find.text('ARCHIVED'), findsOneWidget); // status badge (uppercased)
    expect(find.text('Archived'), findsOneWidget); // audit row label
    expect(find.text('Archived by'), findsOneWidget);
    expect(find.text('ADMIN001'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('2026-01-10'), findsOneWidget);
    expect(find.text('2026-08-01T10:00:00'), findsOneWidget);

    // The active election is filtered out.
    expect(find.text('Election 2026'), findsNothing);

    // Per the UI spec: 'View' and 'Restore' actions on each card.
    expect(find.text('View'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pump();
    expect(fake.restoredIds, contains('election_2025'));

    // Flush the restore toast (2s auto-dismiss) so no timer is left pending.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('shows the empty state when nothing is archived', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final fake = _FakeElectionService(const <ElectionMeta>[]);

    await tester.pumpWidget(_buildApp(fake));
    await tester.pump();
    await tester.pump();

    expect(find.text('No archived elections'), findsOneWidget);
  });
}
