// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/client_speed_limit.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/bandwidth_monitor/screens/bandwidth_throttling_summary_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/client_speed_limit_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client testClient;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    testClient = Client(
      ipAddress: '192.168.1.150',
      macAddress: 'AA:BB:CC:DD:EE:FF',
      hostname: 'Test-Laptop',
      connectionType: ConnectionType.wireless,
      isConnected: true,
    );
  });

  group('ClientSpeedLimitDialog UI tests', () {
    testWidgets('renders inputs and suggestion chips correctly', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: ClientSpeedLimitDialog(client: testClient)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify client details
      expect(find.text('Test-Laptop'), findsOneWidget);
      expect(find.textContaining('192.168.1.150'), findsOneWidget);
      // Verify enable toggle is removed
      expect(find.text('Enable Speed Restriction'), findsNothing);
      expect(find.byType(Switch), findsNothing);

      // Verify labels
      expect(find.text('Download Limit'), findsOneWidget);
      expect(find.text('Upload Limit'), findsOneWidget);

      // Verify suggestion chips: 1 Mbps, 2 Mbps, 5 Mbps, 10 Mbps, 15 Mbps
      expect(find.text('1 Mbps'), findsAtLeastNWidgets(1));
      expect(find.text('2 Mbps'), findsAtLeastNWidgets(1));
      expect(find.text('5 Mbps'), findsAtLeastNWidgets(1));
      expect(find.text('10 Mbps'), findsAtLeastNWidgets(1));
      expect(find.text('15 Mbps'), findsAtLeastNWidgets(1));

      // Tap 15 Mbps suggestion chip under Download
      final chip15 = find.widgetWithText(ActionChip, '15 Mbps').first;
      await tester.tap(chip15);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify download field updated to 15
      expect(find.text('15'), findsOneWidget);
    });

    testWidgets('suggestion chip under upload sets Kbps correctly', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: ClientSpeedLimitDialog(client: testClient)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Tap 512 Kbps suggestion chip under Upload
      final chip512 = find.widgetWithText(ActionChip, '512 Kbps');
      expect(chip512, findsOneWidget);
      await tester.tap(chip512);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify upload field updated to 512
      expect(find.text('512'), findsOneWidget);
    });
  });

  group('BandwidthThrottlingSummaryScreen UI tests', () {
    testWidgets('renders empty state when no clients throttled', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: BandwidthThrottlingSummaryScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Bandwidth Throttling'), findsOneWidget);
      expect(find.text('No Speed Restrictions Active'), findsOneWidget);
      expect(find.text('Add Speed Limit'), findsOneWidget);
    });

    testWidgets('renders throttled clients when present in state', (
      tester,
    ) async {
      final appState = AppState.instance;
      final speedLimit = ClientSpeedLimit(
        targetMac: testClient.macAddress,
        ipAddress: testClient.ipAddress,
        downloadValue: 10,
        downloadUnit: 'Mbps',
        uploadValue: 2,
        uploadUnit: 'Mbps',
        enabled: true,
        hostname: 'Test-Laptop',
        updatedAt: DateTime.now(),
      );

      await appState.setClientSpeedLimit(speedLimit: speedLimit);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: BandwidthThrottlingSummaryScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Bandwidth Throttling'), findsOneWidget);
      expect(find.textContaining('1 Active Speed Restriction'), findsOneWidget);
      expect(find.text('Test-Laptop'), findsOneWidget);
      expect(find.textContaining('10.0 Mbps'), findsAtLeastNWidgets(1));
      expect(find.textContaining('2.0 Mbps'), findsAtLeastNWidgets(1));
      // Verify toggle switch is removed from throttled client card
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('only shows throttled clients for active router profile', (
      tester,
    ) async {
      final appState = AppState.instance;

      final routerA = model.Router(
        id: 'router_profile_A',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
        name: 'Office Router',
      );

      final routerB = model.Router(
        id: 'router_profile_B',
        ipAddress: '10.0.0.1',
        username: 'root',
        password: 'password',
        useHttps: false,
        name: 'Home Router',
      );

      // Set speed limit specifically on Router A
      final speedLimitA = ClientSpeedLimit(
        targetMac: 'AA:BB:CC:11:22:33',
        ipAddress: '192.168.1.55',
        downloadValue: 15,
        downloadUnit: 'Mbps',
        uploadValue: 5,
        uploadUnit: 'Mbps',
        enabled: true,
        hostname: 'Office-Workstation',
        updatedAt: DateTime.now(),
      );
      await appState.setClientSpeedLimit(
        speedLimit: speedLimitA,
        routerId: routerA.id,
      );

      // Make Router B active: it should NOT show Router A's throttled clients
      appState.setSelectedRouterForTesting(routerB);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: BandwidthThrottlingSummaryScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Bandwidth Throttling'), findsOneWidget);
      expect(find.text('Home Router (10.0.0.1)'), findsOneWidget);
      expect(find.text('No Speed Restrictions Active'), findsOneWidget);
      expect(find.text('Office-Workstation'), findsNothing);

      // Now switch active router profile to Router A
      appState.setSelectedRouterForTesting(routerA);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Router A should now show its throttled client
      expect(find.text('Office Router (192.168.1.1)'), findsOneWidget);
      expect(find.text('Office-Workstation'), findsOneWidget);
      expect(find.textContaining('15.0 Mbps'), findsAtLeastNWidgets(1));
      expect(find.textContaining('5.0 Mbps'), findsAtLeastNWidgets(1));
    });

    testWidgets(
      'disabling or removing speed limit transitions to empty state without black screen or crash',
      (tester) async {
        final appState = AppState.instance;

        final router = model.Router(
          id: 'router_test_toggle',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
          name: 'Test Router',
        );
        appState.setSelectedRouterForTesting(router);

        final limit = ClientSpeedLimit(
          targetMac: 'AA:BB:CC:DD:EE:FF',
          ipAddress: '192.168.1.50',
          downloadValue: 10,
          downloadUnit: 'Mbps',
          uploadValue: 2,
          uploadUnit: 'Mbps',
          enabled: true,
          hostname: 'Removable-Client',
          updatedAt: DateTime.now(),
        );
        await appState.setClientSpeedLimit(
          speedLimit: limit,
          routerId: router.id,
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: BandwidthThrottlingSummaryScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Removable-Client'), findsOneWidget);

        // Now remove the client limit
        await appState.removeClientSpeedLimit(
          'AA:BB:CC:DD:EE:FF',
          routerId: router.id,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        // Verifies that empty state renders without crashing with ref.watch error
        expect(find.text('No Speed Restrictions Active'), findsOneWidget);
        expect(find.text('Removable-Client'), findsNothing);
      },
    );
  });
}
