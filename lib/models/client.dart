// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

enum ClientCategoryFilter { all, wired, wireless, banned, dumbAp }

enum ConnectionType { wired, wireless, unknown }

/// Neighbor Unreachability Detection (NUD) state from the kernel's neighbor table.
/// Used for three-state wired client active status instead of binary on/off.
enum NeighborReachability {
  /// Confirmed active — kernel has verified reachability within reachable_time (~30s).
  /// Also covers DELAY and PROBE states (kernel is in the process of confirming).
  reachable,

  /// Probably active but idle — device was reachable but hasn't communicated recently.
  /// Entry persists until gc_stale_time, typically 60s.
  stale,

  /// Disconnected — ARP probe failed or entry absent from neighbor table entirely.
  failed,

  /// Unknown — fallback when `ip neigh` is unavailable and we're using /proc/net/arp
  /// which can't distinguish REACHABLE from STALE.
  unknown,
}

class Client {
  final String ipAddress;
  final String macAddress;
  final String hostname;
  final String? hostId;
  final int? leaseTime; // in seconds
  final String? vendor;
  final String? dnsName;
  final String? clientId;
  final int? activeTime; // in seconds
  final int? expiresAt; // timestamp in seconds
  final ConnectionType connectionType;
  final List<String>? ipv6Addresses;
  final String? ssid;
  final String? wirelessIface;
  final bool isConnected;
  final NeighborReachability neighState;
  final String? staticLeaseName;
  final bool isStaticLease;
  final String? staticLeaseTime;
  final bool isDumbApClient;
  final String? apName;

  Client({
    required this.ipAddress,
    required this.macAddress,
    required this.hostname,
    this.hostId,
    this.leaseTime,
    this.vendor,
    this.dnsName,
    this.clientId,
    this.activeTime,
    this.expiresAt,
    this.connectionType = ConnectionType.unknown,
    this.ipv6Addresses,
    this.ssid,
    this.wirelessIface,
    this.isConnected = true,
    this.neighState = NeighborReachability.unknown,
    this.staticLeaseName,
    this.isStaticLease = false,
    this.staticLeaseTime,
    this.isDumbApClient = false,
    this.apName,
  });

  // Helper function to determine connection type from interface parameters
  static ConnectionType _determineConnectionType(Map<String, dynamic> lease) {
    // Check for explicit wireless fields
    if (lease['signal'] != null ||
        lease['noise'] != null ||
        lease['ssid'] != null) {
      return ConnectionType.wireless;
    }

    final hostname = (lease['hostname'] ?? lease['name'] ?? '')
        .toString()
        .toLowerCase();
    final vendor = (lease['vendor'] ?? '').toString().toLowerCase();
    if (hostname.contains('iphone') ||
        hostname.contains('ipad') ||
        hostname.contains('galaxy') ||
        hostname.contains('android') ||
        hostname.contains('pixel') ||
        hostname.contains('phone') ||
        hostname.contains('tab') ||
        hostname.contains('mobile') ||
        hostname.contains('macbook') ||
        hostname.contains('firestick') ||
        hostname.contains('chromecast') ||
        hostname.contains('roku') ||
        hostname.contains('echo') ||
        hostname.contains('alexa') ||
        vendor.contains('apple') ||
        vendor.contains('samsung') ||
        vendor.contains('xiaomi') ||
        vendor.contains('oneplus') ||
        vendor.contains('oppo') ||
        vendor.contains('vivo') ||
        vendor.contains('realme') ||
        vendor.contains('huawei')) {
      return ConnectionType.wireless;
    }

    final ifname = (lease['ifname'] ?? lease['device'] ?? '')
        .toString()
        .toLowerCase();
    if (ifname.startsWith('wlan') ||
        ifname.startsWith('phy') ||
        ifname.startsWith('ra') ||
        ifname.startsWith('wifi') ||
        ifname.startsWith('ath')) {
      return ConnectionType.wireless;
    }

    if (ifname.startsWith('eth') || ifname.startsWith('lan1')) {
      return ConnectionType.wired;
    }

    // Default to unknown for bridge interfaces (e.g. br-lan) to defer to dynamic station/maclist/ethernet resolution
    return ConnectionType.unknown;
  }

  factory Client.fromLease(Map<String, dynamic> lease) {
    // Helper function to safely convert dynamic to String
    String? toStringValue(dynamic value) {
      return value?.toString();
    }

    // Helper function to safely convert dynamic to int
    int? toIntValue(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is double) return value.toInt();
      return null;
    }

    final expires = toIntValue(
      lease['expires'],
    ); // This is the remaining lease time in seconds
    final activetime = toIntValue(lease['activetime']);

    // 'expires' from the API is the time remaining on the lease in seconds.
    // We can use it directly. If it's not available, we can fall back to 'leasetime',
    // though 'expires' is more accurate for the remaining duration.
    final remainingLeaseTime = expires;

