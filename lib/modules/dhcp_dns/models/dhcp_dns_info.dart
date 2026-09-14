// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class DhcpLease {
  final String hostname;
  final String ipAddress;
  final String ip6Address;
  final String macAddress;
  final String duid;
  final int expirySeconds;
  final bool isStatic;
  final String staticLeaseTime;

  const DhcpLease({
    required this.hostname,
    required this.ipAddress,
    this.ip6Address = '',
    required this.macAddress,
    this.duid = '',
    required this.expirySeconds,
    this.isStatic = false,
    this.staticLeaseTime = '',
  });

  factory DhcpLease.fromJson(Map<String, dynamic> json) {
    int parseSec(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    final expRaw = json['expires'];
    final ltRaw = json['leasetime'];
    final expiry = expRaw != null && expRaw is! bool
        ? parseSec(expRaw)
        : (ltRaw != null && ltRaw is! bool ? parseSec(ltRaw) : 0);

    var ip4 = json['ipaddr']?.toString() ?? json['ip']?.toString() ?? '';
    var ip6 = json['ip6addr']?.toString() ?? json['ip6']?.toString() ?? '';
    if (ip6.isEmpty &&
        json['ip6addrs'] is List &&
        (json['ip6addrs'] as List).isNotEmpty) {
      ip6 = (json['ip6addrs'] as List).first.toString();
    }

    bool isIPv6Addr(String ip) {
      try {
        final cleaned = ip.trim().split('/').first;
        final unbracketed = (cleaned.startsWith('[') && cleaned.endsWith(']'))
            ? cleaned.substring(1, cleaned.length - 1)
            : cleaned;
        Uri.parseIPv6Address(unbracketed);
        return true;
      } catch (_) {
        return false;
      }
    }

    if (ip4.isNotEmpty && isIPv6Addr(ip4) && ip6.isEmpty) {
      ip6 = ip4;
      ip4 = '';
    }

    final mainIp = ip4.isNotEmpty ? ip4 : (ip6.isNotEmpty ? ip6 : 'N/A');

    String mac = json['macaddr']?.toString() ?? json['mac']?.toString() ?? '';
    final duid = json['duid']?.toString() ?? json['host_id']?.toString() ?? '';
    if (mac.isEmpty && duid.isNotEmpty) {
      mac = 'DUID: ${duid.length > 18 ? duid.substring(0, 18) : duid}';
    } else if (mac.isEmpty) {
      mac = 'N/A';
    }

    return DhcpLease(
      hostname:
          json['hostname']?.toString() ??
          json['name']?.toString() ??
          'Anonymous Device',
      ipAddress: mainIp,
      ip6Address: ip6,
      macAddress: mac.toUpperCase(),
      duid: duid,
      expirySeconds: expiry,
      isStatic: json['isStaticLease'] == true || json['isStatic'] == true,
      staticLeaseTime: json['leasetime']?.toString() ?? '',
    );
  }

  String get formattedExpiry {
    if (isStatic) {
      if (staticLeaseTime.isNotEmpty &&
          staticLeaseTime.toLowerCase() != 'infinite') {
        return 'Static ($staticLeaseTime)';
      }
      return 'Static (Unlimited)';
    }
    if (expirySeconds <= 0) return 'Unlimited';
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    int remaining;
    if (expirySeconds > 1000000000) {
      if (expirySeconds <= nowSeconds) return 'Expired';
      remaining = expirySeconds - nowSeconds;
    } else {
      remaining = expirySeconds;
    }
    if (remaining <= 0) return 'Expired';
    final duration = Duration(seconds: remaining);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m remaining';
    if (minutes > 0) return '${minutes}m remaining';
    return '< 1m remaining';
  }
}

/// Represents an active IPv6 DHCP or SLAAC lease (from odhcpd / dhcp6Leases).
class Dhcp6Lease {
  final String hostname;
  final String ip6Address;
  final List<String> ipv6Addresses;
  final String macAddress;
  final String duid;
  final String iaid;
  final int expirySeconds;

