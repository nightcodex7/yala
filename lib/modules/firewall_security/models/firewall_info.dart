// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/models/router_capabilities.dart';

/// Default global firewall policy.
class FirewallDefaultPolicy {
  final String input;
  final String output;
  final String forward;
  final bool synFlood;

  const FirewallDefaultPolicy({
    required this.input,
    required this.output,
    required this.forward,
    required this.synFlood,
  });

  factory FirewallDefaultPolicy.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const FirewallDefaultPolicy(
        input: 'ACCEPT',
        output: 'ACCEPT',
        forward: 'REJECT',
        synFlood: true,
      );
    }

    return FirewallDefaultPolicy(
      input: (json['input']?.toString() ?? 'ACCEPT').toUpperCase(),
      output: (json['output']?.toString() ?? 'ACCEPT').toUpperCase(),
      forward: (json['forward']?.toString() ?? 'REJECT').toUpperCase(),
      synFlood: json['syn_flood'] == '1' || json['syn_flood'] == true,
    );
  }
}

/// Firewall zone definition (e.g., LAN, WAN).
class FirewallZone {
  final String name;
  final String input;
  final String output;
  final String forward;
  final bool masquerade;
  final List<String> networks;

  const FirewallZone({
    required this.name,
    required this.input,
    required this.output,
    required this.forward,
    required this.masquerade,
    required this.networks,
  });

  factory FirewallZone.fromJson(String name, Map<String, dynamic> json) {
    final nets = <String>[];
    final netVal = json['network'];
    if (netVal is List) {
      nets.addAll(netVal.map((e) => e.toString()));
    } else if (netVal is String) {
      nets.add(netVal);
    }

    return FirewallZone(
      name: json['name']?.toString() ?? name,
      input: (json['input']?.toString() ?? 'ACCEPT').toUpperCase(),
      output: (json['output']?.toString() ?? 'ACCEPT').toUpperCase(),
      forward: (json['forward']?.toString() ?? 'REJECT').toUpperCase(),
      masquerade: json['masq'] == '1' || json['masq'] == true,
      networks: nets,
    );
  }
}

/// Firewall inter-zone forwarding rule (e.g. lan -> wan).
class FirewallForwarding {
  final String srcZone;
  final String destZone;

  const FirewallForwarding({required this.srcZone, required this.destZone});

  factory FirewallForwarding.fromJson(Map<String, dynamic> json) {
    return FirewallForwarding(
      srcZone: json['src']?.toString() ?? 'lan',
      destZone: json['dest']?.toString() ?? 'wan',
    );
  }
}

/// Port forwarding rule (redirect).
class FirewallPortForwarding {
  final String name;
  final String srcZone;
  final String srcPort;
  final String destZone;
  final String destIp;
  final String destPort;
  final String proto;

  const FirewallPortForwarding({
    required this.name,
    required this.srcZone,
    required this.srcPort,
    required this.destZone,
    required this.destIp,
    required this.destPort,
    required this.proto,
  });

  factory FirewallPortForwarding.fromJson(Map<String, dynamic> json) {
    return FirewallPortForwarding(
      name: json['name']?.toString() ?? json['.name']?.toString() ?? 'Redirect',
      srcZone: json['src']?.toString() ?? 'wan',
      srcPort:
          json['src_dport']?.toString() ??
          json['src_port']?.toString() ??
          'Any',
      destZone: json['dest']?.toString() ?? 'lan',
      destIp: json['dest_ip']?.toString() ?? 'Any',
      destPort:
          json['dest_port']?.toString() ??
          json['src_dport']?.toString() ??
          'Any',
      proto: json['proto']?.toString() ?? 'tcp',
    );
  }
}

/// Custom security rule.
class FirewallCustomRule {
  final String sectionKey;
  final String name;
  final String srcZone;
  final String destZone;
  final String target;
  final bool enabled;
  final bool isUnrecognizedTarget;

  static const List<String> knownTargets = [
    'ACCEPT',
    'REJECT',
    'DROP',
    'DNAT',
    'SNAT',
    'MASQUERADE',
    'NOTRACK',
    'HELPER',
    'MARK',
    'DSCP',
  ];

  const FirewallCustomRule({
    required this.sectionKey,
    required this.name,
    required this.srcZone,
    required this.destZone,
    required this.target,
    required this.enabled,
    this.isUnrecognizedTarget = false,
  });

  FirewallCustomRule copyWith({
    String? sectionKey,
    String? name,
    String? srcZone,
    String? destZone,
    String? target,
    bool? enabled,
    bool? isUnrecognizedTarget,
  }) {
    return FirewallCustomRule(
      sectionKey: sectionKey ?? this.sectionKey,
      name: name ?? this.name,
      srcZone: srcZone ?? this.srcZone,
      destZone: destZone ?? this.destZone,
      target: target ?? this.target,
      enabled: enabled ?? this.enabled,
      isUnrecognizedTarget: isUnrecognizedTarget ?? this.isUnrecognizedTarget,
    );
  }

