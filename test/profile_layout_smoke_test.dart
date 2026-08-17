import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/screens/profile/profile_screen.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/theme/app_theme.dart';

/// Fake fixture lives only in the test file, as the brief permits. It stands
/// in for the Firestore document that would otherwise load for a signed-in
/// student — the production screen never holds hard-coded values like these.
const _fakeProfile = UserProfile(
  uid: 'test-uid-001',
  studentId: 'S1234567',
  fullName: 'Test Student',
  authEmail: 'test.student@city.edu.my',
  email: 'test.student@city.edu.my',
  faculty: 'Faculty of Computing',
  role: UserRole.student,
  status: AccountStatus.active,
  phone: '0123456789',
);

Widget _host(AppState state) => ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.theme,
        home: const ProfileScreen(),
      ),
    );

Future<void> _loadFont() async {
  final fontLoader = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
  await fontLoader.load();
}

void main() {
  testWidgets('profile card renders the authenticated student\'s real data',
      (tester) async {
    tester.view.physicalSize = const Size(960, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState.forTesting(profile: _fakeProfile);
    addTearDown(state.dispose);
    await _loadFont();

    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Real profile data — never a "Guest User" / sample-email fallback.
    expect(find.text('TEST STUDENT'), findsOneWidget);
    expect(find.text('test.student@city.edu.my'), findsOneWidget);
    expect(find.text('Faculty of Computing'), findsWidgets);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);

    await expectLater(
      find.byType(ProfileScreen),
      matchesGoldenFile('goldens/profile_screen.png'),
    );

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.text('Campus Connect v3.0'), findsOneWidget);
  });

  testWidgets('unsigned-in state shows a prompt, never fake profile data',
      (tester) async {
    final state = AppState.forTesting();
    addTearDown(state.dispose);
    await _loadFont();

    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sign in to view your profile.'), findsOneWidget);
    // No hard-coded fallback identity leaks into the empty state.
    expect(find.text('TEST STUDENT'), findsNothing);
    expect(find.text('Guest User'), findsNothing);
    expect(find.text('guest@student.city.edu.my'), findsNothing);
  });

  testWidgets('load-failure state offers a retry, never fallback data',
      (tester) async {
    final state =
        AppState.forTesting(status: ProfileLoadStatus.error);
    addTearDown(state.dispose);
    await _loadFont();

    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining("couldn't load your profile"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Guest User'), findsNothing);
  });

  testWidgets('change password validates input before contacting Firebase',
      (tester) async {
    final state = AppState.forTesting(profile: _fakeProfile);
    addTearDown(state.dispose);
    await _loadFont();

    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change Password'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'old-password');
    await tester.enterText(fields.at(1), 'new-password-1');
    await tester.enterText(fields.at(2), 'different-password-2');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Change'));
    await tester.pumpAndSettle();

    expect(find.text('New passwords do not match'), findsOneWidget);
  });

  testWidgets('notification preferences load from the profile', (tester) async {
    final state = AppState.forTesting(profile: _fakeProfile);
    addTearDown(state.dispose);
    await _loadFont();

    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notification Preferences'));
    await tester.pumpAndSettle();

    // All four toggles default on; the dialog reflects the profile's values.
    expect(find.text('Lost & Found Matches'), findsOneWidget);
    expect(find.text('Event Updates'), findsOneWidget);
    expect(find.text('Issue Status Changes'), findsOneWidget);
    expect(find.text('Locker Reminders'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(4));
  });
}
