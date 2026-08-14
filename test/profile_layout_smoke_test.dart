import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:campus_connect/screens/profile/profile_screen.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/theme/app_theme.dart';

void main() {
  testWidgets('profile redesign fits a narrow phone viewport', (tester) async {
    tester.view.physicalSize = const Size(960, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState();
    addTearDown(state.dispose);
    final fontLoader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await fontLoader.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: AppTheme.theme, home: const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
    await expectLater(
      find.byType(ProfileScreen),
      matchesGoldenFile('goldens/profile_screen.png'),
    );
  });
}
