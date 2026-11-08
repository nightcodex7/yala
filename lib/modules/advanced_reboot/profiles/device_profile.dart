// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/reboot_capability.dart';

/// Mechanism used to toggle active partitions.
enum PartitionMechanism {
  none,
  uBootEnvBootPart,
  uBootEnvBootPartReady,
  dualImageFlag,
  ubiDualBoot,
}

/// Structured, immutable device profile declaring verified boot capabilities and constraints.
class DeviceProfile {
  /// Unique identifier of the profile (e.g. 'linksys_ea8300').
  final String profileId;

  /// Human-readable display name for the device profile.
  final String displayName;

  /// Exact runtime board identifiers (e.g. from /tmp/sysinfo/board_name or system.board).
  final Set<String> compatibleBoardIds;

  /// Retail/marketing model strings for secondary validation.
  final Set<String> compatibleModels;

  /// Target architecture constraint (e.g. 'ipq40xx/generic').
  final String targetArchitecture;

  /// Supported operations declared independently.
  final Set<RebootOperationType> supportedOperations;

  /// Bootloader and partition control mechanism.
  final PartitionMechanism partitionMechanism;

  /// List of required MTD partition names that must be present in /proc/mtd.
  final Set<String> requiredMtdPartitionNames;

  /// List of required command-line utilities (e.g. fw_printenv, fw_setenv).
  final Set<String> requiredUtilities;

  /// Whether hardware DC power down (ACPI/PMIC) is supported.
  final bool poweroffSupported;

  /// Valid partition slot names (e.g. ['1', '2']).
  final List<String> validPartitionSlots;

  /// Official documentation or OpenWrt wiki reference URL.
  final String documentationUrl;

  /// Specific safety notes and hardware behavior limitations.
  final String notes;

  /// Revision / last reviewed date of this profile definition.
  final String lastReviewed;

  const DeviceProfile({
    required this.profileId,
    required this.displayName,
    required this.compatibleBoardIds,
    this.compatibleModels = const {},
    this.targetArchitecture = '',
    required this.supportedOperations,
    this.partitionMechanism = PartitionMechanism.none,
    this.requiredMtdPartitionNames = const {},
    this.requiredUtilities = const {},
    this.poweroffSupported = false,
    this.validPartitionSlots = const ['1', '2'],
    required this.documentationUrl,
    required this.notes,
    required this.lastReviewed,
  });

  /// Evaluates whether the runtime board and model match this profile.
  /// Strict matching: board identifier must be an exact match in [compatibleBoardIds].
  /// Retail model alone NEVER matches.
  bool matches({required String boardName, String model = ''}) {
    if (boardName.isEmpty) return false;
    final normalizedBoard = boardName.trim().toLowerCase();
    final boardMatches = compatibleBoardIds.any(
      (b) => b.toLowerCase() == normalizedBoard,
    );
    if (!boardMatches) return false;

    // If model constraints are declared and runtime model is provided, check compatibility
    if (compatibleModels.isNotEmpty && model.isNotEmpty) {
      final normalizedModel = model.trim().toLowerCase();
      final modelMatches = compatibleModels.any(
        (m) => normalizedModel.contains(m.toLowerCase()),
      );
      if (!modelMatches) return false;
    }

    return true;
  }

  /// Calculates the alternate slot for a given active slot.
  String? getAlternateSlot(String activeSlot) {
    if (validPartitionSlots.length != 2) return null;
    if (activeSlot == validPartitionSlots[0]) return validPartitionSlots[1];
    if (activeSlot == validPartitionSlots[1]) return validPartitionSlots[0];
    return null;
  }

  /// Generates the fixed, pre-approved commands to switch to [targetSlot].
  /// STRICT: NEVER returns arbitrary user or router-provided shell strings.
  List<List<String>> getSwitchPartitionCommands(String targetSlot) {
    if (!validPartitionSlots.contains(targetSlot)) {
      throw ArgumentError(
        'Target slot "$targetSlot" is not valid for profile $profileId. Valid slots: $validPartitionSlots',
      );
    }

    switch (partitionMechanism) {
      case PartitionMechanism.uBootEnvBootPart:
        return [
          ['fw_setenv', 'boot_part', targetSlot],
        ];
      case PartitionMechanism.uBootEnvBootPartReady:
        return [
          ['fw_setenv', 'boot_part', targetSlot],
          ['fw_setenv', 'boot_part_ready', targetSlot],
        ];
      case PartitionMechanism.dualImageFlag:
        return [
          ['fw_setenv', 'DualImageFlag', targetSlot],
        ];
      case PartitionMechanism.ubiDualBoot:
        return [
          ['fw_setenv', 'active', targetSlot],
        ];
      case PartitionMechanism.none:
        return [];
    }
  }

  Map<String, dynamic> toJson() => {
    'profileId': profileId,
    'displayName': displayName,
    'compatibleBoardIds': compatibleBoardIds.toList(),
    'compatibleModels': compatibleModels.toList(),
    'targetArchitecture': targetArchitecture,
    'supportedOperations': supportedOperations.map((o) => o.name).toList(),
    'partitionMechanism': partitionMechanism.name,
    'requiredMtdPartitionNames': requiredMtdPartitionNames.toList(),
    'requiredUtilities': requiredUtilities.toList(),
    'poweroffSupported': poweroffSupported,
    'validPartitionSlots': validPartitionSlots,
    'documentationUrl': documentationUrl,
    'notes': notes,
    'lastReviewed': lastReviewed,
  };
}
