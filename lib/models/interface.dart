// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class NetworkInterface {
  final String name;
  final bool isUp;
  final String protocol;
  final int uptime;
  final String device;
  final String? ipAddress;
  final String? netmask;
  final String? gateway;
  final List<String> dnsServers;
  final Map<String, dynamic> stats;
  final List<String>? ipv6Addresses;

  NetworkInterface({
    required this.name,
    required this.isUp,
    required this.protocol,
    required this.uptime,
    required this.device,
    this.ipAddress,
    this.netmask,
    this.gateway,
    required this.dnsServers,
    required this.stats,
    this.ipv6Addresses,
  });

  factory NetworkInterface.fromJson(Map<String, dynamic> json) {
    // Defensive parsing for ipv4-address
    final ipv4List = json['ipv4-address'];
    Map<String, dynamic>? ipv4;
    if (ipv4List is List && ipv4List.isNotEmpty && ipv4List.first is Map) {
      ipv4 = ipv4List.first;
    }

    // Defensive parsing for route
    final routeList = json['route'];
    Map<String, dynamic>? route;
    if (routeList is List && routeList.isNotEmpty && routeList.first is Map) {
      route = routeList.first;
    }

    // Extract gateway, but ignore if it's 0.0.0.0 which is not a real gateway
    String? gatewayIp;
    if (route?['nexthop'] != null && route?['nexthop'] != '0.0.0.0') {
      gatewayIp = route?['nexthop'];
    }

    // Defensive parsing for dns-server
    final dnsList = json['dns-server'];
    List<String> dnsServers = [];
    if (dnsList is List) {
      dnsServers = dnsList.map((e) => e.toString()).toList();
    }

    // Defensive parsing for statistics
    final statsMap = json['stats'];
    Map<String, dynamic> stats = {};
    if (statsMap is Map) {
      stats = Map<String, dynamic>.from(statsMap);
    }

    // Defensive parsing for ipv6-address
    final ipv6List = json['ipv6-address'];
    List<String>? ipv6Addresses;
    if (ipv6List is List && ipv6List.isNotEmpty) {
      ipv6Addresses = ipv6List
          .whereType<Map>()
          .map((e) => e['address']?.toString())
          .where((e) => e != null && e.isNotEmpty)
          .cast<String>()
          .toList();
    }

    return NetworkInterface(
      name: json['interface'] ?? 'Unknown',
      isUp: json['up'] ?? false,
      protocol: json['proto'] ?? 'N/A',
      uptime: json['uptime'] ?? 0,
      // Use 'l3_device' as a fallback for 'device'
      device: json['device'] ?? json['l3_device'] ?? 'N/A',
      ipAddress: ipv4?['address'],
      // The mask can be an integer, so convert it to a string
      netmask: ipv4?['mask']?.toString(),
      gateway: gatewayIp,
      dnsServers: dnsServers,
      stats: stats,
      ipv6Addresses: ipv6Addresses,
    );
  }

  String get formattedUptime {
    if (uptime <= 0) return 'N/A';

    final duration = Duration(seconds: uptime);
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);

    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0 || parts.isEmpty) parts.add('${minutes}m');

    return parts.join(' ');
  }
}
