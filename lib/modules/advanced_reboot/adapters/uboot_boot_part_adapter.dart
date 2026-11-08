// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// Portions adapted from OpenWrt luci-app-advanced-reboot:
// Copyright (C) 2017-2024 Stan Grishin <stangri@melmac.ca> & OpenWrt Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/reboot_capability.dart';
import '../profiles/device_profile.dart';
import 'boot_mechanism_adapter.dart';

/// Generic boot mechanism adapter for U-Boot dual-partition systems toggled via `boot_part`.
///
/// Universal coverage: Supports ANY OpenWrt router utilizing standard U-Boot `boot_part`
/// environment variable switching with verified dual kernel/rootfs partitions.
class UBootBootPartAdapter implements BootMechanismAdapter {
  const UBootBootPartAdapter();

  @override
  String get adapterId => 'uboot_boot_part';

  @override
  String get displayName => 'Generic U-Boot Dual-Partition (boot_part)';

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

    // 1. Storage Layout Check
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

    // 2. Bootloader Variable Check
    final rawBootPart = environment.bootloaderEnv['boot_part']?.trim();
    if (rawBootPart == null || (rawBootPart != '1' && rawBootPart != '2')) {
      return OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unknown,
        reason:
            'Current active firmware partition could not be determined from U-Boot variables. Dual-firmware partition layout detected, but U-Boot variable "boot_part" is missing or unreadable.',
        positiveEvidence: ['Dual partition layout verified in storage table'],
        missingOrConflictingEvidence: [
          'boot_part U-Boot environment variable is not present or unreadable',
        ],
        mechanismId: adapterId,
        riskLevel: RiskLevel.high,
      );
    }

    // 3. Bootloader Control Utilities Check
    final missingUtils = <String>[];
    final positiveEvidence = <String>[
      'Dual-firmware partition layout verified in storage table',
      'U-Boot variable "boot_part" is active (value: $rawBootPart)',
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
          'Verified U-Boot dual-partition boot mechanism. Currently booted on Slot $activeSlot. Ready to reboot into Slot $targetSlot.',
      positiveEvidence: positiveEvidence,
      prerequisites: [
        'Storage layout contains valid secondary firmware image in Slot $targetSlot',
        'U-Boot bootloader responds to fw_setenv boot_part',
      ],
      riskLevel: RiskLevel.high,
      targetIdentifier: targetSlot,
      mechanismId: adapterId,
      warningMessage:
          'You are about to switch the active boot partition to Slot $targetSlot via U-Boot boot_part. '
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
        'Operation $operation not supported by UBootBootPartAdapter',
      );
    }
    if (targetSlot == null || (targetSlot != '1' && targetSlot != '2')) {
      throw ArgumentError(
        'Invalid target slot "$targetSlot". Must be "1" or "2".',
      );
    }

    final slot = targetSlot;
    return [
      ['fw_setenv', 'boot_part', slot],
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
