// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// Portions adapted from OpenWrt luci-app-advanced-reboot:
// Copyright (C) 2017-2024 Stan Grishin <stangri@melmac.ca> & OpenWrt Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/reboot_capability.dart';
import '../profiles/device_profile.dart';
import 'boot_mechanism_adapter.dart';

/// Generic boot mechanism adapter for UBI-based dual-boot systems
/// (e.g. NAND flash routers using dual UBI volumes with `active` or `boot_bank` toggles).
class UbiDualBootAdapter implements BootMechanismAdapter {
  const UbiDualBootAdapter();

  @override
  String get adapterId => 'ubi_dual_boot';

  @override
  String get displayName => 'UBI Volume Dual-Boot (active / boot_bank)';

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

    // 1. Storage check: Look for UBI or dual rootfs/kernel indicators in MTD
    final mtdNames = environment.mtdPartitions
        .map((p) => p.name.toLowerCase())
        .toList();
    final hasUbiLayout =
        mtdNames.any((n) => n.contains('ubi')) ||
        (mtdNames.any(
              (n) => n.contains('rootfs_0') || n.contains('kernel_0'),
            ) &&
            mtdNames.any(
              (n) => n.contains('rootfs_1') || n.contains('kernel_1'),
            ));

    if (!hasUbiLayout && !environment.hasDualPartitionLayout) {
      return OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unsupported,
        reason: 'UBI dual-boot layout not detected on storage scan.',
        mechanismId: adapterId,
        riskLevel: RiskLevel.low,
      );
    }

    // 2. Variable check: Look for 'active' or 'boot_bank'
    String? varName;
    String? rawVal;
    if (environment.bootloaderEnv.containsKey('active')) {
      varName = 'active';
      rawVal = environment.bootloaderEnv['active']?.trim();
    } else if (environment.bootloaderEnv.containsKey('boot_bank')) {
      varName = 'boot_bank';
      rawVal = environment.bootloaderEnv['boot_bank']?.trim();
    }

    if (varName == null || rawVal == null || (rawVal != '0' && rawVal != '1')) {
      return OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unsupported,
        reason:
            'Bootloader environment does not use UBI active/boot_bank selection variables.',
        mechanismId: adapterId,
        riskLevel: RiskLevel.low,
      );
    }

    // 3. Utilities check
    final missingUtils = <String>[];
    final positiveEvidence = <String>[
      'UBI dual-bank layout verified in storage scan',
      'Bootloader variable "$varName" is active (value: $rawVal)',
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

    final activeSlot = rawVal;
    final targetSlot = activeSlot == '0' ? '1' : '0';
    positiveEvidence.add('Active UBI bank identified as Bank $activeSlot');
    positiveEvidence.add(
      'Target alternate UBI bank identified as Bank $targetSlot',
    );

    return OperationCapability(
      operation: RebootOperationType.alternatePartitionBoot,
      status: CapabilityStatus.supported,
      reason:
          'Verified UBI dual-boot mechanism. Currently booted on Bank $activeSlot. Ready to reboot into Bank $targetSlot.',
      positiveEvidence: positiveEvidence,
      prerequisites: [
        'Secondary UBI volume bank contains a valid bootable system',
        'Bootloader responds to fw_setenv $varName',
      ],
      riskLevel: RiskLevel.high,
      targetIdentifier: targetSlot,
      mechanismId: adapterId,
      warningMessage:
          'You are about to switch the active boot bank to Bank $targetSlot via $varName. '
          'The alternate bank may contain different firmware, network configurations, or passwords.',
    );
  }

  @override
  Future<String?> identifyActiveTarget({
    required DeviceBootEnvironment environment,
    DeviceProfile? matchedProfile,
  }) async {
    final active = environment.bootloaderEnv['active']?.trim();
    if (active == '0' || active == '1') return active;
    final bank = environment.bootloaderEnv['boot_bank']?.trim();
    if (bank == '0' || bank == '1') return bank;
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
        'Operation $operation not supported by UbiDualBootAdapter',
      );
    }
    if (targetSlot == null || (targetSlot != '0' && targetSlot != '1')) {
      throw ArgumentError(
        'Invalid target slot "$targetSlot". Must be "0" or "1".',
      );
    }

    final varName = environment.bootloaderEnv.containsKey('boot_bank')
        ? 'boot_bank'
        : 'active';
    final slot = targetSlot;

    return [
      ['fw_setenv', varName, slot],
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