  const Dhcp6Lease({
    required this.hostname,
    required this.ip6Address,
    this.ipv6Addresses = const [],
    required this.macAddress,
    required this.duid,
    this.iaid = '',
    required this.expirySeconds,
  });

  factory Dhcp6Lease.fromJson(Map<String, dynamic> json) {
    int parseSec(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    final expRaw = json['expires'];
    final ltRaw = json['leasetime'];
    final expiry = expRaw != null && expRaw is! bool
        ? parseSec(expRaw)
        : (ltRaw != null && ltRaw is! bool ? parseSec(ltRaw) : 0);

    var ip6 =
        json['ip6addr']?.toString() ??
        json['ip6']?.toString() ??
        json['ip']?.toString() ??
        '';
    final v6List = <String>[];
    if (json['ip6addrs'] is List) {
      for (final a in json['ip6addrs']) {
        if (a != null && a.toString().isNotEmpty) v6List.add(a.toString());
      }
    }
    if (ip6.isEmpty && v6List.isNotEmpty) {
      ip6 = v6List.first;
    } else if (ip6.isNotEmpty && !v6List.contains(ip6)) {
      v6List.insert(0, ip6);
    }

    final mac = json['macaddr']?.toString() ?? json['mac']?.toString() ?? 'N/A';
    final duidStr =
        json['duid']?.toString() ?? json['host_id']?.toString() ?? 'N/A';
    final iaidStr = json['iaid']?.toString() ?? '';

    return Dhcp6Lease(
      hostname:
          json['hostname']?.toString() ??
          json['name']?.toString() ??
          'Anonymous IPv6 Host',
      ip6Address: ip6.isNotEmpty ? ip6 : 'N/A',
      ipv6Addresses: v6List,
      macAddress: mac.toUpperCase(),
      duid: duidStr.toUpperCase(),
      iaid: iaidStr,
      expirySeconds: expiry,
    );
  }

  String get formattedExpiry {
    if (expirySeconds <= 0) return 'Unlimited';
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    int remaining;
    if (expirySeconds > 1000000000) {
      if (expirySeconds <= nowSeconds) return 'Expired';
      remaining = expirySeconds - nowSeconds;
    } else {
      remaining = expirySeconds;
    }
    if (remaining <= 0) return 'Expired';
    final duration = Duration(seconds: remaining);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m remaining';
    if (minutes > 0) return '${minutes}m remaining';
    return '< 1m remaining';
  }
}

/// Represents a static IP DHCP reservation mapping (supporting IPv4 and/or IPv6).
class DhcpStaticMapping {
  final String hostname;
  final String ipAddress;
  final String ip6Address;
  final String macAddress;
  final String duid;
  final String leaseTime;

  const DhcpStaticMapping({
    required this.hostname,
    required this.ipAddress,
    this.ip6Address = '',
    required this.macAddress,
    this.duid = '',
    this.leaseTime = '',
  });

  factory DhcpStaticMapping.fromJson(Map<String, dynamic> json) {
    String macStr = 'N/A';
    final macVal = json['mac'] ?? json['macaddr'];
    if (macVal is List) {
      macStr = macVal.join(', ');
    } else if (macVal != null && macVal.toString().isNotEmpty) {
      macStr = macVal.toString();
    }

    final lt =
        json['leasetime']?.toString() ?? json['lease_time']?.toString() ?? '';
    final ip6 = json['ip6addr']?.toString() ?? json['hostid']?.toString() ?? '';
    final duidStr = json['duid']?.toString() ?? '';

    return DhcpStaticMapping(
      hostname:
          json['name']?.toString() ??
          json['hostname']?.toString() ??
          'Unnamed Host',
      ipAddress: json['ip']?.toString() ?? json['ipaddr']?.toString() ?? 'N/A',
      ip6Address: ip6,
      macAddress: macStr.toUpperCase(),
      duid: duidStr.toUpperCase(),
      leaseTime: lt,
    );
  }
}

/// Represents a configured network interface subnet & DHCP pool boundaries.
class SubnetInfo {
  final String interfaceName;
  final String gatewayIp;
  final String netmask;
  final int? poolStart;
  final int? poolLimit;

