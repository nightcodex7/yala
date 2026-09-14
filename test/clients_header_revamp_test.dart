// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/screens/clients_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  final sampleClients = [
    Client(
      ipAddress: '192.168.1.10',
      macAddress: 'AA:11:11:11:11:11',
      hostname: 'Active-Wired-PC',
      isConnected: true,
      connectionType: ConnectionType.wired,
    ),
    Client(
      ipAddress: '192.168.1.20',
      macAddress: 'AA:22:22:22:22:22',
      hostname: 'Inactive-Old-Laptop',
      isConnected: false,
      connectionType: ConnectionType.wireless,
    ),
    Client(
      ipAddress: '192.168.1.30',
      macAddress: 'AA:33:33:33:33:33',
      hostname: 'Dumb-AP-Phone',
      isConnected: true,
      connectionType: ConnectionType.wireless,
      isDumbApClient: true,
      apName: 'LivingRoom-AP',
    ),
  ];

  group('Clients Screen Header Revamp Tests', () {
    testWidgets(
      'renders compact search bar and filters clients on search input & clear',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        appState.clients = sampleClients;

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // Compact search bar should be present with hint
        expect(
          find.text('Search by name, IP, MAC, vendor...'),
          findsOneWidget,
        );

        // Initially all clients rendered
        expect(find.text('Active-Wired-PC'), findsOneWidget);
        expect(find.text('Inactive-Old-Laptop'), findsOneWidget);
        expect(find.text('Dumb-AP-Phone'), findsOneWidget);

        // Enter search term
        await tester.enterText(find.byType(TextField), 'Phone');
        await tester.pumpAndSettle();

        expect(find.text('Dumb-AP-Phone'), findsOneWidget);
        expect(find.text('Active-Wired-PC'), findsNothing);
        expect(find.text('Inactive-Old-Laptop'), findsNothing);

        // Tap clear button
        await tester.tap(find.byIcon(Icons.clear));
        await tester.pumpAndSettle();

        expect(find.text('Active-Wired-PC'), findsOneWidget);
        expect(find.text('Inactive-Old-Laptop'), findsOneWidget);
        expect(find.text('Dumb-AP-Phone'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping "Active Connected Only" filter chip toggles active client filtering',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        appState.clients = sampleClients;

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // Inactive client should be visible initially
        expect(find.text('Inactive-Old-Laptop'), findsOneWidget);

        // Tap "Active Connected Only" chip
        await tester.tap(find.text('Active Connected Only'));
        await tester.pumpAndSettle();

        // Inactive client should now be filtered out
        expect(find.text('Inactive-Old-Laptop'), findsNothing);
        expect(find.text('Active-Wired-PC'), findsOneWidget);
        expect(find.text('Dumb-AP-Phone'), findsOneWidget);

        // Tap again to toggle off
        await tester.tap(find.text('Active Connected Only'));
        await tester.pumpAndSettle();

        // Inactive client is visible again
        expect(find.text('Inactive-Old-Laptop'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping "Show Dumb AP Clients" filter chip toggles dumb AP filtering',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        appState.clients = sampleClients;

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // Tap "Show Dumb AP Clients" chip
        await tester.tap(find.text('Show Dumb AP Clients'));
        await tester.pumpAndSettle();

        // Only Dumb AP client should be visible
        expect(find.text('Dumb-AP-Phone'), findsOneWidget);
        expect(find.text('Active-Wired-PC'), findsNothing);
        expect(find.text('Inactive-Old-Laptop'), findsNothing);

        // Tap "Show Dumb AP Clients" chip again to toggle back to all
        await tester.tap(find.text('Show Dumb AP Clients'));
        await tester.pumpAndSettle();

        expect(find.text('Active-Wired-PC'), findsOneWidget);
        expect(find.text('Inactive-Old-Laptop'), findsOneWidget);
        expect(find.text('Dumb-AP-Phone'), findsOneWidget);
      },
    );

    testWidgets(
      'narrow viewport (320x600) renders both chips without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final appState = AppState.instance;
        appState.clients = sampleClients;

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ClientsScreen())),
        );
        await tester.pumpAndSettle();

        // Verify both filter chips render cleanly without overflow errors
        expect(find.text('Active Connected Only'), findsOneWidget);
        expect(find.text('Show Dumb AP Clients'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
