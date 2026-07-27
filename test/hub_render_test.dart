import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/screens/lost_found/lost_found_screens.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/data_service.dart';

void main() {
  testWidgets('Lost & Found hub renders its content', (tester) async {
    // Phone-sized surface so the layout matches the device.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DataService()),
          ChangeNotifierProvider(create: (_) => AppState()),
        ],
        child: const MaterialApp(home: LostFoundHubScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Privacy Protected'), findsOneWidget);
    expect(find.text('Report Lost Item'), findsOneWidget);
    expect(find.text('Report Found Item'), findsOneWidget);
    expect(find.text('My Lost Reports'), findsOneWidget);
    expect(find.text('My Found Reports'), findsOneWidget);
  });
}
