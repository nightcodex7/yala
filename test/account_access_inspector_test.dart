// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart' hide Router;
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/services/interfaces/ssh_service_interface.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/modules/account_access/models/account_access_models.dart';
import 'package:yet_another_luci_app/modules/account_access/services/account_access_inspector.dart';

class TestInspectorApiService extends MockApiService {
  bool simulateSessionExpiry = false;
  bool simulateNetworkError = false;
  bool simulateMalformedResponse = false;
  bool dropbearConfigPresent = true;
  int dropbearPort = 22;

  // Track all called methods to verify strictly read-only behavior
  final List<String> calledObjectsAndMethods = [];
  int mutationCallCount = 0;

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    calledObjectsAndMethods.add('$object.$method');

    // Detect any mutation attempts
    if (method == 'set' ||
        method == 'commit' ||
        method == 'apply' ||
        method == 'add' ||
        method == 'delete' ||
        method == 'reboot' ||
        method == 'flash' ||
        method == 'upgrade' ||
        method == 'setPassword') {
      mutationCallCount++;
    }

    if (simulateNetworkError) {
      throw Exception('Simulated network timeout connecting to router');
    }

    if (simulateSessionExpiry) {
      return [6, 'Access denied'];
    }

    if (simulateMalformedResponse) {
      return 'Unexpected string response from broken LuCI endpoint';
    }

    if (object == 'system' && method == 'board') {
      return [
        0,
        {
          'model': 'MediaTek MT7981 TestBoard',
          'system': 'ARMv8 Processor rev 4',
          'release': {
            'description': 'OpenWrt 23.05.4 r24012-d4b46c0b39',
            'version': '23.05.4',
          },
        },
      ];
    }

    if (object == 'session' && method == 'access') {
      return [
        0,
        {
          'ubus': {
            'system': ['info', 'board', 'reboot'],
            'network.interface': ['dump', 'status'],
            'file': ['read', 'stat', 'exec'],
            'service': ['list'],
            'uci': ['get'],
            'opkg': ['list'],
            'log': ['read'],
          },
          'uci': {
            'system': ['read'],
            'network': ['read', 'write'],
            'wireless': ['read'],
            'firewall': ['read'],
            'dhcp': ['read', 'write'],
            'dropbear': ['read'],
          },
        },
      ];
    }

    if (object == 'uci' && method == 'get') {
      if (params?['config'] == 'dropbear') {
        if (!dropbearConfigPresent) {
          return [1, 'Entry not found'];
        }
        return [
          0,
          {
            'values': {
              'dropbear': {
                '.type': 'dropbear',
                'Port': dropbearPort.toString(),
                'PasswordAuth': 'on',
              },
            },
          },
        ];
      }
    }

    return super.call(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
    );
  }

  @override
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, String> values,
    BuildContext? context,
  }) async {
    mutationCallCount++;
    throw UnimplementedError('Strictly read-only: uciSet must never be called');
  }

  @override
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    mutationCallCount++;
    throw UnimplementedError(
      'Strictly read-only: uciCommit must never be called',
    );
  }

  @override
  Future<bool> uciApply(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    bool rollback = true,
    int timeout = 30,
  }) async {
    mutationCallCount++;
    throw UnimplementedError(
      'Strictly read-only: uciApply must never be called',
    );
  }

  @override
  Future<bool> reboot(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    mutationCallCount++;
    throw UnimplementedError('Strictly read-only: reboot must never be called');
  }
}

class TestInspectorSshService implements ISshService {
  bool shouldSucceed = true;
  String returnedUsername = 'root';
  String? failureType; // 'auth', 'refused', 'timeout', 'custom'
  String? executedCommand;
  int callCount = 0;

  @override
  Future<SshCommandResult> executeCommand({
    required String host,
    required String username,
    required String password,
    required String command,
    int port = 22,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    callCount++;
    executedCommand = command;

    if (!shouldSucceed) {
      if (failureType == 'auth') {
        return const SshCommandResult(
          exitCode: -1,
          stdout: '',
          stderr: 'SSH authentication failed: Permission denied (password)',
          success: false,
          errorMessage: 'SSH authentication failed: Permission denied',
        );
      } else if (failureType == 'refused') {
        return const SshCommandResult(
          exitCode: -1,
          stdout: '',
          stderr:
              'SocketException: Connection refused (OS Error: Connection refused, errno = 111)',
          success: false,
          errorMessage: 'Connection refused',
        );
      } else if (failureType == 'timeout') {
        return const SshCommandResult(
          exitCode: -1,
          stdout: '',
          stderr: 'TimeoutException after 0:00:04.000000',
          success: false,
          errorMessage: 'SSH connection timed out',
        );
      }
      return const SshCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Generic error',
        success: false,
        errorMessage: 'Probe execution failed',
      );
    }

    return SshCommandResult(
      exitCode: 0,
      stdout: returnedUsername,
      stderr: '',
      success: true,
    );
  }
}

