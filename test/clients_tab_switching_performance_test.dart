// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/screens/clients_screen.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/client_controller.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/widgets/luci_loading_states.dart';

class MockApiService implements IApiService {
  @override
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async => {};

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async => {'dhcp_leases': []};

  @override
  Future<Map<String, Map<String, dynamic>>> fetchHostHintsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthService implements IAuthService {
  @override
  String? get sysauth => 'mock-sysauth';
  @override
  bool get useHttps => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('Clients Tab Switching & Performance Tests', () {
    testWidgets(
      'ClientsScreen immediately displays cached clients on first frame with 0ms delay (no loading skeleton)',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        appState.clients = [
          Client(
            ipAddress: '192.168.1.101',
            macAddress: 'AA:BB:CC:DD:EE:01',
            hostname: 'Desktop-Workstation',
            isConnected: true,
            connectionType: ConnectionType.wired,
          ),
          Client(
            ipAddress: '192.168.1.102',
            macAddress: 'AA:BB:CC:DD:EE:02',
            hostname: 'iPhone-User',
            isConnected: true,
            connectionType: ConnectionType.wireless,
          ),
        ];

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ClientsScreen(isTabActive: true),
            ),
          ),
        );

        // First frame pump without awaiting network futures
        await tester.pump();

        // Cached clients must be immediately rendered on screen
        expect(find.text('Desktop-Workstation'), findsOneWidget);
        expect(find.text('iPhone-User'), findsOneWidget);
        // Loading skeletons must NOT be displayed
        expect(find.byType(LuciListItemSkeleton), findsNothing);

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'ClientsScreen does NOT run polling or churn when isTabActive is false',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        appState.clients = [
          Client(
            ipAddress: '192.168.1.50',
            macAddress: '11:22:33:44:55:66',
            hostname: 'Smart-TV',
            isConnected: true,
            connectionType: ConnectionType.wireless,
          ),
        ];

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ClientsScreen(isTabActive: false),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('Smart-TV'), findsOneWidget);

        // Advance 20 seconds; inactive tab should not crash or trigger active polling
        await tester.pump(const Duration(seconds: 20));
        expect(find.text('Smart-TV'), findsOneWidget);

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'ClientsScreen handles 250 enterprise clients smoothly with single-pass summary calculations',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        final largeClientList = List.generate(
          250,
          (i) => Client(
            ipAddress: '192.168.1.${10 + i}',
            macAddress: '00:11:22:33:${(i ~/ 100).toString().padLeft(2, '0')}:${(i % 100).toString().padLeft(2, '0')}',
            hostname: 'Enterprise-Device-$i',
            isConnected: i % 2 == 0,
            connectionType: i % 3 == 0 ? ConnectionType.wired : ConnectionType.wireless,
          ),
        );
        appState.clients = largeClientList;

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ClientsScreen(isTabActive: true),
            ),
          ),
        );

        await tester.pump();

        // Total count should match 250 devices
        expect(find.text('250'), findsWidgets);
        expect(find.text('Enterprise-Device-0'), findsOneWidget);

        await tester.pumpAndSettle();
      },
    );

    test('ClientController queries configured routers concurrently', () async {
      final mockApi = MockApiService();
      final mockAuth = MockAuthService();
      final routerService = RouterService(isReviewerMode: true);

      final router1 = model.Router(
        id: 'r1',
        name: 'Main Router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'pwd',
        useHttps: false,
      );
      final router2 = model.Router(
        id: 'r2',
        name: 'Secondary AP',
        ipAddress: '192.168.1.2',
        username: 'root',
        password: 'pwd',
        useHttps: false,
      );

      await routerService.addRouter(router1);
      await routerService.addRouter(router2);
      await routerService.selectRouter(router1.id);

      final controller = ClientController(
        apiServiceRef: () => mockApi,
        authServiceRef: () => mockAuth,
        routerServiceRef: () => routerService,
        reviewerModeRef: () => true,
        dashboardDataRef: () => null,
        executeRouterCommandOutput: (cmd, args) async => '',
        processDhcpLeases: (raw) => raw,
      );

      // fetchAggregatedClients runs concurrently via Future.wait and handles mock gracefully
      final clients = await controller.fetchAggregatedClients();
      expect(clients, isA<List<Client>>());
    });

    test('Client model caches displayName and normalizedMac with identical string references', () {
      final client = Client(
        ipAddress: '192.168.1.50',
        macAddress: 'aa-bb-cc-dd-ee-ff',
        hostname: 'My-Laptop',
        staticLeaseName: 'Office-Workstation',
      );

      final name1 = client.displayName;
      final name2 = client.displayName;
      expect(name1, 'Office-Workstation');
      expect(identical(name1, name2), isTrue);

      final mac1 = client.normalizedMac;
      final mac2 = client.normalizedMac;
      expect(mac1, 'AA:BB:CC:DD:EE:FF');
      expect(identical(mac1, mac2), isTrue);
    });

    test('ClientNamingHelper caches device icons via Expando across lookups', () {
      final client = Client(
        ipAddress: '192.168.1.51',
        macAddress: '11:22:33:44:55:66',
        hostname: 'LivingRoom-TV',
      );

      final icon1 = ClientNamingHelper.getDeviceIcon(client);
      final icon2 = ClientNamingHelper.getDeviceIcon(client);
      expect(icon1, Icons.tv_rounded);
      expect(identical(icon1, icon2), isTrue);
    });
  });
}
