import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Reproduction / regression test for the production crash where an
/// [AlertDialog] that contains a [QrImageView] throws:
///
///   "LayoutBuilder does not support returning intrinsic dimensions."
///
/// [QrImageView] (package:qr_flutter 4.1.0) builds on top of a [LayoutBuilder],
/// and the [AlertDialog] content-sizing path asks the QR widget for intrinsic
/// dimensions, which a [LayoutBuilder] cannot provide. The fix (and the
/// pattern this test locks in) is to wrap the QR in a fixed-size [SizedBox]:
/// a tight-constrained box answers the intrinsic query with its own size and
/// never reaches the LayoutBuilder inside.
///
/// The dialog structure below mirrors the real `_showQRDialog` in
/// `lib/screens/lost_found/lost_found_screens.dart`:
///   AlertDialog(
///     content: SingleChildScrollView(
///       child: Column(mainAxisSize: MainAxisSize.min, children: [
///         Container(padding: all(10), decoration: ...) ->
///             SizedBox(width: 190, height: 190) -> QrImageView(...),
///         ...SelectableText(code)...,
///       ]),
///     ),
///   )
void main() {
  testWidgets(
      'AlertDialog with QrImageView does not throw a layout exception',
      (tester) async {
    const token = 'testtoken123456';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: const Text('Your QR Code'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(0xFFE0E0E0)),
                              ),
                              child: SizedBox(
                                width: 190,
                                height: 190,
                                child: QrImageView(
                                  data: token,
                                  version: QrVersions.auto,
                                  size: 190,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SelectableText(token),
                          ],
                        ),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Show QR'),
              ),
            ),
          ),
        ),
      ),
    );

    // Open the dialog.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Show QR'));
    await tester.pumpAndSettle();

    // Regression guard: if the AlertDialog / QrImageView layout throws the
    // LayoutBuilder intrinsic-dimensions exception, it is captured during the
    // pump above and takeException() returns it (non-null) -> this assertion
    // fails. Without the fixed SizedBox wrapper this test fails on the first
    // frame of the dialog.
    expect(tester.takeException(), isNull);

    // The token must be visible inside the rendered dialog (SelectableText).
    expect(
      find.byWidgetPredicate(
          (Widget w) => w is SelectableText && w.data == token),
      findsOneWidget,
    );
  });
}
