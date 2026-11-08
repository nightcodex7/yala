// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import '../../../models/router.dart';
import '../../../services/interfaces/api_service_interface.dart';
import '../../../services/interfaces/ssh_service_interface.dart';
import '../../../services/operation_queue.dart';
import '../../../utils/logger.dart';
import '../adapters/acpi_poweroff_adapter.dart';
import '../adapters/boot_adapter_registry.dart';
import '../models/reboot_capability.dart';
import '../models/reboot_state.dart';
import '../profiles/device_profile_registry.dart';
import 'advanced_reboot_detector.dart';

typedef ProgressCallback = void Function(RebootExecutionProgress progress);

/// Coordinates safe, serialized execution and post-operation verification of reboot actions.
class AdvancedRebootCoordinator {
  final IApiService apiService;
  final ISshService? sshService;
  final RouterScopedOperationQueue operationQueue;
  final AdvancedRebootDetector detector;
  final DeviceProfileRegistry registry;
  final BootAdapterRegistry adapterRegistry;
  final Duration disconnectDelay;
  final Duration initialRebootDelay;
  final Duration Function(int attempt)? pollDelayProvider;
  final Future<bool> Function(String ipAddress, bool useHttps)? onlineProber;
  final int maxPollAttempts;

  bool _isCancelled = false;

  AdvancedRebootCoordinator({
    required this.apiService,
    this.sshService,
    RouterScopedOperationQueue? operationQueue,
    AdvancedRebootDetector? detector,
    DeviceProfileRegistry? registry,
    BootAdapterRegistry? adapterRegistry,
    this.disconnectDelay = const Duration(seconds: 5),
    this.initialRebootDelay = const Duration(seconds: 15),
    this.pollDelayProvider,
    this.onlineProber,
    this.maxPollAttempts = 30,
  }) : operationQueue = operationQueue ?? RouterScopedOperationQueue.instance,
       registry = registry ?? DeviceProfileRegistry.instance,
       adapterRegistry = adapterRegistry ?? BootAdapterRegistry.instance,
       detector =
           detector ??
           AdvancedRebootDetector(
             apiService: apiService,
             sshService: sshService,
             registry: registry,
             adapterRegistry: adapterRegistry,
           );

  /// Requests cancellation if the operation has not yet dispatched commands to the router.
  void cancel() {
    _isCancelled = true;
  }

