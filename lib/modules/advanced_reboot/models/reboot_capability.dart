// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// Portions adapted from OpenWrt luci-app-advanced-reboot:
// Copyright (C) 2017-2024 Stan Grishin <stangri@melmac.ca> & OpenWrt Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Typed boot operations supported by the Advanced Reboot subsystem.
enum RebootOperationType {
  /// Standard system restart using the native OpenWrt LuCI system.reboot or /sbin/reboot.
  standardReboot,

  /// Switching and rebooting into an alternative firmware partition via a verified boot mechanism.
  alternatePartitionBoot,

  /// Complete device shutdown / power down on hardware with power-management support.
  powerOff,
}

/// Explicit, non-collapsing capability evaluation status.
enum CapabilityStatus {
  /// Positive, verified evidence exists confirming that this exact operation is safe and supported.
  supported,

  /// Reliable evidence proves that this operation is not available or not supported on this platform.
  unsupported,

  /// The available evidence is incomplete, contradictory, inconclusive, or the mechanism is unverified.
  /// NEVER collapsed into supported.
  unknown,

  /// Capability detection encountered an operational failure (e.g. connection error, RPC failure).
  error,
}

/// Risk level associated with a reboot operation.
enum RiskLevel { low, medium, high, critical }

/// Primary storage subsystem architecture detected on the router.
enum StorageType { mtd, ubi, block, none, unknown }

/// Parsed MTD partition record from /proc/mtd.
class MtdPartitionInfo {
  final String dev;
  final int size;
  final int erasesize;
  final String name;

  const MtdPartitionInfo({
    required this.dev,
    required this.size,
    required this.erasesize,
    required this.name,
  });

  factory MtdPartitionInfo.fromProcMtdLine(String line) {
    // Format: mtd0: 00080000 00020000 "boot"
    final match = RegExp(
      r'^(mtd\d+):\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+"([^"]+)"',
    ).firstMatch(line.trim());
    if (match != null) {
      return MtdPartitionInfo(
        dev: match.group(1) ?? '',
        size: int.tryParse(match.group(2) ?? '', radix: 16) ?? 0,
        erasesize: int.tryParse(match.group(3) ?? '', radix: 16) ?? 0,
        name: match.group(4) ?? '',
      );
    }
    return MtdPartitionInfo(dev: '', size: 0, erasesize: 0, name: line.trim());
  }

  Map<String, dynamic> toJson() => {
    'dev': dev,
    'size': size,
    'erasesize': erasesize,
    'name': name,
  };

  @override
  String toString() => '$dev ("$name"): 0x${size.toRadixString(16)}';
}

/// Discovered boot-control mechanism on the device.
class DiscoveredBootMechanism {
  final String mechanismId;
  final String displayName;
  final bool isAvailable;
  final List<String> evidence;

  const DiscoveredBootMechanism({
    required this.mechanismId,
    required this.displayName,
    required this.isAvailable,
    this.evidence = const [],
  });

  Map<String, dynamic> toJson() => {
    'mechanismId': mechanismId,
    'displayName': displayName,
    'isAvailable': isAvailable,
    'evidence': evidence,
  };
}

/// Read-only snapshot of the router's runtime boot and firmware environment.
class DeviceBootEnvironment {
  final String boardName;
  final String model;
  final String releaseVersion;
  final String targetArchitecture;
  final StorageType storageType;
  final List<MtdPartitionInfo> mtdPartitions;
  final String? activeSlot;
  final String? alternateSlot;
  final String? activeOs;
  final String? alternateOs;
  final String? discoveredMechanismName;
  final List<String> availableTargets;
  final bool hasFwPrintenv;
  final bool hasFwSetenv;
  final Map<String, String> bootloaderEnv;
  final List<DiscoveredBootMechanism> discoveredMechanisms;
  final Map<String, String> evidenceProvenance;
  final String? cmdline;
  final Map<String, dynamic> rawDiagnostics;