  const SubnetInfo({
    required this.interfaceName,
    required this.gatewayIp,
    required this.netmask,
    this.poolStart,
    this.poolLimit,
  });

  static int? _ipToInt(String ip) {
    final parts = ip.trim().split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) {
      return null;
    }
    return ((parts[0]! << 24) |
            (parts[1]! << 16) |
            (parts[2]! << 8) |
            parts[3]!) &
        0xFFFFFFFF;
  }

  static int _netmaskToInt(String mask) {
    var m = mask.trim();
    if (m.startsWith('/')) {
      final prefix = int.tryParse(m.substring(1));
      if (prefix != null && prefix >= 0 && prefix <= 32) {
        return prefix == 0 ? 0 : ((0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF);
      }
    }
    final parsed = _ipToInt(m);
    if (parsed != null && parsed != 0) return parsed;
    return 0xFFFFFF00;
  }

  bool containsIp(String ip) {
    final ipInt = _ipToInt(ip);
    final gwInt = _ipToInt(gatewayIp);
    if (ipInt == null || gwInt == null) return false;

    final maskInt = _netmaskToInt(netmask);
    return (ipInt & maskInt) == (gwInt & maskInt);
  }

  bool isGateway(String ip) => ip.trim() == gatewayIp.trim();

  bool isNetworkOrBroadcast(String ip) {
    final ipOctets = ip.trim().split('.').map(int.tryParse).toList();
    if (ipOctets.length != 4 || ipOctets.any((o) => o == null)) return false;
    final lastOctet = ipOctets[3]!;
    return lastOctet == 0 || lastOctet == 255;
  }

  bool isInDhcpPool(String ip) {
    if (poolStart == null || poolLimit == null) return true;
    final ipOctets = ip.trim().split('.').map(int.tryParse).toList();
    if (ipOctets.length != 4 || ipOctets.any((o) => o == null)) return false;
    final lastOctet = ipOctets[3]!;
    final poolEnd = poolStart! + poolLimit! - 1;
    return lastOctet >= poolStart! && lastOctet <= poolEnd;
  }

  String get poolRangeLabel {
    if (poolStart == null || poolLimit == null) return 'Entire Subnet';
    final gwPrefix = gatewayIp.contains('.')
        ? gatewayIp.substring(0, gatewayIp.lastIndexOf('.'))
        : gatewayIp;
    final poolEnd = poolStart! + poolLimit! - 1;
    return '$gwPrefix.$poolStart - $gwPrefix.$poolEnd';
  }
}

/// Dnsmasq and upstream DNS forwarders configuration.
class DnsmasqConfig {
  final String localDomain;
  final List<String> upstreamDnsServers;
  final bool rebindProtection;
  final bool domainNeeded;
  final bool authoritative;

  const DnsmasqConfig({
    required this.localDomain,
    required this.upstreamDnsServers,
    required this.rebindProtection,
    required this.domainNeeded,
    required this.authoritative,
  });

  factory DnsmasqConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DnsmasqConfig(
        localDomain: 'lan',
        upstreamDnsServers: ['ISP Default (Dynamic DNS)'],
        rebindProtection: true,
        domainNeeded: true,
        authoritative: true,
      );
    }

    final servers = <String>[];
    final serverVal = json['server'];
    if (serverVal is List) {
      servers.addAll(serverVal.map((e) => e.toString()));
    } else if (serverVal is String) {
      servers.add(serverVal);
    }
    return DnsmasqConfig(
      localDomain: json['domain']?.toString() ?? 'lan',
      upstreamDnsServers: servers.isNotEmpty
          ? servers
          : const ['ISP Default (Dynamic DNS)'],
      rebindProtection:
          json['rebind_protection'] == '1' || json['rebind_protection'] == true,
      domainNeeded: json['domainneeded'] == '1' || json['domainneeded'] == true,
      authoritative:
          json['authoritative'] == '1' || json['authoritative'] == true,
    );
  }
}

