// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// Portions adapted from OpenWrt luci-app-advanced-reboot:
// Copyright (C) 2017-2024 Stan Grishin <stangri@melmac.ca> & OpenWrt Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/reboot_capability.dart';
import '../profiles/device_profile.dart';
import 'boot_mechanism_adapter.dart';

/// Generic boot mechanism adapter for U-Boot dual-partition systems requiring both
/// `boot_part` and `boot_part_ready` variables (e.g. Qualcomm IPQ40xx architectures).
class UBootBootPartReadyAdapter implements BootMechanismAdapter {
  const UBootBootPartReadyAdapter();

  @override
  String get adapterId => 'uboot_boot_part_ready';

  @override
  String get displayName =>
      'U-Boot Dual-Partition with Boot Readiness (boot_part + boot_part_ready)';

  @override
  Set<RebootOperationType> get supportedOperations => {
    RebootOperationType.alternatePartitionBoot,
  };

  @override
  Future<OperationCapability> inspectCapabilities({
    required DeviceBootEnvironment environment,
    required RebootOperationType operation,
    DeviceProfile? matchedProfile,
  }) async {
    if (operation != RebootOperationType.alternatePartitionBoot) {
      return OperationCapability(
        operation: operation,
        status: CapabilityStatus.unsupported,
        reason: '$displayName only handles alternate partition booting.',
        mechanismId: adapterId,
      );
    }

    if (!environment.hasDualPartitionLayout) {
      return OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unsupported,
        reason: 'Device partition scan confirms single firmware layout.',
        positiveEvidence: [
          'Storage scan completed (${environment.mtdPartitions.length} partitions)',
        ],
        mechanismId: adapterId,
        riskLevel: RiskLevel.low,
      );
    }

    final rawBootPart = environment.bootloaderEnv['boot_part']?.trim();
    final rawBootPartReady = environment.bootloaderEnv['boot_part_ready']
        ?.trim();

    if (rawBootPart == null || (rawBootPart != '1' && rawBootPart != '2')) {
      return OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unknown,
        reason:
            'Current active firmware partition could not be determined from U-Boot variables. Dual-firmware partition layout detected, but U-Boot variable "boot_part" is missing or unreadable.',
        mechanismId: adapterId,
        riskLevel: RiskLevel.high,
      );
    }

    // Must have boot_part_ready variable to use this adapter
    if (rawBootPartReady == null || rawBootPartReady.isEmpty) {
      return OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unsupported,
        reason: 'U-Boot environment does not use the boot_part_ready variable.',
        mechanismId: adapterId,
        riskLevel: RiskLevel.low,
      );
    }

    final missingUtils = <String>[];
    final positiveEvidence = <String>[
      'Dual-firmware partition layout verified in storage table',
      'U-Boot variables "boot_part" ($rawBootPart) and "boot_part_ready" ($rawBootPartReady) active',
    ];

    if (!environment.hasFwPrintenv) {
      missingUtils.add('fw_printenv utility missing or inaccessible');
    } else {
      positiveEvidence.add('fw_printenv utility verified');
    }

    if (!environment.hasFwSetenv) {
      missingUtils.add(
        'fw_setenv utility missing or execution permission denied',
      );
    } else {
      positiveEvidence.add(
        'fw_setenv utility verified with execution permission',
      );
    }

    if (missingUtils.isNotEmpty) {
      return OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unsupported,
        reason:
            'Bootloader control utilities are missing on the router (${missingUtils.join("; ")}).',
        positiveEvidence: positiveEvidence,
        missingOrConflictingEvidence: missingUtils,
        mechanismId: adapterId,
        riskLevel: RiskLevel.high,
      );
    }

    final activeSlot = rawBootPart;
    final targetSlot = activeSlot == '1' ? '2' : '1';
    positiveEvidence.add('Active partition identified as Slot $activeSlot');
    positiveEvidence.add(
      'Target alternate partition identified as Slot $targetSlot',
    );

    return OperationCapability(
      operation: RebootOperationType.alternatePartitionBoot,
      status: CapabilityStatus.supported,
      reason:
          'Verified U-Boot dual-partition boot mechanism with boot readiness. Currently booted on Slot $activeSlot. Ready to reboot into Slot $targetSlot.',
      positiveEvidence: positiveEvidence,
      prerequisites: [
        'Storage layout contains valid secondary firmware image in Slot $targetSlot',
        'U-Boot bootloader responds to fw_setenv boot_part and boot_part_ready',
      ],
      riskLevel: RiskLevel.high,
      targetIdentifier: targetSlot,
      mechanismId: adapterId,
      warningMessage:
          'You are about to switch the active boot partition to Slot $targetSlot via U-Boot boot_part and boot_part_ready. '
          'The alternate partition may contain different firmware, network configurations, or passwords. '
          'If the alternate firmware uses a different IP address, you will need to reconnect manually.',
    );
  }

  @override
  Future<String?> identifyActiveTarget({
    required DeviceBootEnvironment environment,
    DeviceProfile? matchedProfile,
  }) async {
    final raw = environment.bootloaderEnv['boot_part']?.trim();
    if (raw == '1' || raw == '2') return raw;
    return null;
  }

  @override
  Future<List<String>> enumerateBootTargets({
    required DeviceBootEnvironment environment,
    DeviceProfile? matchedProfile,
  }) async => const ['1', '2'];

  @override
  Future<bool> validateTarget({
    required DeviceBootEnvironment environment,
    required String targetSlot,
    DeviceProfile? matchedProfile,
  }) async {
    return targetSlot == '1' || targetSlot == '2';
  }

  @override
  List<List<String>> prepareOperation({
    required DeviceBootEnvironment environment,
    required RebootOperationType operation,
    String? targetSlot,
    DeviceProfile? matchedProfile,
  }) {
    if (operation != RebootOperationType.alternatePartitionBoot) {
      throw UnsupportedError(
        'Operation $operation not supported by UBootBootPartReadyAdapter',
      );
    }
    if (targetSlot == null || (targetSlot != '1' && targetSlot != '2')) {
      throw ArgumentError(
        'Invalid target slot "$targetSlot". Must be "1" or "2".',
      );
    }

    final slot = targetSlot;
    final readyVal = environment.bootloaderEnv['boot_part_ready']?.trim() == '3'
        ? '3'
        : slot;
    return [
      ['fw_setenv', 'boot_part', slot],
      ['fw_setenv', 'boot_part_ready', readyVal],
      ['reboot'],
    ];
  }

  @override
  Future<bool> verifyOutcome({
    required DeviceBootEnvironment preBootEnvironment,
    required DeviceBootEnvironment postBootEnvironment,
    required RebootOperationType operation,
    String? expectedTargetSlot,
    DeviceProfile? matchedProfile,
  }) async {
    final postSlot = await identifyActiveTarget(
      environment: postBootEnvironment,
    );
    return postSlot == expectedTargetSlot;
  }
}
