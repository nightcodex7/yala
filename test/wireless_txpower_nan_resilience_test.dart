// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/screens/dashboard_screen.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/screens/wireless_management_screen.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

void main() {
  group('Wireless txpower NaN and Auto handling tests', () {
    test('WirelessRadio.fromJson safely parses config with txpower auto', () {
      final radio = WirelessRadio.fromJson('radio0', {
        'up': true,
        'config': {
          'channel': '1',
          'htmode': 'HT20',
          'country': 'IN',
          'txpower': 'auto',
          'frequency': '2412',
        },
        'interfaces': [],
      }, null);

      expect(radio.name, 'radio0');
      expect(radio.channel, '1');
      expect(radio.txPowerDbm, isNull);
      expect(radio.frequency, 2412);
      expect(radio.country, 'IN');
    });

    test('WirelessStation.fromJson safely parses string/null metrics', () {
      final station = WirelessStation.fromJson('AA:BB:CC:DD:EE:FF', {
        'signal': '-65',
        'noise': '-90',
        'rx_rate': '54.0',
        'tx_rate': '72.2',
        'inactive': '10',
      });

      expect(station.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(station.signalDbm, -65);
      expect(station.noiseDbm, -90);
      expect(station.rxRate, 54.0);
      expect(station.txRate, 72.2);
      expect(station.inactiveSeconds, 10);
    });

    test(
      'WirelessOverview.fromDashboardData handles uci txpower auto and null wireless',
      () {
        final dashboardData = {
          'wireless': <String, dynamic>{},
          'uciWirelessConfig': {
            'values': {
              'radio0': {
                '.type': 'wifi-device',
                '.name': 'radio0',
                'channel': '1',
                'country': 'IN',
                'txpower': 'auto',
              },
              'default_radio0': {
                '.type': 'wifi-iface',
                '.name': 'default_radio0',
                'device': 'radio0',
                'ssid': 'MySSID',
                'disabled': '0',
              },
            },
          },
        };

        final overview = WirelessOverview.fromDashboardData(dashboardData);
        expect(overview.radios.length, 1);
        expect(overview.radios.first.name, 'radio0');
        expect(overview.radios.first.txPowerDbm, isNull);
        expect(overview.radios.first.interfaces.length, 1);
        expect(overview.radios.first.interfaces.first.ssid, 'MySSID');
      },
    );

    testWidgets(
      'DashboardScreen renders without crashing when wireless data has nan/auto',
      (tester) async {
        final container = ProviderContainer();
        final appState = container.read(appStateProvider);

        final liveDashboardData = {
          'boardInfo': {
            'model': 'Test Router',
            'hostname': 'OpenWrt',
            'release': {'version': '23.05.0'},
          },
          'sysInfo': {
            'uptime': 12345,
            'load': [0.1, 0.2, 0.3],
            'memory': {
              'total': 134217728,
              'free': 67108864,
              'shared': 0,
              'buffered': 1048576,
            },
          },
          'networkDevices': <String, dynamic>{},
          'interfaceDump': <String, dynamic>{'interface': []},
          'wireless': <String, dynamic>{
            'radio0': {
              'up': true,
              'config': {
                'channel': '1',
                'txpower': null, // result of sanitized nan
              },
              'interfaces': [],
            },
          },
          'uciWirelessConfig': {
            'values': {
              'radio0': {
                '.type': 'wifi-device',
                '.name': 'radio0',
                'txpower': 'auto',
                'country': 'IN',
                'channel': '1',
              },
            },
          },
          'wirelessStations': <String, dynamic>{},
          'wan': <String, dynamic>{},
        };

        appState.setDashboardDataForTesting(liveDashboardData);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: DashboardScreen(isTabActive: true)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(find.text('Test Router'), findsOneWidget);
      },
    );

    testWidgets(
      'WirelessManagementScreen displays accurate states: ACTIVE, SETUP FAILED, DISABLED',
      (tester) async {
        final container = ProviderContainer();
        final appState = container.read(appStateProvider);

        // radio0: Enabled, but setup failed on router -> SETUP FAILED (Amber)
        // radio1: Enabled and operating -> ACTIVE (Green)
        // radio2: Administratively disabled -> DISABLED (Grey)
        final dashboardData = {
          'wireless': {
            'radio0': {
              'up': false,
              'retry_setup_failed': true,
              'config': {'disabled': false, 'channel': '1', 'country': 'IN'},
              'interfaces': [],
            },
            'radio1': {
              'up': true,
              'retry_setup_failed': false,
              'config': {'disabled': false, 'channel': '36', 'country': 'IN'},
              'interfaces': [],
            },
            'radio2': {
              'up': false,
              'retry_setup_failed': false,
              'config': {'disabled': true, 'channel': '6', 'country': 'IN'},
              'interfaces': [],
            },
          },
        };

        appState.setDashboardDataForTesting(dashboardData);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: WirelessManagementScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('SETUP FAILED'), findsOneWidget);
        expect(find.text('ACTIVE'), findsOneWidget);
        expect(find.text('DISABLED'), findsOneWidget);
      },
    );
  });
}