/// Complete overview container for DHCP & DNS monitoring.
class DhcpDnsOverview {
  final DnsmasqConfig dnsConfig;
  final List<DhcpLease> activeLeases;
  final List<Dhcp6Lease> activeDhcp6Leases;
  final List<DhcpStaticMapping> staticMappings;
  final List<SubnetInfo> configuredSubnets;

  const DhcpDnsOverview({
    required this.dnsConfig,
    required this.activeLeases,
    required this.activeDhcp6Leases,
    required this.staticMappings,
    required this.configuredSubnets,
  });

  factory DhcpDnsOverview.fromDashboardData(
    Map<String, dynamic>? data, {
    bool isReviewerMode = false,
  }) {
    final leaseList = <DhcpLease>[];
    final dhcp6List = <Dhcp6Lease>[];
    final staticList = <DhcpStaticMapping>[];
    final onlineMacSet = <String>{};
    final offlineMacSet = <String>{};
    Map<String, dynamic>? dnsmasqRaw;
    final uciMacs = <String>{};
    final hostHints = data?['hostHints'];

    bool isValidIPv4(String ip) {
      final parts = ip.trim().split('.');
      if (parts.length != 4) return false;
      for (final p in parts) {
        final n = int.tryParse(p);
        if (n == null || n < 0 || n > 255) return false;
      }
      return true;
    }

    bool isValidMac(String mac) {
      final m = mac.trim();
      if (m.isEmpty || m == 'N/A') return false;
      if (m.contains(',')) {
        return m.split(',').any((sub) => isValidMac(sub));
      }
      return RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$').hasMatch(m);
    }

    bool isValidMapping(DhcpStaticMapping mapping) {
      if (!isValidMac(mapping.macAddress)) return false;
      return (isValidIPv4(mapping.ipAddress) && mapping.ipAddress != 'N/A') ||
          mapping.ip6Address.isNotEmpty ||
          mapping.duid.isNotEmpty;
    }

    if (data != null) {
      void processLeaseItem(dynamic item) {
        if (item is DhcpLease) {
          leaseList.add(item);
        } else if (item is Map) {
          final itemMap = Map<String, dynamic>.from(item);
          final parsed = DhcpLease.fromJson(itemMap);
          if (parsed.macAddress.isNotEmpty && parsed.macAddress != 'N/A') {
            leaseList.add(parsed);
          }
        }
      }

      void processRawLeaseString(String rawStr) {
        for (final line in rawStr.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final timestamp = int.tryParse(parts[0]) ?? 0;
            final macAddress = parts[1];
            final ipAddress = parts[2];
            final hostname = parts[3] == '*' ? 'Anonymous Device' : parts[3];

            if (macAddress.isNotEmpty && macAddress != 'N/A') {
              leaseList.add(
                DhcpLease(
                  hostname: hostname,
                  ipAddress: ipAddress,
                  macAddress: macAddress.toUpperCase(),
                  expirySeconds: timestamp,
                ),
              );
            }
          }
        }
      }

      void addLeasesFromList(dynamic raw) {
        if (raw == null) return;
        if (raw is DhcpLease) {
          leaseList.add(raw);
          return;
        }
        if (raw is String) {
          processRawLeaseString(raw);
          return;
        }
        if (raw is List) {
          for (final item in raw) {
            addLeasesFromList(item);
          }
        } else if (raw is Map) {
          if (raw.containsKey('dhcp_leases') ||
              raw.containsKey('dhcpLeases') ||
              raw.containsKey('leases')) {
            addLeasesFromList(
              raw['dhcp_leases'] ?? raw['dhcpLeases'] ?? raw['leases'],
            );
          } else if (raw.containsKey('ipaddr') ||
              raw.containsKey('ip') ||
              raw.containsKey('macaddr') ||
              raw.containsKey('mac')) {
            processLeaseItem(raw);
          } else if (raw['data'] != null || raw['stdout'] != null) {
            final str =
                raw['data']?.toString() ?? raw['stdout']?.toString() ?? '';
            processRawLeaseString(str);
          } else {
            raw.forEach((key, val) {
              addLeasesFromList(val);
            });
          }
        }
      }

      addLeasesFromList(data['dhcpLeases'] ?? data['dhcp_leases']);

      void processDhcp6Item(dynamic item) {
        if (item is Dhcp6Lease) {
          dhcp6List.add(item);
        } else if (item is Map) {
          final itemMap = Map<String, dynamic>.from(item);
          dhcp6List.add(Dhcp6Lease.fromJson(itemMap));
        }
      }

      void addDhcp6LeasesFromList(dynamic raw) {
        if (raw == null) return;
        if (raw is Dhcp6Lease) {
          dhcp6List.add(raw);
          return;
        }
        if (raw is List) {
          for (final item in raw) {
            addDhcp6LeasesFromList(item);
          }
        } else if (raw is Map) {
          if (raw.containsKey('dhcp6_leases') ||
              raw.containsKey('dhcp6Leases')) {
            addDhcp6LeasesFromList(raw['dhcp6_leases'] ?? raw['dhcp6Leases']);
          } else if (raw.containsKey('ip6addr') ||
              raw.containsKey('ip6') ||
              raw.containsKey('duid') ||
              raw.containsKey('iaid')) {
            processDhcp6Item(raw);
          } else {
            raw.forEach((key, val) {
              addDhcp6LeasesFromList(val);
            });
          }
        }
      }

      addDhcp6LeasesFromList(data['dhcp6Leases'] ?? data['dhcp6_leases']);

      final clientsRaw = data['clients'];
      if (clientsRaw is List) {
        for (final c in clientsRaw) {
          if (c is Map) {
            final mac =
                (c['macAddress'] ?? c['macaddr'] ?? c['mac'])
                    ?.toString()
                    .toUpperCase()
                    .replaceAll('-', ':') ??
                '';
            final isOnline =
                c['isConnected'] == true ||
                c['isOnline'] == true ||
                c['connected'] == true;
            final isStatic = c['isStaticLease'] == true;
            if (mac.isNotEmpty && mac != 'N/A') {
              if (isOnline) {
                onlineMacSet.add(mac);
              } else {
                offlineMacSet.add(mac);
              }
            }
            final ip =
                (c['ipAddress'] ?? c['ipaddr'] ?? c['ip'])?.toString() ?? '';
            if (mac.isNotEmpty &&
                mac != 'N/A' &&
                ip.isNotEmpty &&
                ip != 'N/A' &&
                !isStatic) {
              final exists = leaseList.any(
                (l) => l.macAddress.toUpperCase().replaceAll('-', ':') == mac,
              );
              if (!exists && isOnline) {
                leaseList.add(
                  DhcpLease(
                    hostname:
                        (c['name'] ?? c['hostname'])?.toString() ??
                        'Connected Client',
                    ipAddress: ip,
                    macAddress: mac,
                    expirySeconds: 0,
                  ),
                );
              }
            }
          }
        }
      }

      // Parse UCI DHCP config for dnsmasq and static host mappings
      final rawUciDhcp = data['uciDhcpConfig'] ?? data['dhcp'];
      Map<String, dynamic>? uciDhcp;
      if (rawUciDhcp is Map<String, dynamic>) {
        uciDhcp = rawUciDhcp;
      } else if (rawUciDhcp is Map) {
        uciDhcp = rawUciDhcp.cast<String, dynamic>();
      }

      if (uciDhcp != null) {
        final rawValues = uciDhcp['values'] ?? uciDhcp;
        void processHostItem(dynamic val) {
          if (val is Map) {
            final valMap = Map<String, dynamic>.from(val);
            final type = valMap['.type']?.toString();
            if (type == 'dnsmasq') {
              dnsmasqRaw = valMap;
            } else if (type == 'host') {
              final mapping = DhcpStaticMapping.fromJson(valMap);
              if (isValidMapping(mapping)) {
                final normMacs = mapping.macAddress
                    .toUpperCase()
                    .replaceAll('-', ':')
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toSet();

                final existingIndex = staticList.indexWhere((existing) {
                  final eMacs = existing.macAddress
                      .toUpperCase()
                      .replaceAll('-', ':')
                      .split(',')
                      .map((e) => e.trim());
                  return eMacs.any((m) => normMacs.contains(m));
                });

                if (existingIndex >= 0) {
                  staticList[existingIndex] = mapping;
                } else {
                  staticList.add(mapping);
                }

                for (final subMac in normMacs) {
                  uciMacs.add(subMac);
                }
              }
            }
          }
        }

        if (rawValues is Map) {
          rawValues.forEach((key, val) => processHostItem(val));
        } else if (rawValues is List) {
          for (final val in rawValues) {
            processHostItem(val);
          }
        }
      }

      // Merge/update static host mappings from hostHints only if not deleted in UCI
      if (hostHints is Map) {
        hostHints.forEach((macKey, hintVal) {
          if (hintVal is Map) {
            final isStatic =
                hintVal['isStaticLease'] == true ||
                hintVal['staticLeaseIp'] != null;
            if (isStatic) {
              final normMac = macKey.toString().toUpperCase().replaceAll(
                '-',
                ':',
              );
              if (uciDhcp != null &&
                  uciMacs.isNotEmpty &&
                  !uciMacs.contains(normMac)) {
                // Was removed from UCI config, don't re-add from stale hostHints
                return;
              }
              final ipList = hintVal['ipaddrs'];
              final ip = (ipList is List && ipList.isNotEmpty)
                  ? ipList.first.toString()
                  : (hintVal['staticLeaseIp']?.toString() ??
                        hintVal['ip']?.toString() ??
                        '');
              final name =
                  hintVal['staticLeaseName']?.toString() ??
                  hintVal['name']?.toString() ??
                  '';
              final lt =
                  hintVal['leasetime']?.toString() ??
                  hintVal['staticLeaseTime']?.toString() ??
                  '';

              final existingIndex = staticList.indexWhere((s) {
                final sMacs = s.macAddress
                    .toUpperCase()
                    .replaceAll('-', ':')
                    .split(',')
                    .map((e) => e.trim());
                return sMacs.contains(normMac);
              });

              if (existingIndex >= 0) {
                final existing = staticList[existingIndex];
                staticList[existingIndex] = DhcpStaticMapping(
                  hostname: name.isNotEmpty ? name : existing.hostname,
                  ipAddress: ip.isNotEmpty ? ip : existing.ipAddress,
                  macAddress: existing.macAddress,
                  leaseTime: lt.isNotEmpty ? lt : existing.leaseTime,
                );
              } else if (normMac.isNotEmpty &&
                  ip.isNotEmpty &&
                  isValidIPv4(ip) &&
                  isValidMac(normMac)) {
                staticList.add(
                  DhcpStaticMapping(
                    hostname: name.isNotEmpty ? name : 'Static Client',
                    ipAddress: ip,
                    macAddress: normMac,
                    leaseTime: lt,
                  ),
                );
              }
            }
          }
        });
      }
    }