void main() {
  late TestInspectorApiService mockApi;
  late TestInspectorSshService mockSsh;
  late AccountAccessInspector inspector;

  final testRouter = Router(
    id: 'test-router-uuid',
    ipAddress: '192.168.1.1',
    username: 'root',
    password: 'super_secret_test_password_123',
    useHttps: true,
    name: 'Home Test Gateway',
  );

  setUp(() {
    mockApi = TestInspectorApiService();
    mockSsh = TestInspectorSshService();
    inspector = AccountAccessInspector(
      apiService: mockApi,
      sshService: mockSsh,
    );
  });

  group('Account Identity Verification Tests', () {
    test(
      'Independently confirms username when bounded SSH read-only probe succeeds',
      () async {
        mockSsh.shouldSucceed = true;
        mockSsh.returnedUsername = 'root';

        final snapshot = await inspector.inspect(
          router: testRouter,
          sysauth: 'valid_test_sysauth_token',
          capabilities: null,
          isReviewerMode: false,
        );

        expect(snapshot.account.configuredUsername, equals('root'));
        expect(snapshot.account.authenticatedUsername, equals('root'));
        expect(snapshot.account.isUsernameConfirmedByRouter, isTrue);
        expect(snapshot.account.identitySource, contains('UNIX shell'));
        expect(snapshot.account.boardModel, contains('MediaTek MT7981'));
        expect(snapshot.account.firmwareVersion, contains('OpenWrt 23.05.4'));
        expect(mockSsh.executedCommand, equals('id -u -n'));
      },
    );

    test(
      'Marks username as unconfirmed local profile label when SSH is unavailable',
      () async {
        mockSsh.shouldSucceed = false;
        mockSsh.failureType = 'refused';

        final snapshot = await inspector.inspect(
          router: testRouter,
          sysauth: 'valid_test_sysauth_token',
          capabilities: null,
          isReviewerMode: false,
        );

        expect(snapshot.account.configuredUsername, equals('root'));
        expect(snapshot.account.authenticatedUsername, isNull);
        expect(snapshot.account.isUsernameConfirmedByRouter, isFalse);
        expect(snapshot.account.identitySource, contains('unconfirmed'));
      },
    );

    test('Handles missing / offline router gracefully', () async {
      final snapshot = await inspector.inspect(
        router: null,
        sysauth: null,
        capabilities: null,
        isReviewerMode: false,
      );

      expect(snapshot.isOffline, isTrue);
      expect(snapshot.account.sessionStatus, contains('Offline'));
      expect(snapshot.account.isUsernameConfirmedByRouter, isFalse);
    });

    test('Handles expired session token without crashing', () async {
      mockApi.simulateSessionExpiry = true;

      final snapshot = await inspector.inspect(
        router: testRouter,
        sysauth: 'expired_invalid_token',
        capabilities: null,
        isReviewerMode: false,
      );

      expect(snapshot.account.sessionStatus, contains('Expired'));
      expect(snapshot.account.sessionValidity, contains('non-zero'));
    });
  });

  group('Connection Methods & SSH Tests', () {
    test(
      'Reports LuCI HTTP and RPC as Active and Verified upon success',
      () async {
        final snapshot = await inspector.inspect(
          router: testRouter,
          sysauth: 'valid_token',
          capabilities: null,
          isReviewerMode: false,
        );

        final httpMethod = snapshot.connectionMethods.firstWhere(
          (m) => m.id == 'luci_http',
        );
        final rpcMethod = snapshot.connectionMethods.firstWhere(
          (m) => m.id == 'luci_rpc',
        );

        expect(
          httpMethod.status,
          equals(ConnectionMethodStatus.activeAndVerified),
        );
        expect(
          rpcMethod.status,
          equals(ConnectionMethodStatus.activeAndVerified),
        );
        expect(httpMethod.endpointOrPort, contains('HTTPS'));
      },
    );

    test('Reports SSH verified working when probe succeeds', () async {
      mockSsh.shouldSucceed = true;

      final snapshot = await inspector.inspect(
        router: testRouter,
        sysauth: 'valid_token',
        capabilities: null,
        isReviewerMode: false,
      );

      expect(
        snapshot.sshAccess.reachability,
        equals(SshReachabilityStatus.verifiedWorking),
      );
      expect(snapshot.sshAccess.hasActiveConnection, isTrue);
      expect(snapshot.sshAccess.readOnlyExecutionSucceeded, isTrue);
      expect(snapshot.sshAccess.authenticatedUser, equals('root'));
    });

    test('Reports SSH permission denied when password is rejected', () async {
      mockSsh.shouldSucceed = false;
      mockSsh.failureType = 'auth';

      final snapshot = await inspector.inspect(
        router: testRouter,
        sysauth: 'valid_token',
        capabilities: null,
        isReviewerMode: false,
      );

      expect(
        snapshot.sshAccess.reachability,
        equals(SshReachabilityStatus.permissionDenied),
      );
      expect(snapshot.sshAccess.readOnlyExecutionSucceeded, isFalse);
      expect(snapshot.sshAccess.explanation, contains('rejected'));
    });

    test(
      'Reports SSH port closed or unreachable on connection refused',
      () async {
        mockSsh.shouldSucceed = false;
        mockSsh.failureType = 'refused';

        final snapshot = await inspector.inspect(
          router: testRouter,
          sysauth: 'valid_token',
          capabilities: null,
          isReviewerMode: false,
        );

        expect(
          snapshot.sshAccess.reachability,
          equals(SshReachabilityStatus.portClosedOrUnreachable),
        );
        expect(snapshot.sshAccess.explanation, contains('closed'));
      },
    );

    test('Reports SSH connection timeout correctly', () async {
      mockSsh.shouldSucceed = false;
      mockSsh.failureType = 'timeout';

      final snapshot = await inspector.inspect(
        router: testRouter,
        sysauth: 'valid_token',
        capabilities: null,
        isReviewerMode: false,
      );

      expect(
        snapshot.sshAccess.reachability,
        equals(SshReachabilityStatus.portClosedOrUnreachable),
      );
    });

    test(
      'Skips SSH probe and reports Not Tested when password is empty',
      () async {
        final noPassRouter = testRouter.copyWith(password: '');

        final snapshot = await inspector.inspect(
          router: noPassRouter,
          sysauth: 'valid_token',
          capabilities: null,
          isReviewerMode: false,
        );

        expect(
          snapshot.sshAccess.reachability,
          equals(SshReachabilityStatus.notTested),
        );
        expect(mockSsh.callCount, equals(0));
        expect(
          snapshot.sshAccess.explanation,
          contains('password guessing is strictly avoided'),
        );
      },
    );

    test('Discovers custom SSH port from UCI dropbear configuration', () async {
      mockApi.dropbearPort = 2222;

      final snapshot = await inspector.inspect(
        router: testRouter,
        sysauth: 'valid_token',
        capabilities: null,
        isReviewerMode: false,
      );

      expect(snapshot.sshAccess.port, equals(2222));
      expect(snapshot.sshAccess.portSource, contains('UCI dropbear'));
    });
  });

  group('Permission Evaluation Tests', () {
    test('Distinguishes verified read access from write authorization', () async {
      final snapshot = await inspector.inspect(
        router: testRouter,
        sysauth: 'valid_token',
        capabilities: null,
        isReviewerMode: false,
      );

      // System info has verified read access, but write is not applicable
      final sysInfo = snapshot.rpcCapabilities.firstWhere(
        (c) => c.id == 'system_info',
      );
      expect(
        sysInfo.readStatus,
        equals(PermissionAccessStatus.verifiedReadAccess),
      );
      expect(sysInfo.writeStatus, equals(PermissionAccessStatus.notApplicable));

      // Network has verified read and verified write authorization (via UCI network ACL)
      final net = snapshot.rpcCapabilities.firstWhere(
        (c) => c.id == 'network_interfaces',
      );
      expect(net.readStatus, equals(PermissionAccessStatus.verifiedReadAccess));
      expect(
        net.writeStatus,
        equals(PermissionAccessStatus.verifiedWriteAuthorization),
      );

      // Firewall has verified read, but verified denied write (because 'write' was omitted in mock ACL)
      final fw = snapshot.rpcCapabilities.firstWhere(
        (c) => c.id == 'firewall_rules',
      );
      expect(fw.readStatus, equals(PermissionAccessStatus.verifiedReadAccess));
      expect(fw.writeStatus, equals(PermissionAccessStatus.verifiedDenied));
    });

    test('Evaluates unavailable wireless hardware as Not Supported', () async {
      final snapshot = await inspector.inspect(
        router: testRouter,
        sysauth: 'valid_token',
        capabilities: RouterCapabilities(
          routerId: 'wired_only',
          probedAt: DateTime.now(),
          ubusObjects: const {'system'},
        ),
        isReviewerMode: false,
      );

      final wireless = snapshot.rpcCapabilities.firstWhere(
        (c) => c.id == 'wireless_config',
      );
      expect(wireless.readStatus, equals(PermissionAccessStatus.notSupported));
      expect(wireless.writeStatus, equals(PermissionAccessStatus.notSupported));
    });

    test('Handles malformed response without throwing exceptions', () async {
      mockApi.simulateMalformedResponse = true;

      final snapshot = await inspector.inspect(
        router: testRouter,
        sysauth: 'valid_token',
        capabilities: null,
        isReviewerMode: false,
      );

      expect(
        snapshot.account.sessionValidity,
        contains('Session query returned non-zero'),
      );
    });

    test(
      'Handles network error without throwing unhandled exceptions',
      () async {
        mockApi.simulateNetworkError = true;

        final snapshot = await inspector.inspect(
          router: testRouter,
          sysauth: 'valid_token',
          capabilities: null,
          isReviewerMode: false,
        );

        expect(
          snapshot.account.sessionValidity,
          contains('Session probe failed'),
        );
      },
    );
  });

  group('Read-Only Safety Guarantee Tests', () {
    test('VERIFICATION: Zero mutation RPC methods are ever invoked', () async {
      await inspector.inspect(
        router: testRouter,
        sysauth: 'valid_token',
        capabilities: null,
        isReviewerMode: false,
      );

      // Verify that no write RPC was called
      expect(mockApi.mutationCallCount, equals(0));
      for (final call in mockApi.calledObjectsAndMethods) {
        expect(call.endsWith('.set'), isFalse);
        expect(call.endsWith('.commit'), isFalse);
        expect(call.endsWith('.apply'), isFalse);
        expect(call.endsWith('.add'), isFalse);
        expect(call.endsWith('.delete'), isFalse);
        expect(call.endsWith('.reboot'), isFalse);
        expect(call.endsWith('.setPassword'), isFalse);
      }
    });

    test(
      'VERIFICATION: No passwords, keys, or tokens appear in findings or diagnostics',
      () async {
        final snapshot = await inspector.inspect(
          router: testRouter,
          sysauth: 'super_secret_sysauth_token_9999',
          capabilities: null,
          isReviewerMode: false,
        );

        // Verify no password leak
        expect(
          snapshot.account.authMethod,
          isNot(contains('super_secret_test_password_123')),
        );
        expect(
          snapshot.sshAccess.explanation,
          isNot(contains('super_secret_test_password_123')),
        );
        expect(
          snapshot.sshAccess.securityNotes,
          isNot(contains('super_secret_test_password_123')),
        );

        // Verify no sysauth token leak
        for (final diag in snapshot.diagnostics) {
          expect(
            diag.message,
            isNot(contains('super_secret_sysauth_token_9999')),
          );
          expect(
            diag.evidence ?? '',
            isNot(contains('super_secret_sysauth_token_9999')),
          );
          expect(
            diag.message,
            isNot(contains('super_secret_test_password_123')),
          );
          expect(
            diag.evidence ?? '',
            isNot(contains('super_secret_test_password_123')),
          );
        }
      },
    );

    test(
      'Failed SSH probes do not execute repeated retries to prevent lockout',
      () async {
        mockSsh.shouldSucceed = false;
        mockSsh.failureType = 'auth';

        await inspector.inspect(
          router: testRouter,
          sysauth: 'valid_token',
          capabilities: null,
          isReviewerMode: false,
        );

        // Exactly 1 bounded probe was made; no retry loop
        expect(mockSsh.callCount, equals(1));
      },
    );
  });
}
