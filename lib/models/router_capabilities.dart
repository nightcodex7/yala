// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

enum PackageManagerEngine { opkg, apk, none }

/// Firewall engine backend detected on OpenWrt.
enum FirewallBackend {
  fw3, // iptables based (older OpenWrt <= 21.02)
  fw4, // nftables based (OpenWrt >= 22.03)
  none,
}

/// Network switch topology model.
enum NetworkModel {
  dsa, // Distributed Switch Architecture (bridge-vlan)
  swconfig, // Legacy swconfig (switch_vlan)
  unknown,
}

/// Detailed capabilities model probed per router instance.
class RouterCapabilities {
  final String routerId;
  final Set<String> ubusObjects;
  final Map<String, List<String>> ubusMethods;
  final PackageManagerEngine packageEngine;
  final FirewallBackend firewallBackend;
  final NetworkModel networkModel;
  final String releaseVersion;
  final String boardName;
  final DateTime probedAt;
  final bool probeFailed;
  final String? lastProbeError;

  const RouterCapabilities({
    required this.routerId,
    this.ubusObjects = const {},
    this.ubusMethods = const {},
    this.packageEngine = PackageManagerEngine.opkg,
    this.firewallBackend = FirewallBackend.fw4,
    this.networkModel = NetworkModel.dsa,
    this.releaseVersion = '',
    this.boardName = '',
    required this.probedAt,
    this.probeFailed = false,
    this.lastProbeError,
  });

  /// Default conservative fallback capability set when probing fails
  factory RouterCapabilities.conservative(String routerId, {String? error}) {
    return RouterCapabilities(
      routerId: routerId,
      ubusObjects: const {},
      ubusMethods: const {},
      packageEngine: PackageManagerEngine.opkg,
      firewallBackend: FirewallBackend.fw3,
      networkModel: NetworkModel.swconfig,
      releaseVersion: 'Unknown',
      boardName: 'Generic OpenWrt',
      probedAt: DateTime.now(),
      probeFailed: true,
      lastProbeError: error ?? 'Failed to probe router capabilities',
    );
  }

  /// Full mock capability set for offline/review mode
  factory RouterCapabilities.mock() {
    return RouterCapabilities(
      routerId: 'mock_router_id',
      ubusObjects: const {
        'system',
        'luci-rpc',
        'network.interface',
        'iwinfo',
        'file',
        'service',
        'rc',
        'uci',
        'opkg',
        'apk',
        'fw4',
      },
      ubusMethods: const {
        'system': ['info', 'board'],
        'luci-rpc': ['getInitList', 'getWirelessDevices'],
        'file': ['read', 'stat', 'exec'],
      },
      packageEngine: PackageManagerEngine.opkg,
      firewallBackend: FirewallBackend.fw4,
      networkModel: NetworkModel.dsa,
      releaseVersion: 'OpenWrt 23.05.3',
      boardName: 'x86/64',
      probedAt: DateTime.now(),
      probeFailed: false,
    );
  }

  /// Helper to check if a specific ubus object is available
  bool hasObject(String objectName) {
    if (probeFailed || ubusObjects.isEmpty) return true; // conservative attempt
    return ubusObjects.contains(objectName);
  }

  /// Helper to check if a specific ubus method is available
  bool hasMethod(String objectName, String methodName) {
    if (probeFailed || ubusObjects.isEmpty) return true;
    final methods = ubusMethods[objectName];
    if (methods == null) return ubusObjects.contains(objectName);
    return methods.contains(methodName);
  }

  /// Helper to check if luci-rpc or equivalent wireless/RPC ubus objects are available
  bool get hasLuciRpc =>
      ubusObjects.isEmpty ||
      hasObject('luci-rpc') ||
      hasObject('iwinfo') ||
      hasObject('luci');

  /// Helper to check if file.exec or backend execution capability is allowed
  bool get hasFileExec =>
      ubusObjects.isEmpty ||
      hasMethod('file', 'exec') ||
      hasObject('file') ||
      hasObject('rc');

