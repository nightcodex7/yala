// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yet_another_luci_app/modules/vpn_connectivity/models/vpn_info.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/models/storage_info.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/state/controllers/throughput_controller.dart';
import 'package:yet_another_luci_app/utils/http_client_manager.dart';
import 'package:yet_another_luci_app/utils/logger.dart';

/// Enum matching AppState connection status for reporting connection failures.
enum DashboardConnectionStatus { connected, reconnecting, disconnected }

/// Encapsulates central dashboard data aggregation, capability probing/caching,
/// router hardware capabilities detection, and multi-RPC parallel fetching.
///
/// Extracted from [AppState] to enforce single-responsibility.
class DashboardController {
  DashboardController({
    required IApiService? Function() apiServiceRef,
    required IAuthService? Function() authServiceRef,
    required RouterService? Function() routerServiceRef,
    required SecureStorageService Function() secureStorageServiceRef,
    required ThroughputController? Function() throughputControllerRef,
    required DashboardPreferences Function() dashboardPreferencesRef,
    required bool Function() reviewerModeRef,
    required Future<bool> Function({bool force, bool fetchDashboard})
    tryAutoLogin,
    required Future<void> Function() fetchPublicIps,
    required void Function(String v4, String v6) setPublicIps,
    required void Function(DashboardConnectionStatus status)
    setConnectionStatus,
    required void Function() startThroughputTimer,
    required void Function() updateThroughputOnly,
    required Map<String, dynamic> Function(Map<String, dynamic> rawDhcpData)
    processDhcpLeases,
    required VoidCallback notifyListeners,
  }) : _apiServiceRef = apiServiceRef,
       _authServiceRef = authServiceRef,
       _routerServiceRef = routerServiceRef,
       _secureStorageServiceRef = secureStorageServiceRef,
       _throughputControllerRef = throughputControllerRef,
       _dashboardPreferencesRef = dashboardPreferencesRef,
       _reviewerModeRef = reviewerModeRef,
       _tryAutoLogin = tryAutoLogin,
       _fetchPublicIps = fetchPublicIps,
       _setPublicIps = setPublicIps,
       _setConnectionStatus = setConnectionStatus,
       _startThroughputTimer = startThroughputTimer,
       _updateThroughputOnly = updateThroughputOnly,
       _processDhcpLeases = processDhcpLeases,
       _notifyListeners = notifyListeners;

  final IApiService? Function() _apiServiceRef;
  final IAuthService? Function() _authServiceRef;
  final RouterService? Function() _routerServiceRef;
  final SecureStorageService Function() _secureStorageServiceRef;
  final ThroughputController? Function() _throughputControllerRef;
  final DashboardPreferences Function() _dashboardPreferencesRef;
  final bool Function() _reviewerModeRef;
  final Future<bool> Function({bool force, bool fetchDashboard}) _tryAutoLogin;
  final Future<void> Function() _fetchPublicIps;
  final void Function(String v4, String v6) _setPublicIps;
  final void Function(DashboardConnectionStatus status) _setConnectionStatus;
  final void Function() _startThroughputTimer;
  final void Function() _updateThroughputOnly;
  final Map<String, dynamic> Function(Map<String, dynamic> rawDhcpData)
  _processDhcpLeases;
  final VoidCallback _notifyListeners;

  Map<String, dynamic>? _dashboardData;
  bool _isDashboardLoading = false;
  String? _dashboardError;
  RouterCapabilities? _capabilities;
  Future<void>? _activeFetchFuture;
  int _fetchEpoch = 0;

  Map<String, dynamic>? get dashboardData => _dashboardData;
  bool get isDashboardLoading => _isDashboardLoading;
  String? get dashboardError => _dashboardError;
  RouterCapabilities? get capabilities => _capabilities;

  IApiService? get _apiService => _apiServiceRef();
  IAuthService? get _authService => _authServiceRef();
  RouterService? get _routerService => _routerServiceRef();
  SecureStorageService get _secureStorageService => _secureStorageServiceRef();
  ThroughputController? get _throughputController => _throughputControllerRef();
  DashboardPreferences get _dashboardPreferences => _dashboardPreferencesRef();
  bool get _isReviewerMode => _reviewerModeRef();

  /// Resets cached dashboard state and capabilities (e.g. on logout/router change).
  void resetState() {
    _dashboardData = null;
    _capabilities = null;
    _dashboardError = null;
    _isDashboardLoading = false;
    _activeFetchFuture = null;
    _fetchEpoch++;
  }

  /// Updates system information in cached dashboard data (e.g. from throughput ticks).
  /// Only updates if boardInfo is already populated to avoid premature partial data.
  void updateSysInfo(Map<String, dynamic> sysInfoData) {
    if (_dashboardData != null && _dashboardData!.containsKey('boardInfo')) {
      _dashboardData!['sysInfo'] = sysInfoData;
    }
  }

  /// Action to re-detect capabilities for the active router
  Future<void> redetectCapabilities() async {
    await probeRouterCapabilities(forceRefresh: true);
  }

  /// Probe and cache actual ubus objects, methods, package manager engine, firewall backend, and network model.
  Future<RouterCapabilities> probeRouterCapabilities({
    bool forceRefresh = false,
  }) async {
    if (_isReviewerMode) {
      _capabilities = RouterCapabilities.mock();
      _notifyListeners();
      return _capabilities!;
    }

    if (_routerService?.selectedRouter == null ||
        _authService?.sysauth == null) {
      _capabilities = RouterCapabilities.conservative('unknown');
      return _capabilities!;
    }

    final routerId = _routerService!.selectedRouter!.id;
    final cacheKey = 'router_capabilities_$routerId';

    if (!forceRefresh) {
      try {
        final cachedJsonStr = await _secureStorageService.readValue(cacheKey);
        if (cachedJsonStr != null && cachedJsonStr.isNotEmpty) {
          final Map<String, dynamic> cachedMap = jsonDecode(cachedJsonStr);
          final cachedCaps = RouterCapabilities.fromJson(cachedMap);
          if (!cachedCaps.probeFailed &&
              DateTime.now().difference(cachedCaps.probedAt).inHours < 24) {
            _capabilities = cachedCaps;
            Logger.info('Loaded router capabilities from cache for $routerId');
            _notifyListeners();
            return _capabilities!;
          }
        }
      } catch (e) {
        Logger.warning('Failed to load cached router capabilities: $e');
      }
    }

    final ip = _routerService!.selectedRouter!.ipAddress;
    final String sysauth = _authService?.sysauth ?? '';
    if (sysauth.isEmpty && !_isReviewerMode) {
      return _capabilities ??
          RouterCapabilities.conservative('unauthenticated');
    }
    final useHttps = _routerService!.selectedRouter!.useHttps;

    // Silently ensure ACL rules exist on router in the background without prompting user
    if (sysauth.isNotEmpty) {
      unawaited(_apiService!.ensureSilentPermissions(ip, sysauth, useHttps));
    }

    final ubusObjects = <String>{};
    final ubusMethods = <String, List<String>>{};
    PackageManagerEngine pkgEngine = PackageManagerEngine.opkg;
    FirewallBackend fwBackend = FirewallBackend.fw4;
    NetworkModel netModel = NetworkModel.dsa;
    String releaseVer = '';
    String board = '';
    bool probeFailed = false;
    String? probeError;
    Map<String, dynamic> featuresData = {};

    try {
      // 1. Probe available ubus objects and methods via direct lightweight RPC queries
      try {
        final sysInfo = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'system',
          method: 'info',
        );
        if (sysInfo != null) ubusObjects.add('system');
      } catch (_) {}

      try {
        final uciRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'get',
          params: {'config': 'system'},
        );
        if (uciRes != null) ubusObjects.add('uci');
      } catch (_) {}

