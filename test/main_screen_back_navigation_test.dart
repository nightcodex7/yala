// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/screens/login_screen.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});

  group('MainScreen Back Button & Exit Confirmation Tests', () {
    setUp(() async {
      final appState = AppState.instance;
      await appState.setReviewerMode(true);
      appState.markReviewerNoticeShown();
    });

    testWidgets('Pressing back on a secondary tab returns to Dashboard tab without closing app',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MainScreen(initialTab: 3), // Starts on Wireless tab
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger system back button
      final popHandled = await tester.binding.handlePopRoute();
      expect(popHandled, isTrue);
      await tester.pumpAndSettle();

      // Should now be on Dashboard tab, not exit dialog
      expect(find.text('Exit Yala?'), findsNothing);
    });

    testWidgets('Pressing back on Dashboard displays Exit Confirmation Dialog and Cancel dismisses it',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MainScreen(initialTab: 0), // Starts on Dashboard
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger system back button
      final popHandled = await tester.binding.handlePopRoute();
      expect(popHandled, isTrue);
      await tester.pumpAndSettle();

      // Exit Confirmation Dialog should appear
      expect(find.text('Exit Yala?'), findsOneWidget);
      expect(find.text('Are you sure you want to exit the application?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Exit'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog is dismissed and user stays on Dashboard
      expect(find.text('Exit Yala?'), findsNothing);
    });

    testWidgets('Tab navigation history pops through visited tabs before showing exit dialog',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MainScreen(initialTab: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Clients tab (index 2)
      await tester.tap(find.text('Clients').first);
      await tester.pumpAndSettle();

      // Tap Wireless tab (index 3)
      await tester.tap(find.text('Wireless').first);
      await tester.pumpAndSettle();

      // First back press: pops from Wireless -> Clients
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Exit Yala?'), findsNothing);

      // Second back press: pops from Clients -> Dashboard
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Exit Yala?'), findsNothing);

      // Third back press on Dashboard: triggers Exit dialog
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Exit Yala?'), findsOneWidget);
    });

    testWidgets('Pressing back on LoginScreen displays Exit Confirmation Dialog',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger system back button on LoginScreen
      final popHandled = await tester.binding.handlePopRoute();
      expect(popHandled, isTrue);
      await tester.pumpAndSettle();

      // Exit dialog appears
      expect(find.text('Exit Yala?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Exit'), findsOneWidget);
    });
  });
}
