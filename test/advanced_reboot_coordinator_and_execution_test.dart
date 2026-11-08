// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/models/reboot_capability.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/models/reboot_state.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/services/advanced_reboot_coordinator.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/operation_queue.dart';

class ExecutionTestApiService extends MockApiService {
  List<String> executedCommands = [];
  bool rebootCallSucceeded = true;
  String postBootActiveSlot = '2';
  bool shouldFailProbeOnline = false;

  @override
  Future<bool> reboot(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    executedCommands.add('reboot');
    return rebootCallSucceeded;
  }

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
    if (object == 'file' && method == 'exec') {
      final cmd = params?['command']?.toString() ?? '';
      final args =
          (params?['args'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final full = ([cmd, ...args]).join(' ');
      executedCommands.add(full);

      if (cmd.contains('fw_printenv') && args.contains('boot_part')) {
        return {'stdout': postBootActiveSlot, 'code': 0};
      }
      if (cmd.contains('fw_printenv') && args.contains('boot_part_ready')) {
        return {'stdout': '3', 'code': 0};
      }
      if (cmd == 'which') {
        return {'stdout': '/usr/sbin/fw_setenv\n', 'code': 0};
      }
      return {'stdout': 'OK', 'code': 0, 'exit_code': 0};
    }

    if (object == 'system' && method == 'board') {
      return {
        'board_name': 'linksys,ea8300',
        'model': 'Linksys EA8300',
        'release': {'target': 'ipq40xx/generic', 'version': '23.05.3'},
      };
    }

    if (object == 'file' && method == 'read') {
      final path = params?['path'];
      if (path == '/proc/mtd') {
        return {
          'data': '''
mtd0: 00080000 00020000 "sbl1"
mtd5: 00600000 00020000 "kernel"
mtd6: 02800000 00020000 "rootfs"
mtd7: 00600000 00020000 "alt_kernel"
mtd8: 02800000 00020000 "alt_rootfs"
''',
        };
      }
    }

    return super.call(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }
}

/// Coordinator subclass that overrides probeOnline for reliable, fast test execution without real HTTP sockets.
class TestableAdvancedRebootCoordinator extends AdvancedRebootCoordinator {
  bool mockOnlineResponse;
  int probeCalls = 0;

  TestableAdvancedRebootCoordinator({
    required super.apiService,
    super.sshService,
    super.operationQueue,
    super.detector,
    this.mockOnlineResponse = true,
  }) : super(
         disconnectDelay: Duration.zero,
         initialRebootDelay: Duration.zero,
         pollDelayProvider: (_) => Duration.zero,
         maxPollAttempts: 3,
       );

  @override
  Future<bool> probeOnline(String ipAddress, bool useHttps) async {
    probeCalls++;
    return mockOnlineResponse;
  }
}

void main() {
  group('AdvancedRebootCoordinator Execution Tests', () {
    late Router router;
    late AdvancedRebootCapabilities supportedCaps;
    late AdvancedRebootCapabilities unsupportedCaps;

    setUp(() {
      router = Router(
        id: 'router_test_id',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
      );

      supportedCaps = AdvancedRebootCapabilities(
        routerId: router.id,
        detectedAt: DateTime.now(),
        environment: const DeviceBootEnvironment(
          boardName: 'linksys,ea8300',
          model: 'Linksys EA8300',
          releaseVersion: '23.05.3',
          targetArchitecture: 'ipq40xx/generic',
          activeSlot: '1',
          alternateSlot: '2',
          hasFwPrintenv: true,
          hasFwSetenv: true,
        ),
        matchedProfileId: 'linksys_ea8300',
        capabilities: {
          RebootOperationType.standardReboot: const OperationCapability(
            operation: RebootOperationType.standardReboot,
            status: CapabilityStatus.supported,
            reason: 'Standard reboot supported',
          ),
          RebootOperationType.alternatePartitionBoot: const OperationCapability(
            operation: RebootOperationType.alternatePartitionBoot,
            status: CapabilityStatus.supported,
            reason: 'Alternate partition boot supported',
            targetIdentifier: '2',
            riskLevel: RiskLevel.high,
          ),
          RebootOperationType.powerOff: const OperationCapability(
            operation: RebootOperationType.powerOff,
            status: CapabilityStatus.supported,
            reason: 'Power off supported',
          ),
        },
      );

      unsupportedCaps = AdvancedRebootCapabilities(
        routerId: router.id,
        detectedAt: DateTime.now(),
        environment: const DeviceBootEnvironment(
          boardName: 'generic',
          model: 'Generic Router',
          releaseVersion: '23.05.3',
        ),
        capabilities: {
          RebootOperationType.standardReboot: const OperationCapability(
            operation: RebootOperationType.standardReboot,
            status: CapabilityStatus.supported,
            reason: 'Standard reboot supported',
          ),
          RebootOperationType.alternatePartitionBoot: const OperationCapability(
            operation: RebootOperationType.alternatePartitionBoot,
            status: CapabilityStatus.unsupported,
            reason: 'Single partition layout',
          ),
          RebootOperationType.powerOff: const OperationCapability(
            operation: RebootOperationType.powerOff,
            status: CapabilityStatus.unsupported,
            reason: 'Hardware poweroff not supported',
          ),
        },
      );
    });

    test('Unsupported operation is rejected during preflight', () async {
      final api = ExecutionTestApiService();
      final coordinator = TestableAdvancedRebootCoordinator(apiService: api);

      final progress = await coordinator.execute(
        router: router,
        sysauth: 'token',
        operation: RebootOperationType.alternatePartitionBoot,
        capabilities: unsupportedCaps,
        targetSlot: '2',
      );

      expect(progress.isFailed, isTrue);
      expect(progress.failureReason, contains('Single partition layout'));
      expect(api.executedCommands, isEmpty); // No commands sent to router
    });

    test(
      'Missing target slot for alternate boot is rejected during preflight',
      () async {
        final api = ExecutionTestApiService();
        final coordinator = TestableAdvancedRebootCoordinator(apiService: api);

        final progress = await coordinator.execute(
          router: router,
          sysauth: 'token',
          operation: RebootOperationType.alternatePartitionBoot,
          capabilities: supportedCaps,
          targetSlot: null, // missing target slot
        );

        expect(progress.isFailed, isTrue);
        expect(
          progress.failureReason,
          contains('Missing target partition identifier'),
        );
        expect(api.executedCommands, isEmpty);
      },
    );

    test('Conflicting active exclusive operation blocks execution', () async {
      final api = ExecutionTestApiService();
      final queue = RouterScopedOperationQueue.instance;
      final coordinator = TestableAdvancedRebootCoordinator(
        apiService: api,
        operationQueue: queue,
      );

      // Simulate a concurrent upgrade / maintenance operation holding exclusive lock
      await queue.runLocked(
        routerId: router.id,
        domain: '*',
        action: () async {
          final progress = await coordinator.execute(
            router: router,
            sysauth: 'token',
            operation: RebootOperationType.standardReboot,
            capabilities: supportedCaps,
          );

          expect(progress.isFailed, isTrue);
          expect(progress.failureReason, contains('exclusive lock is busy'));
          expect(api.executedCommands, isEmpty);
        },
      );
    });

    test(
      'User cancellation prior to submission safely aborts with cancelled state',
      () async {
        final api = ExecutionTestApiService();
        final coordinator = TestableAdvancedRebootCoordinator(apiService: api);

        coordinator.cancel(); // Pre-cancel

        final progress = await coordinator.execute(
          router: router,
          sysauth: 'token',
          operation: RebootOperationType.standardReboot,
          capabilities: supportedCaps,
        );

        expect(progress.isCancelled, isTrue);
        expect(api.executedCommands, isEmpty);
      },
    );

    test('Standard reboot executes apiService.reboot and succeeds', () async {
      final api = ExecutionTestApiService();
      final coordinator = TestableAdvancedRebootCoordinator(
        apiService: api,
        mockOnlineResponse: true,
      );

      final progressList = <RebootExecutionState>[];
      final result = await coordinator.execute(
        router: router,
        sysauth: 'token',
        operation: RebootOperationType.standardReboot,
        capabilities: supportedCaps,
        onProgress: (p) => progressList.add(p.state),
      );

      expect(result.isSucceeded, isTrue);
      expect(api.executedCommands, contains('reboot'));
      expect(progressList, contains(RebootExecutionState.executing));
      expect(progressList, contains(RebootExecutionState.reconnecting));
      expect(progressList, contains(RebootExecutionState.succeeded));
    });

    test(
      'Alternate boot executes fw_setenv and reboots, verifying new partition',
      () async {
        final api = ExecutionTestApiService();
        api.postBootActiveSlot = '2'; // Router successfully boots into Slot 2

        final coordinator = TestableAdvancedRebootCoordinator(
          apiService: api,
          mockOnlineResponse: true,
        );

        final progressList = <RebootExecutionState>[];
        final result = await coordinator.execute(
          router: router,
          sysauth: 'token',
          operation: RebootOperationType.alternatePartitionBoot,
          capabilities: supportedCaps,
          targetSlot: '2',
          onProgress: (p) => progressList.add(p.state),
        );

        expect(result.isSucceeded, isTrue);
        expect(result.message, contains('booted into Partition Slot 2'));

        // Check fixed commands dispatched
        expect(
          api.executedCommands.any((c) => c.contains('fw_setenv boot_part 2')),
          isTrue,
        );
        expect(
          api.executedCommands.any(
            (c) => c.contains('fw_setenv boot_part_ready 2'),
          ),
          isTrue,
        );
        expect(api.executedCommands, contains('reboot'));

        expect(progressList, contains(RebootExecutionState.verifying));
        expect(progressList, contains(RebootExecutionState.succeeded));
      },
    );

    test('Alternate boot detects partition revert and reports failed', () async {
      final api = ExecutionTestApiService();
      api.postBootActiveSlot = '1'; // Bootloader reverted back to Slot 1!

      final coordinator = TestableAdvancedRebootCoordinator(
        apiService: api,
        mockOnlineResponse: true,
      );

      final result = await coordinator.execute(
        router: router,
        sysauth: 'token',
        operation: RebootOperationType.alternatePartitionBoot,
        capabilities: supportedCaps,
        targetSlot: '2',
      );

      // MUST NOT report succeeded if the router booted back into original partition!
      expect(result.isFailed, isTrue);
      expect(result.isSucceeded, isFalse);
      expect(result.failureReason, contains('reverted to original partition'));
      expect(
        result.message,
        contains('reverted to Partition Slot 1 instead of target Slot 2'),
      );
    });

    test(
      'Reconnection timeout transitions to outcomeUnknown without blind retry',
      () async {
        final api = ExecutionTestApiService();
        final coordinator = TestableAdvancedRebootCoordinator(
          apiService: api,
          mockOnlineResponse: false, // Router never responds
        );

        final result = await coordinator.execute(
          router: router,
          sysauth: 'token',
          operation: RebootOperationType.standardReboot,
          capabilities: supportedCaps,
        );

        expect(result.isOutcomeUnknown, isTrue);
        expect(result.isSucceeded, isFalse);
        expect(result.failureReason, contains('timed out'));

        // Verify command was executed exactly ONCE and not retried blindly
        final rebootCount = api.executedCommands
            .where((c) => c == 'reboot')
            .length;
        expect(rebootCount, equals(1));
      },
    );

    test(
      'Poweroff executes /sbin/poweroff and terminates without infinite polling',
      () async {
        final api = ExecutionTestApiService();
        final coordinator = TestableAdvancedRebootCoordinator(
          apiService: api,
          mockOnlineResponse: false, // Router disconnects when powered off
        );

        final result = await coordinator.execute(
          router: router,
          sysauth: 'token',
          operation: RebootOperationType.powerOff,
          capabilities: supportedCaps,
        );

        expect(result.isSucceeded, isTrue);
        expect(
          result.message,
          contains('Device has powered down successfully'),
        );
        expect(
          api.executedCommands.any((c) => c.contains('/sbin/poweroff')),
          isTrue,
        );
      },
    );
  });
}
