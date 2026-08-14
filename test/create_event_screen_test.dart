import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/screens/events/create_event_screen.dart';
import 'package:campus_connect/screens/events/widgets/create_event_widgets.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/theme/create_event_tokens.dart';

/// ── Agent 6 — Quality, Accessibility and Regression Tester ────────
///
/// Widget tests for the redesigned `CreateEventScreen` (route `/events/create`).
/// Report-only: this file does NOT modify any `lib/` code.
///
/// EXPECTED TO FAIL (reproducing real defects Agent 7 owns):
/// - Test 10b "dirty form: header back must show the discard dialog, not
///   silently pop": go_router's imperative pop bypasses the PopScope guard
///   (see the test comment for the exact mechanism).
/// - Test 14 (320x640): the Submit button's Row overflows by 35px
///   (`create_event_widgets.dart:870`).
/// - Test 15 (2.0 text scale): the section-header Row overflows by 147px
///   (`create_event_widgets.dart:218`) and the Submit button's Row overflows
///   by 250px (`create_event_widgets.dart:870`).
///
/// Test 10 (lead-review-note "discard loop") PASSES under go_router 14.8.1:
/// the pop veto is ignored for imperative pops, so Cancel -> Discard pops
/// cleanly. See the test comment.
///
/// Setup mirrors `test/hub_render_test.dart` / `test/admin_election_archive_test.dart`:
/// a `GoRouter`-backed `MaterialApp` with a minimal route table and an
/// `AppState` provided via `ChangeNotifierProvider`.

/// Fake [AppState] that never touches Firestore. It records every
/// [createEvent] call so tests can assert the submit handler did (or did not)
/// reach the write path. The default `super()` constructor is safe in the
/// test environment (mirrors the existing tests, which construct `AppState()`
/// directly).
class _FakeAppState extends AppState {
  int createEventCalls = 0;

  @override
  Future<Event?> createEvent(Event draft) async {
    createEventCalls++;
    return null; // simulate a failed write; the screen shows its retry toast.
  }
}

/// Placeholder page reached after `/events/create` pops.
const String _eventsPlaceholderText = 'EVENTS HUB PLACEHOLDER';

GoRouter _buildRouter() => GoRouter(
      initialLocation: '/events/create',
      routes: <RouteBase>[
        GoRoute(
          path: '/events',
          builder: (BuildContext context, GoRouterState state) => const Scaffold(
            body: Center(child: Text(_eventsPlaceholderText)),
          ),
          routes: <RouteBase>[
            GoRoute(
              path: 'create',
              builder: (BuildContext context, GoRouterState state) =>
                  const CreateEventScreen(),
            ),
          ],
        ),
      ],
    );

Widget _buildApp(AppState appState, {TextScaler? textScaler}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp.router(
      routerConfig: _buildRouter(),
      title: 'Campus Connect',
      builder: textScaler == null
          ? null
          : (BuildContext context, Widget? child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: textScaler),
                child: child!,
              ),
    ),
  );
}

/// Pumps the screen at the given physical size / DPR. Defaults to a tall
/// phone viewport so every field (including the bottom actions) is laid out
/// and tappable without manual scrolling.
Future<void> _pumpApp(
  WidgetTester tester, {
  AppState? appState,
  Size physicalSize = const Size(390, 2400),
  double devicePixelRatio = 1.0,
  TextScaler? textScaler,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_buildApp(appState ?? AppState(), textScaler: textScaler));
  await tester.pumpAndSettle();
}

/// Matches an error [Text] rendered with the frozen `fieldError` style (color
/// `fieldErrorTextColor`). This disambiguates error copy from helper/placeholder
/// text that happens to share the same string (e.g. "Pick the start time" is
/// both the Time card helper AND its error copy).
Finder _errorText(String copy) => find.byWidgetPredicate(
      (Widget widget) =>
          widget is Text &&
          widget.data == copy &&
          widget.style?.color == CreateEventTokens.fieldErrorTextColor,
    );

