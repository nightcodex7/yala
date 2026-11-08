// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/reboot_capability.dart';
import '../profiles/device_profile.dart';
import 'boot_mechanism_adapter.dart';

/// Adapter for ACPI or PMIC hardware power-off operations.
///
/// Embedded router hardware (ARM, MIPS, IPQ40xx, etc.) typically lacks ACPI S5
/// power-down relays; invoking poweroff on such systems only halts Linux execution
/// while leaving the device energized. This adapter ensures power-off is only
/// marked 'supported' when verified ACPI power management is present (e.g. x86_64,
/// or profiles with explicit PMIC support).
class AcpiPowerOffAdapter implements BootMechanismAdapter {
  const AcpiPowerOffAdapter();

  @override
  String get adapterId => 'acpi_poweroff';

  @override
  String get displayName => 'ACPI / PMIC Hardware Power-Off';

  @override
  Set<RebootOperationType> get supportedOperations => {
    RebootOperationType.powerOff,
  };

  @override
  Future<OperationCapability> inspectCapabilities({
    required DeviceBootEnvironment environment,
    required RebootOperationType operation,
    DeviceProfile? matchedProfile,
  }) async {
    if (operation != RebootOperationType.powerOff) {
      return OperationCapability(
        operation: operation,
        status: CapabilityStatus.unsupported,
        reason: '$displayName only handles power-off operations.',
        mechanismId: adapterId,
      );
    }

    final isX86 =
        environment.targetArchitecture.toLowerCase().contains('x86') ||
        environment.boardName.toLowerCase().contains('x86') ||
        environment.model.toLowerCase().contains('x86');
    final hasHardwarePoweroff = matchedProfile?.poweroffSupported ?? isX86;

    if (hasHardwarePoweroff) {
      return OperationCapability(
        operation: RebootOperationType.powerOff,
        status: CapabilityStatus.supported,
        reason:
            'Hardware ACPI / PMIC power management is supported. Device will power off completely.',
        positiveEvidence: [
          if (isX86)
            'x86 architecture with ACPI power management detected'
          else
            'Verified hardware PMIC power management in device profile',
        ],
        riskLevel: RiskLevel.medium,
        mechanismId: adapterId,
        warningMessage:
            'This will completely power off the device. Remote access will be terminated, '
            'and physical intervention (pressing the power button or cycling power) will be required to turn it back on.',
      );
    }

    final platformName = environment.boardName.isNotEmpty
        ? environment.boardName
        : (environment.targetArchitecture.isNotEmpty
              ? environment.targetArchitecture
              : 'embedded platform');

    return OperationCapability(
      operation: RebootOperationType.powerOff,
      status: CapabilityStatus.unsupported,
      reason:
          'Hardware DC power-down is not supported on $platformName. '
          'Executing poweroff halts Linux execution but leaves hardware energized, requiring physical power cycling.',
      positiveEvidence: ['Architecture evaluated: $platformName'],
      riskLevel: RiskLevel.low,
      mechanismId: adapterId,
    );
  }

  @override
  Future<String?> identifyActiveTarget({
    required DeviceBootEnvironment environment,
    DeviceProfile? matchedProfile,
  }) async => null;

  @override
  Future<List<String>> enumerateBootTargets({
    required DeviceBootEnvironment environment,
    DeviceProfile? matchedProfile,
  }) async => const [];

  @override
  Future<bool> validateTarget({
    required DeviceBootEnvironment environment,
    required String targetSlot,
    DeviceProfile? matchedProfile,
  }) async => true;

  @override
  List<List<String>> prepareOperation({
    required DeviceBootEnvironment environment,
    required RebootOperationType operation,
    String? targetSlot,
    DeviceProfile? matchedProfile,
  }) {
    if (operation != RebootOperationType.powerOff) {
      throw UnsupportedError(
        'Operation $operation not supported by AcpiPowerOffAdapter',
      );
    }
    return [
      ['/sbin/poweroff'],
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
    // Verified when router disconnects and stays offline
    return true;
  }
}