    // Parse Subnets & DHCP Pools from Network & DHCP UCI config
    final subnetsList = <SubnetInfo>[];
    final dhcpPoolMap = <String, Map<String, int>>{};

    if (data != null) {
      final rawUciDhcp = data['uciDhcpConfig'] ?? data['dhcp'];
      final rawUciNetwork = data['uciNetworkConfig'] ?? data['network'];

      if (rawUciDhcp is Map) {
        final rawValues = rawUciDhcp['values'] ?? rawUciDhcp;
        void inspectDhcpSec(dynamic valMap) {
          if (valMap is Map) {
            final type =
                valMap['.type']?.toString() ?? valMap['type']?.toString();
            if (type == 'dhcp') {
              final ifc =
                  valMap['interface']?.toString() ??
                  valMap['.name']?.toString() ??
                  '';
              final start = int.tryParse(valMap['start']?.toString() ?? '');
              final limit = int.tryParse(valMap['limit']?.toString() ?? '');
              if (ifc.isNotEmpty && start != null && limit != null) {
                dhcpPoolMap[ifc] = {'start': start, 'limit': limit};
              }
            }
          }
        }

        if (rawValues is Map) {
          rawValues.values.forEach(inspectDhcpSec);
        } else if (rawValues is List) {
          rawValues.forEach(inspectDhcpSec);
        }
      }

      if (rawUciNetwork is Map) {
        final rawValues = rawUciNetwork['values'] ?? rawUciNetwork;
        void inspectNetSec(dynamic key, dynamic valMap) {
          if (valMap is Map) {
            final type =
                valMap['.type']?.toString() ?? valMap['type']?.toString();
            if (type == 'interface') {
              final ifcName =
                  valMap['.name']?.toString() ?? key?.toString() ?? '';
              var ipaddr = valMap['ipaddr']?.toString() ?? '';
              if (ipaddr.contains('/')) {
                ipaddr = ipaddr.split('/').first;
              }
              final netmask = valMap['netmask']?.toString() ?? '255.255.255.0';

              if (ipaddr.isNotEmpty &&
                  ipaddr != '127.0.0.1' &&
                  !ipaddr.startsWith('169.254')) {
                final poolInfo = dhcpPoolMap[ifcName];
                subnetsList.add(
                  SubnetInfo(
                    interfaceName: ifcName,
                    gatewayIp: ipaddr,
                    netmask: netmask,
                    poolStart: poolInfo?['start'],
                    poolLimit: poolInfo?['limit'],
                  ),
                );
              }
            }
          }
        }

        if (rawValues is Map) {
          rawValues.forEach(inspectNetSec);
        } else if (rawValues is List) {
          for (var item in rawValues) {
            inspectNetSec(null, item);
          }
        }
      }
    }