  factory FirewallCustomRule.fromJson(String key, Map<String, dynamic> json) {
    final rawTarget = (json['target']?.toString() ?? 'ACCEPT').toUpperCase();
    final isUnknown = !knownTargets.contains(rawTarget);
    final secName = json['.name']?.toString() ?? key;

    return FirewallCustomRule(
      sectionKey: secName.isNotEmpty ? secName : key,
      name: json['name']?.toString() ?? 'Custom Rule',
      srcZone: json['src']?.toString() ?? 'wan',
      destZone: json['dest']?.toString() ?? 'lan',
      target: rawTarget,
      enabled: json['enabled'] != '0' && json['enabled'] != false,
      isUnrecognizedTarget: isUnknown,
    );
  }
}

/// Complete firewall & security overview container.
class FirewallOverview {
  final FirewallBackend backend;
  final FirewallDefaultPolicy defaultPolicy;
  final List<FirewallZone> zones;
  final List<FirewallForwarding> forwardings;
  final List<FirewallPortForwarding> portForwards;
  final List<FirewallCustomRule> customRules;
  final bool isAvailable;
  final bool isNoCustomRules;
  final String? errorMessage;

  const FirewallOverview({
    required this.backend,
    required this.defaultPolicy,
    required this.zones,
    required this.forwardings,
    required this.portForwards,
    required this.customRules,
    required this.isAvailable,
    required this.isNoCustomRules,
    this.errorMessage,
  });

  factory FirewallOverview.unavailable(
    FirewallBackend backend, [
    String? reason,
  ]) {
    return FirewallOverview(
      backend: backend,
      defaultPolicy: const FirewallDefaultPolicy(
        input: 'ACCEPT',
        output: 'ACCEPT',
        forward: 'REJECT',
        synFlood: true,
      ),
      zones: const [],
      forwardings: const [],
      portForwards: const [],
      customRules: const [],
      isAvailable: false,
      isNoCustomRules: false,
      errorMessage: reason ?? 'Firewall configuration unavailable',
    );
  }

  factory FirewallOverview.fromUciData(
    Map<String, dynamic>? uciData, {
    FirewallBackend backend = FirewallBackend.fw4,
    bool isReviewerMode = false,
  }) {
    if (uciData == null) {
      if (isReviewerMode) {
        return Fw4FirewallParser.parse({
          'values': {
            'defaults': {
              '.type': 'defaults',
              'input': 'ACCEPT',
              'output': 'ACCEPT',
              'forward': 'REJECT',
            },
            'lan': {
              '.type': 'zone',
              'name': 'lan',
              'input': 'ACCEPT',
              'output': 'ACCEPT',
              'forward': 'ACCEPT',
              'network': ['lan'],
            },
            'wan': {
              '.type': 'zone',
              'name': 'wan',
              'input': 'REJECT',
              'output': 'ACCEPT',
              'forward': 'REJECT',
              'masq': '1',
              'network': ['wan', 'wan6'],
            },
            'fwd': {'.type': 'forwarding', 'src': 'lan', 'dest': 'wan'},
            'ssh': {
              '.type': 'redirect',
              'name': 'SSH Forward',
              'src': 'wan',
              'src_dport': '2222',
              'dest': 'lan',
              'dest_ip': '192.168.1.1',
              'dest_port': '22',
              'proto': 'tcp',
            },
            'r1': {
              '.type': 'rule',
              'name': 'Allow-DHCP-Renew',
              'src': 'wan',
              'dest': 'lan',
              'target': 'ACCEPT',
              'enabled': '1',
            },
          },
        });
      }
      return FirewallOverview.unavailable(
        backend,
        'No firewall configuration data received',
      );
    }

    if (backend == FirewallBackend.fw3) {
      return Fw3FirewallParser.parse(uciData);
    } else {
      return Fw4FirewallParser.parse(uciData);
    }
  }
}

