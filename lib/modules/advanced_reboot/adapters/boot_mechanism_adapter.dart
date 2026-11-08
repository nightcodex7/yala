// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/reboot_capability.dart';
import '../profiles/device_profile.dart';

/// Reusable, typed contract for boot and power-control mechanisms.
///
/// Adapters represent generic boot architectures rather than individual router models.
/// A generic adapter can run against ANY device that satisfies its verified preconditions.
abstract class BootMechanismAdapter {
  /// Unique machine-readable identifier for this mechanism (e.g. 'standard_reboot', 'uboot_boot_part').
  String get adapterId;

  /// User-facing descriptive name of the mechanism.
  String get displayName;

  /// Supported operations declared independently.
  Set<RebootOperationType> get supportedOperations;

  /// Inspects read-only runtime environment evidence and returns an eligibility evaluation for [operation].
  /// Does NOT authorize execution if prerequisites are not satisfied.
  Future<OperationCapability> inspectCapabilities({
    required DeviceBootEnvironment environment,
    required RebootOperationType operation,
    DeviceProfile? matchedProfile,
  });

  /// Identifies the currently active boot slot / partition (e.g. '1', '2', 'kernel1', 'boot_a').
  Future<String?> identifyActiveTarget({
    required DeviceBootEnvironment environment,
    DeviceProfile? matchedProfile,
  });

  /// Enumerates all selectable boot targets on the device.
  Future<List<String>> enumerateBootTargets({
    required DeviceBootEnvironment environment,
    DeviceProfile? matchedProfile,
  });

  /// Validates that a requested target slot is valid and ready to boot.
  Future<bool> validateTarget({
    required DeviceBootEnvironment environment,
    required String targetSlot,
    DeviceProfile? matchedProfile,
  });

  /// Prepares the fixed, pre-approved commands to switch to [targetSlot].
  /// Strictly typed: returns fixed command tuples (command + args), NEVER arbitrary shell strings.
  List<List<String>> prepareOperation({
    required DeviceBootEnvironment environment,
    required RebootOperationType operation,
    String? targetSlot,
    DeviceProfile? matchedProfile,
  });

  /// Verifies that the post-operation state matches the intended outcome.
  Future<bool> verifyOutcome({
    required DeviceBootEnvironment preBootEnvironment,
    required DeviceBootEnvironment postBootEnvironment,
    required RebootOperationType operation,
    String? expectedTargetSlot,
    DeviceProfile? matchedProfile,
  });
}