    // Dynamic subnet inference for any active lease or static mapping IP addresses
    final candidateIps = <String>[];
    for (final lease in leaseList) {
      if (isValidIPv4(lease.ipAddress)) candidateIps.add(lease.ipAddress);
    }
    for (final mapping in staticList) {
      if (isValidIPv4(mapping.ipAddress)) candidateIps.add(mapping.ipAddress);
    }

    for (final ip in candidateIps) {
      if (!subnetsList.any((s) => s.containsIp(ip))) {
        final parts = ip.split('.');
        final gwIp = '${parts[0]}.${parts[1]}.${parts[2]}.1';
        subnetsList.add(
          SubnetInfo(
            interfaceName: 'lan',
            gatewayIp: gwIp,
            netmask: '255.255.255.0',
            poolStart: 100,
            poolLimit: 150,
          ),
        );
      }
    }

    if (subnetsList.isEmpty) {
      subnetsList.add(
        const SubnetInfo(
          interfaceName: 'lan',
          gatewayIp: '192.168.1.1',
          netmask: '255.255.255.0',
          poolStart: 100,
          poolLimit: 150,
        ),
      );
    }

    // Cross-reference active leases with static host entries to accurately reflect static status
    final staticMacSet = <String>{};
    final staticMacToMapping = <String, DhcpStaticMapping>{};
    for (final s in staticList) {
      for (final m
          in s.macAddress.toUpperCase().replaceAll('-', ':').split(',')) {
        final trimmed = m.trim();
        if (trimmed.isNotEmpty) {
          staticMacSet.add(trimmed);
          staticMacToMapping[trimmed] = s;
        }
      }
    }
    for (final m in uciMacs) {
      staticMacSet.add(m.toUpperCase().replaceAll('-', ':'));
    }

