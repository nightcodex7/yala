// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/system_monitoring/models/router_temperature.dart';
import 'package:yet_another_luci_app/screens/dashboard_screen.dart';
import 'package:yet_another_luci_app/screens/more_screen.dart';
import 'package:yet_another_luci_app/screens/settings_screen.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/rpc_permissions_dialog.dart';

RouterCapabilities _createIncompleteCaps() {
  return RouterCapabilities(
    routerId: 'test-router',
    ubusObjects: const {'uci'},
    ubusMethods: const {
      'file': ['read'],
    },
    packageEngine: PackageManagerEngine.opkg,
    firewallBackend: FirewallBackend.fw4,
    networkModel: NetworkModel.dsa,
    releaseVersion: 'OpenWrt 23.05.3',
    boardName: 'test-board',
    probedAt: DateTime.now(),
  );
}

RouterCapabilities _createCompleteCaps() {
  return RouterCapabilities(
    routerId: 'test-router',
    ubusObjects: const {
      'system',
      'luci-rpc',
      'network.interface',
      'iwinfo',
      'file',
      'service',
      'rc',
      'uci',
      'opkg',
      'fw4',
    },
    ubusMethods: const {
      'system': ['info', 'board', 'reboot'],
      'luci-rpc': ['getInitList', 'getWirelessDevices'],
      'file': ['read', 'stat', 'exec'],
    },
    uciPermissions: const {
      '*': ['read', 'write'],
    },
    packageEngine: PackageManagerEngine.opkg,
    firewallBackend: FirewallBackend.fw4,
    networkModel: NetworkModel.dsa,
    releaseVersion: 'OpenWrt 23.05.3',
    boardName: 'test-board',
    probedAt: DateTime.now(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('MoreScreen Deduping & Permanent RPC Management', () {
    testWidgets(
      'MoreScreen does not display duplicate RPC & Permissions or Change Router Password tiles',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(_createIncompleteCaps());

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: MoreScreen())),
        );
        await tester.pumpAndSettle();

        // Duplicate tiles must NOT appear on top-level MoreScreen
        expect(find.text('RPC & Permissions'), findsNothing);
        expect(find.text('Change Router Password'), findsNothing);
      },
    );

    testWidgets(
      'SettingsScreen displays RPC & Permissions and opens verified state in RpcPermissionsDialog',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(_createCompleteCaps());

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: SettingsScreen())),
        );
        await tester.pumpAndSettle();

        expect(find.text('Manage'), findsOneWidget);

        // Tap the tile to verify it opens verified state in RpcPermissionsDialog
        await tester.tap(find.text('Manage'));
        await tester.pumpAndSettle();

        expect(find.byType(RpcPermissionsDialog), findsOneWidget);
        expect(
          find.text(
            'Router RPC modules and backend execution permissions are verified and functioning properly.',
          ),
          findsOneWidget,
        );
        expect(find.text('Re-verify / Repair'), findsOneWidget);
        expect(find.text('Manual Setup / Verification Script'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Re-verify / Repair in SettingsScreen pops dialog and shows Permissions Verified toast without timing out',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(_createCompleteCaps());

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: LuciToastManager.navigatorKey,
            home: const ProviderScope(child: SettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Manage'));
        await tester.pumpAndSettle();

        expect(find.byType(RpcPermissionsDialog), findsOneWidget);

        // Tap Re-verify / Repair
        await tester.tap(find.text('Re-verify / Repair'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Dialog should be popped
        expect(find.byType(RpcPermissionsDialog), findsNothing);

        // Success toast should be displayed
        expect(find.text('Permissions Verified'), findsOneWidget);
        expect(
          find.text('RPC modules and permissions are active.'),
          findsOneWidget,
        );

        // Fast forward past the toast display duration (e.g. 5s)
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        // Verify that "Operation Timed Out" was NEVER shown
        expect(find.text('Operation Timed Out'), findsNothing);
      },
    );
  });

  group('Permanent RPC Status in SettingsScreen', () {
    testWidgets(
      'SettingsScreen capabilities tile shows RPC Status and manage button',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(_createCompleteCaps());

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: SettingsScreen())),
        );
        await tester.pumpAndSettle();

        // Capabilities tile should show RPC Status: READY
        expect(find.text('RPC Status: '), findsOneWidget);
        expect(find.text('READY'), findsOneWidget);
        expect(find.text('Manage'), findsOneWidget);
        expect(
          find.text('RPC permissions & execution modules verified'),
          findsOneWidget,
        );

        // Tap Manage button opens dialog
        await tester.tap(find.text('Manage'));
        await tester.pumpAndSettle();

        expect(find.byType(RpcPermissionsDialog), findsOneWidget);
      },
    );

    testWidgets(
      'SettingsScreen capabilities tile shows SETUP REQUIRED and Auto-Fix when missing',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(_createIncompleteCaps());

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: SettingsScreen())),
        );
        await tester.pumpAndSettle();

        expect(find.text('RPC Status: '), findsOneWidget);
        expect(find.text('SETUP REQUIRED'), findsOneWidget);
        expect(find.text('Auto-Fix'), findsOneWidget);
        expect(
          find.text(
            'Missing RPC permissions may restrict advanced router management features',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('DashboardScreen Banner Dismissal without Lingering Chips', () {
    testWidgets(
      'Dismissing RPC warning removes banner completely from Dashboard',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_incomplete',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
        );
        await appState.routerService?.addRouter(testRouter);
        await appState.routerService?.selectRouter(testRouter.id);

        appState.setDashboardPreferencesForTesting(
          DashboardPreferences(showQuickActions: true),
        );
        appState.setCapabilitiesForTesting(_createIncompleteCaps());
        appState.setDashboardDataForTesting({
          'sysInfo': {
            'uptime': 3600,
            'memory': {
              'total': 256000000,
              'free': 128000000,
              'buffered': 10000000,
            },
            'load': [0.15, 0.20, 0.25],
          },
          'boardInfo': {
            'hostname': 'OpenWrt-Router',
            'model': 'Test Hardware',
            'release': {'version': '23.05.2'},
          },
          'temperature': RouterTemperature.unavailable(
            hasPhysicalSensors: false,
            isHandlerInstalled: false,
            reason:
                'Thermal sensors are not supported on this router hardware.',
          ),
          'wireless': <String, dynamic>{},
          'clients': <Map<String, dynamic>>[],
        });

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: DashboardScreen())),
        );
        await tester.pumpAndSettle();

        // Banner should initially be visible
        expect(find.text('LuCI RPC Package Required'), findsOneWidget);
        expect(find.byTooltip('Dismiss'), findsOneWidget);

        // Dismiss the banner
        await tester.tap(find.byTooltip('Dismiss'));
        await tester.pumpAndSettle();

        // Ensure banner is gone AND no compact notice chip remains in Dashboard
        expect(find.text('LuCI RPC Package Required'), findsNothing);
        expect(find.text('Missing RPC Packages'), findsNothing);
        expect(find.text('RPC Permissions Required'), findsNothing);
        expect(find.text('Fix Permissions'), findsNothing);
      },
    );
  });

  group('RPC Fix Script & Toast Localization Resilience', () {
    test('getPermissionsFixScript creates ACL file and reloads rpcd', () {
      final script = ApiService.getPermissionsFixScript();
      final aclIndex = script.indexOf(
        'cat << \'EOF\' > /usr/share/rpcd/acl.d/yet-another-luci-app.json',
      );
      final reloadIndex = script.indexOf(
        '/etc/init.d/rpcd restart 2>/dev/null || /etc/init.d/rpcd reload',
      );

      expect(aclIndex, isNonNegative);
      expect(reloadIndex, isNonNegative);

      // ACL creation must come before rpcd restart/reload
      expect(aclIndex < reloadIndex, isTrue);

      // Script handles both apk and opkg package managers
      expect(script.contains('command -v apk'), isTrue);
      expect(script.contains('apk add'), isTrue);
      expect(script.contains('opkg install'), isTrue);
    });

    testWidgets(
      'LuciToastManager shows localized Operation Timed Out toast message on timeout',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: LuciToastManager.navigatorKey,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            home: Builder(
              builder: (ctx) {
                return ElevatedButton(
                  onPressed: () {
                    LuciToastManager.safeShowLoading(
                      ctx,
                      'Test Loading',
                      actionKey: 'test_action',
                      timeout: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Start Loading'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Trigger loading toast
        await tester.tap(find.text('Start Loading'));
        await tester.pump();

        expect(find.text('Test Loading'), findsOneWidget);

        // Advance timer past the 100ms timeout
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump();

        // Verify localized German title and subtitle
        expect(find.text('Vorgang abgelaufen'), findsOneWidget);
        expect(
          find.text(
            'Die Anforderung hat zu lange gedauert. Bitte überprüfen Sie die Netzwerkverbindung.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
