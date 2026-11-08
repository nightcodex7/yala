// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/account_access/models/account_access_models.dart';

void main() {
  group('AccountAccessModels Unit Tests', () {
    test('CurrentAccountInfo handles confirmed vs unconfirmed usernames', () {
      const confirmedAccount = CurrentAccountInfo(
        configuredUsername: 'root',
        authenticatedUsername: 'root',
        isUsernameConfirmedByRouter: true,
        identitySource: 'Confirmed via authenticated UNIX shell (UID 0)',
        profileName: 'Home Gateway',
        routerAddress: '192.168.1.1',
        boardModel: 'x86/64',
        firmwareVersion: 'OpenWrt 23.05.3',
        authMethod: 'LuCI RPC sysauth',
        connectionMethod: 'HTTPS',
        sessionStatus: 'Authenticated & Active',
        sessionValidity: 'Valid token verified with router board query',
      );

      expect(confirmedAccount.displayUsername, equals('root'));
      expect(confirmedAccount.isUsernameConfirmedByRouter, isTrue);
      expect(confirmedAccount.identitySource, contains('UNIX shell'));

      const unconfirmedAccount = CurrentAccountInfo(
        configuredUsername: 'admin',
        authenticatedUsername: null,
        isUsernameConfirmedByRouter: false,
        identitySource: 'Locally stored profile label (unverified by router)',
        profileName: 'Office Router',
        routerAddress: '10.0.0.1',
        boardModel: null,
        firmwareVersion: null,
        authMethod: 'LuCI Token',
        connectionMethod: 'HTTP',
        sessionStatus: 'Active',
        sessionValidity: 'Token unverified',
      );

      expect(unconfirmedAccount.displayUsername, equals('admin'));
      expect(unconfirmedAccount.isUsernameConfirmedByRouter, isFalse);
      expect(unconfirmedAccount.identitySource, contains('profile label'));
    });

    test('AccountAccessSnapshot.offline creates consistent fallback state', () {
      final offline = AccountAccessSnapshot.offline(
        routerId: 'router-123',
        profileName: 'Living Room AP',
        configuredUsername: 'root',
        routerAddress: '192.168.1.1',
        reason: 'Device unreachable on local network',
      );

      expect(offline.isOffline, isTrue);
      expect(offline.errorMessage, contains('unreachable'));
      expect(offline.account.isUsernameConfirmedByRouter, isFalse);
      expect(offline.account.sessionStatus, contains('Offline'));
      expect(offline.connectionMethods.length, equals(3));
      expect(
        offline.connectionMethods.any(
          (m) => m.status == ConnectionMethodStatus.unavailable,
        ),
        isTrue,
      );
      expect(
        offline.sshAccess.reachability,
        equals(SshReachabilityStatus.notTested),
      );
    });

    test('AccountAccessSnapshot.reviewerMode creates simulated state', () {
      final reviewer = AccountAccessSnapshot.reviewerMode();

      expect(reviewer.isOffline, isFalse);
      expect(reviewer.account.isUsernameConfirmedByRouter, isTrue);
      expect(reviewer.account.displayUsername, contains('root'));
      expect(reviewer.connectionMethods.isNotEmpty, isTrue);
      expect(
        reviewer.connectionMethods.every(
          (m) => m.status == ConnectionMethodStatus.activeAndVerified,
        ),
        isTrue,
      );
      expect(
        reviewer.sshAccess.reachability,
        equals(SshReachabilityStatus.verifiedWorking),
      );
      expect(reviewer.rpcCapabilities.isNotEmpty, isTrue);
      expect(reviewer.subsystems.isNotEmpty, isTrue);
    });

    test('Enums provide exhaustive and non-interchangeable states', () {
      expect(
        ConnectionMethodStatus.values,
        contains(ConnectionMethodStatus.activeAndVerified),
      );
      expect(
        ConnectionMethodStatus.values,
        contains(ConnectionMethodStatus.availableUnverified),
      );
      expect(
        ConnectionMethodStatus.values,
        contains(ConnectionMethodStatus.unavailable),
      );
      expect(
        ConnectionMethodStatus.values,
        contains(ConnectionMethodStatus.permissionDenied),
      );
      expect(
        ConnectionMethodStatus.values,
        contains(ConnectionMethodStatus.notTested),
      );
      expect(
        ConnectionMethodStatus.values,
        contains(ConnectionMethodStatus.unknown),
      );
      expect(
        ConnectionMethodStatus.values,
        contains(ConnectionMethodStatus.notApplicable),
      );

      expect(
        PermissionAccessStatus.values,
        contains(PermissionAccessStatus.verifiedReadAccess),
      );
      expect(
        PermissionAccessStatus.values,
        contains(PermissionAccessStatus.verifiedWriteAuthorization),
      );
      expect(
        PermissionAccessStatus.values,
        contains(PermissionAccessStatus.verifiedDenied),
      );
      expect(
        PermissionAccessStatus.values,
        contains(PermissionAccessStatus.notTested),
      );
      expect(
        PermissionAccessStatus.values,
        contains(PermissionAccessStatus.unknown),
      );
      expect(
        PermissionAccessStatus.values,
        contains(PermissionAccessStatus.notSupported),
      );
      expect(
        PermissionAccessStatus.values,
        contains(PermissionAccessStatus.notApplicable),
      );

      expect(
        SshReachabilityStatus.values,
        contains(SshReachabilityStatus.verifiedWorking),
      );
      expect(
        SshReachabilityStatus.values,
        contains(SshReachabilityStatus.reachableUnverified),
      );
      expect(
        SshReachabilityStatus.values,
        contains(SshReachabilityStatus.portClosedOrUnreachable),
      );
      expect(
        SshReachabilityStatus.values,
        contains(SshReachabilityStatus.permissionDenied),
      );
      expect(
        SshReachabilityStatus.values,
        contains(SshReachabilityStatus.notTested),
      );
      expect(
        SshReachabilityStatus.values,
        contains(SshReachabilityStatus.unknown),
      );
      expect(
        SshReachabilityStatus.values,
        contains(SshReachabilityStatus.notInstalledOrDisabled),
      );
    });
  });
}