  /// Executes a verified boot operation with full preflight checks, exclusive locking,
  /// bounded disconnect handling, and post-reboot verification.
  Future<RebootExecutionProgress> execute({
    required Router router,
    required String sysauth,
    required RebootOperationType operation,
    required AdvancedRebootCapabilities capabilities,
    String? targetSlot,
    String? sshUsername,
    String? sshPassword,
    int sshPort = 22,
    ProgressCallback? onProgress,
  }) async {
    final wasPreCancelled = _isCancelled;
    _isCancelled = false;
    final routerId = router.id;
    final ipAddress = router.ipAddress;
    final useHttps = router.useHttps;

    void updateProgress(RebootExecutionProgress progress) {
      onProgress?.call(progress);
    }

    // 1. Initial State: Preflight
    var progress = RebootExecutionProgress(
      state: RebootExecutionState.preflight,
      operation: operation,
      message: 'Performing pre-flight safety validations...',
      startedAt: DateTime.now(),
      targetSlot: targetSlot,
      canCancel: true,
    );
    updateProgress(progress);

    // 2. Preflight Validations
    if (wasPreCancelled || _isCancelled) {
      progress = progress.copyWith(
        state: RebootExecutionState.cancelled,
        message: 'Operation cancelled by user prior to submission.',
        canCancel: false,
      );
      updateProgress(progress);
      return progress;
    }

    final cap = capabilities.getOperation(operation);
    if (!cap.isSupported) {
      progress = progress.copyWith(
        state: RebootExecutionState.failed,
        message: 'Operation rejected: ${cap.reason}',
        failureReason: cap.reason,
        canCancel: false,
      );
      updateProgress(progress);
      return progress;
    }

    if (operation == RebootOperationType.alternatePartitionBoot) {
      if (targetSlot == null || targetSlot.isEmpty) {
        progress = progress.copyWith(
          state: RebootExecutionState.failed,
          message: 'Target partition slot is not defined.',
          failureReason: 'Missing target partition identifier',
          canCancel: false,
        );
        updateProgress(progress);
        return progress;
      }
    }

    // Check if another maintenance operation is already running
    if (operationQueue.isBusy(routerId, '*')) {
      progress = progress.copyWith(
        state: RebootExecutionState.failed,
        message:
            'A conflicting maintenance operation is currently running on this router. Reboot refused for safety.',
        failureReason: 'Router-exclusive lock is busy',
        canCancel: false,
      );
      updateProgress(progress);
      return progress;
    }

    // 3. Acquire Exclusive Router Lock
    try {
      return await operationQueue.runLocked<RebootExecutionProgress>(
        routerId: routerId,
        domain: '*',
        timeout: const Duration(seconds: 15),
        action: () async {
          if (_isCancelled) {
            progress = progress.copyWith(
              state: RebootExecutionState.cancelled,
              message:
                  'Operation cancelled by user before dispatching commands.',
              canCancel: false,
            );
            updateProgress(progress);
            return progress;
          }

          // 4. Dispatch Commands
          progress = progress.copyWith(
            state: RebootExecutionState.executing,
            message: 'Dispatching operation commands to router...',
            canCancel: false,
          );
          updateProgress(progress);

          final dispatchSuccess = await _dispatchOperation(
            router: router,
            sysauth: sysauth,
            operation: operation,
            capabilities: capabilities,
            targetSlot: targetSlot,
            sshUsername: sshUsername,
            sshPassword: sshPassword,
            sshPort: sshPort,
          );

          if (!dispatchSuccess) {
            progress = progress.copyWith(
              state: RebootExecutionState.failed,
              message: 'Failed to dispatch command to router.',
              failureReason: 'Router command submission rejected',
            );
            updateProgress(progress);
            return progress;
          }

          // 5. Waiting for Disconnect
          progress = progress.copyWith(
            state: RebootExecutionState.waitingForDisconnect,
            message: operation == RebootOperationType.powerOff
                ? 'Waiting for device to shut down...'
                : 'Waiting for router to initiate reboot...',
          );
          updateProgress(progress);

          // Allow the router a brief grace period to drop network connections
          if (disconnectDelay > Duration.zero) {
            await Future.delayed(disconnectDelay);
          }

          // 6. Handle Poweroff Terminal Path
          if (operation == RebootOperationType.powerOff) {
            // Check that router has indeed disconnected
            final stillOnline = await probeOnline(ipAddress, useHttps);
            if (stillOnline) {
              progress = progress.copyWith(
                state: RebootExecutionState.outcomeUnknown,
                message:
                    'Poweroff command was sent, but router still responds to network probes. Shutdown may be delayed or unsupported by the hardware.',
                failureReason:
                    'Router did not disconnect after poweroff command',
              );
              updateProgress(progress);
              return progress;
            }

            progress = progress.copyWith(
              state: RebootExecutionState.succeeded,
              message:
                  'Device has powered down successfully. Network access has terminated. '
                  'Physical intervention (power button or power cycle) is required to turn the router back on.',
            );
            updateProgress(progress);
            return progress;
          }

          // 7. Reconnection Polling for Reboot Operations
          progress = progress.copyWith(
            state: RebootExecutionState.reconnecting,
            message:
                'Router is rebooting. Waiting for router to come back online...',
            pollAttempt: 0,
            maxPollAttempts: maxPollAttempts,
          );
          updateProgress(progress);

          // Give router time to begin boot cycle before polling
          if (initialRebootDelay > Duration.zero) {
            await Future.delayed(initialRebootDelay);
          }

          final isOnline = await _pollForReconnection(
            ipAddress: ipAddress,
            useHttps: useHttps,
            maxAttempts: maxPollAttempts,
            onPollAttempt: (attempt, max) {
              progress = progress.copyWith(
                pollAttempt: attempt,
                maxPollAttempts: max,
                message:
                    'Polling for router availability (attempt $attempt of $max)...',
              );
              updateProgress(progress);
            },
          );

          if (!isOnline) {
            progress = progress.copyWith(
              state: RebootExecutionState.outcomeUnknown,
              message:
                  'Reboot was initiated, but the router did not become reachable within the timeout window. '
                  'If you rebooted into an alternate firmware, it may have different network settings or IP address.',
              failureReason: 'Reconnection polling timed out',
            );
            updateProgress(progress);
            return progress;
          }

          // 8. Post-Operation Verification
          progress = progress.copyWith(
            state: RebootExecutionState.verifying,
            message: 'Router is back online. Verifying boot outcome...',
          );
          updateProgress(progress);

          if (operation == RebootOperationType.standardReboot) {
            progress = progress.copyWith(
              state: RebootExecutionState.succeeded,
              message: 'Router rebooted successfully.',
            );
            updateProgress(progress);
            return progress;
          }

          if (operation == RebootOperationType.alternatePartitionBoot) {
            final verified = await _verifyAlternatePartitionBoot(
              router: router,
              sysauth: sysauth,
              capabilities: capabilities,
              expectedSlot: targetSlot!,
              sshUsername: sshUsername,
              sshPassword: sshPassword,
              sshPort: sshPort,
            );

            if (verified.isVerified) {
              progress = progress.copyWith(
                state: RebootExecutionState.succeeded,
                message:
                    'Verification successful: router booted into Partition Slot $targetSlot.',
              );
              updateProgress(progress);
              return progress;
            } else if (verified.revertedSlot != null) {
              progress = progress.copyWith(
                state: RebootExecutionState.failed,
                message:
                    'Reboot completed, but the router reverted to Partition Slot ${verified.revertedSlot} instead of target Slot $targetSlot.',
                failureReason: 'Bootloader reverted to original partition',
              );
              updateProgress(progress);
              return progress;
            } else {
              progress = progress.copyWith(
                state: RebootExecutionState.outcomeUnknown,
                message:
                    'Router rebooted, but active partition could not be verified (${verified.reason}).',
                failureReason: verified.reason,
              );
              updateProgress(progress);
              return progress;
            }
          }

          return progress;
        },
      );
    } catch (e, stack) {
      Logger.exception('Advanced Reboot execution failed', e, stack);
      progress = progress.copyWith(
        state: RebootExecutionState.failed,
        message: 'Reboot execution error: $e',
        failureReason: e.toString(),
        canCancel: false,
      );
      updateProgress(progress);
      return progress;
    }
  }