  /// Helper to check if both RPC modules and execution permissions are available
  bool get isRpcComplete => hasLuciRpc && hasFileExec;

  /// Helper to check if ubus session has write authorization for uci configs
  bool get hasUciWriteAccess {
    if (probeFailed || ubusObjects.isEmpty) {
      return true; // conservative optimistic default
    }
    if (!ubusObjects.contains('uci')) return false;
    final methods = ubusMethods['uci'];
    if (methods == null) return ubusObjects.contains('uci');
    return methods.contains('set') &&
        (methods.contains('apply') || methods.contains('commit'));
  }

  /// Serialize for secure storage cache
  Map<String, dynamic> toJson() {
    return {
      'routerId': routerId,
      'ubusObjects': ubusObjects.toList(),
      'ubusMethods': ubusMethods.map((key, value) => MapEntry(key, value)),
      'packageEngine': packageEngine.name,
      'firewallBackend': firewallBackend.name,
      'networkModel': networkModel.name,
      'releaseVersion': releaseVersion,
      'boardName': boardName,
      'probedAt': probedAt.toIso8601String(),
      'probeFailed': probeFailed,
      'lastProbeError': lastProbeError,
    };
  }

  /// Deserialize from secure storage cache
  factory RouterCapabilities.fromJson(Map<String, dynamic> json) {
    try {
      final ubusObjsList = (json['ubusObjects'] as List?)?.cast<String>() ?? [];
      final rawMethods = json['ubusMethods'] as Map<String, dynamic>? ?? {};
      final ubusMethodsMap = rawMethods.map(
        (key, value) => MapEntry(key, (value as List).cast<String>()),
      );

      return RouterCapabilities(
        routerId: json['routerId'] as String? ?? 'default',
        ubusObjects: ubusObjsList.toSet(),
        ubusMethods: ubusMethodsMap,
        packageEngine: PackageManagerEngine.values.firstWhere(
          (e) => e.name == json['packageEngine'],
          orElse: () => PackageManagerEngine.opkg,
        ),
        firewallBackend: FirewallBackend.values.firstWhere(
          (e) => e.name == json['firewallBackend'],
          orElse: () => FirewallBackend.fw4,
        ),
        networkModel: NetworkModel.values.firstWhere(
          (e) => e.name == json['networkModel'],
          orElse: () => NetworkModel.dsa,
        ),
        releaseVersion: json['releaseVersion'] as String? ?? '',
        boardName: json['boardName'] as String? ?? '',
        probedAt: json['probedAt'] != null
            ? DateTime.tryParse(json['probedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        probeFailed: json['probeFailed'] as bool? ?? false,
        lastProbeError: json['lastProbeError'] as String?,
      );
    } catch (_) {
      return RouterCapabilities.conservative(
        json['routerId'] as String? ?? 'default',
      );
    }
  }

  RouterCapabilities copyWith({
    String? routerId,
    Set<String>? ubusObjects,
    Map<String, List<String>>? ubusMethods,
    PackageManagerEngine? packageEngine,
    FirewallBackend? firewallBackend,
    NetworkModel? networkModel,
    String? releaseVersion,
    String? boardName,
    DateTime? probedAt,
    bool? probeFailed,
    String? lastProbeError,
  }) {
    return RouterCapabilities(
      routerId: routerId ?? this.routerId,
      ubusObjects: ubusObjects ?? this.ubusObjects,
      ubusMethods: ubusMethods ?? this.ubusMethods,
      packageEngine: packageEngine ?? this.packageEngine,
      firewallBackend: firewallBackend ?? this.firewallBackend,
      networkModel: networkModel ?? this.networkModel,
      releaseVersion: releaseVersion ?? this.releaseVersion,
      boardName: boardName ?? this.boardName,
      probedAt: probedAt ?? this.probedAt,
      probeFailed: probeFailed ?? this.probeFailed,
      lastProbeError: lastProbeError ?? this.lastProbeError,
    );
  }
}
