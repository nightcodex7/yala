// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart'
    show
        kNeighborProbeInterval,
        kNeighborProbeMaxBatch,
        normalizeMac,
        selectNeighborProbeTargets;
import 'package:yet_another_luci_app/utils/logger.dart';

/// Encapsulates client list aggregation, neighbor table NUD active probing,
/// Layer-2 bridge FDB mapping, DHCP lease processing, and device classification.
///
/// Extracted from [AppState] to enforce single-responsibility.
class ClientController {
  ClientController({
    required IApiService? Function() apiServiceRef,
    required IAuthService? Function() authServiceRef,
    required RouterService? Function() routerServiceRef,
    required bool Function() reviewerModeRef,
    Map<String, dynamic>? Function()? dashboardDataRef,
    required Future<String?> Function(String command, List<String> args)
    executeRouterCommandOutput,
    required Map<String, dynamic> Function(Map<String, dynamic> rawDhcpData)
    processDhcpLeases,
  }) : _apiServiceRef = apiServiceRef,
       _authServiceRef = authServiceRef,
       _routerServiceRef = routerServiceRef,
       _reviewerModeRef = reviewerModeRef,
       _dashboardDataRef = dashboardDataRef,
       _executeRouterCommandOutput = executeRouterCommandOutput,
       _processDhcpLeases = processDhcpLeases;

  final IApiService? Function() _apiServiceRef;
  final IAuthService? Function() _authServiceRef;
  final RouterService? Function() _routerServiceRef;
  final bool Function() _reviewerModeRef;
  final Map<String, dynamic>? Function()? _dashboardDataRef;
  final Future<String?> Function(String command, List<String> args)
  _executeRouterCommandOutput;
  final Map<String, dynamic> Function(Map<String, dynamic> rawDhcpData)
  _processDhcpLeases;

  final Set<String> _knownWirelessMacs = {};
  final Map<String, DateTime> _recentWiredActiveTime = {};
  DateTime? _lastNeighborProbeTime;
  List<Client>? lastFetchedClients;
  bool _isFetchingClients = false;

  Set<String> get knownWirelessMacs => _knownWirelessMacs;
  bool get isFetchingClients => _isFetchingClients;
  bool get hasFetchedClients => lastFetchedClients != null;

  /// Resets client state and caches (e.g. on router profile switch or logout).
  void resetState() {
    _knownWirelessMacs.clear();
    _recentWiredActiveTime.clear();
    _lastNeighborProbeTime = null;
    lastFetchedClients = null;
    _isFetchingClients = false;
  }

  /// Regex to identify access points, dumb APs, bridges, repeaters, or extenders
  /// with proper word boundaries to prevent false positives (e.g. "Apple", "Laptop", "Apartment").
  static final RegExp apIdentifierRegex = RegExp(
    r'(^|[\s_\-\.\(\)\[\]\/])(ap|access[-_\s]*point|dumb[-_\s]*ap|bridge|repeater|extender)($|[\s_\-\.\(\)\[\]\/])',
    caseSensitive: false,
  );

  /// Checks whether a name or hostname explicitly indicates an Access Point or Bridge.
  static bool isDumbApName(String? name) {
    if (name == null || name.trim().isEmpty) return false;
    return apIdentifierRegex.hasMatch(name.trim());
  }

  /// Returns whether a Dumb AP router is present in configuration or detected
  bool get hasDumbAp {
    // 1. If multiple routers are configured in the app, secondary AP management is active
    final routers = _routerService?.routers ?? [];
    if (routers.length > 1) {
      return true;
    }

    // 2. Any currently fetched client is tagged as connected via a Dumb AP
    if (lastFetchedClients != null &&
        lastFetchedClients!.any((c) => c.isDumbApClient)) {
      return true;
    }

    // 3. Check if the currently selected router is identified as an AP
    final selected = _routerService?.selectedRouter;
    if (selected != null &&
        (isDumbApName(selected.name) ||
            isDumbApName(selected.lastKnownHostname))) {
      return true;
    }

    // 4. Check if any router in the configured routers list is identified as an AP
    for (final r in routers) {
      if (isDumbApName(r.name) || isDumbApName(r.lastKnownHostname)) {
        return true;
      }
    }

    return false;
  }

  IApiService? get _apiService => _apiServiceRef();
  IAuthService? get _authService => _authServiceRef();
  RouterService? get _routerService => _routerServiceRef();
  bool get _isReviewerMode => _reviewerModeRef();