      try {
        final fileRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {'command': 'true'},
        );
        if (fileRes is List && fileRes.isNotEmpty && fileRes[0] == 0) {
          ubusObjects.add('file');
          ubusMethods['file'] = ['exec', 'read', 'stat'];
        }
      } catch (_) {}

      try {
        final iwinfoRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'iwinfo',
          method: 'devices',
        );
        if (iwinfoRes != null) {
          ubusObjects.add('iwinfo');
          ubusObjects.add('luci-rpc');
        }
      } catch (_) {}

      try {
        final rcRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'rc',
          method: 'list',
        );
        if (rcRes != null) ubusObjects.add('rc');
      } catch (_) {}

      try {
        final featuresRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'luci',
          method: 'getFeatures',
        );
        if (featuresRes is List &&
            featuresRes.length > 1 &&
            featuresRes[0] == 0) {
          ubusObjects.add('luci');
          final data = featuresRes[1];
          if (data is Map) {
            featuresData = Map<String, dynamic>.from(data);
          }
        }
      } catch (_) {}

      // 2. Probe Package Manager engine: check /etc/apk vs /etc/opkg or ubus objects
      try {
        if (featuresData['apk'] == true || ubusObjects.contains('apk')) {
          pkgEngine = PackageManagerEngine.apk;
        } else if (featuresData['opkg'] == true ||
            ubusObjects.contains('opkg')) {
          pkgEngine = PackageManagerEngine.opkg;
        } else {
          final apkStat = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'file',
            method: 'stat',
            params: {'path': '/lib/apk/db/installed'},
          );
          if (apkStat is List && apkStat.length > 1 && apkStat[0] == 0) {
            pkgEngine = PackageManagerEngine.apk;
          } else {
            final opkgStat = await _apiService!.call(
              ip,
              sysauth,
              useHttps,
              object: 'file',
              method: 'stat',
              params: {'path': '/usr/lib/opkg/status'},
            );
            if (opkgStat is List && opkgStat.length > 1 && opkgStat[0] == 0) {
              pkgEngine = PackageManagerEngine.opkg;
            }
          }
        }
      } catch (e) {
        Logger.warning('Package engine probe failed: $e');
      }

      // 3. Probe Firewall backend (fw3 vs fw4)
      try {
        if (featuresData['firewall4'] == true || ubusObjects.contains('fw4')) {
          fwBackend = FirewallBackend.fw4;
        } else if (featuresData['firewall'] == true ||
            ubusObjects.contains('fw3')) {
          fwBackend = FirewallBackend.fw3;
        } else {
          final uciFw = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
          );
          if (uciFw is List && uciFw.length > 1 && uciFw[0] == 0) {
            final values = uciFw[1] as Map<String, dynamic>?;
            if (values != null && values.toString().contains('nftables')) {
              fwBackend = FirewallBackend.fw4;
            } else {
              fwBackend = FirewallBackend.fw3;
            }
          }
        }
      } catch (e) {
        Logger.warning('Firewall backend probe failed: $e');
      }

      // 4. Probe Network model (DSA vs swconfig)
      try {
        final uciNet = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'get',
          params: {'config': 'network'},
        );
        if (uciNet is List && uciNet.length > 1 && uciNet[0] == 0) {
          final values = uciNet[1] as Map<String, dynamic>?;
          if (values != null) {
            final strVal = values.toString();
            if (strVal.contains('switch_vlan') || strVal.contains('swconfig')) {
              netModel = NetworkModel.swconfig;
            } else {
              netModel = NetworkModel.dsa;
            }
          }
        }
      } catch (e) {
        Logger.warning('Network model probe failed: $e');
      }

      // 5. System board / release info
      try {
        final boardRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'system',
          method: 'board',
        );
        if (boardRes is List && boardRes.length > 1 && boardRes[0] == 0) {
          final bData = boardRes[1] as Map<String, dynamic>?;
          board =
              bData?['model']?.toString() ??
              bData?['hostname']?.toString() ??
              '';
          final release = bData?['release'] as Map<String, dynamic>?;
          releaseVer = release?['version']?.toString() ?? '';
        }
      } catch (e) {
        Logger.warning('Board probe failed: $e');
      }
    } catch (e) {
      probeFailed = true;
      probeError = e.toString();
      Logger.error('Router capability probe error: $e');
    }

    _capabilities = RouterCapabilities(
      routerId: routerId,
      ubusObjects: ubusObjects,
      ubusMethods: ubusMethods,
      packageEngine: pkgEngine,
      firewallBackend: fwBackend,
      networkModel: netModel,
      releaseVersion: releaseVer,
      boardName: board,
      probedAt: DateTime.now(),
      probeFailed: probeFailed,
      lastProbeError: probeError,
    );

    try {
      await _secureStorageService.writeValue(
        cacheKey,
        jsonEncode(_capabilities!.toJson()),
      );
    } catch (e) {
      Logger.warning('Failed to cache router capabilities: $e');
    }

    _notifyListeners();
    return _capabilities!;
  }

  /// Central method to fetch all dashboard data concurrently
  Future<void> fetchDashboardData({bool force = false}) {
    if (force) {
      _activeFetchFuture = null;
    }
    if (_activeFetchFuture != null) {
      return _activeFetchFuture!;
    }
    final future = _fetchDashboardDataInternal();
    _activeFetchFuture = future;
    return future.whenComplete(() {
      if (_activeFetchFuture == future) {
        _activeFetchFuture = null;
      }
    });
  }

  Future<void> _fetchDashboardDataInternal() async {
    if (_isReviewerMode) {
      _isDashboardLoading = true;
      _dashboardError = null;
      _notifyListeners();

      await probeRouterCapabilities();

      await Future.delayed(const Duration(milliseconds: 500));

      try {
        final results = await Future.wait([
          _apiService!.callSimple('system', 'board', {}),
          _apiService!.callSimple('system', 'info', {}),
          _apiService!.callSimple('network', 'device', {}),
          _apiService!.callSimple('network.interface', 'dump', {}),
          _apiService!.callSimple('wireless', 'devices', {}),
          _apiService!.callSimple('luci-rpc', 'getDHCPLeases', {}),
          _apiService!.callSimple('uci', 'get', {'config': 'wireless'}),
          _apiService!.callSimple('uci', 'get', {'config': 'network'}),
          _apiService!.callSimple('uci', 'get', {'config': 'dhcp'}),
          _apiService!.callSimple('uci', 'get', {'config': 'firewall'}),
          _apiService!.callSimple('service', 'list', {}),
          _apiService!.callSimple('rc', 'list', {}),
          _apiService!.callSimple('uci', 'get', {'config': 'openvpn'}),
          _apiService!.callSimple('uci', 'get', {'config': 'tailscale'}),
          _apiService!.callSimple('uci', 'get', {'config': 'nextdns'}),
          _apiService!.callSimple('uci', 'get', {'config': 'cloudflared'}),
          _apiService!.fetchAssociatedStations(),
          _apiService!.fetchWireGuardPeers(
            ipAddress: '192.168.1.1',
            sysauth: 'mock',
            useHttps: false,
            interface: 'wg0',
          ),
          _apiService!.callSimple('file', 'read', {
            'path': '/etc/crontabs/root',
          }),
        ]);

        dynamic getResData(dynamic res) {
          if (res is List && res.length > 1 && res[0] == 0) return res[1];
          if (res is Map) return res;
          return null;
        }

        final interfaceDump =
            getResData(results[3]) as Map<String, dynamic>? ?? {};
        final rawDhcpData =
            getResData(results[5]) as Map<String, dynamic>? ?? {};
        final processedDhcpData = _processDhcpLeases(rawDhcpData);
        final wirelessStations = results[16] as Map<String, Set<String>>? ?? {};
        final wireguardRaw = results[17];
        final cronRes = getResData(results[18]);
        final cronJobs = cronRes is Map && cronRes['data'] != null
            ? (cronRes['data'] as String).split('\n')
            : ['0 4 * * * /sbin/reboot', '*/15 * * * * /usr/bin/check_wan.sh'];

        final uciNetworkConfig = getResData(results[7]);
        final networkDevices = getResData(results[2]);
        final servicesData = getResData(results[10]);
        final initScriptsData = getResData(results[11]);
        final uciOpenvpnRaw = results[12];

        Map<String, dynamic>? liveWg;
        if (wireguardRaw is Map<String, dynamic>) {
          if (wireguardRaw.containsKey('peers') ||
              wireguardRaw.containsKey('public_key')) {
            liveWg = {
              wireguardRaw['interface']?.toString() ?? 'wg0': wireguardRaw,
            };
          } else {
            liveWg = wireguardRaw;
          }
        }

        final wireguardData = synthesizeWireGuardData(
          interfaceDump: interfaceDump,
          uciNetworkConfig: uciNetworkConfig,
          liveWireGuardData: liveWg,
        );

        final openvpnData = synthesizeOpenVpnData(
          uciOpenvpnRaw: uciOpenvpnRaw,
          interfaceDump: interfaceDump,
          networkDevices: networkDevices,
          servicesData: servicesData,
          initScriptsData: initScriptsData,
        );

        _dashboardData = {
          'boardInfo': getResData(results[0]),
          'sysInfo': getResData(results[1]),
          'networkDevices': networkDevices,
          'interfaceDump': interfaceDump,
          'wireless': getResData(results[4]),
          'wirelessStations': wirelessStations,
          'dhcpLeases': processedDhcpData,
          'uciWirelessConfig': getResData(results[6]),
          'uciNetworkConfig': uciNetworkConfig,
          'uciDhcpConfig': getResData(results[8]),
          'uciFirewallConfig': getResData(results[9]),
          'services': servicesData,
          'initScripts': initScriptsData,
          'openvpn': openvpnData,
          'tailscale': getResData(results[13]),
          'nextdns': getResData(results[14]),
          'cloudflared': getResData(results[15]),
          'wireguard': wireguardData,
          'cronJobs': cronJobs,
          'packageManager': PackageManagerEngine.opkg,
          'wan': extractWanData(interfaceDump),
          'mountPoints': [
            {
              'mount': '/',
              'device': '/dev/root',
              'fs': 'squashfs',
              'size': 131072,
              'used': 46080,
              'avail': 84992,
            },
            {
              'mount': '/overlay',
              'device': '/dev/mtdblock6',
              'fs': 'ext4',
              'size': 65536,
              'used': 16384,
              'avail': 49152,
            },
            {
              'mount': '/tmp',
              'device': 'tmpfs',
              'fs': 'tmpfs',
              'size': 262144,
              'used': 2048,
              'avail': 260096,
            },
          ],
          '_lastUpdated': DateTime.now().millisecondsSinceEpoch,
        };

        _setPublicIps('203.0.113.195', '2001:db8:85a3::8a2e:0370:7334');

        if (_throughputController != null) {
          final networkData = results[2][1] as Map<String, dynamic>?;
          final wanDeviceNames = {'eth0', 'wlan0', 'br-lan'};

          final prefs = _dashboardPreferences;
          final specificInterface =
              ThroughputController.resolveSpecificInterface(
                prefs,
                deviceNameResolver: (iface) => getDeviceNameForInterface(iface),
              );

          _throughputController!.updateThroughput(
            networkData,
            wanDeviceNames,
            specificInterface: specificInterface,
          );
        }

        _startThroughputTimer();

        Future.delayed(const Duration(milliseconds: 100), () {
          _updateThroughputOnly();
        });

        _isDashboardLoading = false;
        _notifyListeners();
      } catch (e) {
        _dashboardError = 'Failed to fetch dashboard data: $e';
        _isDashboardLoading = false;
        _notifyListeners();
      }
      return;
    }

    final currentEpoch = ++_fetchEpoch;
    final targetRouterId = _routerService?.selectedRouter?.id;

    if (_routerService?.selectedRouter == null ||
        _authService?.sysauth == null) {
      return;
    }

    if (_dashboardData == null) {
      _isDashboardLoading = true;
      _dashboardError = null;
      _notifyListeners();
    }

    await probeRouterCapabilities();

    // Yield to the event loop so the UI has a chance to render the loading state
    // and avoid dropping Choreographer frames when firing 20+ parallel requests.
    await Future.delayed(const Duration(milliseconds: 100));

    final ip = _routerService!.selectedRouter!.ipAddress;
    final useHttps = _routerService!.selectedRouter!.useHttps;

    try {
      Future<dynamic> callOptionalRpc({
        required String object,
        required String method,
        Map<String, dynamic>? params,
      }) async {
        try {
          final currentSysauth = _authService?.sysauth;
          if (currentSysauth == null || currentSysauth.isEmpty) {
            if (!_isReviewerMode) {
              throw Exception('No active sysauth token');
            }
          }
          return await _apiService!.call(
            ip,
            currentSysauth ?? '',
            useHttps,
            object: object,
            method: method,
            params: params,
          );
        } catch (e, stack) {
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('unauthenticated') ||
              errStr.contains('http 401') ||
              errStr.contains('invalid sysauth') ||
              errStr.contains('session expired') ||
              errStr.contains('no active sysauth token')) {
            Logger.warning('RPC $object.$method failed with auth error: $e');
            rethrow;
          } else {
            Logger.warning('Optional RPC $object.$method failed: $e');
            Logger.debug('Optional RPC $object.$method stack: $stack');
          }
          return null;
        }
      }

      dynamic getData(dynamic result) {
        if (result is List && result.length > 1) {
          if (result[0] == 0) {
            return result[1];
          } else {
            final errorMessage = result[1] is String
                ? result[1]
                : 'Unknown API Error';
            throw Exception(errorMessage);
          }
        }
        return result;
      }

      dynamic getOptionalData(dynamic result, String label) {
        try {
          return getData(result);
        } catch (e) {
          Logger.warning('Optional RPC $label returned error: $e');
          return null;
        }
      }

      final wirelessFuture = callOptionalRpc(
        object: 'luci-rpc',
        method: 'getWirelessDevices',
        params: {},
      );

      final uciWirelessFuture = callOptionalRpc(
        object: 'uci',
        method: 'get',
        params: {'config': 'wireless'},
      );

      final uciDhcpFuture = callOptionalRpc(
        object: 'uci',
        method: 'get',
        params: {'config': 'dhcp'},
      );

      final uciFirewallFuture = callOptionalRpc(
        object: 'uci',
        method: 'get',
        params: {'config': 'firewall'},
      );

      final uciOpenvpnFuture = callOptionalRpc(
        object: 'uci',
        method: 'get',
        params: {'config': 'openvpn'},
      );

      final uciTailscaleFuture = callOptionalRpc(
        object: 'uci',
        method: 'get',
        params: {'config': 'tailscale'},
      );

      final uciNetworkFuture = callOptionalRpc(
        object: 'uci',
        method: 'get',
        params: {'config': 'network'},
      );

      Future<dynamic> fetchTailscaleExecData() async {
        try {
          // Attempt 1: /usr/sbin/tailscale status --json
          final res1 = await callOptionalRpc(
            object: 'file',
            method: 'exec',
            params: {
              'command': '/usr/sbin/tailscale',
              'params': ['status', '--json'],
              'args': ['status', '--json'],
            },
          );
          final data1 = getOptionalData(res1, 'file.exec.tailscale1');
          if (data1 is Map &&
              data1['stdout'] is String &&
              (data1['stdout'] as String).trim().isNotEmpty) {
            return data1;
          }

          // Attempt 2: /usr/bin/tailscale status --json
          final res2 = await callOptionalRpc(
            object: 'file',
            method: 'exec',
            params: {
              'command': '/usr/bin/tailscale',
              'params': ['status', '--json'],
              'args': ['status', '--json'],
            },
          );
          final data2 = getOptionalData(res2, 'file.exec.tailscale2');
          if (data2 is Map &&
              data2['stdout'] is String &&
              (data2['stdout'] as String).trim().isNotEmpty) {
            return data2;
          }

          // Attempt 3: tailscale status --json
          final res3 = await callOptionalRpc(
            object: 'file',
            method: 'exec',
            params: {
              'command': 'tailscale',
              'params': ['status', '--json'],
              'args': ['status', '--json'],
            },
          );
          final data3 = getOptionalData(res3, 'file.exec.tailscale3');
          if (data3 is Map &&
              data3['stdout'] is String &&
              (data3['stdout'] as String).trim().isNotEmpty) {
            return data3;
          }

          // Attempt 4: /usr/sbin/tailscale ip -4
          final res4 = await callOptionalRpc(
            object: 'file',
            method: 'exec',
            params: {
              'command': '/usr/sbin/tailscale',
              'params': ['ip', '-4'],
              'args': ['ip', '-4'],
            },
          );
          final data4 = getOptionalData(res4, 'file.exec.tailscale4');
          if (data4 is Map &&
              data4['stdout'] is String &&
              (data4['stdout'] as String).trim().isNotEmpty) {
            return data4;
          }
        } catch (_) {}
        return null;
      }

      final tailscaleExecFuture = fetchTailscaleExecData();

      final uciNextdnsFuture = callOptionalRpc(
        object: 'uci',
        method: 'get',
        params: {'config': 'nextdns'},
      );

      final uciCloudflaredFuture = callOptionalRpc(
        object: 'uci',
        method: 'get',
        params: {'config': 'cloudflared'},
      );

      final uciDdnsFuture = callOptionalRpc(
        object: 'uci',
        method: 'get',
        params: {'config': 'ddns'},
      );

      Future<dynamic> fetchCronData() async {
        try {
          final res1 = await callOptionalRpc(
            object: 'file',
            method: 'read',
            params: {'path': '/etc/crontabs/root'},
          );
          final data1 = getOptionalData(res1, 'file.read.cron');
          if (data1 is Map && data1['data'] != null) {
            return (data1['data'] as String).split('\n');
          }

          final res2 = await callOptionalRpc(
            object: 'file',
            method: 'exec',
            params: {
              'command': 'crontab',
              'params': ['-l'],
              'args': ['-l'],
            },
          );
          final data2 = getOptionalData(res2, 'file.exec.cron');
          if (data2 is Map && data2['stdout'] != null) {
            return (data2['stdout'] as String).split('\n');
          }
        } catch (_) {}
        return null;
      }

      Future<dynamic> fetchDhcpLeasesData() async {
        try {
          bool hasLeases(dynamic data) {
            if (data == null) return false;
            if (data is List) return data.isNotEmpty;
            if (data is Map) {
              final leases =
                  data['dhcp_leases'] ?? data['dhcpLeases'] ?? data['leases'];
              if (leases is List) return leases.isNotEmpty;
              if (data['data'] != null || data['stdout'] != null) {
                final str = (data['data'] ?? data['stdout']).toString().trim();
                return str.isNotEmpty;
              }
              return data.isNotEmpty;
            }
            return false;
          }

          final res1 = await callOptionalRpc(
            object: 'luci-rpc',
            method: 'getDHCPLeases',
            params: {},
          );
          final data1 = getOptionalData(res1, 'luci-rpc.getDHCPLeases');
          if (hasLeases(data1)) return data1;

          final leasePaths = [
            '/tmp/dhcp.leases',
            '/var/dhcp.leases',
            '/tmp/dnsmasq.leases',
            '/var/lib/misc/dnsmasq.leases',
          ];
          for (final path in leasePaths) {
            final resFile = await callOptionalRpc(
              object: 'file',
              method: 'read',
              params: {'path': path},
            );
            final dataFile = getOptionalData(resFile, 'file.read.$path');
            if (dataFile is Map && dataFile['data'] != null) {
              final processed = _processDhcpLeases(
                Map<String, dynamic>.from(dataFile),
              );
              if (hasLeases(processed)) return processed;
            }
          }

          if (data1 != null) return data1;
        } catch (_) {}
        return null;
      }

      final cronFuture = fetchCronData();
      final dhcpLeasesFuture = fetchDhcpLeasesData();

      final servicesFuture = callOptionalRpc(
        object: 'service',
        method: 'list',
        params: {},
      );

      final initScriptsFuture = callOptionalRpc(
        object: 'rc',
        method: 'list',
        params: {},
      );

      Future<dynamic> fetchStorageData() async {
        try {
          bool hasValidMounts(dynamic rawData) {
            if (rawData == null) return false;
            final overview = StorageOverview.fromRpcData(rawData);
            return overview.mountPoints.isNotEmpty;
          }

          Future<dynamic> safeCandidateCall({
            required String object,
            required String method,
            Map<String, dynamic>? params,
          }) async {
            try {
              return await callOptionalRpc(
                object: object,
                method: method,
                params: params,
              );
            } catch (e) {
              Logger.warning('Candidate RPC $object.$method failed: $e');
              return null;
            }
          }

          final res1 = await safeCandidateCall(
            object: 'luci-rpc',
            method: 'getMountPoints',
            params: {},
          );
          final data1 = getOptionalData(res1, 'luci-rpc.getMountPoints');
          if (hasValidMounts(data1)) return data1;

          final res2 = await safeCandidateCall(
            object: 'system',
            method: 'mounts',
            params: {},
          );
          final data2 = getOptionalData(res2, 'system.mounts');
          if (hasValidMounts(data2)) return data2;

          final res3 = await safeCandidateCall(
            object: 'luci',
            method: 'getMountPoints',
            params: {},
          );
          final data3 = getOptionalData(res3, 'luci.getMountPoints');
          if (hasValidMounts(data3)) return data3;

          final procMountPaths = [
            '/proc/mounts',
            '/proc/self/mounts',
            '/etc/mtab',
          ];
          for (final mountPath in procMountPaths) {
            final resProc = await callOptionalRpc(
              object: 'file',
              method: 'read',
              params: {'path': mountPath},
            );
            final dataProc = getOptionalData(resProc, 'file.read.$mountPath');
            if (dataProc is Map) {
              final fileData = dataProc['data']?.toString();
              if (hasValidMounts(fileData)) return fileData;
            }
          }

          final res4 = await callOptionalRpc(
            object: 'uci',
            method: 'get',
            params: {'config': 'fstab'},
          );
          final data4 = getOptionalData(res4, 'uci.get.fstab');
          if (hasValidMounts(data4)) return data4;

          final dfVariations = [
            {
              'command': 'df',
              'params': ['-k'],
              'args': ['-k'],
            },
            {
              'command': '/bin/df',
              'params': ['-k'],
              'args': ['-k'],
            },
            {
              'command': '/usr/bin/df',
              'params': ['-k'],
              'args': ['-k'],
            },
            {
              'command': 'df',
              'params': ['-h'],
              'args': ['-h'],
            },
            {
              'command': 'df',
              'params': ['-P'],
              'args': ['-P'],
            },
            {'command': 'df', 'params': <String>[], 'args': <String>[]},
            {
              'command': 'sh',
              'params': ['-c', 'df -k'],
              'args': ['-c', 'df -k'],
            },
            {
              'command': '/bin/sh',
              'params': ['-c', 'df -k'],
              'args': ['-c', 'df -k'],
            },
            {
              'command': 'cat',
              'params': ['/proc/mounts'],
              'args': ['/proc/mounts'],
            },
          ];

          for (final dfParams in dfVariations) {
            final resDf = await callOptionalRpc(
              object: 'file',
              method: 'exec',
              params: dfParams,
            );
            final dataDf = getOptionalData(resDf, 'file.exec.df');
            if (dataDf is Map) {
              final stdout = dataDf['stdout']?.toString();
              if (hasValidMounts(stdout)) return stdout;
            }
          }

          final resProc = await callOptionalRpc(
            object: 'file',
            method: 'read',
            params: {'path': '/proc/mounts'},
          );
          final dataProc = getOptionalData(resProc, 'file.read.mounts');
          if (dataProc is Map) {
            final fileData = dataProc['data']?.toString();
            if (hasValidMounts(fileData)) return fileData;
          }

          final resSelfProc = await callOptionalRpc(
            object: 'file',
            method: 'read',
            params: {'path': '/proc/self/mounts'},
          );
          final dataSelfProc = getOptionalData(
            resSelfProc,
            'file.read.selfmounts',
          );
          if (dataSelfProc is Map) {
            final fileData = dataSelfProc['data']?.toString();
            if (hasValidMounts(fileData)) return fileData;
          }

          final resMtab = await callOptionalRpc(
            object: 'file',
            method: 'read',
            params: {'path': '/etc/mtab'},
          );
          final dataMtab = getOptionalData(resMtab, 'file.read.mtab');
          if (dataMtab is Map) {
            final fileData = dataMtab['data']?.toString();
            if (hasValidMounts(fileData)) return fileData;
          }
        } catch (e) {
          Logger.warning('Storage data RPC error: $e');
        }
        return null;
      }

      final mountPointsFuture = fetchStorageData();

      final currentSysauth = _authService?.sysauth;
      if (currentSysauth == null || currentSysauth.isEmpty) {
        if (!_isReviewerMode) {
          Logger.warning(
            'fetchDashboardData aborted: no sysauth session token available',
          );
          return;
        }
      }
      final activeSysauth = currentSysauth ?? '';

      final results = await Future.wait([
        callOptionalRpc(object: 'system', method: 'board', params: {}),
        callOptionalRpc(object: 'system', method: 'info', params: {}),
        callOptionalRpc(
          object: 'luci-rpc',
          method: 'getNetworkDevices',
          params: {},
        ),
        callOptionalRpc(
          object: 'network.interface',
          method: 'dump',
          params: {},
        ),
      ]);

      final boardInfoData = getOptionalData(results[0], 'system.board');
      final sysInfoData = getOptionalData(results[1], 'system.info');
      if (!_isReviewerMode && boardInfoData == null && sysInfoData == null) {
        throw Exception(
          'Session expired or router unreachable: core system info failed',
        );
      }
      final networkData =
          getOptionalData(results[2], 'luci-rpc.getNetworkDevices')
              as Map<String, dynamic>?;
      final interfaceDump =
          getOptionalData(results[3], 'network.interface.dump')
              as Map<String, dynamic>?;

      final optionalResults = await Future.wait([
        wirelessFuture,
        uciWirelessFuture,
        uciDhcpFuture,
        uciFirewallFuture,
        servicesFuture,
        initScriptsFuture,
        mountPointsFuture,
        cronFuture,
        dhcpLeasesFuture,
        uciOpenvpnFuture,
        uciTailscaleFuture,
        uciNextdnsFuture,
        uciCloudflaredFuture,
        tailscaleExecFuture,
        uciDdnsFuture,
        uciNetworkFuture,
      ]);
      final wirelessRaw = optionalResults[0];
      final uciWirelessRaw = optionalResults[1];
      final uciDhcpRaw = optionalResults[2];
      final uciFirewallRaw = optionalResults[3];
      final servicesRaw = optionalResults[4];
      final initScriptsRaw = optionalResults[5];
      final mountPointsRaw = optionalResults[6];
      final cronRaw = optionalResults[7];
      final dhcpLeasesRaw = optionalResults[8];
      final uciOpenvpnRaw = optionalResults[9];
      final uciTailscaleRaw = optionalResults[10];
      final uciNextdnsRaw = optionalResults[11];
      final uciCloudflaredRaw = optionalResults[12];
      final tailscaleExecRaw = optionalResults[13];
      final uciDdnsRaw = optionalResults[14];
      final uciNetworkRaw = optionalResults[15];

      Map<String, dynamic>? wirelessData;
      if (wirelessRaw != null) {
        final parsedWireless = getOptionalData(
          wirelessRaw,
          'luci-rpc.getWirelessDevices',
        );
        if (parsedWireless is Map<String, dynamic>) {
          wirelessData = parsedWireless;
        }
      }

      dynamic uciWirelessConfig;
      if (uciWirelessRaw != null) {
        uciWirelessConfig = getOptionalData(uciWirelessRaw, 'uci.get wireless');
      }

      dynamic uciNetworkConfig;
      if (uciNetworkRaw != null) {
        uciNetworkConfig = getOptionalData(uciNetworkRaw, 'uci.get network');
      }

      dynamic uciDhcpConfig;
      if (uciDhcpRaw != null) {
        uciDhcpConfig = getOptionalData(uciDhcpRaw, 'uci.get dhcp');
      }

      dynamic uciFirewallConfig;
      if (uciFirewallRaw != null) {
        uciFirewallConfig = getOptionalData(uciFirewallRaw, 'uci.get firewall');
      }

      Map<String, dynamic>? tailscaleData;

      // 1. CLI status lookup via file.exec
      String? cliNodeName;
      String? cliTailscaleIp;
      String? cliState;
      bool cliIsRunning = false;
      bool cliConfigured = false;

      String? cliTailnet;
      String? cliMagicDns;
      int cliPeersCount = 0;
      bool cliIsExitNode = false;

      if (tailscaleExecRaw != null) {
        final parsedExec = tailscaleExecRaw is Map<String, dynamic>
            ? tailscaleExecRaw
            : (tailscaleExecRaw is Map
                  ? Map<String, dynamic>.from(tailscaleExecRaw)
                  : getOptionalData(tailscaleExecRaw, 'file.exec.tailscale'));

        if (parsedExec is Map<String, dynamic> &&
            parsedExec['stdout'] is String) {
          final stdoutStr = (parsedExec['stdout'] as String).trim();
          if (stdoutStr.isNotEmpty) {
            if (stdoutStr.startsWith('{')) {
              try {
                final jsonStatus =
                    jsonDecode(stdoutStr) as Map<String, dynamic>;
                cliState = jsonStatus['BackendState']?.toString();
                if (cliState != null && cliState.isNotEmpty) {
                  cliConfigured = true;
                  cliIsRunning = (cliState == 'Running');
                }
                final selfObj = jsonStatus['Self'] as Map<String, dynamic>?;
                if (selfObj != null) {
                  cliNodeName =
                      selfObj['HostName']?.toString() ??
                      selfObj['DNSName']?.toString();
                  cliIsExitNode =
                      selfObj['ExitNode'] == true ||
                      selfObj['ExitNodeOption'] == true;
                }
                cliMagicDns = jsonStatus['MagicDNSSuffix']?.toString();
                final tailnetObj = jsonStatus['CurrentTailnet'];
                if (tailnetObj is Map) {
                  cliTailnet = tailnetObj['Name']?.toString();
                }
                final peerObj = jsonStatus['Peer'];
                if (peerObj is Map) {
                  cliPeersCount = peerObj.length;
                }
                final ips = jsonStatus['TailscaleIPs'];
                if (ips is List && ips.isNotEmpty) {
                  final v4 = ips.firstWhere(
                    (ip) => !ip.toString().contains(':'),
                    orElse: () => ips.first,
                  );
                  cliTailscaleIp = v4.toString();
                }
              } catch (_) {}
            } else if (!stdoutStr.contains(' ')) {
              cliTailscaleIp = stdoutStr;
              cliConfigured = true;
              cliIsRunning = true;
            }
          }
        }
      }

      // 2. Service process manager lookup
      bool serviceIsRunning = false;
      bool serviceIsConfigured = false;
      final parsedServices = getOptionalData(servicesRaw, 'service.list');
      final parsedInit = getOptionalData(initScriptsRaw, 'rc.list');

      if (parsedServices is Map<String, dynamic> &&
          parsedServices.containsKey('tailscale')) {
        serviceIsConfigured = true;
        final sObj = parsedServices['tailscale'];
        if (sObj is Map && sObj['instances'] is Map) {
          final instances = sObj['instances'] as Map;
          if (instances.isNotEmpty) {
            serviceIsRunning = instances.values.any(
              (i) => i is Map && (i['running'] == true || i['running'] == 1),
            );
          }
        } else if (sObj is Map && sObj.containsKey('running')) {
          serviceIsRunning = sObj['running'] == true || sObj['running'] == 1;
        }
      }
      if (!serviceIsRunning &&
          parsedInit is Map<String, dynamic> &&
          parsedInit.containsKey('tailscale')) {
        final iObj = parsedInit['tailscale'];
        if (iObj is Map) {
          if (iObj.containsKey('running')) {
            serviceIsRunning = iObj['running'] == true || iObj['running'] == 1;
          }
          if (iObj.containsKey('enabled')) {
            if (iObj['enabled'] == true || iObj['enabled'] == 1) {
              serviceIsConfigured = true;
            }
          }
        }
      }

      // 3. UCI configuration lookup
      Map<String, dynamic>? uciSec;
      bool uciConfigured = false;
      bool uciEnabled = false;
      if (uciTailscaleRaw != null) {
        final parsedTailscale = getOptionalData(
          uciTailscaleRaw,
          'uci.get tailscale',
        );
        if (parsedTailscale is Map<String, dynamic>) {
          final values = parsedTailscale['values'] is Map<String, dynamic>
              ? parsedTailscale['values'] as Map<String, dynamic>
              : parsedTailscale;
          if (values.containsKey('settings')) {
            uciSec = values['settings'] as Map<String, dynamic>?;
          } else if (values.isNotEmpty) {
            uciSec =
                values.values.firstWhere(
                      (v) => v is Map<String, dynamic>,
                      orElse: () => null,
                    )
                    as Map<String, dynamic>?;
          }
          if (uciSec != null) {
            uciConfigured = true;
            uciEnabled = uciSec['enabled'] == '1' || uciSec['enabled'] == true;
          }
        }
      }

      final isTailscaleConfigured =
          cliConfigured || serviceIsConfigured || uciConfigured;
      final isTailscaleRunning = cliIsRunning || serviceIsRunning;

      if (isTailscaleConfigured || isTailscaleRunning) {
        final finalNodeName = (cliNodeName != null && cliNodeName.isNotEmpty)
            ? cliNodeName
            : (uciSec?['hostname']?.toString() ??
                  uciSec?['node_name']?.toString() ??
                  sysInfoData?['hostname']?.toString() ??
                  'OpenWrt-Router');

        final finalIp = (cliTailscaleIp != null && cliTailscaleIp.isNotEmpty)
            ? cliTailscaleIp
            : (uciSec?['ip']?.toString() ?? '');

        final finalState =
            cliState ??
            (isTailscaleRunning
                ? 'Running'
                : (uciEnabled ? 'Starting' : 'Stopped'));

        tailscaleData = {
          'configured': true,
          'enabled': isTailscaleRunning || uciEnabled,
          'running': isTailscaleRunning,
          'node_name': finalNodeName,
          'tailscale_ip': finalIp,
          'state': finalState,
          'tailnet': cliTailnet ?? '',
          'magic_dns': cliMagicDns ?? '',
          'peers_count': cliPeersCount,
          'is_exit_node': cliIsExitNode,
        };
      }

      Map<String, dynamic>? nextdnsData;
      if (uciNextdnsRaw != null) {
        final parsedNextdns = getOptionalData(uciNextdnsRaw, 'uci.get nextdns');
        if (parsedNextdns is Map<String, dynamic>) {
          final values = parsedNextdns['values'] is Map<String, dynamic>
              ? parsedNextdns['values'] as Map<String, dynamic>
              : parsedNextdns;
          Map<String, dynamic>? sec;
          if (values.containsKey('main')) {
            sec = values['main'] as Map<String, dynamic>?;
          } else if (values.isNotEmpty) {
            sec =
                values.values.firstWhere(
                      (v) => v is Map<String, dynamic>,
                      orElse: () => null,
                    )
                    as Map<String, dynamic>?;
          }
          if (sec != null) {
            final isEnabled = sec['enabled'] == '1' || sec['enabled'] == true;
            bool isRunning = isEnabled;

            final parsedServices = servicesRaw != null
                ? getOptionalData(servicesRaw, 'service.list')
                : null;
            final parsedInit = initScriptsRaw != null
                ? getOptionalData(initScriptsRaw, 'rc.list')
                : null;

            if (parsedServices is Map<String, dynamic> &&
                parsedServices.containsKey('nextdns')) {
              final sObj = parsedServices['nextdns'];
              if (sObj is Map && sObj['instances'] is Map) {
                final instances = sObj['instances'] as Map;
                if (instances.isNotEmpty) {
                  isRunning = instances.values.any(
                    (i) =>
                        i is Map && (i['running'] == true || i['running'] == 1),
                  );
                } else {
                  isRunning = false;
                }
              } else if (sObj is Map && sObj.containsKey('running')) {
                isRunning = sObj['running'] == true || sObj['running'] == 1;
              }
            } else if (parsedInit is Map<String, dynamic> &&
                parsedInit.containsKey('nextdns')) {
              final iObj = parsedInit['nextdns'];
              if (iObj is Map && iObj.containsKey('running')) {
                isRunning = iObj['running'] == true || iObj['running'] == 1;
              }
            }

            nextdnsData = {
              'configured': true,
              'enabled': isEnabled,
              'running': isRunning,
              'profile':
                  sec['profile']?.toString() ??
                  sec['profile_id']?.toString() ??
                  '',
              'report_client_info':
                  sec['report_client_info'] == '1' ||
                  sec['report_client_info'] == true,
            };
          }
        }
      }

      Map<String, dynamic>? cloudflaredData;
      if (uciCloudflaredRaw != null) {
        final parsedCf = getOptionalData(
          uciCloudflaredRaw,
          'uci.get cloudflared',
        );
        if (parsedCf is Map<String, dynamic>) {
          final values = parsedCf['values'] is Map<String, dynamic>
              ? parsedCf['values'] as Map<String, dynamic>
              : parsedCf;

          String foundTunnelId = '';
          String foundTunnelName = '';
          String foundToken = '';
          bool isEnabled = false;

          for (final entry in values.entries) {
            if (entry.value is! Map) continue;
            final secMap = Map<String, dynamic>.from(entry.value as Map);
            secMap['.name'] = entry.key;

            final secEnabled =
                secMap['enabled'] == '1' ||
                secMap['enabled'] == true ||
                secMap['enable'] == '1' ||
                secMap['enable'] == true;
            if (secEnabled) isEnabled = true;

            final secTunnelId = CloudflaredStatus.extractTunnelId(secMap);
            if (secTunnelId.isNotEmpty && secTunnelId != 'N/A') {
              foundTunnelId = secTunnelId;
            }

            final secName =
                secMap['tunnel_name']?.toString() ??
                secMap['name']?.toString() ??
                secMap['tunnel']?.toString() ??
                '';
            if (secName.isNotEmpty &&
                secName != foundTunnelId &&
                secName != 'config' &&
                secName != 'main' &&
                secName != 'global') {
              foundTunnelName = secName;
            }

            final secToken =
                secMap['token']?.toString() ??
                secMap['tunnel_token']?.toString() ??
                '';
            if (secToken.isNotEmpty) {
              foundToken = secToken;
            }
          }

          if (values.isNotEmpty) {
            bool isRunning = isEnabled;
            final parsedServices = servicesRaw != null
                ? getOptionalData(servicesRaw, 'service.list')
                : null;
            final parsedInit = initScriptsRaw != null
                ? getOptionalData(initScriptsRaw, 'rc.list')
                : null;

            if (parsedServices is Map<String, dynamic> &&
                parsedServices.containsKey('cloudflared')) {
              final sObj = parsedServices['cloudflared'];
              if (sObj is Map && sObj['instances'] is Map) {
                final instances = sObj['instances'] as Map;
                if (instances.isNotEmpty) {
                  isRunning = instances.values.any(
                    (i) =>
                        i is Map && (i['running'] == true || i['running'] == 1),
                  );
                } else {
                  isRunning = false;
                }
              } else if (sObj is Map && sObj.containsKey('running')) {
                isRunning = sObj['running'] == true || sObj['running'] == 1;
              }
            } else if (parsedInit is Map<String, dynamic> &&
                parsedInit.containsKey('cloudflared')) {
              final iObj = parsedInit['cloudflared'];
              if (iObj is Map && iObj.containsKey('running')) {
                isRunning = iObj['running'] == true || iObj['running'] == 1;
              }
            }

            cloudflaredData = {
              'configured': true,
              'enabled': isEnabled,
              'running': isRunning,
              'tunnel_id': foundTunnelId,
              'tunnel_name': foundTunnelName.isNotEmpty
                  ? foundTunnelName
                  : ((foundTunnelId.isNotEmpty && foundTunnelId != 'N/A')
                        ? 'Cloudflare Tunnel'
                        : ''),
              'token': foundToken,
              'connections': isRunning ? 4 : 0,
            };
          }
        }
      }

      dynamic servicesData;
      if (servicesRaw != null) {
        servicesData = getOptionalData(servicesRaw, 'service.list');
      }

      dynamic initScriptsData;
      if (initScriptsRaw != null) {
        initScriptsData = getOptionalData(initScriptsRaw, 'rc.list');
      }

      dynamic mountPointsData = mountPointsRaw;

      final pkgMgrType = _capabilities?.packageEngine.name ?? 'opkg';

      final openvpnData = synthesizeOpenVpnData(
        uciOpenvpnRaw: uciOpenvpnRaw,
        interfaceDump: interfaceDump,
        networkDevices: networkData,
        servicesData: servicesData,
        initScriptsData: initScriptsData,
      );

      bool hasWireGuard = false;
      if (interfaceDump != null && interfaceDump['interface'] is List) {
        hasWireGuard = (interfaceDump['interface'] as List).any((iface) {
          if (iface is Map<String, dynamic>) {
            final proto = iface['proto'] as String?;
            final dev = (iface['device'] ?? iface['l3_device']) as String?;
            return proto == 'wireguard' ||
                (dev != null && dev.toLowerCase().startsWith('wg'));
          }
          return false;
        });
      }
      if (!hasWireGuard && uciNetworkConfig is Map) {
        final uciValues = uciNetworkConfig['values'] is Map
            ? uciNetworkConfig['values'] as Map
            : uciNetworkConfig;
        hasWireGuard = uciValues.values.any((sec) {
          if (sec is Map) {
            return sec['proto'] == 'wireguard' ||
                sec['.type']?.toString().startsWith('wireguard') == true;
          }
          return false;
        });
      }

      Map<String, dynamic>? liveWireGuardData;
      if (hasWireGuard && _apiService != null) {
        try {
          liveWireGuardData = await _apiService!.fetchWireGuardPeers(
            ipAddress: ip,
            sysauth: activeSysauth,
            useHttps: useHttps,
            interface: '',
          );
        } catch (e) {
          Logger.warning('Failed to fetch live WireGuard peers: $e');
        }
      }

      final wireguardData = synthesizeWireGuardData(
        interfaceDump: interfaceDump,
        uciNetworkConfig: uciNetworkConfig,
        liveWireGuardData: liveWireGuardData,
      );

      final wanDeviceNames = <String>{};
      if (interfaceDump != null && interfaceDump['interface'] is List) {
        for (final interface in interfaceDump['interface']) {
          if (interface is Map<String, dynamic>) {
            final ifname = interface['interface'] as String?;
            if (ifname != null && ifname != 'loopback' && ifname != 'lo') {
              final device = interface['device'] as String?;
              final l3Device = interface['l3_device'] as String?;
              if (device != null) {
                wanDeviceNames.add(device);
              }
              if (l3Device != null && l3Device != device) {
                wanDeviceNames.add(l3Device);
              }
            }
          }
        }
      }

      final prefs = _dashboardPreferences;
      final specificInterface = ThroughputController.resolveSpecificInterface(
        prefs,
        deviceNameResolver: (iface) => getDeviceNameForInterface(iface),
      );

      _throughputController?.updateThroughput(
        networkData,
        wanDeviceNames,
        specificInterface: specificInterface,
      );

      final wirelessStationsMap = <String, dynamic>{};
      final wirelessDevs =
          wirelessData ??
          (uciWirelessConfig is Map<String, dynamic>
              ? uciWirelessConfig
              : null);
      final ifnamesToQuery = <String>{};

      if (wirelessDevs is Map<String, dynamic>) {
        wirelessDevs.forEach((k, v) {
          if (v is Map<String, dynamic>) {
            final ifaces = v['interfaces'];
            if (ifaces is List) {
              for (final ifc in ifaces) {
                if (ifc is Map<String, dynamic>) {
                  final name =
                      ifc['ifname']?.toString() ?? ifc['section']?.toString();
                  if (name != null && name.isNotEmpty) {
                    ifnamesToQuery.add(name);
                  }
                }
              }
            } else if (v['ifname'] != null) {
              ifnamesToQuery.add(v['ifname'].toString());
            }
          }
        });
      }

      try {
        final devRes = await callOptionalRpc(
          object: 'iwinfo',
          method: 'devices',
        );
        final devData = getOptionalData(devRes, 'iwinfo.devices');
        if (devData is List) {
          for (final item in devData) {
            if (item != null && item.toString().isNotEmpty) {
              ifnamesToQuery.add(item.toString());
            }
          }
        }
      } catch (_) {}

      if (interfaceDump is Map<String, dynamic> &&
          interfaceDump['interface'] is List) {
        for (final ifc in interfaceDump['interface']) {
          if (ifc is Map<String, dynamic>) {
            final dev =
                ifc['device']?.toString() ?? ifc['l3_device']?.toString();
            if (dev != null &&
                (dev.contains('wlan') ||
                    dev.contains('phy') ||
                    dev.contains('wifi') ||
                    dev.contains('ath') ||
                    dev.contains('ra'))) {
              ifnamesToQuery.add(dev);
            }
          }
        }
      }

      final assocResults = await Future.wait(
        ifnamesToQuery.map((ifname) async {
          try {
            final res = await callOptionalRpc(
              object: 'iwinfo',
              method: 'assoclist',
              params: {'device': ifname},
            );
            return MapEntry(
              ifname,
              getOptionalData(res, 'iwinfo.assoclist.$ifname'),
            );
          } catch (_) {
            return MapEntry(ifname, null);
          }
        }),
      );

      for (final entry in assocResults) {
        if (entry.value != null) {
          wirelessStationsMap[entry.key] = entry.value;
        }
      }

      Map<String, dynamic>? ddnsData;
      if (uciDdnsRaw != null) {
        final parsedDdns = getOptionalData(uciDdnsRaw, 'uci.get ddns');
        if (parsedDdns is Map<String, dynamic>) {
          final values = parsedDdns['values'] is Map<String, dynamic>
              ? parsedDdns['values'] as Map<String, dynamic>
              : parsedDdns;
          ddnsData = Map<String, dynamic>.from(values);
        }
      }

      if (currentEpoch != _fetchEpoch ||
          targetRouterId != _routerService?.selectedRouter?.id) {
        Logger.info(
          'Discarding stale dashboard data for router $targetRouterId',
        );
        return;
      }

      _dashboardData = {
        'boardInfo': boardInfoData,
        'sysInfo': sysInfoData,
        'networkDevices': networkData,
        'interfaceDump': interfaceDump,
        'wireless': wirelessData ?? <String, dynamic>{},
        'wirelessStations': wirelessStationsMap,
        'dhcpLeases': dhcpLeasesRaw,
        'wan': extractWanData(interfaceDump),
        'uciWirelessConfig': uciWirelessConfig,
        'uciNetworkConfig': uciNetworkConfig,
        'uciDhcpConfig': uciDhcpConfig,
        'uciFirewallConfig': uciFirewallConfig,
        'packageManager': pkgMgrType,
        'installedPackages': null,
        'availablePackages': null,
        'cronJobs': cronRaw,
        'services': servicesData,
        'initScripts': initScriptsData,
        'mountPoints': mountPointsData ?? sysInfoData,
        'wireguard': wireguardData,
        'openvpn': openvpnData,
        'tailscale': tailscaleData,
        'nextdns': nextdnsData,
        'cloudflared': cloudflaredData,
        'ddns': ddnsData,
        '_lastUpdated': DateTime.now().millisecondsSinceEpoch,
      };

      final boardInfo = _dashboardData?['boardInfo'] as Map<String, dynamic>?;
      final hostname = boardInfo?['hostname']?.toString();
      if (hostname != null && hostname.isNotEmpty) {
        await _routerService?.updateSelectedRouterHostname(hostname);
      }

      _startThroughputTimer();
      unawaited(_fetchPublicIps());

      Future.delayed(const Duration(milliseconds: 100), () {
        _updateThroughputOnly();
      });
    } catch (e) {
      if (currentEpoch != _fetchEpoch ||
          targetRouterId != _routerService?.selectedRouter?.id) {
        Logger.info(
          'Ignoring error from stale dashboard fetch for router $targetRouterId',
        );
        return;
      }

      _activeFetchFuture = null;
      if (!_isReviewerMode && _authService != null) {
        _setConnectionStatus(DashboardConnectionStatus.reconnecting);
        _notifyListeners();

        // Flush stale HTTP client socket pools on connection error to ensure fresh socket connection on active network interface
        HttpClientManager().disposeAll();

        bool reconnected = false;
        for (int attempt = 1; attempt <= 3; attempt++) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          if (currentEpoch != _fetchEpoch ||
              targetRouterId != _routerService?.selectedRouter?.id) {
            return;
          }
          try {
            final autoLoginSuccess = await _tryAutoLogin(
              force: true,
              fetchDashboard: false,
            );
            if (autoLoginSuccess) {
              reconnected = true;
              break;
            }
          } catch (_) {}
        }

        if (reconnected) {
          if (currentEpoch != _fetchEpoch ||
              targetRouterId != _routerService?.selectedRouter?.id) {
            return;
          }
          _setConnectionStatus(DashboardConnectionStatus.connected);
          _dashboardError = null;
          _isDashboardLoading = false;
          _notifyListeners();
          unawaited(fetchDashboardData(force: true));
          return;
        }
      }

      if (currentEpoch != _fetchEpoch ||
          targetRouterId != _routerService?.selectedRouter?.id) {
        return;
      }
      _setConnectionStatus(DashboardConnectionStatus.disconnected);
      final errorMessage = e.toString();
      if (errorMessage.contains('Access denied')) {
        _dashboardError = 'Access Denied: Check RPC permissions for this user.';
      } else {
        _dashboardError = 'Failed to fetch dashboard data: $e';
      }
      // Preserve cached _dashboardData if present so existing UI components remain populated during temporary network interruptions
    } finally {
      if (currentEpoch == _fetchEpoch &&
          targetRouterId == _routerService?.selectedRouter?.id) {
        _isDashboardLoading = false;
        _notifyListeners();
      }
    }
  }

  /// Maps an interface name to its actual Linux device name (e.g. eth0, br-lan)
  String? getDeviceNameForInterface(String interfaceName) {
    if (interfaceName.contains('(')) {
      final match = RegExp(r'\(([^)]+)\)').firstMatch(interfaceName);
      return match?.group(1);
    }

    final interfaceDump =
        _dashboardData?['interfaceDump'] as Map<String, dynamic>?;
    if (interfaceDump != null && interfaceDump['interface'] is List) {
      for (final interface in interfaceDump['interface']) {
        if (interface is Map<String, dynamic>) {
          final ifname = interface['interface'] as String?;
          if (ifname == interfaceName) {
            final l3Dev = interface['l3_device'] as String?;
            final dev = interface['device'] as String?;
            if (l3Dev != null && l3Dev.isNotEmpty && !l3Dev.startsWith('@')) {
              return l3Dev;
            }
            if (dev != null && dev.isNotEmpty && !dev.startsWith('@')) {
              return dev;
            }
            final fallback = l3Dev ?? dev;
            if (fallback != null && fallback.isNotEmpty) {
              return fallback;
            }
          }
        }
      }
    }

    // Smart fallbacks for common OpenWrt logical interface names
    if (interfaceName == 'lan') return 'br-lan';
    if (interfaceName == 'wan') return 'eth0';

    return interfaceName;
  }

  static Map<String, dynamic>? extractWanData(
    Map<String, dynamic>? interfaceDump,
  ) {
    if (interfaceDump == null || interfaceDump['interface'] == null) {
      return null;
    }
    try {
      for (var interface in interfaceDump['interface']) {
        if (interface['route'] is List) {
          for (var route in interface['route']) {
            if (route is Map &&
                route['target'] == '0.0.0.0' &&
                route['mask'] == 0) {
              return interface;
            }
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Multi-source synthesis of WireGuard interfaces and peers from interfaceDump,
  /// UCI network configuration, and live LuCI WireGuard stats.
  static Map<String, dynamic> synthesizeWireGuardData({
    required dynamic interfaceDump,
    required dynamic uciNetworkConfig,
    Map<String, dynamic>? liveWireGuardData,
  }) {
    final wireguardData = <String, Map<String, dynamic>>{};

    // 1. Scan interfaceDump for WireGuard interfaces
    List<dynamic>? interfaces;
    if (interfaceDump is Map && interfaceDump['interface'] is List) {
      interfaces = interfaceDump['interface'] as List;
    } else if (interfaceDump is List) {
      interfaces = interfaceDump;
    }

    if (interfaces != null) {
      for (final item in interfaces) {
        if (item is Map<String, dynamic>) {
          final ifname = item['interface']?.toString() ?? '';
          final proto = item['proto']?.toString().toLowerCase() ?? '';
          final dev =
              (item['device'] ?? item['l3_device'])?.toString() ?? ifname;
          final isUp =
              item['up'] == true || item['up'] == 1 || item['up'] == '1';

          if (ifname.isNotEmpty &&
              (proto == 'wireguard' || dev.toLowerCase().startsWith('wg'))) {
            wireguardData[ifname] = {
              'interface': ifname,
              'device': dev,
              'public_key': '',
              'listen_port': 51820,
              'up': isUp,
              'peers': <String, dynamic>{},
            };
          }
        }
      }
    }

    // 2. Scan UCI network configuration for interface and peer sections
    if (uciNetworkConfig is Map) {
      final uciValues = uciNetworkConfig['values'] is Map
          ? uciNetworkConfig['values'] as Map
          : uciNetworkConfig;

      // 2a. Identify WireGuard interface sections
      uciValues.forEach((secName, sec) {
        if (sec is Map) {
          final proto = sec['proto']?.toString().toLowerCase();
          if (proto == 'wireguard') {
            final name = sec['.name']?.toString() ?? secName.toString();
            final dev = sec['device']?.toString() ?? name;
            final listenPort =
                int.tryParse(sec['listen_port']?.toString() ?? '') ?? 51820;

            if (wireguardData.containsKey(name)) {
              if (sec['listen_port'] != null) {
                wireguardData[name]!['listen_port'] = listenPort;
              }
            } else {
              wireguardData[name] = {
                'interface': name,
                'device': dev,
                'public_key': '',
                'listen_port': listenPort,
                'up': false,
                'peers': <String, dynamic>{},
              };
            }
          }
        }
      });

      // 2b. Identify WireGuard peer sections
      uciValues.forEach((secName, sec) {
        if (sec is Map) {
          final type = sec['.type']?.toString() ?? '';
          final pubKey = sec['public_key']?.toString();
          final isPeerSection =
              type.startsWith('wireguard_') ||
              type == 'wireguard_peer' ||
              (pubKey != null && pubKey.isNotEmpty);

          if (isPeerSection && pubKey != null && pubKey.isNotEmpty) {
            String targetIface = '';
            if (sec['interface'] != null) {
              targetIface = sec['interface'].toString();
            } else if (type.startsWith('wireguard_') &&
                type != 'wireguard_peer') {
              targetIface = type.substring('wireguard_'.length);
            } else if (wireguardData.length == 1) {
              targetIface = wireguardData.keys.first;
            } else if (wireguardData.isNotEmpty) {
              targetIface = wireguardData.keys.first;
            } else {
              targetIface = 'wg0';
            }

            if (!wireguardData.containsKey(targetIface)) {
              wireguardData[targetIface] = {
                'interface': targetIface,
                'device': targetIface,
                'public_key': '',
                'listen_port': 51820,
                'up': false,
                'peers': <String, dynamic>{},
              };
            }

            final endpointHost = sec['endpoint_host']?.toString() ?? '';
            final endpointPort = sec['endpoint_port']?.toString();
            final endpoint = endpointHost.isNotEmpty
                ? (endpointPort != null
                      ? '$endpointHost:$endpointPort'
                      : endpointHost)
                : 'N/A';

            final allowedIps = <String>[];
            final rawAllowed = sec['allowed_ips'];
            if (rawAllowed is List) {
              allowedIps.addAll(rawAllowed.map((e) => e.toString()));
            } else if (rawAllowed != null) {
              allowedIps.add(rawAllowed.toString());
            }

            final peers =
                wireguardData[targetIface]!['peers'] as Map<String, dynamic>;
            peers[pubKey] = {
              'public_key': pubKey,
              'endpoint': endpoint,
              'allowed_ips': allowedIps,
              'last_handshake': 0,
              'rx_bytes': 0,
              'tx_bytes': 0,
            };
          }
        }
      });
    }

    // 3. Merge live stats if available
    if (liveWireGuardData != null && liveWireGuardData.isNotEmpty) {
      liveWireGuardData.forEach((liveKey, liveVal) {
        if (liveVal is Map<String, dynamic>) {
          String? matchedKey;
          if (wireguardData.containsKey(liveKey)) {
            matchedKey = liveKey;
          } else {
            for (final entry in wireguardData.entries) {
              if (entry.value['device'] == liveKey ||
                  (liveVal['device'] != null &&
                      entry.value['device'] == liveVal['device']) ||
                  (liveVal['interface'] != null &&
                      entry.key == liveVal['interface'])) {
                matchedKey = entry.key;
                break;
              }
            }
          }

          if (matchedKey == null) {
            matchedKey = liveKey;
            wireguardData[matchedKey] = Map<String, dynamic>.from(liveVal);
          } else {
            final ifaceMap = wireguardData[matchedKey]!;
            if (liveVal['public_key'] != null &&
                liveVal['public_key'].toString().isNotEmpty) {
              ifaceMap['public_key'] = liveVal['public_key'];
            }
            if (liveVal['listen_port'] != null) {
              ifaceMap['listen_port'] = liveVal['listen_port'];
            }
            if (liveVal['up'] != null) {
              ifaceMap['up'] =
                  liveVal['up'] == true ||
                  liveVal['up'] == 1 ||
                  liveVal['up'] == '1';
            }

            final livePeers = liveVal['peers'];
            final existingPeers = ifaceMap['peers'] as Map<String, dynamic>;
            if (livePeers is Map<String, dynamic>) {
              livePeers.forEach((pKey, pVal) {
                if (pVal is Map<String, dynamic>) {
                  if (existingPeers.containsKey(pKey)) {
                    final pExisting =
                        existingPeers[pKey] as Map<String, dynamic>;
                    if (pVal['endpoint'] != null && pVal['endpoint'] != 'N/A') {
                      pExisting['endpoint'] = pVal['endpoint'];
                    }
                    if (pVal['last_handshake'] != null &&
                        pVal['last_handshake'] != 0) {
                      pExisting['last_handshake'] = pVal['last_handshake'];
                    }
                    pExisting['rx_bytes'] =
                        pVal['rx_bytes'] ?? pExisting['rx_bytes'] ?? 0;
                    pExisting['tx_bytes'] =
                        pVal['tx_bytes'] ?? pExisting['tx_bytes'] ?? 0;
                    if (pVal['allowed_ips'] is List &&
                        (pVal['allowed_ips'] as List).isNotEmpty) {
                      pExisting['allowed_ips'] = pVal['allowed_ips'];
                    }
                  } else {
                    existingPeers[pKey] = Map<String, dynamic>.from(pVal);
                  }
                }
              });
            }
          }
        }
      });
    }

    return wireguardData;
  }

  /// Multi-source synthesis of OpenVPN instances, computing runtime status
  /// from network devices, interfaceDump, and service states.
  static Map<String, dynamic> synthesizeOpenVpnData({
    required dynamic uciOpenvpnRaw,
    required dynamic interfaceDump,
    required dynamic networkDevices,
    required dynamic servicesData,
    required dynamic initScriptsData,
  }) {
    final openvpnData = <String, Map<String, dynamic>>{};

    // 1. Gather all UP network devices
    final activeDevices = <String>{};
    if (interfaceDump is Map && interfaceDump['interface'] is List) {
      for (final iface in interfaceDump['interface'] as List) {
        if (iface is Map<String, dynamic>) {
          final isUp =
              iface['up'] == true || iface['up'] == 1 || iface['up'] == '1';
          if (isUp) {
            if (iface['device'] != null) {
              activeDevices.add(iface['device'].toString().toLowerCase());
            }
            if (iface['l3_device'] != null) {
              activeDevices.add(iface['l3_device'].toString().toLowerCase());
            }
            if (iface['interface'] != null) {
              activeDevices.add(iface['interface'].toString().toLowerCase());
            }
          }
        }
      }
    }
    if (networkDevices is Map<String, dynamic>) {
      networkDevices.forEach((devName, devInfo) {
        if (devInfo is Map<String, dynamic>) {
          final isUp =
              devInfo['up'] == true ||
              devInfo['up'] == 1 ||
              devInfo['up'] == '1';
          final flags = devInfo['flags'];
          final hasUpFlag = flags is List && flags.contains('UP');
          if (isUp || hasUpFlag) {
            activeDevices.add(devName.toLowerCase());
          }
        }
      });
    }

    final anyTunTapActive = activeDevices.any(
      (d) => d.startsWith('tun') || d.startsWith('tap'),
    );

    // 2. Check service status
    bool isServiceRunning = false;
    if (servicesData is Map<String, dynamic>) {
      final ovpnSvc = servicesData['openvpn'];
      if (ovpnSvc is Map &&
          (ovpnSvc['running'] == true || ovpnSvc['running'] == 1)) {
        isServiceRunning = true;
      }
    }

    // 3. Parse UCI openvpn config
    if (uciOpenvpnRaw != null) {
      dynamic parsedOpenvpn = uciOpenvpnRaw;
      if (parsedOpenvpn is List &&
          parsedOpenvpn.length > 1 &&
          parsedOpenvpn[0] == 0) {
        parsedOpenvpn = parsedOpenvpn[1];
      }
      if (parsedOpenvpn is Map<String, dynamic>) {
        final values = parsedOpenvpn['values'] is Map<String, dynamic>
            ? parsedOpenvpn['values'] as Map<String, dynamic>
            : parsedOpenvpn;

        values.forEach((name, sec) {
          if (sec is Map<String, dynamic>) {
            final type = sec['.type']?.toString();
            if (type == 'openvpn' || type == 'instance' || type == null) {
              final instanceMap = Map<String, dynamic>.from(sec);

              // Enabled by default unless explicitly disabled
              final enabledVal = instanceMap['enabled'];
              final disabledVal = instanceMap['disabled'];
              final isEnabled =
                  enabledVal != '0' &&
                  enabledVal != false &&
                  disabledVal != '1' &&
                  disabledVal != true;
              instanceMap['enabled'] = isEnabled ? '1' : '0';

              // Dynamic running check
              final dev = (instanceMap['dev'] ?? '').toString().toLowerCase();
              final nameLower = name.toLowerCase();
              final hasMatchingDevice =
                  dev.isNotEmpty && activeDevices.contains(dev);
              final hasMatchingName = activeDevices.contains(nameLower);

              final isRunning =
                  (instanceMap['running'] == true ||
                      instanceMap['running'] == 1) ||
                  hasMatchingDevice ||
                  hasMatchingName ||
                  (isEnabled && anyTunTapActive) ||
                  (isEnabled && isServiceRunning);

              instanceMap['running'] = isRunning;
              openvpnData[name] = instanceMap;
            }
          }
        });
      }
    }

    // 4. Scan interfaceDump for OpenVPN interfaces not configured in UCI
    if (interfaceDump is Map && interfaceDump['interface'] is List) {
      for (final iface in interfaceDump['interface'] as List) {
        if (iface is Map<String, dynamic>) {
          final proto = iface['proto']?.toString().toLowerCase() ?? '';
          final ifname = iface['interface']?.toString() ?? '';
          final dev =
              (iface['device'] ?? iface['l3_device'])
                  ?.toString()
                  .toLowerCase() ??
              '';
          final isUp =
              iface['up'] == true || iface['up'] == 1 || iface['up'] == '1';

          if (proto == 'openvpn' ||
              dev.startsWith('tun') ||
              dev.startsWith('tap') ||
              ifname.toLowerCase().contains('openvpn') ||
              ifname.toLowerCase().contains('ovpn')) {
            final key = ifname.isNotEmpty ? ifname : dev;
            if (key.isNotEmpty && !openvpnData.containsKey(key)) {
              openvpnData[key] = {
                '.type': 'openvpn',
                '.name': key,
                'dev': dev.isNotEmpty ? dev : 'tun',
                'proto': 'udp',
                'enabled': '1',
                'running': isUp,
              };
            }
          }
        }
      }
    }

    return openvpnData;
  }
}
