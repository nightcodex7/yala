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
  final Map<String, List<String>> uciPermissions;
  final Map<String, List<String>> filePermissions;
  final PackageManagerEngine packageEngine;
  final FirewallBackend firewallBackend;
  final NetworkModel networkModel;
  final String releaseVersion;
  final String boardName;
  final DateTime probedAt;
  final bool probeFailed;
  final String? lastProbeError;
  final bool hasAdGuardHome;
  final bool hasOdhcpd;
  final bool hasCron;
  final bool hasDropbear;
  final bool supportsIpv6InternetFirewall;
  final Map<String, dynamic>? boardJson;

  const RouterCapabilities({
    required this.routerId,
    this.ubusObjects = const {},
    this.ubusMethods = const {},
    this.uciPermissions = const {},
    this.filePermissions = const {},
    this.packageEngine = PackageManagerEngine.opkg,
    this.firewallBackend = FirewallBackend.fw4,
    this.networkModel = NetworkModel.dsa,
    this.releaseVersion = '',
    this.boardName = '',
    required this.probedAt,
    this.probeFailed = false,
    this.lastProbeError,
    this.hasAdGuardHome = false,
    this.hasOdhcpd = false,
    this.hasCron = false,
    this.hasDropbear = false,
    this.supportsIpv6InternetFirewall = false,
    this.boardJson,
  });

  /// Default conservative fallback capability set when probing fails
  factory RouterCapabilities.conservative(String routerId, {String? error}) {
    return RouterCapabilities(
      routerId: routerId,
      ubusObjects: const {},
      ubusMethods: const {},
      uciPermissions: const {},
      filePermissions: const {},
      packageEngine: PackageManagerEngine.opkg,
      firewallBackend: FirewallBackend.fw3,
      networkModel: NetworkModel.swconfig,
      releaseVersion: 'Unknown',
      boardName: 'Generic OpenWrt',
      probedAt: DateTime.now(),
      probeFailed: true,
      lastProbeError: error ?? 'Failed to probe router capabilities',
      hasAdGuardHome: false,
      hasOdhcpd: false,
      hasCron: false,
      hasDropbear: false,
      supportsIpv6InternetFirewall: false,
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
        'luci',
      },
      ubusMethods: const {
        'system': ['info', 'board'],
        'luci-rpc': ['getInitList', 'getWirelessDevices'],
        'luci': ['setPassword'],
        'file': ['read', 'stat', 'exec'],
      },
      uciPermissions: const {
        '*': ['read', 'write'],
      },
      filePermissions: const {
        '*': ['read', 'write', 'exec'],
      },
      packageEngine: PackageManagerEngine.opkg,
      firewallBackend: FirewallBackend.fw4,
      networkModel: NetworkModel.dsa,
      releaseVersion: 'OpenWrt 23.05.3',
      boardName: 'x86/64',
      probedAt: DateTime.now(),
      probeFailed: false,
      hasAdGuardHome: true,
      hasOdhcpd: true,
      hasCron: true,
      hasDropbear: true,
      supportsIpv6InternetFirewall: true,
    );
  }

  /// Helper to check if a specific ubus object is available (or covered by wildcard '*')
  bool hasObject(String objectName) {
    if (probeFailed || ubusObjects.isEmpty) return true; // conservative attempt
    return ubusObjects.contains(objectName) || ubusObjects.contains('*');
  }

  /// Helper to check if a specific ubus method is available
  bool hasMethod(String objectName, String methodName) {
    if (probeFailed || ubusObjects.isEmpty) return true;
    if (ubusObjects.contains('*')) return true;
    final methods = ubusMethods[objectName];
    if (methods == null) return ubusObjects.contains(objectName);
    return methods.contains(methodName) || methods.contains('*');
  }

  /// Helper to check if luci-rpc or equivalent wireless/RPC ubus objects are available
  bool get hasLuciRpc {
    if (probeFailed || ubusObjects.isEmpty) return true;
    if (hasObject('*')) return true;
    return hasObject('luci-rpc') || hasObject('iwinfo');
  }

  /// Helper to check if wireless capabilities or objects are supported on this router
  bool get hasWireless {
    if (probeFailed || ubusObjects.isEmpty) return true;
    if (hasObject('*')) return true;
    return hasObject('iwinfo') ||
        hasMethod('luci-rpc', 'getWirelessDevices') ||
        uciPermissions.containsKey('wireless');
  }

  /// Checks whether a specific command or binary path is permitted for execution by OpenWrt rpcd ACLs.
  bool canExecCommand(String command) {
    if (probeFailed) return true; // optimistic default if probing failed
    if (filePermissions.isEmpty) {
      // If file ACLs were not probed, fall back to general ubus method check
      return hasMethod('file', 'exec');
    }
    // Check global wildcard
    if (filePermissions.containsKey('*') &&
        (filePermissions['*']?.contains('exec') == true ||
            filePermissions['*']?.contains('*') == true)) {
      return true;
    }
    // Check exact path match
    if (filePermissions.containsKey(command) &&
        (filePermissions[command]?.contains('exec') == true ||
            filePermissions[command]?.contains('*') == true)) {
      return true;
    }
    // Check wildcard prefix path match (e.g. /bin/*, /usr/bin/*, /*)
    for (final entry in filePermissions.entries) {
      final pattern = entry.key;
      if (pattern.endsWith('*')) {
        final prefix = pattern.substring(0, pattern.length - 1);
        if (command.startsWith(prefix) &&
            (entry.value.contains('exec') || entry.value.contains('*'))) {
          return true;
        }
      }
    }
    return false;
  }

  /// Helper to check if file.exec or backend execution capability is allowed.
  ///
  /// On OpenWrt with rpcd, file.so always exposes the 'exec' ubus method, but rpcd
  /// strictly enforces ACLs. Default LuCI only permits /bin/ping and /bin/traceroute,
  /// but blocks /bin/sh and /usr/bin/curl with UBUS_STATUS_PERMISSION_DENIED (6).
  /// If file ACLs are probed, this verifies that /bin/sh or general command execution is granted.
  bool get hasFileExec {
    if (probeFailed || ubusObjects.isEmpty) return true;
    if (ubusObjects.contains('*')) return true;
    final hasUbusExec =
        ubusMethods.containsKey('file') &&
        (ubusMethods['file']?.contains('exec') == true ||
            ubusMethods['file']?.contains('*') == true);
    if (!hasUbusExec && !hasObject('file')) return false;

    if (filePermissions.isNotEmpty) {
      return canExecCommand('/bin/sh') || canExecCommand('/usr/bin/curl');
    }

    return hasUbusExec;
  }

  /// Helper to check if both RPC modules and execution permissions are available
  bool get isRpcComplete => hasLuciRpc && hasFileExec;

  /// Helper to check if ubus session has write authorization for uci configs
  bool get hasUciWriteAccess {
    if (probeFailed || ubusObjects.isEmpty) {
      return true; // conservative optimistic default
    }
    if (ubusObjects.contains('*')) return true;
    if (uciPermissions.containsKey('*') &&
        (uciPermissions['*']?.contains('write') == true ||
            uciPermissions['*']?.contains('*') == true)) {
      return true;
    }
    if (uciPermissions.values.any(
      (perms) => perms.contains('write') || perms.contains('*'),
    )) {
      return true;
    }
    if (!ubusObjects.contains('uci')) return false;
    final methods = ubusMethods['uci'];
    if (methods == null) return ubusObjects.contains('uci');
    return (methods.contains('set') || methods.contains('*')) &&
        (methods.contains('apply') ||
            methods.contains('commit') ||
            methods.contains('*'));
  }

  /// Helper to check if ubus session has write authorization for firewall UCI config
  bool get canModifyFirewall {
    if (!hasUciWriteAccess) return false;
    if (uciPermissions.containsKey('firewall')) {
      final perms = uciPermissions['firewall'] ?? [];
      return perms.contains('write') || perms.contains('*');
    }
    return hasUciWriteAccess;
  }

  /// Helper to check if active package manager engine is Alpine Package Keeper (apk)
  bool get isApk => packageEngine == PackageManagerEngine.apk;

  /// Helper to check if active package manager engine is OPKG (ipk)
  bool get isOpkg => packageEngine == PackageManagerEngine.opkg;

  /// Helper to check if uci.apply ubus method is available
  bool get hasUciApply => hasMethod('uci', 'apply');

  /// Helper to check if uci.confirm ubus method is available
  bool get hasUciConfirm => hasMethod('uci', 'confirm');

  /// Helper to check if luci.setPassword method is explicitly available
  /// Method-level capability verification: does not rely solely on luci object presence.
  bool get hasSetPasswordRpc {
    return ubusMethods['luci']?.contains('setPassword') ?? false;
  }

  /// Serialize for secure storage cache
  Map<String, dynamic> toJson() {
    return {
      'routerId': routerId,
      'ubusObjects': ubusObjects.toList(),
      'ubusMethods': ubusMethods.map((key, value) => MapEntry(key, value)),
      'uciPermissions': uciPermissions.map(
        (key, value) => MapEntry(key, value),
      ),
      'filePermissions': filePermissions.map(
        (key, value) => MapEntry(key, value),
      ),
      'packageEngine': packageEngine.name,
      'firewallBackend': firewallBackend.name,
      'networkModel': networkModel.name,
      'releaseVersion': releaseVersion,
      'boardName': boardName,
      'probedAt': probedAt.toIso8601String(),
      'probeFailed': probeFailed,
      'lastProbeError': lastProbeError,
      'hasAdGuardHome': hasAdGuardHome,
      'hasOdhcpd': hasOdhcpd,
      'hasCron': hasCron,
      'hasDropbear': hasDropbear,
      'supportsIpv6InternetFirewall': supportsIpv6InternetFirewall,
      'boardJson': boardJson,
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
      final rawUciPermissions =
          json['uciPermissions'] as Map<String, dynamic>? ?? {};
      final uciPermissionsMap = rawUciPermissions.map(
        (key, value) => MapEntry(key, (value as List).cast<String>()),
      );
      final rawFilePermissions =
          json['filePermissions'] as Map<String, dynamic>? ?? {};
      final filePermissionsMap = rawFilePermissions.map(
        (key, value) => MapEntry(key, (value as List).cast<String>()),
      );

      return RouterCapabilities(
        routerId: json['routerId'] as String? ?? 'default',
        ubusObjects: ubusObjsList.toSet(),
        ubusMethods: ubusMethodsMap,
        uciPermissions: uciPermissionsMap,
        filePermissions: filePermissionsMap,
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
        hasAdGuardHome: json['hasAdGuardHome'] as bool? ?? false,
        hasOdhcpd: json['hasOdhcpd'] as bool? ?? false,
        hasCron: json['hasCron'] as bool? ?? false,
        hasDropbear: json['hasDropbear'] as bool? ?? false,
        supportsIpv6InternetFirewall:
            json['supportsIpv6InternetFirewall'] as bool? ?? false,
        boardJson: json['boardJson'] is Map
            ? Map<String, dynamic>.from(json['boardJson'] as Map)
            : null,
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
    Map<String, List<String>>? uciPermissions,
    Map<String, List<String>>? filePermissions,
    PackageManagerEngine? packageEngine,
    FirewallBackend? firewallBackend,
    NetworkModel? networkModel,
    String? releaseVersion,
    String? boardName,
    DateTime? probedAt,
    bool? probeFailed,
    String? lastProbeError,
    bool? hasAdGuardHome,
    bool? hasOdhcpd,
    bool? hasCron,
    bool? hasDropbear,
    bool? supportsIpv6InternetFirewall,
    Map<String, dynamic>? boardJson,
  }) {
    return RouterCapabilities(
      routerId: routerId ?? this.routerId,
      ubusObjects: ubusObjects ?? this.ubusObjects,
      ubusMethods: ubusMethods ?? this.ubusMethods,
      uciPermissions: uciPermissions ?? this.uciPermissions,
      filePermissions: filePermissions ?? this.filePermissions,
      packageEngine: packageEngine ?? this.packageEngine,
      firewallBackend: firewallBackend ?? this.firewallBackend,
      networkModel: networkModel ?? this.networkModel,
      releaseVersion: releaseVersion ?? this.releaseVersion,
      boardName: boardName ?? this.boardName,
      probedAt: probedAt ?? this.probedAt,
      probeFailed: probeFailed ?? this.probeFailed,
      lastProbeError: lastProbeError ?? this.lastProbeError,
      hasAdGuardHome: hasAdGuardHome ?? this.hasAdGuardHome,
      hasOdhcpd: hasOdhcpd ?? this.hasOdhcpd,
      hasCron: hasCron ?? this.hasCron,
      hasDropbear: hasDropbear ?? this.hasDropbear,
      supportsIpv6InternetFirewall:
          supportsIpv6InternetFirewall ?? this.supportsIpv6InternetFirewall,
      boardJson: boardJson ?? this.boardJson,
    );
  }
}