/// Dedicated Firewall3 (iptables backend) parser
class Fw3FirewallParser {
  static FirewallOverview parse(Map<String, dynamic> uciFirewallConfig) {
    try {
      final rawValues = uciFirewallConfig['values'];
      final Map<String, dynamic> uciValues = (rawValues is Map)
          ? Map<String, dynamic>.from(rawValues)
          : Map<String, dynamic>.from(uciFirewallConfig);

      if (uciValues.isEmpty) {
        return FirewallOverview.unavailable(
          FirewallBackend.fw3,
          'UCI firewall configuration payload is empty or unpopulated',
        );
      }

      Map<String, dynamic>? defaultsMap;
      final zoneList = <FirewallZone>[];
      final fwdList = <FirewallForwarding>[];
      final pfList = <FirewallPortForwarding>[];
      final ruleList = <FirewallCustomRule>[];
      bool hasDefaultsOrZone = false;

      uciValues.forEach((key, val) {
        if (val is Map) {
          final type = val['.type']?.toString();
          if (type == 'defaults') {
            defaultsMap = Map<String, dynamic>.from(val);
            hasDefaultsOrZone = true;
          } else if (type == 'zone') {
            zoneList.add(
              FirewallZone.fromJson(key, Map<String, dynamic>.from(val)),
            );
            hasDefaultsOrZone = true;
          } else if (type == 'forwarding') {
            fwdList.add(
              FirewallForwarding.fromJson(Map<String, dynamic>.from(val)),
            );
          } else if (type == 'redirect') {
            pfList.add(
              FirewallPortForwarding.fromJson(Map<String, dynamic>.from(val)),
            );
          } else if (type == 'rule') {
            ruleList.add(
              FirewallCustomRule.fromJson(key, Map<String, dynamic>.from(val)),
            );
          }
        }
      });

      if (!hasDefaultsOrZone) {
        return FirewallOverview.unavailable(
          FirewallBackend.fw3,
          'No valid firewall defaults or zone sections found in payload',
        );
      }

      final isNoCustom = ruleList.isEmpty && pfList.isEmpty;

      return FirewallOverview(
        backend: FirewallBackend.fw3,
        defaultPolicy: FirewallDefaultPolicy.fromJson(defaultsMap),
        zones: zoneList,
        forwardings: fwdList,
        portForwards: pfList,
        customRules: ruleList,
        isAvailable: true,
        isNoCustomRules: isNoCustom,
      );
    } catch (e) {
      return FirewallOverview.unavailable(
        FirewallBackend.fw3,
        'Failed to parse fw3 firewall config: $e',
      );
    }
  }
}

/// Dedicated Firewall4 (nftables backend) parser
class Fw4FirewallParser {
  static FirewallOverview parse(Map<String, dynamic> uciFirewallConfig) {
    try {
      final rawValues = uciFirewallConfig['values'];
      final Map<String, dynamic> uciValues = (rawValues is Map)
          ? Map<String, dynamic>.from(rawValues)
          : Map<String, dynamic>.from(uciFirewallConfig);

      if (uciValues.isEmpty) {
        return FirewallOverview.unavailable(
          FirewallBackend.fw4,
          'UCI firewall configuration payload is empty or unpopulated',
        );
      }

      Map<String, dynamic>? defaultsMap;
      final zoneList = <FirewallZone>[];
      final fwdList = <FirewallForwarding>[];
      final pfList = <FirewallPortForwarding>[];
      final ruleList = <FirewallCustomRule>[];
      bool hasDefaultsOrZone = false;

      uciValues.forEach((key, val) {
        if (val is Map) {
          final type = val['.type']?.toString();
          if (type == 'defaults') {
            defaultsMap = Map<String, dynamic>.from(val);
            hasDefaultsOrZone = true;
          } else if (type == 'zone') {
            zoneList.add(
              FirewallZone.fromJson(key, Map<String, dynamic>.from(val)),
            );
            hasDefaultsOrZone = true;
          } else if (type == 'forwarding') {
            fwdList.add(
              FirewallForwarding.fromJson(Map<String, dynamic>.from(val)),
            );
          } else if (type == 'redirect') {
            pfList.add(
              FirewallPortForwarding.fromJson(Map<String, dynamic>.from(val)),
            );
          } else if (type == 'rule') {
            ruleList.add(
              FirewallCustomRule.fromJson(key, Map<String, dynamic>.from(val)),
            );
          }
        }
      });

      if (!hasDefaultsOrZone) {
        return FirewallOverview.unavailable(
          FirewallBackend.fw4,
          'No valid firewall defaults or zone sections found in payload',
        );
      }

      final isNoCustom = ruleList.isEmpty && pfList.isEmpty;

      return FirewallOverview(
        backend: FirewallBackend.fw4,
        defaultPolicy: FirewallDefaultPolicy.fromJson(defaultsMap),
        zones: zoneList,
        forwardings: fwdList,
        portForwards: pfList,
        customRules: ruleList,
        isAvailable: true,
        isNoCustomRules: isNoCustom,
      );
    } catch (e) {
      return FirewallOverview.unavailable(
        FirewallBackend.fw4,
        'Failed to parse fw4 firewall config: $e',
      );
    }
  }
}
