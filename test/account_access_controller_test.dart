// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/account_access/controllers/account_access_controller.dart';
import 'package:yet_another_luci_app/modules/account_access/models/account_access_models.dart';
import 'package:yet_another_luci_app/modules/account_access/services/account_access_inspector.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class ControllableAccountInspector extends AccountAccessInspector {
  Completer<AccountAccessSnapshot>? delayedCompleter;
  int inspectCallCount = 0;
  String? lastInspectedRouterId;

  ControllableAccountInspector();

  @override
  Future<AccountAccessSnapshot> inspect({
    required Router? router,
    required String? sysauth,
    required RouterCapabilities? capabilities,
    required bool isReviewerMode,
  }) async {
    inspectCallCount++;
    lastInspectedRouterId = router?.id;

    if (delayedCompleter != null) {
      return await delayedCompleter!.future;
    }

    if (router == null) {
      return AccountAccessSnapshot.offline(
        routerId: 'none',
        profileName: 'No router',
        configuredUsername: 'none',
        routerAddress: '0.0.0.0',
      );
    }

    return AccountAccessSnapshot(
      routerId: router.id,
      inspectedAt: DateTime.now(),
      inspectionDuration: const Duration(milliseconds: 15),
      account: CurrentAccountInfo(
        configuredUsername: router.username,
        authenticatedUsername: router.username,
        isUsernameConfirmedByRouter: true,
        identitySource: 'Test Mock Inspector',
        profileName: router.displayName,
        routerAddress: router.ipAddress,
        authMethod: 'Mock Auth',
        connectionMethod: 'HTTPS',
        sessionStatus: 'Active',
        sessionValidity: 'Valid',
      ),
      connectionMethods: const [],
      rpcCapabilities: const [],
      sshAccess: const SshAccessInfo(
        reachability: SshReachabilityStatus.verifiedWorking,
        port: 22,
        portSource: 'Test',
        daemonStatus: 'Active',
        hasActiveConnection: true,
        authenticatedUser: 'root',
        isIdentityConfirmed: true,
        readOnlyExecutionSucceeded: true,
        explanation: 'Verified',
        securityNotes: 'Safe',
      ),
      subsystems: const [],
      diagnostics: const [],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ControllableAccountInspector mockInspector;
  late ProviderContainer container;

  final routerA = Router(
    id: 'router-uuid-A',
    ipAddress: '192.168.1.1',
    username: 'root',
    password: 'passwordA',
    useHttps: true,
    name: 'Primary Router A',
  );

  final routerB = Router(
    id: 'router-uuid-B',
    ipAddress: '10.0.0.1',
    username: 'admin',
    password: 'passwordB',
    useHttps: false,
    name: 'Secondary Router B',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockInspector = ControllableAccountInspector();

    final appState = AppState.instance;
    appState.setSelectedRouterForTesting(routerA);

    container = ProviderContainer(
      overrides: [
        appStateProvider.overrideWith((ref) => appState),
        accountAccessControllerProvider.overrideWith((ref) {
          return AccountAccessController(ref: ref, inspector: mockInspector);
        }),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('AccountAccessController State Management Tests', () {
    test('Initializes and automatically performs first inspection', () async {
      final controller = container.read(
        accountAccessControllerProvider.notifier,
      );
      await controller.inspect(force: true);

      final state = container.read(accountAccessControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.hasSnapshot, isTrue);
      expect(state.snapshot?.routerId, equals('router-uuid-A'));
      expect(state.snapshot?.account.profileName, equals('Primary Router A'));
      expect(mockInspector.inspectCallCount, greaterThanOrEqualTo(1));
    });

    test('Manual refresh forces a fresh inspection query', () async {
      final controller = container.read(
        accountAccessControllerProvider.notifier,
      );
      await controller.inspect();
      final initialCount = mockInspector.inspectCallCount;

      await controller.refresh();

      expect(mockInspector.inspectCallCount, equals(initialCount + 1));
      final state = container.read(accountAccessControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.hasSnapshot, isTrue);
    });

    test(
      'Router switched while loading: late asynchronous response from previous router is discarded',
      () async {
        // Setup delayed completer to simulate long in-flight probe for router A
        final delayedCompleterA = Completer<AccountAccessSnapshot>();
        mockInspector.delayedCompleter = delayedCompleterA;

        final controller = container.read(
          accountAccessControllerProvider.notifier,
        );
        // Start inspection for Router A
        final futureA = controller.refresh();
        expect(
          container.read(accountAccessControllerProvider).isLoading,
          isTrue,
        );

        // While probe A is in-flight, user switches active router to Router B
        final appState = container.read(appStateProvider);
        appState.setSelectedRouterForTesting(routerB);

        // Trigger new inspection for Router B with immediate return
        mockInspector.delayedCompleter = null;
        final futureB = controller.refresh();
        await futureB;

        // Router B state should now be applied
        var currentState = container.read(accountAccessControllerProvider);
        expect(currentState.snapshot?.routerId, equals('router-uuid-B'));
        expect(
          currentState.snapshot?.account.profileName,
          equals('Secondary Router B'),
        );

        // Now resolve the late probe A response
        delayedCompleterA.complete(
          AccountAccessSnapshot.offline(
            routerId: 'router-uuid-A',
            profileName: 'Old Stale Router A',
            configuredUsername: 'root',
            routerAddress: '192.168.1.1',
          ),
        );
        await futureA;

        // Ensure Router A result DID NOT overwrite the active Router B state
        currentState = container.read(accountAccessControllerProvider);
        expect(currentState.snapshot?.routerId, equals('router-uuid-B'));
        expect(
          currentState.snapshot?.account.profileName,
          equals('Secondary Router B'),
        );
      },
    );
  });
}