    // We can calculate the absolute expiration timestamp for display purposes if needed.
    int? expiresAtTimestamp;
    if (expires != null && expires > 0) {
      expiresAtTimestamp =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000) + expires;
    }

    List<String>? ipv6Addresses;
    if (lease['ipv6addrs'] != null && lease['ipv6addrs'] is List) {
      ipv6Addresses = (lease['ipv6addrs'] as List)
          .map((e) => e.toString())
          .toList();
    } else if (lease['ipv6addr'] != null) {
      // Some APIs may use a single string or a comma-separated string
      final v6 = lease['ipv6addr'];
      if (v6 is String) {
        ipv6Addresses = v6
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (v6 is List) {
        ipv6Addresses = v6.map((e) => e.toString()).toList();
      }
    }

    final rawName =
        toStringValue(lease['hostname']) ??
        toStringValue(lease['name']) ??
        toStringValue(lease['dnsname']);
    final parsedHostname =
        (rawName != null && rawName.trim().isNotEmpty && rawName.trim() != '*')
        ? rawName.trim()
        : 'Unknown';

    return Client(
      ipAddress: toStringValue(lease['ipaddr']) ?? 'N/A',
      macAddress: toStringValue(lease['macaddr']) ?? 'N/A',
      hostname: parsedHostname,
      hostId: toStringValue(lease['hostid']),
      leaseTime: remainingLeaseTime, // Use the 'expires' value directly
      vendor: toStringValue(lease['vendor']),
      dnsName: toStringValue(lease['dnsname']),
      clientId: toStringValue(lease['clientid']),
      activeTime: activetime,
      expiresAt: expiresAtTimestamp, // Store the calculated absolute timestamp
      connectionType: _determineConnectionType(lease),
      ipv6Addresses: ipv6Addresses,
      staticLeaseName: toStringValue(lease['staticLeaseName']),
      isStaticLease: lease['isStaticLease'] == true,
      staticLeaseTime: toStringValue(
        lease['staticLeaseTime'] ?? lease['leasetime'],
      ),
    );
  }

  /// Creates a Client from a wireless association MAC address (no DHCP data).
  /// Used as a fallback for AP-mode routers where DHCP is handled upstream.
  factory Client.fromWirelessStation(
    String macAddress, {
    String? ssid,
    String? wirelessIface,
    bool isDumbApClient = false,
    String? apName,
  }) {
    return Client(
      ipAddress: 'N/A',
      macAddress: macAddress,
      hostname: 'Unknown',
      connectionType: ConnectionType.wireless,
      neighState: NeighborReachability
          .reachable, // Wireless stations are confirmed live by association
      ssid: ssid,
      wirelessIface: wirelessIface,
      isDumbApClient: isDumbApClient,
      apName: apName,
    );
  }

  // Get formatted lease time (e.g., "2d 4h 30m" or "Static (Permanent)")
  String get formattedLeaseTime {
    if (isStatic) {
      final lt = staticLeaseTime?.trim();
      if (lt != null &&
          lt.isNotEmpty &&
          lt.toLowerCase() != 'infinite' &&
          lt.toLowerCase() != '0') {
        return 'Static ($lt)';
      }
      return 'Static (Permanent)';
    }
    if (leaseTime == null) return 'No active lease';
    if (leaseTime == 0) return 'Unlimited';
    if (leaseTime! < 0) return 'Expired';
    return Client.formatDuration(leaseTime!);
  }

  // Get formatted active time
  String get formattedActiveTime {
    if (activeTime == null) return 'N/A';
    return Client.formatDuration(activeTime!);
  }

  // Get formatted expiration timestamp
  String get formattedExpiresAt {
    if (expiresAt == null || expiresAt == 0) return 'N/A';
    final date = DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000);
    return '${date.toLocal()}';
  }

  // Static helper to format duration in seconds to a human-readable string
  static String formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0m';

    final days = totalSeconds ~/ (24 * 3600);
    totalSeconds %= (24 * 3600);
    final hours = totalSeconds ~/ 3600;
    totalSeconds %= 3600;
    final minutes = totalSeconds ~/ 60;

    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0 || parts.isEmpty) parts.add('${minutes}m');

    return parts.join(' ');
  }

  /// Cached normalized MAC address (uppercase with colons)
  late final String normalizedMac = macAddress
      .toUpperCase()
      .replaceAll('-', ':');

  /// Returns display name following OpenWrt client naming rules:
  /// 1. Client's Static Lease Name configured on router (highest priority).
  /// 2. Router-assigned hostname / dnsName if present and valid.
  /// 3. MAC address fallback.
  late final String displayName = _computeDisplayName();

  String _computeDisplayName() {
    final normMac = normalizedMac
        .split(':')
        .map((b) => b.length == 1 ? '0$b' : b)
        .join(':');
    String norm(String val) => val
        .toUpperCase()
        .replaceAll('-', ':')
        .split(':')
        .map((b) => b.length == 1 ? '0$b' : b)
        .join(':');

    if (staticLeaseName != null &&
        staticLeaseName!.trim().isNotEmpty &&
        staticLeaseName != 'Unknown' &&
        staticLeaseName != '*' &&
        norm(staticLeaseName!) != normMac) {
      return staticLeaseName!.trim();
    }
    if (hostname.isNotEmpty &&
        hostname != 'Unknown' &&
        hostname != '*' &&
        norm(hostname) != normMac) {
      return hostname;
    }
    if (dnsName != null &&
        dnsName!.isNotEmpty &&
        dnsName != 'Unknown' &&
        dnsName != '*' &&
        norm(dnsName!) != normMac) {
      return dnsName!;
    }
    return macAddress;
  }

  /// Whether this client is configured as a static lease in UCI dhcp
  bool get isStatic =>
      isStaticLease ||
      (staticLeaseName != null && staticLeaseName!.trim().isNotEmpty);

  Client copyWith({
    String? ipAddress,
    String? macAddress,
    String? hostname,
    String? hostId,
    int? leaseTime,
    String? vendor,
    String? dnsName,
    String? clientId,
    int? activeTime,
    int? expiresAt,
    ConnectionType? connectionType,
    List<String>? ipv6Addresses,
    String? ssid,
    String? wirelessIface,
    bool? isConnected,
    NeighborReachability? neighState,
    String? staticLeaseName,
    bool? isStaticLease,
    String? staticLeaseTime,
    bool? isDumbApClient,
    String? apName,
  }) {
    return Client(
      ipAddress: ipAddress ?? this.ipAddress,
      macAddress: macAddress ?? this.macAddress,
      hostname: hostname ?? this.hostname,
      hostId: hostId ?? this.hostId,
      leaseTime: leaseTime ?? this.leaseTime,
      vendor: vendor ?? this.vendor,
      dnsName: dnsName ?? this.dnsName,
      clientId: clientId ?? this.clientId,
      activeTime: activeTime ?? this.activeTime,
      expiresAt: expiresAt ?? this.expiresAt,
      connectionType: connectionType ?? this.connectionType,
      ipv6Addresses: ipv6Addresses ?? this.ipv6Addresses,
      ssid: ssid ?? this.ssid,
      wirelessIface: wirelessIface ?? this.wirelessIface,
      isConnected: isConnected ?? this.isConnected,
      neighState: neighState ?? this.neighState,
      staticLeaseName: staticLeaseName ?? this.staticLeaseName,
      isStaticLease: isStaticLease ?? this.isStaticLease,
      staticLeaseTime: staticLeaseTime ?? this.staticLeaseTime,
      isDumbApClient: isDumbApClient ?? this.isDumbApClient,
      apName: apName ?? this.apName,
    );
  }

  /// Merges DHCP leases and active wireless station MACs into a sorted list of Clients.
  static List<Client> buildMergedClientList(
    List<Map<String, dynamic>> dhcpLeases,
    Set<String> wirelessMacs, {
    bool isDumbAp = false,
    String? apName,
  }) {
    String norm(String m) => m
        .toUpperCase()
        .replaceAll('-', ':')
        .split(':')
        .map((b) => b.length == 1 ? '0$b' : b)
        .join(':');

    final normalizedWireless = wirelessMacs.map(norm).toSet();

    final clients = <String, Client>{};
    for (final lease in dhcpLeases) {
      final client = Client.fromLease(lease);
      final macNorm = norm(client.macAddress);
      final isWireless = normalizedWireless.contains(macNorm);
      clients[macNorm] = client.copyWith(
        connectionType: isWireless
            ? ConnectionType.wireless
            : ConnectionType.wired,
        isDumbApClient: isWireless && isDumbAp,
        apName: isWireless && isDumbAp ? apName : null,
      );
    }

    for (final mac in normalizedWireless) {
      if (!clients.containsKey(mac)) {
        clients[mac] = Client.fromWirelessStation(
          mac,
          isDumbApClient: isDumbAp,
          apName: apName,
        );
      }
    }

    final list = clients.values.toList();
    list.sort((a, b) {
      int typeOrder(ConnectionType t) {
        switch (t) {
          case ConnectionType.wireless:
            return 0;
          case ConnectionType.wired:
            return 1;
          default:
            return 2;
        }
      }

      final cmpType = typeOrder(
        a.connectionType,
      ).compareTo(typeOrder(b.connectionType));
      if (cmpType != 0) return cmpType;
      return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
    });
    return list;
  }
}