  /// Dispatches the specific operation commands safely.
  Future<bool> _dispatchOperation({
    required Router router,
    required String sysauth,
    required RebootOperationType operation,
    required AdvancedRebootCapabilities capabilities,
    String? targetSlot,
    String? sshUsername,
    String? sshPassword,
    int sshPort = 22,
  }) async {
    final ipAddress = router.ipAddress;
    final useHttps = router.useHttps;

    switch (operation) {
      case RebootOperationType.standardReboot:
        return await apiService.reboot(ipAddress, sysauth, useHttps);

      case RebootOperationType.alternatePartitionBoot:
        final cap = capabilities.getOperation(operation);
        final mechanismId = cap.mechanismId;
        final profileId = capabilities.matchedProfileId;
        final profile = profileId != null
            ? registry.allProfiles
                  .where((p) => p.profileId == profileId)
                  .firstOrNull
            : null;

        final adapter = adapterRegistry.getAdapter(mechanismId ?? '');

        List<List<String>> switchCommands;
        if (adapter != null) {
          switchCommands = adapter.prepareOperation(
            environment: capabilities.environment,
            operation: operation,
            targetSlot: targetSlot,
            matchedProfile: profile,
          );
        } else if (profile != null) {
          switchCommands = profile.getSwitchPartitionCommands(targetSlot!);
        } else {
          throw StateError(
            'No adapter or profile available to execute partition switch',
          );
        }

        // Execute verified partition-switch commands sequentially
        for (final cmd in switchCommands) {
          final execSuccess = await _executeFixedCommand(
            ipAddress: ipAddress,
            sysauth: sysauth,
            useHttps: useHttps,
            command: cmd[0],
            args: cmd.sublist(1),
            sshUsername: sshUsername,
            sshPassword: sshPassword,
            sshPort: sshPort,
          );
          if (!execSuccess) {
            Logger.error(
              'Failed to execute partition switch command: ${cmd.join(" ")}',
            );
            return false;
          }
        }

        // Trigger reboot after partition variables have been written
        return await apiService.reboot(ipAddress, sysauth, useHttps);

      case RebootOperationType.powerOff:
        final cap = capabilities.getOperation(operation);
        final adapter =
            adapterRegistry.getAdapter(cap.mechanismId ?? '') ??
            const AcpiPowerOffAdapter();
        final poweroffCmds = adapter.prepareOperation(
          environment: capabilities.environment,
          operation: operation,
        );
        for (final cmd in poweroffCmds) {
          final execSuccess = await _executeFixedCommand(
            ipAddress: ipAddress,
            sysauth: sysauth,
            useHttps: useHttps,
            command: cmd[0],
            args: cmd.sublist(1),
            sshUsername: sshUsername,
            sshPassword: sshPassword,
            sshPort: sshPort,
          );
          if (!execSuccess) return false;
        }
        return true;
    }
  }

