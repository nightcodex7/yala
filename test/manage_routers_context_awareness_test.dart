// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/screens/manage_routers_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('ManageRoutersScreen Context Awareness Tests', () {
    testWidgets('Empty state shows Add Router and Import without Export', (
      WidgetTester tester,
    ) async {
      final appState = AppState.instance;
      for (final r in List.of(appState.routers)) {
        await appState.removeRouter(r.id);
      }

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ManageRoutersScreen())),
      );

      await tester.pumpAndSettle();

      // Empty state message
      expect(find.text('No routers added yet.'), findsOneWidget);

      // Empty state must have primary Add Router button
      expect(find.widgetWithText(ElevatedButton, 'Add Router'), findsOneWidget);

      // Empty state must have Import Profiles button
      expect(
        find.widgetWithText(OutlinedButton, 'Import Profiles from JSON'),
        findsOneWidget,
      );

      // Export button should NOT be present when 0 routers exist
      expect(find.text('Export Profiles as JSON'), findsNothing);
      expect(find.byTooltip('Export Profiles as JSON'), findsNothing);

      // AppBar should still have Import action
      expect(find.byTooltip('Import Profiles from JSON'), findsOneWidget);
    });

    testWidgets(
      'Populated state shows router cards, Add Router, and compact Import/Export JSON buttons',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        for (final r in List.of(appState.routers)) {
          await appState.removeRouter(r.id);
        }

        await appState.addRouter(
          model.Router(
            id: 'router_1',
            ipAddress: '192.168.1.1',
            username: 'root',
            password: 'password',
            useHttps: false,
            name: 'Primary Router',
          ),
        );

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ManageRoutersScreen())),
        );

        await tester.pumpAndSettle();

        // Router card is visible
        expect(find.text('Primary Router'), findsOneWidget);

        // Add Router button in list
        expect(
          find.widgetWithText(ElevatedButton, 'Add Router'),
          findsOneWidget,
        );

        // Compact side-by-side Import JSON and Export JSON buttons
        expect(
          find.widgetWithText(OutlinedButton, 'Import JSON'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Export JSON'),
          findsOneWidget,
        );

        // AppBar has both Import and Export actions
        expect(find.byTooltip('Import Profiles from JSON'), findsOneWidget);
        expect(find.byTooltip('Export Profiles as JSON'), findsOneWidget);

        // Verify that Import uses download (down arrow) and Export uses upload (up arrow)
        expect(find.byIcon(Icons.file_download_outlined), findsWidgets);
        expect(find.byIcon(Icons.file_upload_outlined), findsWidgets);
      },
    );

    testWidgets(
      'Import and Export actions use correct download/upload icon semantics',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        for (final r in List.of(appState.routers)) {
          await appState.removeRouter(r.id);
        }

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: ManageRoutersScreen())),
        );
        await tester.pumpAndSettle();

        // In empty state, the Import action in AppBar and the Import button in body both use file_download_outlined (arrow pointing down)
        final importIconFinder = find.byIcon(Icons.file_download_outlined);
        expect(importIconFinder, findsNWidgets(2));

        // In empty state, no file_upload_outlined icon is visible
        expect(find.byIcon(Icons.file_upload_outlined), findsNothing);
      },
    );
  });
}
