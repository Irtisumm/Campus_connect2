import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/main.dart';
import 'package:campus_connect/models/event.dart';
import 'package:campus_connect/models/user_profile.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/event_service.dart';
import 'package:campus_connect/screens/events/events_screens.dart';

class _FakeEventService extends EventService {
  final List<Event> pending;
  final List<Event> all;

  _FakeEventService({required this.pending, required this.all}) : super();

  @override
  Stream<List<Event>> watchPendingEvents() => Stream.value(pending);

  @override
  Stream<List<Event>> watchEvents() => Stream.value(all);
}

Event _event(String id, String title, String status) => Event(
      id: id,
      title: title,
      date: '2026-08-20',
      time: '10:00 AM',
      location: 'Main Hall',
      category: 'Academic',
      organizer: 'Campus Club',
      description: 'Test event',
      status: status,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<Event> pending,
  required List<Event> all,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>(
      create: (_) => AppState(
        eventService: _FakeEventService(pending: pending, all: all),
      ),
      child: const MaterialApp(home: AdminEventsListScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Admin Events uses live counts and the new dashboard hierarchy',
      (tester) async {
    await _pump(
      tester,
      pending: [_event('p1', 'Pending Event', 'Pending')],
      all: [
        _event('pub', 'Published Event', 'Published'),
        _event('done', 'Completed Event', 'Completed'),
        _event('rejected', 'Rejected Event', 'Rejected'),
      ],
    );

    expect(find.text('Events Management'), findsNothing);
    expect(find.text('Admin Mode'), findsOneWidget);
    expect(find.text('Manage Events'), findsOneWidget);
    expect(find.text('Election Management'), findsOneWidget);
    expect(find.text('Create Event'), findsWidgets);
    expect(find.text('View, approve and manage all events'), findsNothing);
    expect(find.text('Manage elections and candidates'), findsNothing);
    expect(find.text('Add a new event or activity'), findsNothing);
    expect(find.text('Pending (1)'), findsOneWidget);
    expect(find.text('Published (1)'), findsOneWidget);
    expect(find.text('Pending Event'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Completed Event'), findsNothing);
    expect(find.text('Rejected Event'), findsNothing);

    await tester.tap(find.text('Manage Events'));
    await tester.pumpAndSettle();
    expect(find.text('Pending Event'), findsOneWidget);

    await tester.tap(find.text('Published (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Published Event'), findsOneWidget);
    expect(find.text('Pending Event'), findsNothing);
  });

  testWidgets('Admin Events keeps the shared bottom navigation visible',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/events',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/lost-found',
              builder: (context, state) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/issues',
              builder: (context, state) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/events',
              builder: (context, state) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/lockers',
              builder: (context, state) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState.forTesting(
          profile: const UserProfile(
            uid: 'admin-uid',
            studentId: 'A001',
            fullName: 'Admin',
            authEmail: 'admin@example.test',
            email: 'admin@example.test',
            faculty: 'Computing',
            role: UserRole.admin,
            status: AccountStatus.active,
          ),
        ),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdminEventsListScreen), findsOneWidget);
    expect(find.text('Lost & Found'), findsOneWidget);
    expect(find.text('Issues'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('Lockers'), findsOneWidget);
  });
}
