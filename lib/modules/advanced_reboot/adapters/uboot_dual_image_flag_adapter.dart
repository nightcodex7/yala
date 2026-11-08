// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// Portions adapted from OpenWrt luci-app-advanced-reboot:
// Copyright (C) 2017-2024 Stan Grishin <stangri@melmac.ca> & OpenWrt Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/reboot_capability.dart';
import '../profiles/device_profile.dart';
import 'boot_mechanism_adapter.dart';

/// Generic boot mechanism adapter for U-Boot dual-partition systems toggled via `DualImageFlag` (e.g. ZyXEL, D-Link).
class UBootDualImageFlagAdapter implements BootMechanismAdapter {
  const UBootDualImageFlagAdapter();

  @override
  String get adapterId => 'uboot_dual_image_flag';

  @override
  String get displayName =>
      'U-Boot Dual Image Flag Environment (DualImageFlag)';

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

    final rawFlag = environment.bootloaderEnv['DualImageFlag']?.trim();
    if (rawFlag == null || (rawFlag != '0' && rawFlag != '1')) {
      return OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unsupported,
        reason: 'U-Boot environment does not use DualImageFlag variable.',
        mechanismId: adapterId,
        riskLevel: RiskLevel.low,
      );
    }

    final missingUtils = <String>[];
    final positiveEvidence = <String>[
      'Dual-firmware partition layout verified in storage table',
      'U-Boot variable "DualImageFlag" is active (value: $rawFlag)',
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

    final activeSlot = rawFlag;
    final targetSlot = activeSlot == '0' ? '1' : '0';
    positiveEvidence.add('Active partition identified as Image $activeSlot');
    positiveEvidence.add(
      'Target alternate partition identified as Image $targetSlot',
    );

    return OperationCapability(
      operation: RebootOperationType.alternatePartitionBoot,
      status: CapabilityStatus.supported,
      reason:
          'Verified U-Boot DualImageFlag boot mechanism. Currently booted on Image $activeSlot. Ready to reboot into Image $targetSlot.',
      positiveEvidence: positiveEvidence,
      prerequisites: [
        'Storage layout contains valid secondary firmware image in Image $targetSlot',
        'U-Boot bootloader responds to fw_setenv DualImageFlag',
      ],
      riskLevel: RiskLevel.high,
      targetIdentifier: targetSlot,
      mechanismId: adapterId,
      warningMessage:
          'You are about to switch the active boot partition to Image $targetSlot via U-Boot DualImageFlag. '
          'The alternate partition may contain different firmware, network configurations, or passwords.',
    );
  }

  @override
  Future<String?> identifyActiveTarget({
    required DeviceBootEnvironment environment,
    DeviceProfile? matchedProfile,
  }) async {
    final raw = environment.bootloaderEnv['DualImageFlag']?.trim();
    if (raw == '0' || raw == '1') return raw;
    return null;
  }

  @override
  Future<List<String>> enumerateBootTargets({
    required DeviceBootEnvironment environment,
    DeviceProfile? matchedProfile,
  }) async => const ['0', '1'];

  @override
  Future<bool> validateTarget({
    required DeviceBootEnvironment environment,
    required String targetSlot,
    DeviceProfile? matchedProfile,
  }) async {
    return targetSlot == '0' || targetSlot == '1';
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
        'Operation $operation not supported by UBootDualImageFlagAdapter',
      );
    }
    if (targetSlot == null || (targetSlot != '0' && targetSlot != '1')) {
      throw ArgumentError(
        'Invalid target slot "$targetSlot". Must be "0" or "1".',
      );
    }

    final slot = targetSlot;
    return [
      ['fw_setenv', 'DualImageFlag', slot],
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
