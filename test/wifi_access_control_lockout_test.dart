// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/wireless_management/screens/wifi_access_control_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    SelfDeviceGuard.setMockLocalAddresses({
      '192.168.1.50',
      'AA:AA:AA:AA:AA:AA',
    });
    await AppState.instance.initializationFuture;
  });

  tearDown(() {
    SelfDeviceGuard.setMockLocalAddresses(null);
  });

  group('WifiAccessControlScreen Self-Device Guard Lockout Tests', () {
    testWidgets(
      'Does NOT trigger phone lockout warning when editing a different MAC on a different SSID',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test-router-1',
          name: 'Primary Router',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'secret',
          useHttps: false,
        );
        await appState.routerService?.addRouter(testRouter);
        await appState.routerService?.selectRouter(testRouter.id);

        // Managing phone client connected to 5GHz SSID "Home_5G"
        final phoneClient = Client(
          ipAddress: '192.168.1.50',
          macAddress: 'AA:AA:AA:AA:AA:AA',
          hostname: 'My-Phone',
          connectionType: ConnectionType.wireless,
          ssid: 'Home_5G',
          wirelessIface: 'wlan0',
          isConnected: true,
        );

        // Different device to configure
        final otherClient = Client(
          ipAddress: '192.168.1.60',
          macAddress: 'BB:BB:BB:BB:BB:BB',
          hostname: 'Smart-Bulb',
          connectionType: ConnectionType.wireless,
          ssid: 'IoT_2.4G',
          wirelessIface: 'wlan1',
          isConnected: true,
        );

        appState.clients = [phoneClient, otherClient];

        // Seed wireless config with 2 interfaces: Home_5G and IoT_2.4G
        appState.setDashboardDataForTesting({
          'wireless': {
            'radio0': {
              'interfaces': [
                {
                  'section': 'default_radio0',
                  'config': {
                    'ssid': 'Home_5G',
                    'device': 'radio0',
                    'mode': 'ap',
                    'macfilter': 'disable',
                    'maclist': <String>[],
                  },
                },
              ],
            },
            'radio1': {
              'interfaces': [
                {
                  'section': 'default_radio1',
                  'config': {
                    'ssid': 'IoT_2.4G',
                    'device': 'radio1',
                    'mode': 'ap',
                    'macfilter': 'disable',
                    'maclist': <String>[],
                  },
                },
              ],
            },
          },
        });

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: WifiAccessControlScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Select the other client
        await tester.tap(find.byType(DropdownButtonFormField<Client>));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Smart-Bulb').last);
        await tester.pumpAndSettle();

        // Check the IoT_2.4G SSID checkbox (where the phone is NOT connected)
        final iotCheckbox = find.widgetWithText(CheckboxListTile, 'IoT_2.4G');
        expect(iotCheckbox, findsOneWidget);
        await tester.tap(iotCheckbox);
        await tester.pumpAndSettle();

        // Tap the Apply button
        final applyButton = find.textContaining('Access Rules');
        expect(applyButton, findsOneWidget);
        await tester.tap(applyButton);
        await tester.pumpAndSettle();

        // Verify: Device Lockout Warning dialog should NOT be shown!
        expect(find.text('Device Lockout Warning'), findsNothing);

        // Verify: Confirm Wi-Fi Access Rules dialog IS shown directly
        expect(find.text('Confirm Wi-Fi Access Rules'), findsOneWidget);
        expect(
          find.textContaining(
            'Updating Wi-Fi Access Control for BB:BB:BB:BB:BB:BB',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Does NOT trigger phone lockout warning when managing device is connected via wired Ethernet',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;

        // Managing device connected via wired Ethernet
        final wiredClient = Client(
          ipAddress: '192.168.1.50',
          macAddress: 'AA:AA:AA:AA:AA:AA',
          hostname: 'Admin-PC',
          connectionType: ConnectionType.wired,
          isConnected: true,
        );

        final otherClient = Client(
          ipAddress: '192.168.1.70',
          macAddress: 'CC:CC:CC:CC:CC:CC',
          hostname: 'Tablet',
          connectionType: ConnectionType.wireless,
          ssid: 'Home_5G',
          isConnected: true,
        );

        appState.clients = [wiredClient, otherClient];

        appState.setDashboardDataForTesting({
          'wireless': {
            'radio0': {
              'interfaces': [
                {
                  'section': 'default_radio0',
                  'config': {
                    'ssid': 'Home_5G',
                    'device': 'radio0',
                    'mode': 'ap',
                    'macfilter': 'disable',
                    'maclist': <String>[],
                  },
                },
              ],
            },
          },
        });

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: WifiAccessControlScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Select the other client
        await tester.tap(find.byType(DropdownButtonFormField<Client>));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Tablet').last);
        await tester.pumpAndSettle();

        // Check the Home_5G checkbox
        final homeCheckbox = find.widgetWithText(CheckboxListTile, 'Home_5G');
        expect(homeCheckbox, findsOneWidget);
        await tester.tap(homeCheckbox);
        await tester.pumpAndSettle();

        // Tap Apply
        final applyButton = find.textContaining('Access Rules');
        await tester.tap(applyButton);
        await tester.pumpAndSettle();

        // Because admin is on wired Ethernet, no lockout warning should appear
        expect(find.text('Device Lockout Warning'), findsNothing);
        expect(find.text('Confirm Wi-Fi Access Rules'), findsOneWidget);
      },
    );

    testWidgets(
      'DOES trigger phone lockout warning when changing access on the SSID the phone is actively connected to',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;

        // Managing phone client connected to Home_5G
        final phoneClient = Client(
          ipAddress: '192.168.1.50',
          macAddress: 'AA:AA:AA:AA:AA:AA',
          hostname: 'My-Phone',
          connectionType: ConnectionType.wireless,
          ssid: 'Home_5G',
          wirelessIface: 'wlan0',
          isConnected: true,
        );

        final otherClient = Client(
          ipAddress: '192.168.1.60',
          macAddress: 'BB:BB:BB:BB:BB:BB',
          hostname: 'Friend-Phone',
          connectionType: ConnectionType.wireless,
          ssid: 'Home_5G',
          isConnected: true,
        );

        appState.clients = [phoneClient, otherClient];

        appState.setDashboardDataForTesting({
          'wireless': {
            'radio0': {
              'interfaces': [
                {
                  'section': 'default_radio0',
                  'config': {
                    'ssid': 'Home_5G',
                    'device': 'radio0',
                    'mode': 'ap',
                    'macfilter': 'disable',
                    'maclist': <String>[],
                  },
                },
              ],
            },
          },
        });

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: WifiAccessControlScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Select Friend-Phone
        await tester.tap(find.byType(DropdownButtonFormField<Client>));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Friend-Phone').last);
        await tester.pumpAndSettle();

        // Check Home_5G (which will restrict Home_5G to allow-only with only Friend-Phone, kicking off My-Phone!)
        final homeCheckbox = find.widgetWithText(CheckboxListTile, 'Home_5G');
        expect(homeCheckbox, findsOneWidget);
        await tester.tap(homeCheckbox);
        await tester.pumpAndSettle();

        // Tap Apply
        final applyButton = find.textContaining('Access Rules');
        await tester.tap(applyButton);
        await tester.pumpAndSettle();

        // Now the Device Lockout Warning MUST appear to prevent user from locking out their active Wi-Fi session!
        expect(find.text('Device Lockout Warning'), findsOneWidget);
        expect(find.textContaining('AA:AA:AA:AA:AA:AA'), findsOneWidget);
      },
    );
  });
}
