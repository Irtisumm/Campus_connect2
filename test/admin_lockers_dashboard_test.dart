import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/main.dart';
import 'package:campus_connect/models/locker.dart';
import 'package:campus_connect/models/locker_booking.dart';
import 'package:campus_connect/models/locker_issue.dart';
import 'package:campus_connect/models/user_profile.dart';
import 'package:campus_connect/screens/lockers/lockers_screens.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/locker_service.dart';

class _FakeLockerService extends LockerService {
  final List<Locker> lockers;
  final List<LockerBooking> bookings;
  final List<LockerIssue> issues;

  _FakeLockerService({
    required this.lockers,
    required this.bookings,
    required this.issues,
  }) : super();

  @override
  Stream<List<Locker>> watchLockers() => Stream.value(lockers);

  @override
  Stream<List<LockerBooking>> watchAllBookings() => Stream.value(bookings);

  @override
  Stream<List<LockerIssue>> watchAllLockerIssues() => Stream.value(issues);
}

Locker _locker(String id, String status, {String? studentId}) => Locker(
      id: id,
      location: 'North Wing',
      status: status,
      studentId: studentId,
    );

LockerBooking _booking(
  String id,
  String status, {
  String? releaseStatus,
}) =>
    LockerBooking(
      id: id,
      lockerId: 'LK-A01',
      location: 'North Wing',
      startDate: '2026-08-01',
      endDate: '2027-02-01',
      status: status,
      daysLeft: 120,
      releaseStatus: releaseStatus,
    );

LockerIssue _issue(String id, String status) => LockerIssue(
      id: id,
      lockerId: 'LK-A01',
      studentId: 'S001',
      description: 'Test issue',
      status: status,
      reportedDate: '2026-08-01T10:00:00Z',
    );

void main() {
  testWidgets('admin locker dashboard maps live source records to statuses',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final appState = AppState(
      lockerService: _FakeLockerService(
        lockers: [
          _locker('LK-A01', 'Available'),
          _locker('LK-A02', 'Active', studentId: 'S001'),
          _locker('LK-A03', 'Overdue', studentId: 'S002'),
          _locker('LK-A04', 'Blocked'),
        ],
        bookings: [
          _booking('b1', 'Waiting Approval'),
          _booking('b2', 'Pending Pickup'),
          _booking('b3', 'Active', releaseStatus: 'Requested'),
        ],
        issues: [_issue('i1', 'Reported'), _issue('i2', 'Resolved')],
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: AdminLockerDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Campus Connect'), findsOneWidget);
    expect(find.text('Admin Mode'), findsOneWidget);
    expect(find.text('Locker Overview'), findsOneWidget);
    expect(find.text('Total Lockers'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Rented'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Waiting'), findsNothing);

    await tester.tap(find.text('More Status Details'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Release Requests'), findsOneWidget);
    expect(find.text('Open Issues'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    // The compact breakpoint used on a smaller phone must still lay out the
    // four-card row and expanded status grid without overflow.
    tester.view.physicalSize = const Size(960, 1920);
    await tester.pump();
    expect(find.text('Locker Overview'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Student Lookup'), findsOneWidget);
  });

  testWidgets('admin locker route keeps one header and the shared bottom nav',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/lockers',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
                path: '/lost-found',
                builder: (context, state) => const SizedBox.shrink()),
            GoRoute(
                path: '/issues',
                builder: (context, state) => const SizedBox.shrink()),
            GoRoute(
                path: '/events',
                builder: (context, state) => const SizedBox.shrink()),
            GoRoute(
                path: '/lockers',
                builder: (context, state) => const SizedBox.shrink()),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    final appState = AppState.forTesting(
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
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdminLockerDashboardScreen), findsOneWidget);
    expect(find.text('Campus Connect'), findsOneWidget);
    expect(find.text('Lost & Found'), findsOneWidget);
    expect(find.text('Issues'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('Lockers'), findsOneWidget);
  });
}
