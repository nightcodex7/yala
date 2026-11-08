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
    void Function()? onClientsUpdated,
  }) : _apiServiceRef = apiServiceRef,
       _authServiceRef = authServiceRef,
       _routerServiceRef = routerServiceRef,
       _reviewerModeRef = reviewerModeRef,
       _dashboardDataRef = dashboardDataRef,
       _executeRouterCommandOutput = executeRouterCommandOutput,
       _processDhcpLeases = processDhcpLeases,
       _onClientsUpdated = onClientsUpdated;

  final IApiService? Function() _apiServiceRef;
  final IAuthService? Function() _authServiceRef;
  final RouterService? Function() _routerServiceRef;
  final bool Function() _reviewerModeRef;
  final Map<String, dynamic>? Function()? _dashboardDataRef;
  final Future<String?> Function(String command, List<String> args)
  _executeRouterCommandOutput;
  final Map<String, dynamic> Function(Map<String, dynamic> rawDhcpData)
  _processDhcpLeases;
  final void Function()? _onClientsUpdated;

  final Map<String, DateTime> _knownWirelessMacs = {};
  final Map<String, DateTime> _recentWiredActiveTime = {};
  final Map<String, ({int rxBytes, int txBytes, DateTime timestamp})>
  _previousStationTraffic = {};
  final Map<String, ({String token, bool useHttps, DateTime cachedAt})>
  _secondaryRouterTokens = {};
  final Map<String, DateTime> _lastNeighborProbeTime = {};
  List<Client>? lastFetchedClients;
  bool _isFetchingClients = false;
  int _fetchEpoch = 0;

  Map<String, DateTime> get knownWirelessMacs => _knownWirelessMacs;
  bool get isFetchingClients => _isFetchingClients;
  bool get hasFetchedClients => lastFetchedClients != null;

  /// Resets client state and caches (e.g. on router profile switch or logout).
  void resetState() {
    _fetchEpoch++;
    _knownWirelessMacs.clear();
    _recentWiredActiveTime.clear();
    _previousStationTraffic.clear();
    _secondaryRouterTokens.clear();
    _lastNeighborProbeTime.clear();
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
    // 1. Any currently fetched client is tagged as connected via a Dumb AP
    if (lastFetchedClients != null &&
        lastFetchedClients!.any((c) => c.isDumbApClient)) {
      return true;
    }

    final selected = _routerService?.selectedRouter;
    final routers = _routerService?.routers ?? [];

    // 2. Check if any secondary router in the configured routers list is identified as an AP
    for (final r in routers) {
      if (r.id != selected?.id &&
          (isDumbApName(r.name) || isDumbApName(r.lastKnownHostname))) {
        return true;
      }
    }

    // 3. If multiple routers are configured in the app, secondary AP management is active
    if (routers.length > 1) {
      return true;
    }

    return false;
  }

  static int? _extractInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  static num? _extractNum(dynamic val) {
    if (val == null) return null;
    if (val is num) return val;
    if (val is String) return num.tryParse(val);
    return null;
  }

  ({
    int? rxBytes,
    int? txBytes,
    int? rxPackets,
    int? txPackets,
    num? rxRate,
    num? txRate,
    int? signalDbm,
    int? noiseDbm,
    int? throughput,
    double? rxSpeed,
    double? txSpeed,
    int? connectedTime,
  })
  _computeStationVitals(String mac, Map<String, dynamic> station) {
    final rxMap = station['rx'] is Map ? (station['rx'] as Map) : null;
    final txMap = station['tx'] is Map ? (station['tx'] as Map) : null;
    final bytesMap = station['bytes'] is Map ? (station['bytes'] as Map) : null;
    final packetsMap = station['packets'] is Map
        ? (station['packets'] as Map)
        : null;
    final rateMap = station['rate'] is Map ? (station['rate'] as Map) : null;

    final rxBytes = _extractInt(
      rxMap?['bytes'] ?? bytesMap?['rx'] ?? station['rx_bytes'],
    );
    final txBytes = _extractInt(
      txMap?['bytes'] ?? bytesMap?['tx'] ?? station['tx_bytes'],
    );
    final rxPackets = _extractInt(
      rxMap?['packets'] ?? packetsMap?['rx'] ?? station['rx_packets'],
    );
    final txPackets = _extractInt(
      txMap?['packets'] ?? packetsMap?['tx'] ?? station['tx_packets'],
    );
    final rxRate = _extractNum(
      rxMap?['rate'] ?? rateMap?['rx'] ?? station['rx_rate'],
    );
    final txRate = _extractNum(
      txMap?['rate'] ?? rateMap?['tx'] ?? station['tx_rate'],
    );
    final signalDbm = _extractInt(station['signal']);
    final noiseDbm = _extractInt(station['noise']);
    final throughput = _extractInt(station['thr'] ?? station['throughput']);
    final connectedTime = _extractInt(station['connected_time']);

    final now = DateTime.now();
    double? rxSpeed;
    double? txSpeed;

    final prev = _previousStationTraffic[mac];
    if (prev != null && rxBytes != null && txBytes != null) {
      final deltaSeconds =
          now.difference(prev.timestamp).inMilliseconds / 1000.0;
      if (deltaSeconds >= 0.5 && deltaSeconds <= 120.0) {
        if (rxBytes >= prev.rxBytes) {
          rxSpeed = (rxBytes - prev.rxBytes) / deltaSeconds;
        } else if (prev.rxBytes > 0x7FFFFFFF && rxBytes < 0x20000000) {
          // 32-bit unsigned counter rollover: 2^32 = 4294967296
          final delta = (4294967296 - prev.rxBytes) + rxBytes;
          rxSpeed = delta / deltaSeconds;
        }

        if (txBytes >= prev.txBytes) {
          txSpeed = (txBytes - prev.txBytes) / deltaSeconds;
        } else if (prev.txBytes > 0x7FFFFFFF && txBytes < 0x20000000) {
          // 32-bit unsigned counter rollover: 2^32 = 4294967296
          final delta = (4294967296 - prev.txBytes) + txBytes;
          txSpeed = delta / deltaSeconds;
        }
      }
    }

    if (rxBytes != null && txBytes != null) {
      _previousStationTraffic[mac] = (
        rxBytes: rxBytes,
        txBytes: txBytes,
        timestamp: now,
      );
    }

    return (
      rxBytes: rxBytes,
      txBytes: txBytes,
      rxPackets: rxPackets,
      txPackets: txPackets,
      rxRate: rxRate,
      txRate: txRate,
      signalDbm: signalDbm,
      noiseDbm: noiseDbm,
      throughput: throughput,
      rxSpeed: rxSpeed,
      txSpeed: txSpeed,
      connectedTime: connectedTime,
    );
  }

  IApiService? get _apiService => _apiServiceRef();
  IAuthService? get _authService => _authServiceRef();
  RouterService? get _routerService => _routerServiceRef();
  bool get _isReviewerMode => _reviewerModeRef();

  /// Aggregates DHCP leases across all configured routers and classifies clients
  /// as wireless if their MAC appears in any router's associated stations list.
  /// Also tags clients associated with secondary Dumb APs.
  ///
  /// Implements lazy loading: the selected Main Router is queried and published
  /// immediately, while secondary Dumb AP routers are fetched concurrently in the
  /// background and merged into the client list as each completes.
  Future<List<Client>> fetchAggregatedClients({
    void Function(List<Client> clients)? onIncrementalUpdate,
  }) async {
    _isFetchingClients = true;
    final fetchEpoch = ++_fetchEpoch;
    try {
      final clientsMap = <String, Client>{};
      final routers = _routerService?.routers ?? [];
      if (routers.isEmpty) {
        return lastFetchedClients ?? [];
      }

      // Sort routers so the currently selected Main Router is processed first,
      // establishing authoritative DHCP leases, hostnames, and connection states.
      final selectedId = _routerService?.selectedRouter?.id;
      final sortedRouters = List<model.Router>.from(routers);
      if (selectedId != null) {
        sortedRouters.sort((a, b) {
          if (a.id == selectedId) return -1;
          if (b.id == selectedId) return 1;
          return 0;
        });
      }

      // 1. Fetch Main Router first and immediately publish its clients
      final mainRouter = sortedRouters.first;
      final isMain = mainRouter.id == selectedId;
      List<Client> mainClients = [];
      try {
        mainClients = await _fetchClientsForRouter(mainRouter);
      } catch (e, stack) {
        Logger.exception(
          'Failed to fetch clients for main router ${mainRouter.ipAddress}',
          e,
          stack,
        );
      }

      if (_fetchEpoch != fetchEpoch) {
        return lastFetchedClients ?? [];
      }

      _mergeClientsIntoMap(clientsMap, mainClients, isMain);
      lastFetchedClients = _sortedClients(clientsMap);

      // Lazy Loading: Immediately emit Main Router clients so the Clients tab renders them right away!
      onIncrementalUpdate?.call(List<Client>.unmodifiable(lastFetchedClients!));
      _onClientsUpdated?.call();

      // 2. Fetch secondary routers (Dumb APs) concurrently in the background
      final secondaryRouters = sortedRouters.sublist(1);
      if (secondaryRouters.isNotEmpty) {
        await Future.wait(
          secondaryRouters.map((secRouter) async {
            try {
              final secClients = await _fetchClientsForRouter(secRouter);
              if (_fetchEpoch != fetchEpoch) return;

              _mergeClientsIntoMap(clientsMap, secClients, false);
              lastFetchedClients = _sortedClients(clientsMap);

              // Incrementally update UI and AppState with the newly fetched Dumb AP clients
              onIncrementalUpdate?.call(
                List<Client>.unmodifiable(lastFetchedClients!),
              );
              _onClientsUpdated?.call();
            } catch (e, stack) {
              Logger.exception(
                'Failed to fetch clients for secondary router ${secRouter.ipAddress}',
                e,
                stack,
              );
            }
          }),
        );
      }

      if (_fetchEpoch != fetchEpoch) {
        return lastFetchedClients ?? [];
      }

      return lastFetchedClients ?? [];
    } catch (e, stack) {
      Logger.exception('Failed to aggregate clients', e, stack);
      return lastFetchedClients ?? [];
    } finally {
      if (_fetchEpoch == fetchEpoch) {
        _isFetchingClients = false;
      }
    }
  }

  List<Client> _sortedClients(Map<String, Client> clientsMap) {
    final list = clientsMap.values.toList();
    list.sort((a, b) {
      if (a.isConnected != b.isConnected) {
        return a.isConnected ? -1 : 1;
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return list;
  }

  void _mergeClientsIntoMap(
    Map<String, Client> clientsMap,
    List<Client> routerClients,
    bool isMainRouter,
  ) {
    for (final c in routerClients) {
      final macNorm = c.macAddress.toUpperCase().replaceAll('-', ':');
      if (!clientsMap.containsKey(macNorm)) {
        // New client discovered: Main router clients are never Dumb AP clients.
        clientsMap[macNorm] = isMainRouter
            ? c.copyWith(isDumbApClient: false, apName: null)
            : c;
      } else {
        final existing = clientsMap[macNorm]!;

        // Resolution rules:
        // 1. If client is active on Main Router (wired or wireless), Main Router takes precedence.
        // 2. Only if actively connected wirelessly to a secondary Dumb AP is it a Dumb AP client.
        final existingActiveOnMain =
            (existing.isConnected && !existing.isDumbApClient);
        final clientActiveOnSecondaryAp =
            !isMainRouter && c.isDumbApClient && c.isConnected;

        final bool isDumb;
        final String? apName;
        final ConnectionType preferredConnType;
        final String? preferredSsid;
        final String? preferredIface;
        int? signalDbm;
        int? noiseDbm;
        int? throughput;
        int? rxBytes;
        int? txBytes;
        int? rxPackets;
        int? txPackets;
        num? rxRate;
        num? txRate;
        double? rxSpeed;
        double? txSpeed;
        int? connectedTime;

        if (clientActiveOnSecondaryAp &&
            existing.connectionType != ConnectionType.wireless) {
          // Client is actively connected to the secondary Dumb AP (wireless or wired)
          isDumb = true;
          apName = c.apName;
          preferredConnType =
              (c.connectionType == ConnectionType.wireless ||
                  existing.connectionType == ConnectionType.wireless)
              ? ConnectionType.wireless
              : ConnectionType.wired;
          preferredSsid = c.ssid ?? existing.ssid;
          preferredIface = c.wirelessIface ?? existing.wirelessIface;
          signalDbm = c.signalDbm ?? existing.signalDbm;
          noiseDbm = c.noiseDbm ?? existing.noiseDbm;
          throughput = c.throughput ?? existing.throughput;
          rxBytes = c.rxBytes ?? existing.rxBytes;
          txBytes = c.txBytes ?? existing.txBytes;
          rxPackets = c.rxPackets ?? existing.rxPackets;
          txPackets = c.txPackets ?? existing.txPackets;
          rxRate = c.rxRate ?? existing.rxRate;
          txRate = c.txRate ?? existing.txRate;
          rxSpeed = c.rxSpeed ?? existing.rxSpeed;
          txSpeed = c.txSpeed ?? existing.txSpeed;
          connectedTime = c.connectedTime ?? existing.connectedTime;
        } else if (existingActiveOnMain || isMainRouter) {
          // Client is associated with the Main Router:
          // Main Router connection is authoritative; NEVER a Dumb AP client.
          isDumb = false;
          apName = null;
          preferredConnType = existing.connectionType;
          preferredSsid = existing.ssid ?? c.ssid;
          preferredIface = existing.wirelessIface ?? c.wirelessIface;
          signalDbm = existing.signalDbm ?? c.signalDbm;
          noiseDbm = existing.noiseDbm ?? c.noiseDbm;
          throughput = existing.throughput ?? c.throughput;
          rxBytes = existing.rxBytes ?? c.rxBytes;
          txBytes = existing.txBytes ?? c.txBytes;
          rxPackets = existing.rxPackets ?? c.rxPackets;
          txPackets = existing.txPackets ?? c.txPackets;
          rxRate = existing.rxRate ?? c.rxRate;
          txRate = existing.txRate ?? c.txRate;
          rxSpeed = existing.rxSpeed ?? c.rxSpeed;
          txSpeed = existing.txSpeed ?? c.txSpeed;
          connectedTime = existing.connectedTime ?? c.connectedTime;
        } else {
          isDumb = existing.isDumbApClient || c.isDumbApClient;
          apName = c.isDumbApClient
              ? (c.apName ?? existing.apName)
              : (existing.apName ?? c.apName);
          preferredConnType =
              (existing.connectionType == ConnectionType.wireless ||
                  c.connectionType == ConnectionType.wireless)
              ? ConnectionType.wireless
              : existing.connectionType;
          preferredSsid = existing.ssid ?? c.ssid;
          preferredIface = existing.wirelessIface ?? c.wirelessIface;
          signalDbm = c.signalDbm ?? existing.signalDbm;
          noiseDbm = c.noiseDbm ?? existing.noiseDbm;
          throughput = c.throughput ?? existing.throughput;
          rxBytes = c.rxBytes ?? existing.rxBytes;
          txBytes = c.txBytes ?? existing.txBytes;
          rxPackets = c.rxPackets ?? existing.rxPackets;
          txPackets = c.txPackets ?? existing.txPackets;
          rxRate = c.rxRate ?? existing.rxRate;
          txRate = c.txRate ?? existing.txRate;
          rxSpeed = c.rxSpeed ?? existing.rxSpeed;
          txSpeed = c.txSpeed ?? existing.txSpeed;
          connectedTime = c.connectedTime ?? existing.connectedTime;
        }

        final preferredHostname =
            (existing.hostname != 'Unknown' &&
                existing.hostname != existing.macAddress)
            ? existing.hostname
            : c.hostname;
        final preferredIp =
            (existing.ipAddress != 'N/A' && existing.ipAddress.isNotEmpty)
            ? existing.ipAddress
            : c.ipAddress;
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
          rxBytes: rxBytes,
          txBytes: txBytes,
          rxPackets: rxPackets,
          txPackets: txPackets,
          rxRate: rxRate,
          txRate: txRate,
          signalDbm: signalDbm,
          noiseDbm: noiseDbm,
          throughput: throughput,
          rxSpeed: rxSpeed,
          txSpeed: txSpeed,
          connectedTime: connectedTime,
        );
      }
    }
  }

  /// Returns clients for the currently selected router only
  Future<List<Client>> fetchClientsForSelectedRouter() async {
    final fetchEpoch = ++_fetchEpoch;
    _isFetchingClients = true;
    try {
      if (_isReviewerMode) {
        final stationsMap = await _apiService!
            .fetchAllAssociatedWirelessStationsWithDetailsContext(
              ipAddress: '192.168.1.1',
              sysauth: 'mock',
              useHttps: false,
            );
        final macToSsidMap = <String, String>{};
        final macToIfaceMap = <String, String>{};
        final macToStationDetailsMap = <String, Map<String, dynamic>>{};
        final macs = <String>{};
        stationsMap.forEach((key, stations) {
          String iface = key;
          String? ssid = key;
          if (key.contains('|')) {
            final parts = key.split('|');
            iface = parts[0];
            ssid = parts.sublist(1).join('|');
          }
          for (final station in stations) {
            final rawMac = station['mac']?.toString();
            if (rawMac == null || rawMac.isEmpty) continue;
            final macLower = rawMac.toLowerCase();
            macs.add(macLower);
            final macNorm = rawMac.toUpperCase().replaceAll('-', ':');
            macToIfaceMap[macNorm] = iface;
            if (ssid.isNotEmpty) {
              macToSsidMap[macNorm] = ssid;
            }
            macToStationDetailsMap[macNorm] = station;
          }
        });

        final vitalsMap =
            <
              String,
              ({
                int? rxBytes,
                int? txBytes,
                int? rxPackets,
                int? txPackets,
                num? rxRate,
                num? txRate,
                int? signalDbm,
                int? noiseDbm,
                int? throughput,
                double? rxSpeed,
                double? txSpeed,
                int? connectedTime,
              })
            >{};
        macToStationDetailsMap.forEach((mac, data) {
          vitalsMap[mac] = _computeStationVitals(mac, data);
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
          final vitals = vitalsMap[macNorm];

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
            rxBytes: vitals?.rxBytes,
            txBytes: vitals?.txBytes,
            rxPackets: vitals?.rxPackets,
            txPackets: vitals?.txPackets,
            rxRate: vitals?.rxRate,
            txRate: vitals?.txRate,
            signalDbm: vitals?.signalDbm,
            noiseDbm: vitals?.noiseDbm,
            throughput: vitals?.throughput,
            rxSpeed: vitals?.rxSpeed,
            txSpeed: vitals?.txSpeed,
            connectedTime: vitals?.connectedTime,
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
            final vitals = vitalsMap[mac];
            clientMap[mac] =
                Client.fromWirelessStation(
                  mac,
                  ssid: macToSsidMap[mac],
                  wirelessIface: macToIfaceMap[mac],
                  rxBytes: vitals?.rxBytes,
                  txBytes: vitals?.txBytes,
                  rxPackets: vitals?.rxPackets,
                  txPackets: vitals?.txPackets,
                  rxRate: vitals?.rxRate,
                  txRate: vitals?.txRate,
                  signalDbm: vitals?.signalDbm,
                  noiseDbm: vitals?.noiseDbm,
                  throughput: vitals?.throughput,
                  rxSpeed: vitals?.rxSpeed,
                  txSpeed: vitals?.txSpeed,
                  connectedTime: vitals?.connectedTime,
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
            final vitals = vitalsMap[macN];

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
              rxBytes: vitals?.rxBytes,
              txBytes: vitals?.txBytes,
              rxPackets: vitals?.rxPackets,
              txPackets: vitals?.txPackets,
              rxRate: vitals?.rxRate,
              txRate: vitals?.txRate,
              signalDbm: vitals?.signalDbm,
              noiseDbm: vitals?.noiseDbm,
              throughput: vitals?.throughput,
              rxSpeed: vitals?.rxSpeed,
              txSpeed: vitals?.txSpeed,
              connectedTime: vitals?.connectedTime,
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
      if (_fetchEpoch != fetchEpoch) {
        return lastFetchedClients ?? [];
      }
      lastFetchedClients = result;
      _onClientsUpdated?.call();
      return result;
    } catch (e, stack) {
      Logger.exception('Failed to fetch clients for selected router', e, stack);
      return lastFetchedClients ?? [];
    } finally {
      if (_fetchEpoch == fetchEpoch) {
        _isFetchingClients = false;
      }
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
      final cached = _secondaryRouterTokens[router.id];
      if (cached != null &&
          DateTime.now().difference(cached.cachedAt) <
              const Duration(minutes: 50)) {
        routerSysauth = cached.token;
        actualUseHttps = cached.useHttps;
      } else if (_apiService != null) {
        // Evict expired/missing token before re-authenticating
        _secondaryRouterTokens.remove(router.id);
        try {
          final authRes = await _apiService!.authenticate(
            router.ipAddress,
            router.username,
            router.password,
            router.useHttps,
          );
          if (authRes.isSuccess && authRes.token != null) {
            final token = authRes.token!;
            routerSysauth = token;
            actualUseHttps = authRes.actualUseHttps;
            _secondaryRouterTokens[router.id] = (
              token: token,
              useHttps: actualUseHttps,
              cachedAt: DateTime.now(),
            );
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

      // Router-scoped command execution helper:
      // Commands for the active selected router use the AppState helper;
      // commands for secondary routers execute strictly against that router's session
      // to prevent cross-router command leakage.
      Future<String?> execRouterCmd(String command, List<String> args) async {
        if (router.id == _routerService?.selectedRouter?.id) {
          return await _executeRouterCommandOutput(command, args);
        }
        if (_apiService == null ||
            activeSysauth.isEmpty ||
            activeSysauth == 'mock') {
          return null;
        }
        try {
          if (command == 'cat' && args.isNotEmpty) {
            final readRes = await _apiService!.call(
              router.ipAddress,
              activeSysauth,
              actualUseHttps,
              object: 'file',
              method: 'read',
              params: {'path': args.first},
            );
            if (readRes is List &&
                readRes.length > 1 &&
                readRes[0] == 0 &&
                readRes[1] is Map) {
              final data = readRes[1] as Map;
              if (data['data'] != null) return data['data'].toString();
            }
          }
          final res = await _apiService!.call(
            router.ipAddress,
            activeSysauth,
            actualUseHttps,
            object: 'file',
            method: 'exec',
            params: {'command': command, 'params': args, 'args': args},
          );
          if (res is List && res.length > 1 && res[0] == 0 && res[1] is Map) {
            final data = res[1] as Map;
            final stdout = data['stdout']?.toString() ?? '';
            if (stdout.isNotEmpty) return stdout;
          }
          final isShell =
              command == 'sh' ||
              command == '/bin/sh' ||
              command == 'ash' ||
              command == '/bin/ash';
          final cmdStr = isShell && args.length >= 2 && args[0] == '-c'
              ? args[1]
              : ([command, ...args]).join(' ');
          final shellRes = await _apiService!.call(
            router.ipAddress,
            activeSysauth,
            actualUseHttps,
            object: 'file',
            method: 'exec',
            params: {
              'command': '/bin/sh',
              'params': ['-c', cmdStr],
              'args': ['-c', cmdStr],
            },
          );
          if (shellRes is List &&
              shellRes.length > 1 &&
              shellRes[0] == 0 &&
              shellRes[1] is Map) {
            final data = shellRes[1] as Map;
            final stdout = data['stdout']?.toString() ?? '';
            if (stdout.isNotEmpty) return stdout;
          }
        } catch (_) {}
        return null;
      }

      // Pre-start all independent fetch operations so they run concurrently with
      // the wireless station query below. By the time each is awaited, it will
      // often already be complete, effectively parallelising the data-gather phase.
      final _dhcpFuture = _apiService!.call(
        router.ipAddress,
        activeSysauth,
        router.useHttps,
        object: 'luci-rpc',
        method: 'getDHCPLeases',
        params: {},
      );
      final _ifaceDumpFuture = _apiService!.call(
        router.ipAddress,
        activeSysauth,
        router.useHttps,
        object: 'network.interface',
        method: 'dump',
        params: {},
      );
      final _hostHintsFuture = _apiService!.fetchHostHintsWithContext(
        ipAddress: router.ipAddress,
        sysauth: activeSysauth,
        useHttps: router.useHttps,
      );
      final _deviceStatusFuture = _apiService!.call(
        router.ipAddress,
        activeSysauth,
        router.useHttps,
        object: 'network.device',
        method: 'status',
        params: {},
      );

      // 1. Fetch live associated wireless stations with full traffic & PHY stats
      final stationsMap = await _apiService!
          .fetchAllAssociatedWirelessStationsWithDetailsContext(
            ipAddress: router.ipAddress,
            sysauth: activeSysauth,
            useHttps: actualUseHttps,
          );
      final macToSsidMap = <String, String>{};
      final macToIfaceMap = <String, String>{};
      final macToStationDetailsMap = <String, Map<String, dynamic>>{};
      final wireless = <String>{};
      stationsMap.forEach((key, stationList) {
        String iface = key;
        String? ssid = key;
        if (key.contains('|')) {
          final parts = key.split('|');
          iface = parts[0];
          ssid = parts.sublist(1).join('|');
        }
        for (final station in stationList) {
          final rawMac = station['mac']?.toString();
          if (rawMac == null || rawMac.isEmpty) continue;
          final n = normMac(rawMac);
          wireless.add(n);
          macToIfaceMap[n] = iface;
          if (ssid.isNotEmpty) {
            macToSsidMap[n] = ssid;
          }
          macToStationDetailsMap[n] = station;
        }
      });

      final vitalsMap =
          <
            String,
            ({
              int? rxBytes,
              int? txBytes,
              int? rxPackets,
              int? txPackets,
              num? rxRate,
              num? txRate,
              int? signalDbm,
              int? noiseDbm,
              int? throughput,
              double? rxSpeed,
              double? txSpeed,
              int? connectedTime,
            })
          >{};
      macToStationDetailsMap.forEach((mac, data) {
        vitalsMap[mac] = _computeStationVitals(mac, data);
      });

      // Fallback: Shell station dump if station map is empty
      if (wireless.isEmpty) {
        final iwDevOut = await execRouterCmd('iw', ['dev']);
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
        await Future.wait(
          ifaces.map((iface) async {
            final iwDump =
                await execRouterCmd('iw', ['dev', iface, 'station', 'dump']) ??
                await execRouterCmd('iwinfo', [iface, 'assoclist']);
            if (iwDump != null && iwDump.isNotEmpty) {
              final macRegex = RegExp(
                r'([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})',
              );
              for (final match in macRegex.allMatches(iwDump)) {
                final m = match.group(0);
                if (m != null) {
                  wireless.add(normMac(m));
                }
              }
            }
          }),
        );
      }
      final normalizedWireless = wireless.map(normMac).toSet();
      final nowStamp = DateTime.now();
      // Stamp each freshly-seen wireless MAC with the current time.
      // Entries older than 20 min are considered stale and evicted at
      // the start of the classification pass below.
      for (final mac in normalizedWireless) {
        _knownWirelessMacs[mac] = nowStamp;
      }
      // Evict wired-active cache entries older than 5 minutes (well beyond the
      // 90-second recency window) to prevent unbounded map growth.
      _recentWiredActiveTime.removeWhere(
        (_, ts) => nowStamp.difference(ts) > const Duration(minutes: 5),
      );

      // 2. Fetch getDHCPLeases from luci-rpc (future pre-started above)
      final callRes = await _dhcpFuture;
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
            await execRouterCmd('cat', ['/tmp/dhcp.leases']) ??
            await execRouterCmd('cat', ['/var/dhcp.leases']) ??
            await execRouterCmd('cat', ['/tmp/dnsmasq.leases']);
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

      // The router to which the Yala app is currently logged into is strictly the Main Router.
      // Under no circumstance can the active logged-in router ever be considered a Dumb AP.
      final isSelectedMainRouter =
          router.id == _routerService?.selectedRouter?.id;

      final isRouterDumbAp =
          !isSelectedMainRouter &&
          ((hasNoDhcp && otherRouters.isNotEmpty) ||
              (hasNoDhcp && normalizedWireless.isNotEmpty) ||
              (hasNoDhcp && hasApName) ||
              (hasApName && otherRouters.isNotEmpty) ||
              otherRouters.isNotEmpty);

      final wanDevices = <String>{};
      final wanIps = <String>{};
      final wanMacs = <String>{};

      try {
        final ifaceRes = await _ifaceDumpFuture;
        if (ifaceRes is List &&
            ifaceRes.length > 1 &&
            ifaceRes[0] == 0 &&
            ifaceRes[1] is Map) {
          final data = ifaceRes[1] as Map<String, dynamic>;
          final ifaces = data['interface'] as List?;
          if (ifaces != null) {
            for (final item in ifaces) {
              if (item is Map<String, dynamic>) {
                final name = (item['interface'] as String? ?? '').toLowerCase();
                final dev = (item['device'] as String? ?? '').toLowerCase();
                final l3Dev = (item['l3_device'] as String? ?? '')
                    .toLowerCase();
                final isWan =
                    name == 'wan' ||
                    name == 'wan6' ||
                    name.startsWith('wan') ||
                    name.startsWith('wwan') ||
                    item['defaultroute'] == true;
                if (isWan) {
                  if (dev.isNotEmpty) wanDevices.add(dev);
                  if (l3Dev.isNotEmpty) wanDevices.add(l3Dev);
                  final v4 = item['ipv4-address'] as List?;
                  if (v4 != null) {
                    for (final a in v4) {
                      if (a is Map && a['address'] != null) {
                        wanIps.add(a['address'].toString());
                      }
                    }
                  }
                  final v6 = item['ipv6-address'] as List?;
                  if (v6 != null) {
                    for (final a in v6) {
                      if (a is Map && a['address'] != null) {
                        wanIps.add(a['address'].toString());
                      }
                    }
                  }
                  final routes = item['route'] as List?;
                  if (routes != null) {
                    for (final r in routes) {
                      if (r is Map && r['nexthop'] != null) {
                        wanIps.add(r['nexthop'].toString());
                      }
                    }
                  }
                }
              }
            }
          }
        }
      } catch (_) {}

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
          final nudState = parts.last.toUpperCase();
          final llIdx = parts.indexOf('lladdr');
          if (llIdx >= 0 && llIdx + 1 < parts.length) {
            mac = parts[llIdx + 1];
          }
          if (mac == null || !mac.contains(':')) continue;
          if (mac == '00:00:00:00:00:00') continue;
          final norm = normMac(mac);
          final devLower = dev.toLowerCase();
          final isWanNeigh =
              wanDevices.contains(devLower) ||
              devLower.startsWith('wan') ||
              devLower.startsWith('wwan') ||
              devLower.contains('wan');
          if (isWanNeigh) {
            wanMacs.add(norm);
            wanIps.add(ip);
            continue;
          }
          list.add({
            'ipaddr': ip,
            'macaddr': norm,
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
            await execRouterCmd('/sbin/ip', ['-4', 'neigh', 'show']) ??
            await execRouterCmd('ip', ['-4', 'neigh', 'show']) ??
            await execRouterCmd('ip', ['neigh', 'show']);
        final neighV6Str =
            await execRouterCmd('/sbin/ip', ['-6', 'neigh', 'show']) ??
            await execRouterCmd('ip', ['-6', 'neigh', 'show']);

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
            await execRouterCmd('/sbin/bridge', ['fdb', 'show']) ??
            await execRouterCmd('bridge', ['fdb', 'show']);
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
        if (fdbMacs.isEmpty) {
          // Fallback: BusyBox brctl showmacs for standard OpenWrt without iproute2-bridge
          final brctlStr =
              await execRouterCmd('/usr/sbin/brctl', ['showmacs', 'br-lan']) ??
              await execRouterCmd('brctl', ['showmacs', 'br-lan']);
          if (brctlStr != null && brctlStr.trim().isNotEmpty) {
            final macRegex = RegExp(r'([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})');
            for (final line in brctlStr.split('\n')) {
              final lower = line.toLowerCase();
              if (lower.contains('yes')) {
                continue; // Skip router's own bridge ports (is local? yes)
              }
              final match = macRegex.firstMatch(line);
              if (match != null) {
                final m = match.group(0);
                if (m != null) fdbMacs.add(normMac(m));
              }
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
          final lastProbe = _lastNeighborProbeTime[router.id];
          final shouldProbe =
              lastProbe == null ||
              now.difference(lastProbe) >= kNeighborProbeInterval;

          if (shouldProbe && probeIps.isNotEmpty) {
            final cmd =
                'for ip in ${probeIps.join(' ')}; do ping -c 1 -W 1 \$ip >/dev/null 2>&1 & done; wait; ip neigh show';
            final probedNeighStr = await execRouterCmd('sh', ['-c', cmd]);
            if (probedNeighStr != null && probedNeighStr.trim().isNotEmpty) {
              neighClients.clear();
              neighClients.addAll(parseIpNeighOutput(probedNeighStr));
            }
            _lastNeighborProbeTime[router.id] = now;
          }
        } catch (e) {
          Logger.warning('Active neighbor probing failed: $e');
        }
      }

      // Fallback: /proc/net/arp
      if (!usedIpNeigh || neighClients.isEmpty) {
        try {
          final arpStr = await execRouterCmd('cat', ['/proc/net/arp']);
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
                  final norm = normMac(mac);
                  final devLower = dev.toLowerCase();
                  final isWanNeigh =
                      wanDevices.contains(devLower) ||
                      devLower.startsWith('wan') ||
                      devLower.startsWith('wwan') ||
                      devLower.contains('wan');
                  if (isWanNeigh) {
                    wanMacs.add(norm);
                    wanIps.add(ip);
                    continue;
                  }
                  neighClients.add({
                    'ipaddr': ip,
                    'macaddr': norm,
                    'device': dev,
                    'nud_state': 'UNKNOWN',
                  });
                }
              }
            }
          }
        } catch (_) {}
      }

      // 4. Fetch Host Hints dictionary (future pre-started above)
      final hostHints = await _hostHintsFuture;

      final routerIps = <String>{
        router.ipAddress,
        '127.0.0.1',
        '0.0.0.0',
        ...wanIps,
      };
      final routerMacs = <String>{};

      try {
        final devRes = await _deviceStatusFuture;
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

        final vitals = vitalsMap[macN];
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
          rxBytes: vitals?.rxBytes,
          txBytes: vitals?.txBytes,
          rxPackets: vitals?.rxPackets,
          txPackets: vitals?.txPackets,
          rxRate: vitals?.rxRate,
          txRate: vitals?.txRate,
          signalDbm: vitals?.signalDbm,
          noiseDbm: vitals?.noiseDbm,
          throughput: vitals?.throughput,
          rxSpeed: vitals?.rxSpeed,
          txSpeed: vitals?.txSpeed,
          connectedTime: vitals?.connectedTime,
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

        final cleanV6Addrs = v6Addrs
            .map((a) => a.split('/')[0].trim().toLowerCase())
            .where((a) => a.isNotEmpty)
            .toSet();

        String? matchedMac;
        if (macN.isNotEmpty) {
          matchedMac = macN;
        } else {
          // 1. Correlate with L3 neighbor table (neighClients) by IPv6 address
          if (cleanV6Addrs.isNotEmpty) {
            for (final n in neighClients) {
              final nIp = (n['ipaddr']?.toString() ?? '')
                  .split('/')[0]
                  .trim()
                  .toLowerCase();
              if (nIp.isNotEmpty && cleanV6Addrs.contains(nIp)) {
                final m = normMac(n['macaddr']?.toString() ?? '');
                if (m.isNotEmpty && m != 'N/A' && m != '00:00:00:00:00:00') {
                  matchedMac = m;
                  break;
                }
              }
            }
          }

          // 2. Correlate with hostHints['ip6addrs']
          if (matchedMac == null && cleanV6Addrs.isNotEmpty) {
            hostHints.forEach((hMac, info) {
              if (matchedMac != null) return;
              final hintV6 = info['ip6addrs'] as List?;
              if (hintV6 != null) {
                for (final v in hintV6) {
                  final cleanV = v
                      .toString()
                      .split('/')[0]
                      .trim()
                      .toLowerCase();
                  if (cleanV6Addrs.contains(cleanV)) {
                    matchedMac = normMac(hMac);
                    break;
                  }
                }
              }
            });
          }

          // 3. Correlate with existing clientMap entries' ipv6Addresses
          if (matchedMac == null && cleanV6Addrs.isNotEmpty) {
            for (final c in clientMap.values) {
              if (c.ipv6Addresses != null) {
                for (final v in c.ipv6Addresses!) {
                  final cleanV = v.split('/')[0].trim().toLowerCase();
                  if (cleanV6Addrs.contains(cleanV)) {
                    matchedMac = normMac(c.macAddress);
                    break;
                  }
                }
              }
              if (matchedMac != null) break;
            }
          }

          // 4. Fallback: match by hostname against hostHints
          if (matchedMac == null) {
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
        }

        final finalMac = matchedMac;
        if (finalMac != null && finalMac.isNotEmpty) {
          if (clientMap.containsKey(finalMac)) {
            final existing = clientMap[finalMac]!;
            final mergedV6 = <String>{
              ...?(existing.ipv6Addresses),
              ...v6Addrs,
            }.toList();
            final shouldUpdateName =
                hostname != null &&
                hostname.isNotEmpty &&
                hostname != '*' &&
                (existing.hostname.isEmpty ||
                    existing.hostname == 'Unknown' ||
                    existing.hostname == existing.macAddress ||
                    existing.hostname == normMac(existing.macAddress));
            clientMap[finalMac] = existing.copyWith(
              ipv6Addresses: mergedV6,
              hostname: shouldUpdateName ? hostname : existing.hostname,
            );
          } else {
            final isWireless = normalizedWireless.contains(finalMac);
            final staticName = hostHints[finalMac]?['staticLeaseName']
                ?.toString();
            final isStaticEntry = hostHints[finalMac]?['isStaticLease'] == true;
            final vitals = vitalsMap[finalMac];
            final resolvedNeighIp = neighClients
                .firstWhere(
                  (n) =>
                      normMac(n['macaddr'] as String? ?? '') == finalMac &&
                      !(n['ipaddr'] as String? ?? '').contains(':'),
                  orElse: () => <String, dynamic>{},
                )['ipaddr']
                ?.toString();
            clientMap[finalMac] = Client(
              ipAddress: resolvedNeighIp ?? 'N/A',
              macAddress: finalMac,
              hostname:
                  (hostname != null && hostname.isNotEmpty && hostname != '*')
                  ? hostname
                  : finalMac,
              connectionType: isWireless
                  ? ConnectionType.wireless
                  : ConnectionType.wired,
              ssid: macToSsidMap[finalMac],
              wirelessIface: macToIfaceMap[finalMac],
              staticLeaseName: staticName,
              isStaticLease: isStaticEntry,
              ipv6Addresses: v6Addrs,
              rxBytes: vitals?.rxBytes,
              txBytes: vitals?.txBytes,
              rxPackets: vitals?.rxPackets,
              txPackets: vitals?.txPackets,
              rxRate: vitals?.rxRate,
              txRate: vitals?.txRate,
              signalDbm: vitals?.signalDbm,
              noiseDbm: vitals?.noiseDbm,
              throughput: vitals?.throughput,
              rxSpeed: vitals?.rxSpeed,
              txSpeed: vitals?.txSpeed,
              connectedTime: vitals?.connectedTime,
            );
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
          final vitals = vitalsMap[macN];

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
            rxBytes: vitals?.rxBytes,
            txBytes: vitals?.txBytes,
            rxPackets: vitals?.rxPackets,
            txPackets: vitals?.txPackets,
            rxRate: vitals?.rxRate,
            txRate: vitals?.txRate,
            signalDbm: vitals?.signalDbm,
            noiseDbm: vitals?.noiseDbm,
            throughput: vitals?.throughput,
            rxSpeed: vitals?.rxSpeed,
            txSpeed: vitals?.txSpeed,
            connectedTime: vitals?.connectedTime,
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
          final vitals = vitalsMap[mac];

          clientMap[mac] =
              Client.fromWirelessStation(
                mac,
                ssid: resolvedSsid,
                wirelessIface: resolvedIface,
                isDumbApClient: isRouterDumbAp,
                apName: isRouterDumbAp ? router.displayName : null,
                rxBytes: vitals?.rxBytes,
                txBytes: vitals?.txBytes,
                rxPackets: vitals?.rxPackets,
                txPackets: vitals?.txPackets,
                rxRate: vitals?.rxRate,
                txRate: vitals?.txRate,
                signalDbm: vitals?.signalDbm,
                noiseDbm: vitals?.noiseDbm,
                throughput: vitals?.throughput,
                rxSpeed: vitals?.rxSpeed,
                txSpeed: vitals?.txSpeed,
                connectedTime: vitals?.connectedTime,
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
        final hasActiveLease = c.leaseTime != null && c.leaseTime! > 0;
        final isStaticLease =
            hostHints[macN]?['isStaticLease'] == true || c.isStaticLease;

        if (routerMacs.contains(macN) ||
            routerIps.contains(c.ipAddress) ||
            wanMacs.contains(macN) ||
            wanIps.contains(c.ipAddress)) {
          if (!hasActiveLease && !isStaticLease) {
            continue;
          }
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

        if (routerIps.contains(resolvedIp) || wanIps.contains(resolvedIp)) {
          if (!hasActiveLease && !isStaticLease) {
            continue;
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
          final isWanDev =
              wanDevices.contains(dev) ||
              dev.startsWith('wan') ||
              dev.startsWith('wwan') ||
              dev.contains('wan');
          if (!isWlanDev && !isWanDev) {
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
            _knownWirelessMacs.containsKey(macN) ||
            macToSsidMap.containsKey(macN) ||
            macToIfaceMap.containsKey(macN) ||
            normalizedWireless.contains(macN) ||
            c.connectionType == ConnectionType.wireless ||
            resolvedSsid != null ||
            resolvedIface != null;

        if (isWirelessClient) {
          _knownWirelessMacs[macN] = DateTime.now();
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
            final hasKnownIp =
                (resolvedIp != 'N/A' && resolvedIp.isNotEmpty) ||
                (c.ipv6Addresses != null && c.ipv6Addresses!.isNotEmpty);
            if ((hasActiveLease || isStaticLease || hasKnownIp) &&
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
          final isClientDumbAp = isRouterDumbAp;
          final clientApName = isClientDumbAp ? router.displayName : null;
          final vitals = vitalsMap[macN];
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
              rxBytes: c.rxBytes ?? vitals?.rxBytes,
              txBytes: c.txBytes ?? vitals?.txBytes,
              rxPackets: c.rxPackets ?? vitals?.rxPackets,
              txPackets: c.txPackets ?? vitals?.txPackets,
              rxRate: c.rxRate ?? vitals?.rxRate,
              txRate: c.txRate ?? vitals?.txRate,
              signalDbm: c.signalDbm ?? vitals?.signalDbm,
              noiseDbm: c.noiseDbm ?? vitals?.noiseDbm,
              throughput: c.throughput ?? vitals?.throughput,
              rxSpeed: c.rxSpeed ?? vitals?.rxSpeed,
              txSpeed: c.txSpeed ?? vitals?.txSpeed,
              connectedTime: c.connectedTime ?? vitals?.connectedTime,
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