  const DeviceBootEnvironment({
    required this.boardName,
    required this.model,
    required this.releaseVersion,
    this.targetArchitecture = '',
    this.storageType = StorageType.mtd,
    this.mtdPartitions = const [],
    this.activeSlot,
    this.alternateSlot,
    this.activeOs,
    this.alternateOs,
    this.discoveredMechanismName,
    this.availableTargets = const [],
    this.hasFwPrintenv = false,
    this.hasFwSetenv = false,
    this.bootloaderEnv = const {},
    this.discoveredMechanisms = const [],
    this.evidenceProvenance = const {},
    this.cmdline,
    this.rawDiagnostics = const {},
  });

  bool get hasDualPartitionLayout {
    final names = mtdPartitions.map((p) => p.name.toLowerCase()).toSet();
    final hasKernelPair =
        (names.contains('kernel') && names.contains('alt_kernel')) ||
        (names.contains('kernel1') && names.contains('kernel2')) ||
        (names.contains('kernel') && names.contains('kernel2')) ||
        (names.contains('kernel_0') && names.contains('kernel_1')) ||
        (names.contains('pri_kernel') && names.contains('alt_kernel'));
    final hasRootfsPair =
        (names.contains('rootfs') && names.contains('alt_rootfs')) ||
        (names.contains('rootfs1') && names.contains('rootfs2')) ||
        (names.contains('rootfs') && names.contains('rootfs2')) ||
        (names.contains('rootfs_0') && names.contains('rootfs_1')) ||
        (names.contains('pri_rootfs') && names.contains('alt_rootfs'));
    final hasImagePair =
        (names.contains('image0') && names.contains('image1')) ||
        (names.contains('firmware') && names.contains('firmware2')) ||
        (names.contains('firmware1') && names.contains('firmware2')) ||
        (names.contains('linux') && names.contains('linux2'));
    return hasKernelPair || hasRootfsPair || hasImagePair;
  }

  Map<String, dynamic> toJson() => {
    'boardName': boardName,
    'model': model,
    'releaseVersion': releaseVersion,
    'targetArchitecture': targetArchitecture,
    'storageType': storageType.name,
    'mtdPartitions': mtdPartitions.map((p) => p.toJson()).toList(),
    'activeSlot': activeSlot,
    'alternateSlot': alternateSlot,
    'activeOs': activeOs,
    'alternateOs': alternateOs,
    'discoveredMechanismName': discoveredMechanismName,
    'availableTargets': availableTargets,
    'hasFwPrintenv': hasFwPrintenv,
    'hasFwSetenv': hasFwSetenv,
    'bootloaderEnv': bootloaderEnv,
    'hasDualPartitionLayout': hasDualPartitionLayout,
    'discoveredMechanisms': discoveredMechanisms
        .map((m) => m.toJson())
        .toList(),
    'evidenceProvenance': evidenceProvenance,
  };
}

/// Evaluation result for an individual reboot operation.
class OperationCapability {
  final RebootOperationType operation;
  final CapabilityStatus status;
  final String reason;
  final List<String> positiveEvidence;
  final List<String> missingOrConflictingEvidence;
  final List<String> prerequisites;
  final RiskLevel riskLevel;
  final String? warningMessage;
  final String? targetIdentifier;
  final String? mechanismId;

  const OperationCapability({
    required this.operation,
    required this.status,
    required this.reason,
    this.positiveEvidence = const [],
    this.missingOrConflictingEvidence = const [],
    this.prerequisites = const [],
    this.riskLevel = RiskLevel.low,
    this.warningMessage,
    this.targetIdentifier,
    this.mechanismId,
  });

  bool get isSupported => status == CapabilityStatus.supported;
  bool get isUnsupported => status == CapabilityStatus.unsupported;
  bool get isUnknown => status == CapabilityStatus.unknown;
  bool get isError => status == CapabilityStatus.error;

