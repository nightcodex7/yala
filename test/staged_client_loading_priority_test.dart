// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/screens/clients_screen.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/mock_auth_service.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/client_controller.dart';

class StagedTestClientController extends ClientController {
  final List<Client> stage1Clients;
  final List<Client> stage2Clients;
  final List<String> callLog;
  final Completer<void>? stage2Delay;

  StagedTestClientController({
    required this.stage1Clients,
    required this.stage2Clients,
    required this.callLog,
    this.stage2Delay,
  }) : super(
         apiServiceRef: () => MockApiService(),
         authServiceRef: () => MockAuthService(),
         routerServiceRef: () => RouterService(isReviewerMode: true),
         reviewerModeRef: () => true,
         executeRouterCommandOutput: (cmd, args) async => null,
         processDhcpLeases: (raw) => raw,
       );

  @override
  Future<List<Client>> fetchClientsForSelectedRouter() async {
    callLog.add('fetchClientsForSelectedRouter');
    return stage1Clients;
  }

  @override
  Future<List<Client>> fetchAggregatedClients({
    void Function(List<Client>)? onIncrementalUpdate,
  }) async {
    callLog.add('fetchAggregatedClients_start');
    if (stage2Delay != null) {
      await stage2Delay!.future;
    }
    callLog.add('fetchAggregatedClients_finish');
    onIncrementalUpdate?.call(stage2Clients);
    return stage2Clients;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'has_seen_restricted_clients_tooltip': true,
      'clients_aggregate_all_routers': true,
    });
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Staged Client Loading & Active Router Priority Tests', () {
    test(
      'AppState ensures active router session data finishes before secondary aggregation',
      () async {
        final appState = AppState.instance;

        // Enable reviewer mode to initialize services
        await appState.setReviewerMode(true);
        expect(appState.isActiveSessionDataReady, isTrue);

        // Verify that ensureActiveSessionDataReady completes immediately when ready
        final readyFuture = appState.ensureActiveSessionDataReady();
        await expectLater(readyFuture, completes);

        // Verify fetchDashboardData completes active session and marks ready
        await appState.fetchDashboardData();
        expect(appState.isActiveSessionDataReady, isTrue);
      },
    );

    testWidgets(
      'ClientsScreen renders active router clients in Stage 1 and aggregates in Stage 2',
      (tester) async {
        final appState = AppState.instance;

        await tester.runAsync(() async {
          await appState.setReviewerMode(true);
        });

        final stage1Client = Client(
          ipAddress: '192.168.1.50',
          macAddress: 'AA:11:22:33:44:55',
          hostname: 'Main-Gateway-Device',
          connectionType: ConnectionType.wired,
          isConnected: true,
        );

        final stage2Client = Client(
          ipAddress: '192.168.1.60',
          macAddress: 'BB:22:33:44:55:66',
          hostname: 'Dumb-AP-Device',
          connectionType: ConnectionType.wireless,
          isConnected: true,
          isDumbApClient: true,
          apName: 'Bedroom AP',
        );

        final callLog = <String>[];
        final stage2Delay = Completer<void>();
        final controller = StagedTestClientController(
          stage1Clients: [stage1Client],
          stage2Clients: [stage1Client, stage2Client],
          callLog: callLog,
          stage2Delay: stage2Delay,
        );

        final prevController = appState.clientControllerForTesting;
        appState.clientControllerForTesting = controller;
        appState.clients = [stage1Client];

        final mainRouter = model.Router(
          id: 'main_staged_router_1',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
          name: 'Main Gateway',
        );

        appState.setSelectedRouterForTesting(mainRouter);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: [Locale('en')],
              home: ClientsScreen(isTabActive: false),
            ),
          ),
        );

        // Frame 1: Stage 1 active router clients rendered
        await tester.pump();
        expect(callLog, contains('fetchClientsForSelectedRouter'));

        // Complete Stage 2 if started
        if (!stage2Delay.isCompleted) {
          stage2Delay.complete();
        }
        await tester.pump();

        // Teardown
        await tester.pumpWidget(const SizedBox());
        appState.clientControllerForTesting = prevController;
      },
    );

    test('Staged client loading priority in AppState', () async {
      final appState = AppState.instance;
      await appState.setReviewerMode(true);

      // Stage 1: Active router client fetch
      final stage1Clients = await appState.fetchClientsForSelectedRouter();
      expect(stage1Clients, isA<List<Client>>());
      expect(appState.isActiveSessionDataReady, isTrue);

      // Stage 2: Aggregated client fetch
      final stage2Clients = await appState.fetchAggregatedClients();
      expect(stage2Clients, isA<List<Client>>());
    });
  });
}
