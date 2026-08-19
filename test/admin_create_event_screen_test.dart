import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/screens/events/admin_create_event_screen.dart';
import 'package:campus_connect/services/app_state.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Size physicalSize,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>(
      create: (_) => AppState(),
      child: const MaterialApp(home: AdminCreateEventScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the premium admin create event form', (tester) async {
    await _pump(tester, physicalSize: const Size(390, 2400));

    expect(find.text('Create Event'), findsOneWidget);
    expect(
        find.text('Fill in the details to create a new event'), findsOneWidget);
    expect(find.text('ADMIN MODE'), findsOneWidget);
    expect(find.text('Event Image'), findsOneWidget);
    expect(find.text('Upload Image'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);
    expect(find.text('Save as Draft'), findsOneWidget);
    expect(find.text('View, approve and manage all events'), findsNothing);
  });

  testWidgets('scrolls cleanly on a narrow phone viewport', (tester) async {
    await _pump(tester, physicalSize: const Size(320, 640));

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('Publish'), findsOneWidget);
    expect(find.text('Save as Draft'), findsOneWidget);
  });
}