  Map<String, dynamic> toJson() => {
    'operation': operation.name,
    'status': status.name,
    'reason': reason,
    'positiveEvidence': positiveEvidence,
    'missingOrConflictingEvidence': missingOrConflictingEvidence,
    'prerequisites': prerequisites,
    'riskLevel': riskLevel.name,
    'warningMessage': warningMessage,
    'targetIdentifier': targetIdentifier,
    'mechanismId': mechanismId,
  };
}

/// Aggregate capability container for all advanced reboot operations on a router.
class AdvancedRebootCapabilities {
  final String routerId;
  final DateTime detectedAt;
  final DeviceBootEnvironment environment;
  final Map<RebootOperationType, OperationCapability> capabilities;
  final String? matchedAdapterId;
  final String? matchedProfileId;
  final String? detectionError;

  const AdvancedRebootCapabilities({
    required this.routerId,
    required this.detectedAt,
    required this.environment,
    required this.capabilities,
    this.matchedAdapterId,
    this.matchedProfileId,
    this.detectionError,
  });

  OperationCapability get standardReboot =>
      capabilities[RebootOperationType.standardReboot] ??
      const OperationCapability(
        operation: RebootOperationType.standardReboot,
        status: CapabilityStatus.unknown,
        reason: 'Standard reboot capability not evaluated',
      );