  /// Aggregates DHCP leases across all configured routers and classifies clients
  /// as wireless if their MAC appears in any router's associated stations list.
  /// Also tags clients associated with secondary Dumb APs.
  Future<List<Client>> fetchAggregatedClients() async {
    _isFetchingClients = true;
    try {
      final clientsMap = <String, Client>{};
      final routers = _routerService?.routers ?? [];
      if (routers.isEmpty) {
        return lastFetchedClients ?? [];
      }
      final routerClientsList = await Future.wait(
        routers.map(
          (router) => _fetchClientsForRouter(router).catchError((e, stack) {
            Logger.exception(
              'Failed to fetch clients for router ${router.ipAddress}',
              e,
              stack,
            );
            return <Client>[];
          }),
        ),
      );
      for (final routerClients in routerClientsList) {
        for (final c in routerClients) {
          final macNorm = c.macAddress.toUpperCase().replaceAll('-', ':');
          if (!clientsMap.containsKey(macNorm)) {
            clientsMap[macNorm] = c;
          } else {
            final existing = clientsMap[macNorm]!;
            final isDumb = existing.isDumbApClient || c.isDumbApClient;
            final apName = c.isDumbApClient
                ? (c.apName ?? existing.apName)
                : (existing.apName ?? c.apName);
            final preferredHostname =
                (existing.hostname != 'Unknown' &&
                    existing.hostname != existing.macAddress)
                ? existing.hostname
                : c.hostname;
            final preferredIp =
                (existing.ipAddress != 'N/A' && existing.ipAddress.isNotEmpty)
                ? existing.ipAddress
                : c.ipAddress;
            final preferredConnType =
                (existing.connectionType == ConnectionType.wireless ||
                    c.connectionType == ConnectionType.wireless)
                ? ConnectionType.wireless
                : existing.connectionType;
            final preferredSsid = existing.ssid ?? c.ssid;
            final preferredIface = existing.wirelessIface ?? c.wirelessIface;
            final staticName = existing.staticLeaseName ?? c.staticLeaseName;
            final isStatic = existing.isStaticLease || c.isStaticLease;
            final ipv6Addrs = existing.ipv6Addresses ?? c.ipv6Addresses;
            final vendor = existing.vendor ?? c.vendor;

            clientsMap[macNorm] = existing.copyWith(
              hostname: preferredHostname,
              ipAddress: preferredIp,
              connectionType: preferredConnType,
              ssid: preferredSsid,
              wirelessIface: preferredIface,
              isConnected: existing.isConnected || c.isConnected,
              isDumbApClient: isDumb,
              apName: apName,
              staticLeaseName: staticName,
              isStaticLease: isStatic,
              ipv6Addresses: ipv6Addrs,
              vendor: vendor,
            );
          }
        }
      }
      final list = clientsMap.values.toList();
      list.sort((a, b) {
        if (a.isConnected != b.isConnected) {
          return a.isConnected ? -1 : 1;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
      lastFetchedClients = list;
      return list;
    } catch (e, stack) {
      Logger.exception('Failed to aggregate clients', e, stack);
      return lastFetchedClients ?? [];
    } finally {
      _isFetchingClients = false;
    }
  }

  /// Returns clients for the currently selected router only
  Future<List<Client>> fetchClientsForSelectedRouter() async {
    _isFetchingClients = true;
    try {
      if (_isReviewerMode) {
        final stationsMap = await _apiService!.fetchAssociatedStations();
        final macToSsidMap = <String, String>{};
        final macToIfaceMap = <String, String>{};
        final macs = <String>{};
        stationsMap.forEach((key, stations) {
          String iface = key;
          String? ssid = key;
          if (key.contains('|')) {
            final parts = key.split('|');
            iface = parts[0];
            ssid = parts.sublist(1).join('|');
          }
          for (final m in stations) {
            final macLower = m.toLowerCase();
            macs.add(macLower);
            final macNorm = m.toUpperCase().replaceAll('-', ':');
            macToIfaceMap[macNorm] = iface;
            if (ssid.isNotEmpty) {
              macToSsidMap[macNorm] = ssid;
            }
          }
        });
        final result = await _apiService!.callSimple(
          'luci-rpc',
          'getDHCPLeases',
          {},
        );
        final leases = <Map<String, dynamic>>[];
        if (result is List && result.length > 1 && result[0] == 0) {
          final data = result[1] as Map<String, dynamic>;
          final processed = data['dhcp_leases'] != null
              ? data
              : _processDhcpLeases(data);
          if (processed['dhcp_leases'] is List) {
            leases.addAll(
              (processed['dhcp_leases'] as List<dynamic>)
                  .cast<Map<String, dynamic>>(),
            );
          }
        }
        final hostHints = await _apiService!.fetchHostHintsWithContext(
          ipAddress: '192.168.1.1',
          sysauth: 'mock',
          useHttps: false,
        );
        final normalizedMacs = macs
            .map((m) => m.toUpperCase().replaceAll('-', ':'))
            .toSet();
        final clientMap = <String, Client>{};
        for (final l in leases) {
          final c = Client.fromLease(l);
          final macNorm = c.macAddress.toUpperCase().replaceAll('-', ':');
          final isWireless = normalizedMacs.contains(macNorm);
          final staticName = hostHints[macNorm]?['staticLeaseName']?.toString();
          final isStaticEntry = hostHints[macNorm]?['isStaticLease'] == true;
          final hintV6 = hostHints[macNorm]?['ip6addrs'] as List?;
          final v6List = (hintV6 != null && hintV6.isNotEmpty)
              ? hintV6.map((e) => e.toString()).toList()
              : c.ipv6Addresses;
          final vendorName =
              hostHints[macNorm]?['vendor']?.toString() ?? c.vendor;

          clientMap[macNorm] = c.copyWith(
            connectionType: isWireless
                ? ConnectionType.wireless
                : ConnectionType.wired,
            ssid: macToSsidMap[macNorm],
            wirelessIface: macToIfaceMap[macNorm],
            staticLeaseName: staticName,
            isStaticLease: isStaticEntry,
            ipv6Addresses: v6List,
            vendor: vendorName,
          );
        }
        for (final mac in normalizedMacs) {
          if (!clientMap.containsKey(mac)) {
            final staticName = hostHints[mac]?['staticLeaseName']?.toString();
            final isStaticEntry = hostHints[mac]?['isStaticLease'] == true;
            final hintV6 = hostHints[mac]?['ip6addrs'] as List?;
            final v6List = (hintV6 != null && hintV6.isNotEmpty)
                ? hintV6.map((e) => e.toString()).toList()
                : null;
            final vendorName = hostHints[mac]?['vendor']?.toString();
            clientMap[mac] =
                Client.fromWirelessStation(
                  mac,
                  ssid: macToSsidMap[mac],
                  wirelessIface: macToIfaceMap[mac],
                ).copyWith(
                  staticLeaseName: staticName,
                  isStaticLease: isStaticEntry,
                  ipv6Addresses: v6List,
                  vendor: vendorName,
                );
          }
        }
        hostHints.forEach((mac, info) {
          final macN = mac.toUpperCase().replaceAll('-', ':');
          if (!clientMap.containsKey(macN)) {
            final hintName = info['name']?.toString();
            final staticName = info['staticLeaseName']?.toString();
            final isStaticEntry = info['isStaticLease'] == true;
            final ipaddrs = info['ipaddrs'] as List?;
            final ip = (ipaddrs != null && ipaddrs.isNotEmpty)
                ? ipaddrs.first.toString()
                : 'N/A';
            final name =
                (hintName != null && hintName.isNotEmpty && hintName != '*')
                ? hintName
                : macN;
            final isWireless = normalizedMacs.contains(macN);
            final hintV6 = info['ip6addrs'] as List?;
            final v6List = (hintV6 != null && hintV6.isNotEmpty)
                ? hintV6.map((e) => e.toString()).toList()
                : null;
            final vendorName = info['vendor']?.toString();

            clientMap[macN] = Client(
              ipAddress: ip,
              macAddress: macN,
              hostname: name,
              connectionType: isWireless
                  ? ConnectionType.wireless
                  : ConnectionType.wired,
              ssid: macToSsidMap[macN],
              wirelessIface: macToIfaceMap[macN],
              staticLeaseName: staticName,
              isStaticLease: isStaticEntry,
              ipv6Addresses: v6List,
              vendor: vendorName,
            );
          }
        });
        final reviewerClients = clientMap.values.toList();
        reviewerClients.sort((a, b) {
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
        lastFetchedClients = reviewerClients;
        return reviewerClients;
      }

      if (_routerService?.selectedRouter == null ||
          _authService?.sysauth == null) {
        return lastFetchedClients ?? [];
      }
      final result = await _fetchClientsForRouter(
        _routerService!.selectedRouter!,
      );
      lastFetchedClients = result;
      return result;
    } catch (e, stack) {
      Logger.exception('Failed to fetch clients for selected router', e, stack);
      return lastFetchedClients ?? [];
    } finally {
      _isFetchingClients = false;
    }
  }

  Future<List<Client>> _fetchClientsForRouter(model.Router router) async {
    String? routerSysauth;
    bool actualUseHttps = router.useHttps;
    if (_isReviewerMode) {
      routerSysauth = 'mock';
    } else if (router.id == _routerService?.selectedRouter?.id) {
      routerSysauth = _authService?.sysauth;
      actualUseHttps = _authService?.useHttps ?? router.useHttps;
    } else {
      if (_apiService != null) {
        try {
          final authRes = await _apiService!.authenticate(
            router.ipAddress,
            router.username,
            router.password,
            router.useHttps,
          );
          if (authRes.isSuccess && authRes.token != null) {
            routerSysauth = authRes.token;
            actualUseHttps = authRes.actualUseHttps;
          }
        } catch (_) {}
      }
    }

    if ((routerSysauth == null || routerSysauth.isEmpty) && !_isReviewerMode) {
      return [];
    }
    final activeSysauth = routerSysauth ?? 'mock';

    try {
      String normMac(String mac) => normalizeMac(mac);

      // 1. Fetch live associated wireless stations
      final stationsMap = await _apiService!
          .fetchAllAssociatedWirelessMacsWithContext(
            ipAddress: router.ipAddress,
            sysauth: activeSysauth,
            useHttps: actualUseHttps,
          );
      final macToSsidMap = <String, String>{};
      final macToIfaceMap = <String, String>{};
      final wireless = <String>{};
      stationsMap.forEach((key, s) {
        String iface = key;
        String? ssid = key;
        if (key.contains('|')) {
          final parts = key.split('|');
          iface = parts[0];
          ssid = parts.sublist(1).join('|');
        }
        for (final m in s) {
          final n = normMac(m);
          wireless.add(n);
          macToIfaceMap[n] = iface;
          if (ssid.isNotEmpty) {
            macToSsidMap[n] = ssid;
          }
        }
      });

      // Fallback: Shell station dump if station map is empty
      if (wireless.isEmpty) {
        final iwDevOut = await _executeRouterCommandOutput('iw', ['dev']);
        final ifaces = <String>[];
        if (iwDevOut != null && iwDevOut.isNotEmpty) {
          for (final line in iwDevOut.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.startsWith('Interface ')) {
              ifaces.add(trimmed.substring(10).trim());
            }
          }
        }
        if (ifaces.isEmpty) {
          ifaces.addAll([
            'wlan0',
            'wlan1',
            'phy0-ap0',
            'phy1-ap0',
            'phy2-ap0',
            'ra0',
          ]);
        }
        for (final iface in ifaces) {
          final iwDump =
              await _executeRouterCommandOutput('iw', [
                'dev',
                iface,
                'station',
                'dump',
              ]) ??
              await _executeRouterCommandOutput('iwinfo', [iface, 'assoclist']);
          if (iwDump != null && iwDump.isNotEmpty) {
            final macRegex = RegExp(r'([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})');
            for (final match in macRegex.allMatches(iwDump)) {
              final m = match.group(0);
              if (m != null) {
                wireless.add(normMac(m));
              }
            }
          }
        }
      }
      final normalizedWireless = wireless.map(normMac).toSet();
      _knownWirelessMacs.addAll(normalizedWireless);

      // 2. Fetch getDHCPLeases from luci-rpc
      final callRes = await _apiService!.call(
        router.ipAddress,
        activeSysauth,
        router.useHttps,
        object: 'luci-rpc',
        method: 'getDHCPLeases',
        params: {},
      );
      final dhcp4Leases = <Map<String, dynamic>>[];
      final dhcp6Leases = <Map<String, dynamic>>[];
      if (callRes is List && callRes.length > 1 && callRes[0] == 0) {
        final data = callRes[1] as Map<String, dynamic>;
        if (data['dhcp_leases'] is List) {
          dhcp4Leases.addAll(
            (data['dhcp_leases'] as List).cast<Map<String, dynamic>>(),
          );
        }
        if (data['dhcp6_leases'] is List) {
          dhcp6Leases.addAll(
            (data['dhcp6_leases'] as List).cast<Map<String, dynamic>>(),
          );
        }
      }

      if (dhcp4Leases.isEmpty) {
        final rawLeaseStr =
            await _executeRouterCommandOutput('cat', ['/tmp/dhcp.leases']) ??
            await _executeRouterCommandOutput('cat', ['/var/dhcp.leases']) ??
            await _executeRouterCommandOutput('cat', ['/tmp/dnsmasq.leases']);
        if (rawLeaseStr != null && rawLeaseStr.isNotEmpty) {
          final processed = _processDhcpLeases({'data': rawLeaseStr});
          if (processed['dhcp_leases'] is List) {
            dhcp4Leases.addAll(
              (processed['dhcp_leases'] as List).cast<Map<String, dynamic>>(),
            );
          }
        }
      }

      final otherRouters = (_routerService?.routers ?? [])
          .where((r) => r.ipAddress != router.ipAddress)
          .toList();

      final hasNoDhcp = dhcp4Leases.isEmpty && dhcp6Leases.isEmpty;
      final hasApName =
          isDumbApName(router.name) || isDumbApName(router.lastKnownHostname);

      final isRouterDumbAp =
          (hasNoDhcp && otherRouters.isNotEmpty) ||
          (hasNoDhcp && normalizedWireless.isNotEmpty) ||
          (hasNoDhcp && hasApName) ||
          (hasApName && otherRouters.isNotEmpty) ||
          (otherRouters.isNotEmpty &&
              router.id != _routerService?.selectedRouter?.id);

      List<Map<String, dynamic>> parseIpNeighOutput(String raw) {
        final list = <Map<String, dynamic>>[];
        for (final line in raw.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length < 4) continue;
          final ip = parts[0];
          final dev = parts.length > 2 ? parts[2] : '';
          String? mac;
          String nudState = parts.last.toUpperCase();
          final llIdx = parts.indexOf('lladdr');
          if (llIdx >= 0 && llIdx + 1 < parts.length) {
            mac = parts[llIdx + 1];
          }
          if (mac == null || !mac.contains(':')) continue;
          if (mac == '00:00:00:00:00:00') continue;
          list.add({
            'ipaddr': ip,
            'macaddr': normMac(mac),
            'device': dev,
            'nud_state': nudState,
          });
        }
        return list;
      }

      // 3. Fetch neighbor table via `ip neigh show`
      final neighClients = <Map<String, dynamic>>[];
      bool usedIpNeigh = false;
      try {
        final neighV4Str =
            await _executeRouterCommandOutput('/sbin/ip', [
              '-4',
              'neigh',
              'show',
            ]) ??
            await _executeRouterCommandOutput('ip', ['-4', 'neigh', 'show']) ??
            await _executeRouterCommandOutput('ip', ['neigh', 'show']);
        final neighV6Str =
            await _executeRouterCommandOutput('/sbin/ip', [
              '-6',
              'neigh',
              'show',
            ]) ??
            await _executeRouterCommandOutput('ip', ['-6', 'neigh', 'show']);

        final combined = [
          if (neighV4Str != null && neighV4Str.trim().isNotEmpty) neighV4Str,
          if (neighV6Str != null && neighV6Str.trim().isNotEmpty) neighV6Str,
        ].join('\n');

        if (combined.trim().isNotEmpty) {
          usedIpNeigh = true;
          neighClients.addAll(parseIpNeighOutput(combined));
        }
      } catch (_) {}

      // L2 Bridge FDB MAC learning
      final fdbMacs = <String>{};
      try {
        final fdbStr =
            await _executeRouterCommandOutput('/sbin/bridge', [
              'fdb',
              'show',
            ]) ??
            await _executeRouterCommandOutput('bridge', ['fdb', 'show']);
        if (fdbStr != null && fdbStr.trim().isNotEmpty) {
          final macRegex = RegExp(r'([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})');
          for (final line in fdbStr.split('\n')) {
            final lower = line.toLowerCase();
            if (lower.contains('self') || lower.contains('permanent')) continue;
            final match = macRegex.firstMatch(line);
            if (match != null) {
              final m = match.group(0);
              if (m != null) fdbMacs.add(normMac(m));
            }
          }
        }
      } catch (_) {}

      // Active Probing for Absent/Incomplete Wired Clients
      if (usedIpNeigh) {
        try {
          final probeIps = selectNeighborProbeTargets(
            dhcp4Leases,
            normalizedWireless,
            neighClients,
            routerIp: router.ipAddress,
            maxBatch: kNeighborProbeMaxBatch,
          );

          final now = DateTime.now();
          final shouldProbe =
              _lastNeighborProbeTime == null ||
              now.difference(_lastNeighborProbeTime!) >= kNeighborProbeInterval;

          if (shouldProbe && probeIps.isNotEmpty) {
            final cmd =
                'for ip in ${probeIps.join(' ')}; do ping -c 1 -W 1 \$ip >/dev/null 2>&1 & done; wait; ip neigh show';
            final probedNeighStr = await _executeRouterCommandOutput('sh', [
              '-c',
              cmd,
            ]);
            if (probedNeighStr != null && probedNeighStr.trim().isNotEmpty) {
              neighClients.clear();
              neighClients.addAll(parseIpNeighOutput(probedNeighStr));
            }
            _lastNeighborProbeTime = now;
          }
        } catch (e) {
          Logger.warning('Active neighbor probing failed: $e');
        }
      }

      // Fallback: /proc/net/arp
      if (!usedIpNeigh || neighClients.isEmpty) {
        try {
          final arpStr = await _executeRouterCommandOutput('cat', [
            '/proc/net/arp',
          ]);
          if (arpStr != null && arpStr.isNotEmpty) {
            for (final line in arpStr.split('\n')) {
              final trimmed = line.trim();
              if (trimmed.isEmpty ||
                  trimmed.startsWith('IP address') ||
                  trimmed.startsWith('IP')) {
                continue;
              }
              final parts = trimmed.split(RegExp(r'\s+'));
              if (parts.length >= 4) {
                final ip = parts[0];
                final flags = parts[2];
                final mac = parts[3];
                final dev = parts.length >= 6 ? parts[5] : '';
                if (mac != '00:00:00:00:00:00' &&
                    mac.contains(':') &&
                    flags != '0x0') {
                  neighClients.add({
                    'ipaddr': ip,
                    'macaddr': normMac(mac),
                    'device': dev,
                    'nud_state': 'UNKNOWN',
                  });
                }
              }
            }
          }
        } catch (_) {}
      }

      // 4. Fetch Host Hints dictionary
      final hostHints = await _apiService!.fetchHostHintsWithContext(
        ipAddress: router.ipAddress,
        sysauth: activeSysauth,
        useHttps: router.useHttps,
      );

      final routerIps = <String>{router.ipAddress, '127.0.0.1', '0.0.0.0'};
      final routerMacs = <String>{};

      try {
        final devRes = await _apiService!.call(
          router.ipAddress,
          activeSysauth,
          router.useHttps,
          object: 'network.device',
          method: 'status',
          params: {},
        );
        if (devRes is List &&
            devRes.length > 1 &&
            devRes[0] == 0 &&
            devRes[1] is Map) {
          final devs = devRes[1] as Map<String, dynamic>;
          devs.forEach((devName, devData) {
            if (devData is Map && devData['macaddr'] != null) {
              final m = normMac(devData['macaddr'].toString());
              if (m.isNotEmpty && m != '00:00:00:00:00:00') {
                routerMacs.add(m);
              }
            }
          });
        }
      } catch (_) {}

      hostHints.forEach((mac, info) {
        final m = normMac(mac);
        final ipaddrs = info['ipaddrs'] as List?;
        if (ipaddrs != null && ipaddrs.contains(router.ipAddress)) {
          routerMacs.add(m);
          for (final ip in ipaddrs) {
            routerIps.add(ip.toString());
          }
        }
      });

      final staticUciMacs = <String>{};
      final staticUciNames = <String, String>{};
      final staticUciTimes = <String, String>{};
      final dashboardData = _dashboardDataRef?.call();
      if (dashboardData != null) {
        final rawUci = dashboardData['uciDhcpConfig'] ?? dashboardData['dhcp'];
        if (rawUci is Map) {
          final values = rawUci['values'] ?? rawUci;
          if (values is Map) {
            values.forEach((_, sec) {
              if (sec is Map && sec['.type'] == 'host') {
                final rawMac = sec['mac'];
                final sName =
                    sec['name']?.toString() ??
                    sec['hostname']?.toString() ??
                    '';
                final sTime =
                    sec['leasetime']?.toString() ??
                    sec['lease_time']?.toString() ??
                    '';
                final macList = <String>[];
                if (rawMac is List) {
                  macList.addAll(rawMac.map((e) => e.toString()));
                } else if (rawMac != null) {
                  macList.addAll(rawMac.toString().split(RegExp(r'\s+')));
                }
                for (final m in macList) {
                  final nM = normMac(m);
                  if (nM.isNotEmpty) {
                    staticUciMacs.add(nM);
                    if (sName.isNotEmpty) staticUciNames[nM] = sName;
                    if (sTime.isNotEmpty) staticUciTimes[nM] = sTime;
                  }
                }
              }
            });
          }
        }
      }

      final clientMap = <String, Client>{};

      // A. Process IPv4 DHCP leases
      for (final l in dhcp4Leases) {
        final c = Client.fromLease(l);
        final macN = normMac(c.macAddress);
        if (macN.isEmpty || macN == 'N/A' || macN == '00:00:00:00:00:00') {
          continue;
        }

        var hostname = c.hostname;
        if ((hostname == 'Unknown' || hostname.isEmpty) &&
            hostHints.containsKey(macN)) {
          final hintName = hostHints[macN]?['name']?.toString();
          if (hintName != null && hintName.isNotEmpty && hintName != '*') {
            hostname = hintName;
          }
        }

        final staticName =
            hostHints[macN]?['staticLeaseName']?.toString() ??
            staticUciNames[macN];
        final staticTime =
            staticUciTimes[macN] ??
            hostHints[macN]?['staticLeaseTime']?.toString() ??
            hostHints[macN]?['leasetime']?.toString();
        final isStaticEntry =
            hostHints[macN]?['isStaticLease'] == true ||
            staticUciMacs.contains(macN);
        final isWireless = normalizedWireless.contains(macN);
        final foundSsid = macToSsidMap[macN];
        final foundIface = macToIfaceMap[macN];

        final hintV6 = hostHints[macN]?['ip6addrs'] as List?;
        final v6List = (hintV6 != null && hintV6.isNotEmpty)
            ? hintV6.map((e) => e.toString()).toList()
            : c.ipv6Addresses;

        clientMap[macN] = c.copyWith(
          hostname: hostname,
          connectionType: isWireless
              ? ConnectionType.wireless
              : ConnectionType.wired,
          ssid: foundSsid,
          wirelessIface: foundIface,
          staticLeaseName: staticName,
          isStaticLease: isStaticEntry,
          staticLeaseTime: staticTime,
          ipv6Addresses: v6List,
        );
      }

      // B. Process IPv6 DHCP leases
      for (final l in dhcp6Leases) {
        final macRaw = l['macaddr']?.toString() ?? l['mac']?.toString() ?? '';
        final macN = macRaw.isNotEmpty ? normMac(macRaw) : '';
        final hostname = l['hostname']?.toString();

        List<String> v6Addrs = [];
        if (l['ip6addrs'] is List) {
          v6Addrs = (l['ip6addrs'] as List).map((e) => e.toString()).toList();
        } else if (l['ip6addr'] != null) {
          v6Addrs = [l['ip6addr'].toString()];
        }

        if (macN.isNotEmpty && clientMap.containsKey(macN)) {
          final existing = clientMap[macN]!;
          final mergedV6 = <String>{
            ...?(existing.ipv6Addresses),
            ...v6Addrs,
          }.toList();
          clientMap[macN] = existing.copyWith(ipv6Addresses: mergedV6);
        } else {
          String? matchedMac;
          if (macN.isNotEmpty) {
            matchedMac = macN;
          } else {
            hostHints.forEach((hMac, info) {
              if (matchedMac != null) return;
              final hName = info['name']?.toString();
              if (hostname != null &&
                  hostname.isNotEmpty &&
                  hName != null &&
                  (hName == hostname || hName == '$hostname.lan')) {
                matchedMac = normMac(hMac);
              }
            });
          }

          if (matchedMac != null && matchedMac!.isNotEmpty) {
            if (clientMap.containsKey(matchedMac)) {
              final existing = clientMap[matchedMac]!;
              final mergedV6 = <String>{
                ...?(existing.ipv6Addresses),
                ...v6Addrs,
              }.toList();
              clientMap[matchedMac!] = existing.copyWith(
                ipv6Addresses: mergedV6,
              );
            } else {
              final isWireless = normalizedWireless.contains(matchedMac!);
              final staticName = hostHints[matchedMac]?['staticLeaseName']
                  ?.toString();
              final isStaticEntry =
                  hostHints[matchedMac]?['isStaticLease'] == true;
              clientMap[matchedMac!] = Client(
                ipAddress: 'N/A',
                macAddress: matchedMac!,
                hostname: (hostname != null && hostname.isNotEmpty)
                    ? hostname
                    : matchedMac!,
                connectionType: isWireless
                    ? ConnectionType.wireless
                    : ConnectionType.wired,
                ssid: macToSsidMap[matchedMac],
                wirelessIface: macToIfaceMap[matchedMac],
                staticLeaseName: staticName,
                isStaticLease: isStaticEntry,
                ipv6Addresses: v6Addrs,
              );
            }
          }
        }
      }

      // C. Merge Static Leases configured on router
      hostHints.forEach((mac, info) {
        final macN = normMac(mac);
        if (!clientMap.containsKey(macN)) {
          final hintName = info['name']?.toString();
          final staticName = info['staticLeaseName']?.toString();
          final isStaticEntry = info['isStaticLease'] == true;
          final ipaddrs = info['ipaddrs'] as List?;
          final ip = (ipaddrs != null && ipaddrs.isNotEmpty)
              ? ipaddrs.first.toString()
              : 'N/A';
          final name =
              (hintName != null && hintName.isNotEmpty && hintName != '*')
              ? hintName
              : macN;
          final isWireless = normalizedWireless.contains(macN);
          final hintV6 = info['ip6addrs'] as List?;
          final v6List = (hintV6 != null && hintV6.isNotEmpty)
              ? hintV6.map((e) => e.toString()).toList()
              : null;

          clientMap[macN] = Client(
            ipAddress: ip,
            macAddress: macN,
            hostname: name,
            connectionType: isWireless
                ? ConnectionType.wireless
                : ConnectionType.wired,
            ssid: macToSsidMap[macN],
            wirelessIface: macToIfaceMap[macN],
            staticLeaseName: staticName,
            isStaticLease: isStaticEntry,
            ipv6Addresses: v6List,
          );
        }
      });

      // C2. Merge live associated wireless stations (vital for Dumb APs where DHCP leases are empty)
      for (final mac in normalizedWireless) {
        if (!clientMap.containsKey(mac)) {
          final staticName = hostHints[mac]?['staticLeaseName']?.toString();
          final isStaticEntry = hostHints[mac]?['isStaticLease'] == true;
          final hintV6 = hostHints[mac]?['ip6addrs'] as List?;
          final v6List = (hintV6 != null && hintV6.isNotEmpty)
              ? hintV6.map((e) => e.toString()).toList()
              : null;
          final vendorName = hostHints[mac]?['vendor']?.toString();
          final resolvedSsid = macToSsidMap[mac];
          final resolvedIface = macToIfaceMap[mac];

          clientMap[mac] =
              Client.fromWirelessStation(
                mac,
                ssid: resolvedSsid,
                wirelessIface: resolvedIface,
                isDumbApClient: isRouterDumbAp,
                apName: isRouterDumbAp ? router.displayName : null,
              ).copyWith(
                staticLeaseName: staticName,
                isStaticLease: isStaticEntry,
                ipv6Addresses: v6List,
                vendor: vendorName,
              );
        }
      }

      // D. Final pass
      final processedClients = <Client>[];
      final sysHostname = (router.lastKnownHostname ?? '').trim().toLowerCase();

      for (final c in clientMap.values) {
        final macN = normMac(c.macAddress);

        if (routerMacs.contains(macN) || routerIps.contains(c.ipAddress)) {
          continue;
        }
        if (sysHostname.isNotEmpty) {
          final nameLower = c.displayName.trim().toLowerCase();
          if (nameLower == sysHostname || nameLower == '$sysHostname.lan') {
            continue;
          }
        }

        var resolvedIp = c.ipAddress;
        if ((resolvedIp == 'N/A' || resolvedIp.isEmpty) &&
            hostHints.containsKey(macN)) {
          final hintIps = hostHints[macN]?['ipaddrs'] as List?;
          if (hintIps != null && hintIps.isNotEmpty) {
            resolvedIp = hintIps.first.toString();
          }
          if ((resolvedIp == 'N/A' || resolvedIp.isEmpty) &&
              hostHints[macN]?['staticLeaseIp'] != null) {
            resolvedIp = hostHints[macN]!['staticLeaseIp'].toString();
          }
        }
        if (resolvedIp == 'N/A' || resolvedIp.isEmpty) {
          final neighMatch = neighClients.firstWhere(
            (a) => normMac(a['macaddr'] as String) == macN,
            orElse: () => <String, dynamic>{},
          );
          if (neighMatch.containsKey('ipaddr')) {
            resolvedIp = neighMatch['ipaddr']?.toString() ?? 'N/A';
          }
        }

        final isWirelessActive = normalizedWireless.contains(macN);

        Map<String, dynamic>? wiredNeighEntry;
        int maxRank = -1;
        for (final a in neighClients) {
          final aMac = normMac(a['macaddr'] as String);
          if (aMac != macN) continue;
          final dev = (a['device'] as String? ?? '').toLowerCase();
          final isWlanDev =
              dev.startsWith('wlan') ||
              dev.startsWith('phy') ||
              dev.startsWith('ra') ||
              dev.startsWith('wifi') ||
              dev.startsWith('ath');
          if (!isWlanDev) {
            final nud = (a['nud_state'] as String? ?? '').toUpperCase();
            int rank = 0;
            switch (nud) {
              case 'REACHABLE':
                rank = 4;
                break;
              case 'DELAY':
              case 'PROBE':
                rank = 3;
                break;
              case 'STALE':
                rank = 2;
                break;
              case 'UNKNOWN':
                rank = 1;
                break;
              default:
                rank = 0;
            }
            if (rank > maxRank) {
              maxRank = rank;
              wiredNeighEntry = a;
            }
          }
        }

        final resolvedSsid = c.ssid ?? macToSsidMap[macN];
        final resolvedIface = c.wirelessIface ?? macToIfaceMap[macN];
        final isWirelessClient =
            isWirelessActive ||
            _knownWirelessMacs.contains(macN) ||
            macToSsidMap.containsKey(macN) ||
            macToIfaceMap.containsKey(macN) ||
            normalizedWireless.contains(macN) ||
            c.connectionType == ConnectionType.wireless ||
            resolvedSsid != null ||
            resolvedIface != null;

        if (isWirelessClient) {
          _knownWirelessMacs.add(macN);
        }

        final isFdbActive = fdbMacs.contains(macN);

        NeighborReachability neighState;
        if (isWirelessActive) {
          neighState = NeighborReachability.reachable;
        } else if (isFdbActive) {
          neighState = NeighborReachability.reachable;
        } else if (wiredNeighEntry != null) {
          final nud = (wiredNeighEntry['nud_state'] as String? ?? '')
              .toUpperCase();
          switch (nud) {
            case 'REACHABLE':
            case 'DELAY':
            case 'PROBE':
              neighState = NeighborReachability.reachable;
              break;
            case 'STALE':
              neighState = NeighborReachability.stale;
              break;
            case 'FAILED':
            case 'INCOMPLETE':
            case 'NOARP':
              neighState = NeighborReachability.failed;
              break;
            case 'UNKNOWN':
              neighState = NeighborReachability.unknown;
              break;
            default:
              neighState = NeighborReachability.unknown;
          }
        } else {
          neighState = NeighborReachability.failed;
        }

        final hasActiveLease = c.leaseTime != null && c.leaseTime! > 0;
        final isStaticLease =
            hostHints[macN]?['isStaticLease'] == true || c.isStaticLease;

        bool isConnected;
        ConnectionType finalConnType;

        if (isWirelessClient) {
          isConnected = isWirelessActive;
          finalConnType = ConnectionType.wireless;
        } else {
          final isL3Active =
              wiredNeighEntry != null &&
              (neighState == NeighborReachability.reachable ||
                  neighState == NeighborReachability.unknown);

          bool isCurrentlyActive = isFdbActive || isL3Active;

          final now = DateTime.now();
          if (isCurrentlyActive) {
            _recentWiredActiveTime[macN] = now;
          } else {
            final lastSeen = _recentWiredActiveTime[macN];
            if ((hasActiveLease || isStaticLease) &&
                lastSeen != null &&
                now.difference(lastSeen) < const Duration(seconds: 90)) {
              isCurrentlyActive = true;
              if (neighState == NeighborReachability.failed) {
                neighState = NeighborReachability.stale;
              }
            }
          }

          isConnected = isCurrentlyActive;
          finalConnType = ConnectionType.wired;
        }

        final hasValidIp = resolvedIp != 'N/A' && resolvedIp.isNotEmpty;
        final hasGlobalV6 =
            c.ipv6Addresses != null &&
            c.ipv6Addresses!.any(
              (addr) => !addr.toLowerCase().startsWith('fe80:'),
            );
        final hasName =
            (c.staticLeaseName != null && c.staticLeaseName!.isNotEmpty) ||
            (c.hostname != 'Unknown' &&
                c.hostname.isNotEmpty &&
                c.hostname != macN);

        if (!hasValidIp && !hasGlobalV6 && !hasName && !isConnected) {
          continue;
        }

        if (isConnected || hasActiveLease || isStaticLease) {
          final isClientDumbAp =
              c.isDumbApClient || (isWirelessActive && isRouterDumbAp);
          final clientApName =
              c.apName ?? (isClientDumbAp ? router.displayName : null);
          processedClients.add(
            c.copyWith(
              ipAddress: resolvedIp,
              isConnected: isConnected,
              neighState: neighState,
              connectionType: finalConnType,
              ssid: resolvedSsid,
              wirelessIface: resolvedIface,
              isDumbApClient: isClientDumbAp,
              apName: clientApName,
            ),
          );
        }
      }

      processedClients.sort((a, b) {
        if (a.isConnected != b.isConnected) {
          return a.isConnected ? -1 : 1;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });

      return processedClients;
    } catch (e, stack) {
      Logger.exception('Failed to fetch clients for selected router', e, stack);
      return [];
    }
  }

  /// Returns a union set of associated wireless MAC addresses across all routers
  Future<Set<String>> fetchAllAssociatedWirelessMacsAggregated() async {
    try {
      if (_isReviewerMode) {
        final stationsMap = await _apiService!.fetchAssociatedStations();
        final macs = <String>{};
        stationsMap.forEach((_, stations) {
          macs.addAll(stations.map((m) => m.toLowerCase()));
        });
        return macs;
      }

      final routers = _routerService?.routers ?? const <model.Router>[];
      if (routers.isEmpty) return {};

      final tasks = routers.map((r) async {
        try {
          if (_apiService != null) {
            final res = await _apiService!.authenticate(
              r.ipAddress,
              r.username,
              r.password,
              r.useHttps,
            );
            if (!res.isSuccess || res.token == null) return <String>{};
            final map = await _apiService!
                .fetchAllAssociatedWirelessMacsWithContext(
                  ipAddress: r.ipAddress,
                  sysauth: res.token!,
                  useHttps: res.actualUseHttps,
                );
            final set = <String>{};
            map.forEach((_, stations) {
              set.addAll(stations.map((m) => m.toLowerCase()));
            });
            return set;
          }
        } catch (e) {
          // Skip router on failure
        }
        return <String>{};
      }).toList();

      final results = await Future.wait(tasks);
      return results.fold<Set<String>>(<String>{}, (acc, s) => acc..addAll(s));
    } catch (e, stack) {
      Logger.exception('Failed to aggregate wireless MACs', e, stack);
      return {};
    }
  }

  /// Returns a combined list of DHCP lease maps from all routers
  Future<List<Map<String, dynamic>>> fetchAggregatedDhcpLeases() async {
    try {
      if (_isReviewerMode) {
        final result = await _apiService!.callSimple(
          'luci-rpc',
          'getDHCPLeases',
          {},
        );
        if (result is List && result.length > 1 && result[0] == 0) {
          final data = result[1] as Map<String, dynamic>;
          final leases = (data['dhcp_leases'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          return leases;
        }
        return [];
      }

      final routers = _routerService?.routers ?? const <model.Router>[];
      if (routers.isEmpty) return [];

      final tasks = routers.map((r) async {
        try {
          if (_apiService != null) {
            final res = await _apiService!.authenticate(
              r.ipAddress,
              r.username,
              r.password,
              r.useHttps,
            );
            if (!res.isSuccess || res.token == null) {
              return <Map<String, dynamic>>[];
            }
            final callRes = await _apiService!.call(
              r.ipAddress,
              res.token!,
              res.actualUseHttps,
              object: 'luci-rpc',
              method: 'getDHCPLeases',
              params: {},
            );
            if (callRes is List && callRes.length > 1 && callRes[0] == 0) {
              final data = callRes[1] as Map<String, dynamic>;
              final leases = (data['dhcp_leases'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>();
              return leases;
            }
          }
        } catch (e) {
          // Skip router on failure
        }
        return <Map<String, dynamic>>[];
      }).toList();

      final results = await Future.wait(tasks);
      final seen = <String, Map<String, dynamic>>{};
      for (final list in results) {
        for (final lease in list) {
          final mac = (lease['macaddr']?.toString() ?? '').toUpperCase();
          final ip = lease['ipaddr']?.toString() ?? '';
          final key = '$mac|$ip';
          if (!seen.containsKey(key)) {
            seen[key] = lease;
          }
        }
      }
      return seen.values.toList();
    } catch (e, stack) {
      Logger.exception('Failed to aggregate DHCP leases', e, stack);
      return [];
    }
  }
}
