// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/screens/clients_screen.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  testWidgets(
    'ClientsScreen hides Dumb AP options when no Dumb AP is configured',
    (WidgetTester tester) async {
      final appState = AppState.instance;
      appState.clients = [
        Client(
          ipAddress: '10.0.0.10',
          macAddress: 'AA:11:11:11:11:11',
          hostname: 'Main-Desktop',
          isConnected: true,
          connectionType: ConnectionType.wired,
        ),
      ];

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ClientsScreen())),
      );

      await tester.pumpAndSettle();

      // "Show Dumb AP Clients" should NOT be present
      expect(find.text('Show Dumb AP Clients'), findsNothing);
      // "Dumb AP" summary item should NOT be present
      expect(find.text('Dumb AP: '), findsNothing);
      // AppBar antenna icon should NOT be present
      expect(find.byIcon(Icons.settings_input_antenna_outlined), findsNothing);
      expect(find.byIcon(Icons.settings_input_antenna_rounded), findsNothing);
    },
  );

  testWidgets(
    'ClientsScreen displays Dumb AP options when a Dumb AP client is present',
    (WidgetTester tester) async {
      final appState = AppState.instance;
      appState.clients = [
        Client(
          ipAddress: '10.0.0.10',
          macAddress: 'AA:11:11:11:11:11',
          hostname: 'Main-Desktop',
          isConnected: true,
          connectionType: ConnectionType.wired,
        ),
        Client(
          ipAddress: '10.0.0.20',
          macAddress: 'AA:22:22:22:22:22',
          hostname: 'AP-Phone',
          isConnected: true,
          connectionType: ConnectionType.wireless,
          isDumbApClient: true,
          apName: 'Archer C60',
        ),
      ];

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ClientsScreen())),
      );

      await tester.pumpAndSettle();

      // "Show Dumb AP Clients" should be visible
      expect(find.text('Show Dumb AP Clients'), findsOneWidget);
      // "Dumb AP" summary item should be visible
      expect(find.text('Dumb AP: '), findsOneWidget);
      // Badge pill should be displayed
      expect(find.text('Dumb AP • Archer C60'), findsOneWidget);

      // Verify AppBar does NOT have the antenna icon
      expect(
        find.descendant(
          of: find.byType(LuciAppBar),
          matching: find.byIcon(Icons.settings_input_antenna_outlined),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(LuciAppBar),
          matching: find.byIcon(Icons.settings_input_antenna_rounded),
        ),
        findsNothing,
      );

      // Tap "Show Dumb AP Clients" switch to isolate Dumb AP clients
      await tester.tap(find.text('Show Dumb AP Clients'));
      await tester.pumpAndSettle();

      // AP-Phone should remain visible
      expect(find.text('AP-Phone'), findsOneWidget);
      // Main-Desktop should be filtered out
      expect(find.text('Main-Desktop'), findsNothing);

      // Tap "Total: " to restore all clients
      await tester.tap(find.text('Total: '));
      await tester.pumpAndSettle();

      // Both should be visible again
      expect(find.text('Main-Desktop'), findsOneWidget);
      expect(find.text('AP-Phone'), findsOneWidget);

      // Tap "Dumb AP: " summary item directly
      await tester.tap(find.text('Dumb AP: '));
      await tester.pumpAndSettle();

      expect(find.text('AP-Phone'), findsOneWidget);
      expect(find.text('Main-Desktop'), findsNothing);
    },
  );

  testWidgets(
    'ClientsScreen displays empty state when Dumb AP filter is active but has no matching clients',
    (WidgetTester tester) async {
      final appState = AppState.instance;
      // Mark as having Dumb AP via AppState requested filter
      appState.requestedClientCategoryFilter = ClientCategoryFilter.dumbAp;
      appState.clients = [
        Client(
          ipAddress: '10.0.0.10',
          macAddress: 'AA:11:11:11:11:11',
          hostname: 'Main-Desktop',
          isConnected: true,
          connectionType: ConnectionType.wired,
        ),
      ];

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ClientsScreen())),
      );

      await tester.pumpAndSettle();

      // Should show the specific Dumb AP empty state
      expect(find.text('No Dumb AP Clients'), findsOneWidget);
      expect(
        find.text(
          'No clients are currently associated with the secondary Access Point.',
        ),
        findsOneWidget,
      );
    },
  );
}