  OperationCapability get alternatePartitionBoot =>
      capabilities[RebootOperationType.alternatePartitionBoot] ??
      const OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unknown,
        reason: 'Alternate firmware partition capability not evaluated',
        riskLevel: RiskLevel.high,
      );

  OperationCapability get powerOff =>
      capabilities[RebootOperationType.powerOff] ??
      const OperationCapability(
        operation: RebootOperationType.powerOff,
        status: CapabilityStatus.unknown,
        reason: 'Power off capability not evaluated',
        riskLevel: RiskLevel.medium,
      );

  OperationCapability getOperation(RebootOperationType type) {
    switch (type) {
      case RebootOperationType.standardReboot:
        return standardReboot;
      case RebootOperationType.alternatePartitionBoot:
        return alternatePartitionBoot;
      case RebootOperationType.powerOff:
        return powerOff;
    }
  }

  Map<String, dynamic> toJson() => {
    'routerId': routerId,
    'detectedAt': detectedAt.toIso8601String(),
    'environment': environment.toJson(),
    'capabilities': capabilities.map(
      (key, value) => MapEntry(key.name, value.toJson()),
    ),
    'matchedAdapterId': matchedAdapterId,
    'matchedProfileId': matchedProfileId,
    'detectionError': detectionError,
  };

  /// Produces a sanitized diagnostic string suitable for user inspection or export.
  /// Strictly excludes passwords, authentication tokens, or private router credentials.
  String toSanitizedDiagnosticString() {
    final buffer = StringBuffer();
    buffer.writeln('=== YALA Advanced Reboot Diagnostics ===');
    buffer.writeln('Timestamp: ${detectedAt.toUtc().toIso8601String()}');
    buffer.writeln('Router ID: $routerId');
    buffer.writeln(
      'Board Identifier: ${environment.boardName.isEmpty ? "(unknown)" : environment.boardName}',
    );
    buffer.writeln(
      'Model: ${environment.model.isEmpty ? "(unknown)" : environment.model}',
    );
    buffer.writeln(
      'Release: ${environment.releaseVersion.isEmpty ? "(unknown)" : environment.releaseVersion}',
    );
    buffer.writeln(
      'Target Architecture: ${environment.targetArchitecture.isEmpty ? "(unknown)" : environment.targetArchitecture}',
    );
    buffer.writeln(
      'Storage Subsystem: ${environment.storageType.name.toUpperCase()}',
    );
    buffer.writeln('Matched Generic Adapter: ${matchedAdapterId ?? "None"}');
    buffer.writeln(
      'Matched Device Profile: ${matchedProfileId ?? "None (Universal Generic Resolution)"}',
    );
    buffer.writeln('Active Slot: ${environment.activeSlot ?? "(unknown)"}');
    if (environment.activeOs != null) {
      buffer.writeln('Active OS: ${environment.activeOs}');
    }
    buffer.writeln(
      'Alternate Slot: ${environment.alternateSlot ?? "(none/unknown)"}',
    );
    if (environment.alternateOs != null) {
      buffer.writeln('Alternate OS: ${environment.alternateOs}');
    }
    if (environment.discoveredMechanismName != null) {
      buffer.writeln(
        'Discovered Mechanism: ${environment.discoveredMechanismName}',
      );
    }
    buffer.writeln(
      'Available Targets: ${environment.availableTargets.isEmpty ? "(none)" : environment.availableTargets.join(", ")}',
    );
    buffer.writeln(
      'Dual Partition MTD Layout: ${environment.hasDualPartitionLayout}',
    );
    buffer.writeln('fw_printenv Available: ${environment.hasFwPrintenv}');
    buffer.writeln('fw_setenv Available: ${environment.hasFwSetenv}');
    buffer.writeln('');
    buffer.writeln('--- Evidence Provenance ---');
    if (environment.evidenceProvenance.isEmpty) {
      buffer.writeln('  No provenance metadata recorded');
    } else {
      for (final entry in environment.evidenceProvenance.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    }
    buffer.writeln('');
    buffer.writeln('--- Discovered Boot Mechanisms ---');
    if (environment.discoveredMechanisms.isEmpty) {
      buffer.writeln('  No distinct boot-control mechanisms discovered');
    } else {
      for (final mech in environment.discoveredMechanisms) {
        buffer.writeln(
          '  [${mech.isAvailable ? "DISCOVERED" : "INCOMPLETE"}] ${mech.displayName} (${mech.mechanismId})',
        );
        for (final ev in mech.evidence) {
          buffer.writeln('    • $ev');
        }
      }
    }
    buffer.writeln('');
    buffer.writeln('--- MTD Partition Table ---');
    if (environment.mtdPartitions.isEmpty) {
      buffer.writeln('  No MTD partitions detected or /proc/mtd inaccessible');
    } else {
      for (final part in environment.mtdPartitions) {
        buffer.writeln(
          '  ${part.dev}: "${part.name}" (size: 0x${part.size.toRadixString(16)})',
        );
      }
    }
    buffer.writeln('');
    buffer.writeln('--- Bootloader Environment (Read-Only) ---');
    if (environment.bootloaderEnv.isEmpty) {
      buffer.writeln('  No bootloader variables detected');
    } else {
      for (final entry in environment.bootloaderEnv.entries) {
        buffer.writeln('  ${entry.key} = ${entry.value}');
      }
    }
    buffer.writeln('');
    buffer.writeln('--- Capabilities Evaluation ---');
    for (final op in RebootOperationType.values) {
      final cap = getOperation(op);
      buffer.writeln('Operation: ${op.name}');
      buffer.writeln('  Status: ${cap.status.name.toUpperCase()}');
      buffer.writeln('  Reason: ${cap.reason}');
      if (cap.mechanismId != null) {
        buffer.writeln('  Mechanism: ${cap.mechanismId}');
      }
      if (cap.targetIdentifier != null) {
        buffer.writeln('  Target Slot: ${cap.targetIdentifier}');
      }
      if (cap.positiveEvidence.isNotEmpty) {
        buffer.writeln('  Positive Evidence:');
        for (final ev in cap.positiveEvidence) {
          buffer.writeln('    + $ev');
        }
      }
      if (cap.missingOrConflictingEvidence.isNotEmpty) {
        buffer.writeln('  Missing / Conflicting Evidence:');
        for (final ev in cap.missingOrConflictingEvidence) {
          buffer.writeln('    - $ev');
        }
      }
      if (cap.warningMessage != null) {
        buffer.writeln('  Warning: ${cap.warningMessage}');
      }
      buffer.writeln('');
    }
    return buffer.toString();
  }
}
