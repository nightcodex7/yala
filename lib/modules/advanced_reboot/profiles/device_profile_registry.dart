// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/reboot_capability.dart';
import 'device_profile.dart';

/// Result of looking up a device profile against runtime environment evidence.
class ProfileMatchResult {
  /// The matched profile if exactly one profile matched unambiguously.
  final DeviceProfile? profile;

  /// Whether matching was ambiguous (multiple conflicting profiles matched).
  final bool isAmbiguous;

  /// All profiles that matched the board identifier.
  final List<DeviceProfile> candidateMatches;

  /// Diagnostic message explaining the lookup result.
  final String message;

  const ProfileMatchResult({
    this.profile,
    this.isAmbiguous = false,
    this.candidateMatches = const [],
    required this.message,
  });

  bool get hasMatch => profile != null && !isAmbiguous;
}

/// Registry of curated, reviewed, and version-controlled device profiles.
class DeviceProfileRegistry {
  DeviceProfileRegistry._();

  static final DeviceProfileRegistry instance = DeviceProfileRegistry._();

  /// Curated list of verified profiles.
  final List<DeviceProfile> _profiles = [
    // 1. Linksys EA8300 (Qualcomm IPQ4019, dual kernel/rootfs partitions, U-Boot boot_part)
    const DeviceProfile(
      profileId: 'linksys_ea8300',
      displayName: 'Linksys EA8300',
      compatibleBoardIds: {'linksys,ea8300', 'linksys_ea8300', 'ea8300'},
      compatibleModels: {'Linksys EA8300', 'EA8300'},
      targetArchitecture: 'ipq40xx/generic',
      supportedOperations: {
        RebootOperationType.standardReboot,
        RebootOperationType.alternatePartitionBoot,
      },
      partitionMechanism: PartitionMechanism.uBootEnvBootPartReady,
      requiredMtdPartitionNames: {'alt_kernel', 'alt_rootfs'},
      requiredUtilities: {'fw_printenv', 'fw_setenv'},
      validPartitionSlots: ['1', '2'],
      poweroffSupported: false,
      documentationUrl: 'https://openwrt.org/toh/linksys/ea8300',
      notes:
          'Dual-partition Qualcomm IPQ4019 router. U-Boot inspects boot_part and boot_part_ready environment variables. '
          'Standard poweroff puts the SoC in an infinite halt loop without cutting DC rail power; physical power cycling is required.',
      lastReviewed: '2026-10-25',
    ),

    // 2. Linksys WRT3200ACM (Marvell Armada 385, dual partition, U-Boot boot_part)
    const DeviceProfile(
      profileId: 'linksys_wrt3200acm',
      displayName: 'Linksys WRT3200ACM',
      compatibleBoardIds: {
        'linksys,wrt3200acm',
        'linksys_wrt3200acm',
        'wrt3200acm',
      },
      compatibleModels: {'Linksys WRT3200ACM', 'WRT3200ACM'},
      targetArchitecture: 'mvebu/cortexa9',
      supportedOperations: {
        RebootOperationType.standardReboot,
        RebootOperationType.alternatePartitionBoot,
      },
      partitionMechanism: PartitionMechanism.uBootEnvBootPart,
      requiredMtdPartitionNames: {'alt_kernel', 'alt_rootfs'},
      requiredUtilities: {'fw_printenv', 'fw_setenv'},
      validPartitionSlots: ['1', '2'],
      poweroffSupported: false,
      documentationUrl: 'https://openwrt.org/toh/linksys/wrt3200acm',
      notes:
          'Dual-partition Marvell Armada 385 router. Bootloader toggles partition using boot_part variable. '
          'Poweroff halts Linux execution without physical DC shutdown.',
      lastReviewed: '2026-10-25',
    ),

    // 3. Linksys WRT1900ACS (Marvell Armada 385, dual partition, U-Boot boot_part)
    const DeviceProfile(
      profileId: 'linksys_wrt1900acs',
      displayName: 'Linksys WRT1900ACS',
      compatibleBoardIds: {
        'linksys,wrt1900acs',
        'linksys_wrt1900acs',
        'linksys,wrt1900ac-v2',
      },
      compatibleModels: {'Linksys WRT1900ACS'},
      targetArchitecture: 'mvebu/cortexa9',
      supportedOperations: {
        RebootOperationType.standardReboot,
        RebootOperationType.alternatePartitionBoot,
      },
      partitionMechanism: PartitionMechanism.uBootEnvBootPart,
      requiredMtdPartitionNames: {'alt_kernel', 'alt_rootfs'},
      requiredUtilities: {'fw_printenv', 'fw_setenv'},
      validPartitionSlots: ['1', '2'],
      poweroffSupported: false,
      documentationUrl: 'https://openwrt.org/toh/linksys/wrt1900acs',
      notes:
          'Dual-partition Marvell Armada 385 router. Bootloader toggles partition using boot_part variable.',
      lastReviewed: '2026-10-25',
    ),

    // 4. Generic x86_64 (PC / VM / Appliances with ACPI support)
    const DeviceProfile(
      profileId: 'generic_x86_64',
      displayName: 'Generic x86_64 Appliance',
      compatibleBoardIds: {'x86/64', 'x86_64', 'generic,x86-64'},
      compatibleModels: {'x86/64', 'PC Engines', 'QEMU', 'Generic x86/64'},
      targetArchitecture: 'x86/64',
      supportedOperations: {
        RebootOperationType.standardReboot,
        RebootOperationType.powerOff,
      },
      partitionMechanism: PartitionMechanism.none,
      poweroffSupported: true,
      documentationUrl:
          'https://openwrt.org/docs/guide-user/installation/openwrt_x86',
      notes:
          'x86 architecture with ACPI power management support. /sbin/poweroff triggers ACPI S5 state shutdown.',
      lastReviewed: '2026-10-25',
    ),
  ];

  List<DeviceProfile> get allProfiles => List.unmodifiable(_profiles);

  /// Resolves a device profile using exact runtime evidence.
  /// Rejects ambiguous matches where more than one profile matches the board.
  ProfileMatchResult findMatchingProfile({
    required String boardName,
    String model = '',
  }) {
    if (boardName.trim().isEmpty) {
      return const ProfileMatchResult(
        message: 'Board identifier is empty or unavailable.',
      );
    }

    final matches = _profiles
        .where((p) => p.matches(boardName: boardName, model: model))
        .toList();

    if (matches.isEmpty) {
      return ProfileMatchResult(
        message: 'No verified device profile matches board "$boardName".',
      );
    }

    if (matches.length > 1) {
      return ProfileMatchResult(
        isAmbiguous: true,
        candidateMatches: matches,
        message:
            'Ambiguous match: multiple profiles (${matches.map((p) => p.profileId).join(", ")}) matched board "$boardName". Operation refused for safety.',
      );
    }

    return ProfileMatchResult(
      profile: matches.first,
      candidateMatches: matches,
      message: 'Matched verified profile "${matches.first.profileId}".',
    );
  }
}