  /// Executes a fixed command with RPC first and SSH as fallback.
  Future<bool> _executeFixedCommand({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String command,
    required List<String> args,
    String? sshUsername,
    String? sshPassword,
    int sshPort = 22,
  }) async {
    // 1. Try LuCI RPC file.exec
    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': command, 'params': args, 'args': args},
      );
      if (res is Map && (res['code'] == 0 || res['exit_code'] == 0)) {
        return true;
      }
      if (res is List && res.isNotEmpty && res[0] == 0) {
        return true;
      }
    } catch (_) {}

    // 2. Fallback to SSH if available
    if (sshService != null && sshUsername != null && sshPassword != null) {
      try {
        final fullCmd = ([command, ...args]).join(' ');
        final sshRes = await sshService!.executeCommand(
          host: ipAddress,
          username: sshUsername,
          password: sshPassword,
          port: sshPort,
          command: fullCmd,
        );
        return sshRes.success;
      } catch (_) {}
    }

    return false;
  }

  /// Polls the router until it responds or max attempts are exhausted.
  Future<bool> _pollForReconnection({
    required String ipAddress,
    required bool useHttps,
    required void Function(int attempt, int max) onPollAttempt,
    int maxAttempts = 30,
  }) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      onPollAttempt(attempt, maxAttempts);

      final online = await probeOnline(ipAddress, useHttps);
      if (online) {
        return true;
      }

      // Delay before next poll attempt
      final delay = pollDelayProvider != null
          ? pollDelayProvider!(attempt)
          : Duration(
              seconds: attempt < 2
                  ? 3
                  : attempt < 4
                  ? 5
                  : attempt < 6
                  ? 8
                  : 12,
            );
      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }
    }

    return false;
  }

  /// Probes router availability with a quick HTTP request or custom prober.
  Future<bool> probeOnline(String ipAddress, bool useHttps) async {
    if (onlineProber != null) {
      return await onlineProber!(ipAddress, useHttps);
    }
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..badCertificateCallback = ((cert, host, port) => true);
      final scheme = useHttps ? 'https' : 'http';
      final uri = Uri.parse('$scheme://$ipAddress/ubus');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write('{"jsonrpc":"2.0","id":1,"method":"list","params":[]}');
      final response = await request.close();
      return response.statusCode == 200 ||
          response.statusCode == 403 ||
          response.statusCode == 400;
    } catch (_) {
      return false;
    }
  }

  /// Verifies whether the newly booted router is running on the expected partition slot.
  Future<_PartitionVerificationResult> _verifyAlternatePartitionBoot({
    required Router router,
    required String sysauth,
    required AdvancedRebootCapabilities capabilities,
    required String expectedSlot,
    String? sshUsername,
    String? sshPassword,
    int sshPort = 22,
  }) async {
    try {
      // Re-detect environment using read-only queries
      final envRes = await detector.detect(
        routerId: router.id,
        ipAddress: router.ipAddress,
        sysauth: sysauth,
        useHttps: router.useHttps,
        sshUsername: sshUsername,
        sshPassword: sshPassword,
        sshPort: sshPort,
      );

      final currentSlot = envRes.environment.activeSlot;
      final cap = capabilities.getOperation(
        RebootOperationType.alternatePartitionBoot,
      );
      final profileId = capabilities.matchedProfileId;
      final profile = profileId != null
          ? registry.allProfiles
                .where((p) => p.profileId == profileId)
                .firstOrNull
          : null;
      final adapter = adapterRegistry.getAdapter(cap.mechanismId ?? '');

      if (adapter != null) {
        final verified = await adapter.verifyOutcome(
          preBootEnvironment: capabilities.environment,
          postBootEnvironment: envRes.environment,
          operation: RebootOperationType.alternatePartitionBoot,
          expectedTargetSlot: expectedSlot,
          matchedProfile: profile,
        );
        if (verified) {
          return _PartitionVerificationResult(
            isVerified: true,
            activeSlot: currentSlot ?? expectedSlot,
          );
        }
      }

      if (currentSlot == null) {
        return _PartitionVerificationResult(
          isVerified: false,
          reason: 'Active slot could not be read after reconnection',
        );
      }

      if (currentSlot == expectedSlot) {
        return _PartitionVerificationResult(
          isVerified: true,
          activeSlot: currentSlot,
        );
      } else {
        return _PartitionVerificationResult(
          isVerified: false,
          activeSlot: currentSlot,
          revertedSlot: currentSlot,
          reason: 'Active slot is $currentSlot, expected $expectedSlot',
        );
      }
    } catch (e) {
      return _PartitionVerificationResult(
        isVerified: false,
        reason: 'Post-boot verification query failed: $e',
      );
    }
  }
}

class _PartitionVerificationResult {
  final bool isVerified;
  final String? activeSlot;
  final String? revertedSlot;
  final String? reason;

  _PartitionVerificationResult({
    required this.isVerified,
    this.activeSlot,
    this.revertedSlot,
    this.reason,
  });
}