/// The `CreateEventFieldCard` whose label matches [label].
Finder _fieldCard(String label) => find.byWidgetPredicate(
      (Widget widget) => widget is CreateEventFieldCard && widget.label == label,
    );

/// The `TextFormField` inside the field card labelled [label].
Finder _textFieldIn(String label) => find.descendant(
      of: _fieldCard(label),
      matching: find.byType(TextFormField),
    );

/// Selects [item] from the dropdown at [dropdown] (opens, taps the menu item).
Future<void> _selectDropdown(
  WidgetTester tester,
  Finder dropdown,
  String item,
) async {
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  // ── 1. Render / composition ────────────────────────────────────────
  testWidgets('renders header, info cards, sections, fields, actions, PDF card',
      (tester) async {
    await _pumpApp(tester);

    // Header.
    expect(find.text('Create Event'), findsOneWidget);
    expect(find.text('Fill in the details to create your event.'), findsOneWidget);

    // Info cards.
    expect(find.text('Admin approval required'), findsOneWidget);
    expect(find.text('Submission deadline'), findsOneWidget);

    // Section headers (uppercased).
    expect(find.text('EVENT DETAILS'), findsOneWidget);
    expect(find.text('APPROVAL LETTER (PDF)'), findsOneWidget);

    // Field labels.
    for (final String label in <String>[
      'Event Title',
      'Category',
      'Event Type',
      'Max Participants',
      'Date',
      'Time',
      'Location',
      'Organizer',
      'Description',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'missing field label "$label"');
    }

    // Actions + PDF card + privacy note.
    expect(find.text('Submit for Approval'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('No PDF selected'), findsOneWidget);
    expect(find.text('Your document will be secure and confidential.'),
        findsOneWidget);
  });

  // ── 2. Conditional cards (Club-ID / Entry Fee) ────────────────────
  testWidgets('shows Club-ID / Entry Fee cards conditionally by event type',
      (tester) async {
    await _pumpApp(tester);

    final Finder eventTypeDropdown =
        find.byType(DropdownButtonFormField<String>).at(1);

    // Default (Open): neither card.
    expect(find.text('Require Club ID'), findsNothing);
    expect(find.text('Entry Fee (RM)'), findsNothing);

    // Club: Club-ID only.
    await _selectDropdown(tester, eventTypeDropdown, 'Club');
    expect(find.text('Require Club ID'), findsOneWidget);
    expect(find.text('Entry Fee (RM)'), findsNothing);

    // Club+Payment: both.
    await _selectDropdown(tester, eventTypeDropdown, 'Club+Payment');
    expect(find.text('Require Club ID'), findsOneWidget);
    expect(find.text('Entry Fee (RM)'), findsOneWidget);

    // Paid: Entry Fee only.
    await _selectDropdown(tester, eventTypeDropdown, 'Paid');
    expect(find.text('Require Club ID'), findsNothing);
    expect(find.text('Entry Fee (RM)'), findsOneWidget);

    // Back to Open: neither again.
    await _selectDropdown(tester, eventTypeDropdown, 'Open');
    expect(find.text('Require Club ID'), findsNothing);
    expect(find.text('Entry Fee (RM)'), findsNothing);
  });

  // ── 3. Validation UX: empty submit ────────────────────────────────
  testWidgets('empty submit shows inline errors (no toast) and clears on edit',
      (tester) async {
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('Submit for Approval'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit for Approval'));
    await tester.pumpAndSettle();

    // Exact frozen copy, one error each (helper/error collisions resolved via
    // the error-style matcher).
    expect(_errorText('Event title is required'), findsOneWidget);
    expect(_errorText('Select a category'), findsOneWidget);
    expect(_errorText('Select an event type'), findsOneWidget);
    expect(_errorText('Pick the event date (at least 10 days from today)'),
        findsOneWidget);
    expect(_errorText('Pick the start time'), findsOneWidget);
    expect(_errorText('Event location is required'), findsOneWidget);
    expect(_errorText('Organizer is required'), findsOneWidget);
    expect(_errorText('Provide a description'), findsOneWidget);

    // Field errors are inline — no toast.
    expect(find.byType(SnackBar), findsNothing);

    // Autovalidate flipped to onUserInteraction: typing a valid title clears
    // the title error WITHOUT resubmitting.
    await tester.enterText(_textFieldIn('Event Title'), 'My Event');
    await tester.pumpAndSettle();
    expect(_errorText('Event title is required'), findsNothing);
  });

  // ── 4. Title counter + 100-char cap ───────────────────────────────
  testWidgets('title counter updates live and enforces the 100-char cap',
      (tester) async {
    await _pumpApp(tester);

    expect(find.text('0/100'), findsOneWidget);

    await tester.enterText(_textFieldIn('Event Title'), 'Hello');
    await tester.pumpAndSettle();
    expect(find.text('5/100'), findsOneWidget);

    // 150 chars -> truncated to 100 by maxLength; counter shows 100/100.
    await tester.enterText(_textFieldIn('Event Title'), 'a' * 150);
    await tester.pumpAndSettle();
    expect(find.text('100/100'), findsOneWidget);

    final TextFormField titleField =
        tester.widget<TextFormField>(_textFieldIn('Event Title'));
    expect(titleField.controller!.text.length, 100);
  });

  // ── 5. Max Participants: digits-only ──────────────────────────────
  testWidgets('max participants rejects letters via digitsOnly formatter',
      (tester) async {
    await _pumpApp(tester);

    await tester.enterText(_textFieldIn('Max Participants'), 'abc');
    await tester.pumpAndSettle();

    final TextFormField field =
        tester.widget<TextFormField>(_textFieldIn('Max Participants'));
    expect(field.controller!.text, isNot(contains(RegExp('[a-zA-Z]'))));
  });

  // ── 6. Date picker bounds ─────────────────────────────────────────
  testWidgets('tapping the Date card opens the date picker dialog',
      (tester) async {
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('Select event date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select event date'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('Select date'), findsOneWidget); // Material help text

    // Dismiss via the dialog's Cancel action (the screen also has a "Cancel"
    // button, so scope the finder to the dialog).
    await tester.tap(find.descendant(
        of: find.byType(DatePickerDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
  });

  // ── 7. PDF missing at submit ─────────────────────────────────────
  testWidgets('valid form without PDF shows inline PDF error and does not submit',
      (tester) async {
    final _FakeAppState fake = _FakeAppState();
    await _pumpApp(tester, appState: fake);

    // Fill every field validly.
    await tester.enterText(_textFieldIn('Event Title'), 'Tech Talk 2026');
    await _selectDropdown(
        tester, find.byType(DropdownButtonFormField<String>).at(0), 'Academic');
    await _selectDropdown(
        tester, find.byType(DropdownButtonFormField<String>).at(1), 'Open');
    await tester.enterText(_textFieldIn('Max Participants'), '50');

    // Date via picker OK (initialDate = today + 10 days, the earliest allowed).
    await tester.ensureVisible(find.text('Select event date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select event date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Time via picker OK (initialTime = 10:00 AM).
    await tester.ensureVisible(find.text('Select start time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select start time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldIn('Location'), 'Main Hall');
    await tester.enterText(_textFieldIn('Organizer'), 'Student Council');
    await tester.enterText(_textFieldIn('Description'), 'A great campus event.');

    await tester.ensureVisible(find.text('Submit for Approval'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit for Approval'));
    await tester.pumpAndSettle();

    expect(_errorText('Approval letter is required'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(fake.createEventCalls, 0);
  });

  // ── 8. PDF picker graceful failure ────────────────────────────────
  testWidgets('Choose PDF with no plugin shows a graceful toast and keeps state',
      (tester) async {
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('Choose PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Unable to open file picker. Please try again.'),
        findsOneWidget);
    expect(find.text('No PDF selected'), findsOneWidget);

    // Flush the toast's auto-dismiss timer so no timer is left pending.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
  });

  // ── 9. Cancel when clean ──────────────────────────────────────────
  testWidgets('Cancel on a clean form pops without a dialog', (tester) async {
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(CreateEventScreen), findsNothing);
    expect(find.text(_eventsPlaceholderText), findsOneWidget);
  });

  // ── 10. PopScope discard flow (lead-review-note repro) ────────────
  // The lead-review-note defect: `_confirmDiscard` sets `_discardConfirmed =
  // true` WITHOUT setState, then calls `context.pop()` synchronously, so
  // `PopScope.canPop` is still false at that instant. IN PLAIN NAVIGATOR this
  // re-vetoes the pop and the dialog re-appears (a loop). EMPIRICAL RESULT
  // under this app's GoRouter 14.8.1: the pop is IMPERATIVE — Navigator's
  // onPopPage (`GoRouterDelegate._handlePopPageWithRouteMatch`) calls
  // `route.didPop(result)` (firing the veto + `onPopInvokedWithResult(false)`
  // -> `_confirmDiscard()` again, transiently) but then IGNORES the false
  // return and completes the pop anyway. Net effect: Cancel -> Discard pops
  // cleanly, so THIS test passes. The veto-bypass is still a real defect —
  // see test 10b, where the header back silently discards a dirty form.
  testWidgets('dirty form discard should pop once (PopScope discard loop)',
      (tester) async {
    await _pumpApp(tester);

    // Make the form dirty.
    await tester.enterText(_textFieldIn('Event Title'), 'My Event');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // The discard dialog appears.
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    // Dialog gone and we are back at the previous route, exactly once.
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(CreateEventScreen), findsNothing);
    expect(find.text(_eventsPlaceholderText), findsOneWidget);
  });

  // ── 10b. DEFECT REPRODUCTION — PopScope guard bypassed by header back ─
  // EXPECTED TO FAIL (real defect found by Agent 6; Agent 7 owns the fix).
  // Lead decision #8: "Header back stays context.pop() (the PopScope
  // intercepts it while dirty)". Reality under go_router: `context.pop()` is
  // an imperative pop — the PopScope veto fires inside `route.didPop`, but
  // `GoRouterDelegate._handlePopPageWithRouteMatch` ignores the false return
  // and completes the pop. So on a DIRTY form the header back arrow pops the
  // route with NO discard dialog: silent data loss. (System back DOES show
  // the dialog, because `maybePop` goes through `willPop`, which respects
  // `canPopNotifier`.)
  testWidgets(
      'dirty form: header back must show the discard dialog, not silently pop',
      (tester) async {
    await _pumpApp(tester);

    // Make the form dirty.
    await tester.enterText(_textFieldIn('Event Title'), 'My Event');
    await tester.pumpAndSettle();

    // Tap the header back arrow (48x48 circular button, top-left).
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    // The PopScope guard must intercept: dialog shown, form retained.
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.byType(CreateEventScreen), findsOneWidget);

    // Discard then pops exactly once.
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(CreateEventScreen), findsNothing);
    expect(find.text(_eventsPlaceholderText), findsOneWidget);
  });

  // ── 11. Semantics ─────────────────────────────────────────────────
  testWidgets('back/date/time/counter expose correct semantics', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await _pumpApp(tester);

    // Back button: labelled + tappable (its node has no merging child text,
    // so the exact-string match works).
    final SemanticsNode back = tester.getSemantics(find.bySemanticsLabel('Back'));
    expect(back.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    // Date card announced as a button with its purpose. The card's child
    // texts merge into the node, so match by regex (framework-combined label).
    final SemanticsNode date = tester
        .getSemantics(find.bySemanticsLabel(RegExp('Date, pick the event date')));
    expect(date.getSemanticsData().flagsCollection.isButton, isTrue);

    // Time card announced as a button with its purpose.
    final SemanticsNode time = tester
        .getSemantics(find.bySemanticsLabel(RegExp('Time, pick the start time')));
    expect(time.getSemanticsData().flagsCollection.isButton, isTrue);

    // Title counter is a live region announcing "n of 100 characters".
    final SemanticsNode counter = tester
        .getSemantics(find.bySemanticsLabel(RegExp('0 of 100 characters')));
    expect(counter.getSemanticsData().flagsCollection.isLiveRegion, isTrue);

    handle.dispose();
  });

  // ── 12. Touch targets ─────────────────────────────────────────────
  testWidgets('interactive controls meet minimum touch-target sizes',
      (tester) async {
    await _pumpApp(tester);

    // Choose PDF button >= 44.
    final Size choosePdf =
        tester.getSize(find.widgetWithText(OutlinedButton, 'Choose PDF'));
    expect(choosePdf.height, greaterThanOrEqualTo(44));

    // Submit + Cancel buttons 56.
    final Size submit = tester.getSize(find
        .ancestor(
            of: find.text('Submit for Approval'), matching: find.byType(Material))
        .first);
    expect(submit.height, 56);

    final Size cancel =
        tester.getSize(find.widgetWithText(OutlinedButton, 'Cancel'));
    expect(cancel.height, 56);

    // Back button 48x48.
    final Size back = tester.getSize(find.ancestor(
        of: find.byIcon(Icons.arrow_back_rounded),
        matching: find.byType(InkWell)));
    expect(back.width, 48);
    expect(back.height, 48);
  });

  // ── 13. Error states are not color-only ───────────────────────────
  testWidgets('failed submit renders explicit error TEXT for key fields',
      (tester) async {
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('Submit for Approval'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit for Approval'));
    await tester.pumpAndSettle();

    expect(_errorText('Event title is required'), findsOneWidget);
    expect(_errorText('Pick the event date (at least 10 days from today)'),
        findsOneWidget);
    expect(_errorText('Pick the start time'), findsOneWidget);
    expect(_errorText('Event location is required'), findsOneWidget);
  });

  // ── 14. Narrow viewport 320x640 ───────────────────────────────────
  testWidgets('320x640 viewport renders without overflow and stacks the PDF card',
      (tester) async {
    await _pumpApp(tester,
        physicalSize: const Size(320, 640), devicePixelRatio: 1.0);

    expect(tester.takeException(), isNull);

    // PDF card stacks: the Choose PDF button renders below the file-name row.
    final Offset fileNameTopLeft = tester.getTopLeft(find.text('No PDF selected'));
    final Offset choosePdfTopLeft =
        tester.getTopLeft(find.widgetWithText(OutlinedButton, 'Choose PDF'));
    expect(choosePdfTopLeft.dy, greaterThan(fileNameTopLeft.dy));
  });

  // ── 15. Text scale 2.0 ────────────────────────────────────────────
  testWidgets('2.0 text scale renders a filled form without exceptions',
      (tester) async {
    await _pumpApp(tester,
        physicalSize: const Size(390, 844),
        devicePixelRatio: 1.0,
        textScaler: const TextScaler.linear(2.0));

    await tester.enterText(_textFieldIn('Event Title'), 'Tech Talk 2026');
    await _selectDropdown(
        tester, find.byType(DropdownButtonFormField<String>).at(0), 'Academic');
    await _selectDropdown(
        tester, find.byType(DropdownButtonFormField<String>).at(1), 'Open');
    await tester.enterText(_textFieldIn('Max Participants'), '50');
    await tester.enterText(_textFieldIn('Location'), 'Main Hall');
    await tester.enterText(_textFieldIn('Organizer'), 'Student Council');
    await tester.enterText(_textFieldIn('Description'), 'A great campus event.');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // ── 16. Golden screenshot (for the lead's visual comparison) ──────
  testWidgets('golden: default screen at 390x844 logical (DPR 3)',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // Load the bundled Inter font so the golden uses real glyphs (the design
    // uses Inter; without this the test font would render placeholder boxes).
    final FontLoader fontLoader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await fontLoader.load();

    await tester.pumpWidget(_buildApp(AppState()));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(CreateEventScreen),
      matchesGoldenFile('goldens/create_event_screen.png'),
    );
  });
}
