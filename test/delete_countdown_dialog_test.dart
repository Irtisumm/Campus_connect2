import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_connect/widgets/delete_countdown_dialog.dart';

void main() {
  Widget host() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showArchiveCountdownDialog(
                  context,
                  itemName: 'Election 2026',
                  warning: 'Moves to archive.',
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );

  // The confirm button is the only ElevatedButton inside the dialog (the
  // Cancel action is a TextButton), so scope the lookup to the Dialog to
  // avoid matching the host's "OPEN" ElevatedButton.
  Finder dialogConfirm() => find.descendant(
        of: find.byType(Dialog),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );

  ElevatedButton confirmButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(dialogConfirm());

  Finder pleaseWait() =>
      find.textContaining('Please wait', findRichText: true);

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('confirm stays disabled until the countdown completes',
      (tester) async {
    await tester.pumpWidget(host());
    await openDialog(tester);

    expect(pleaseWait(), findsWidgets);
    expect(confirmButton(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(confirmButton(tester).onPressed, isNotNull);
    expect(find.text('Archive Election'), findsOneWidget);
  });

  testWidgets('cancel closes the dialog and a reopen restarts the countdown',
      (tester) async {
    await tester.pumpWidget(host());
    await openDialog(tester);
    expect(pleaseWait(), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(pleaseWait(), findsNothing);
    expect(find.text('Archive Election'), findsNothing);

    // Reopen: the countdown must start over from the full duration.
    await openDialog(tester);
    expect(pleaseWait(), findsWidgets);
    expect(confirmButton(tester).onPressed, isNull);

    // One second later the countdown must still be running (not resumed).
    await tester.pump(const Duration(seconds: 1));
    expect(confirmButton(tester).onPressed, isNull);

    // Flush the remaining countdown duration so no timer is left pending.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });
}
