// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/reboot_capability.dart';
import '../profiles/device_profile.dart';
import 'boot_mechanism_adapter.dart';

/// Generic adapter for standard OpenWrt system reboots via native LuCI RPC / ubus.
class StandardRebootAdapter implements BootMechanismAdapter {
  const StandardRebootAdapter();

  @override
  String get adapterId => 'standard_reboot';

  @override
  String get displayName => 'Standard OpenWrt System Reboot';

  @override
  Set<RebootOperationType> get supportedOperations => {
    RebootOperationType.standardReboot,
  };

  @override
  Future<OperationCapability> inspectCapabilities({
    required DeviceBootEnvironment environment,
    required RebootOperationType operation,
    DeviceProfile? matchedProfile,
  }) async {
    if (operation != RebootOperationType.standardReboot) {
      return OperationCapability(
        operation: operation,
        status: CapabilityStatus.unsupported,
        reason: 'StandardRebootAdapter only supports standard system reboots.',
        mechanismId: adapterId,
      );
    }

    return OperationCapability(
      operation: RebootOperationType.standardReboot,
      status: CapabilityStatus.supported,
      reason:
          'Standard reboot is supported via OpenWrt LuCI system.reboot RPC.',
      positiveEvidence: ['LuCI ubus system.reboot available'],
      riskLevel: RiskLevel.low,
      mechanismId: adapterId,
      warningMessage:
          'This will restart the router. Remote access will drop until the router completes its reboot cycle.',
    );
  }

  @override
  Future<String?> identifyActiveTarget({
    required DeviceBootEnvironment environment,
    DeviceProfile? matchedProfile,
  }) async => 'current';

  @override
  Future<List<String>> enumerateBootTargets({
    required DeviceBootEnvironment environment,
    DeviceProfile? matchedProfile,
  }) async => ['current'];

  @override
  Future<bool> validateTarget({
    required DeviceBootEnvironment environment,
    required String targetSlot,
    DeviceProfile? matchedProfile,
  }) async => targetSlot == 'current';

  @override
  List<List<String>> prepareOperation({
    required DeviceBootEnvironment environment,
    required RebootOperationType operation,
    String? targetSlot,
    DeviceProfile? matchedProfile,
  }) {
    if (operation != RebootOperationType.standardReboot) {
      throw UnsupportedError(
        'Operation $operation not supported by StandardRebootAdapter',
      );
    }
    return [
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
    // Standard reboot outcome is verified by successful reconnection
    return postBootEnvironment.boardName.isNotEmpty;
  }
}