    final finalLeaseList = <DhcpLease>[];
    for (final lease in leaseList) {
      final normMac = lease.macAddress.toUpperCase().replaceAll('-', ':');
      final staticMapping = staticMacToMapping[normMac];
      final isStatic =
          staticMacSet.contains(normMac) ||
          (hostHints is Map &&
              hostHints[normMac] is Map &&
              (hostHints[normMac]['isStaticLease'] == true ||
                  hostHints[normMac]['staticLeaseIp'] != null));

      if (isStatic) {
        final sLt = staticMapping?.leaseTime ?? '';
        final sName =
            (staticMapping != null &&
                staticMapping.hostname.isNotEmpty &&
                staticMapping.hostname != 'Unnamed Host' &&
                staticMapping.hostname != 'Static Client')
            ? staticMapping.hostname
            : lease.hostname;
        final sIp =
            (staticMapping != null &&
                staticMapping.ipAddress.isNotEmpty &&
                staticMapping.ipAddress != 'N/A')
            ? staticMapping.ipAddress
            : lease.ipAddress;

        finalLeaseList.add(
          DhcpLease(
            hostname: sName,
            ipAddress: sIp,
            ip6Address: lease.ip6Address,
            macAddress: lease.macAddress,
            duid: lease.duid,
            expirySeconds: lease.expirySeconds,
            isStatic: true,
            staticLeaseTime: sLt,
          ),
        );
      } else {
        final forcePurged =
            data?['forcePurged'] == true ||
            (data?['forcePurgedAt'] != null && data!['forcePurgedAt'] > 0);
        final isOffline =
            offlineMacSet.contains(normMac) && !onlineMacSet.contains(normMac);
        final isDisconnectedGhostLease =
            !onlineMacSet.contains(normMac) && lease.expirySeconds <= 0;

        if (forcePurged || isOffline || isDisconnectedGhostLease) {
          continue;
        }
        finalLeaseList.add(lease);
      }
    }

    // Default mock data only if in Reviewer Mode
    if (isReviewerMode) {
      if (finalLeaseList.isEmpty) {
        finalLeaseList.addAll([
          const DhcpLease(
            hostname: 'Android-Phone',
            ipAddress: '192.168.1.105',
            macAddress: 'DC:F5:05:12:34:56',
            expirySeconds: 38400,
          ),
          const DhcpLease(
            hostname: 'Linux-Workstation',
            ipAddress: '192.168.1.110',
            macAddress: '48:21:0B:78:90:AB',
            expirySeconds: 41200,
          ),
          const DhcpLease(
            hostname: 'Smart-TV',
            ipAddress: '192.168.1.115',
            macAddress: '70:B3:D5:CD:EF:01',
            expirySeconds: 21600,
          ),
          const DhcpLease(
            hostname: 'IPv6-Gateway-Node',
            ipAddress: '2405:201:12:3456::88',
            ip6Address: '2405:201:12:3456::88',
            macAddress: 'DUID: 0001000129A1B2C3',
            expirySeconds: 28800,
          ),
        ]);
      }
      if (dhcp6List.isEmpty) {
        dhcp6List.addAll([
          const Dhcp6Lease(
            hostname: 'MacBook-Pro-M2',
            ip6Address: '2405:201:12:3456::102',
            ipv6Addresses: ['2405:201:12:3456::102', 'fe80::1a2b:3c4d:5e6f'],
            macAddress: 'A4:83:E7:12:34:56',
            duid: '0001000129A1B2C3D4E5F6789A0B',
            expirySeconds: 43200,
          ),
          const Dhcp6Lease(
            hostname: 'IPv6-IoT-Gateway',
            ip6Address: '2405:201:12:3456::188',
            ipv6Addresses: ['2405:201:12:3456::188'],
            macAddress: 'DC:F5:05:99:88:77',
            duid: '0004A1B2C3D4E5F6789A',
            expirySeconds: 28800,
          ),
        ]);
      }
      if (staticList.isEmpty) {
        staticList.addAll([
          const DhcpStaticMapping(
            hostname: 'Home-NAS',
            ipAddress: '192.168.1.200',
            macAddress: '00:11:22:33:44:55',
            leaseTime: '12h',
          ),
          const DhcpStaticMapping(
            hostname: 'Printer-Office',
            ipAddress: '192.168.1.201',
            macAddress: '66:77:88:99:AA:BB',
            leaseTime: '24h',
          ),
        ]);
      }
    }

    return DhcpDnsOverview(
      dnsConfig: DnsmasqConfig.fromJson(dnsmasqRaw),
      activeLeases: finalLeaseList,
      activeDhcp6Leases: dhcp6List,
      staticMappings: staticList,
      configuredSubnets: subnetsList,
    );
  }
}
