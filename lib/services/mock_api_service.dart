// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/modules/services_system/models/ddns_info.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_queue.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/internet_reachability.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/ping_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/traceroute_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/dns_lookup_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/routing_neighbor_info.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/diagnostic_report.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/flush_dns_result.dart';
import 'package:yet_another_luci_app/modules/bandwidth_monitor/models/bandwidth_data.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dnsmasq_service_result.dart';
import 'package:yet_another_luci_app/modules/log_viewer/models/log_entry.dart';
import 'package:yet_another_luci_app/modules/log_viewer/models/log_fetch_result.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/models/network_access_policy.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/modules/domain_blocking/models/domain_block_rule.dart';
import 'package:yet_another_luci_app/models/client_speed_limit.dart';

/// The four approved capability profiles for Reviewer Mode and test isolation.
enum MockCapabilityProfile {
  fullModernStack, // Profile A: fw4, IPv4 + IPv6, DSA, AGH, UCI write
  legacyConstrained, // Profile B: fw3, IPv4 only, swconfig, no AGH, UCI write
  readOnlyLuci, // Profile C: fw4, IPv4 + IPv6, UCI write access disabled
  constrainedFailure, // Profile D: fw4, missing optional RPC, simulated network timeout
}

class MockApiService implements IApiService {
  static final Random _random = Random();
  static PackageManagerEngine mockPackageEngine = PackageManagerEngine.opkg;
  static NetworkModel mockNetworkModel = NetworkModel.dsa;
  static int _baseUptime = 86400; // Base uptime of 1 day
  static int _baseRxBytes = 1234567890;
  static int _baseTxBytes = 987654321;
  static int _baseRxPackets = 12345;
  static int _baseTxPackets = 9876;
  static int _baseLanRxBytes = 2345678901;
  static int _baseLanTxBytes = 1876543210;
  static int _baseLanRxPackets = 23456;
  static int _baseLanTxPackets = 18765;
  static final Set<String> _mockRestrictedMacs = {'11:22:33:44:55:66'};
  static final Set<String> _mockBannedMacs = {'99:88:77:66:55:44'};
  static String _mockHostname = 'MockRouter';
  static MockCapabilityProfile activeProfile =
      MockCapabilityProfile.fullModernStack;
  static bool simulateRollbackFailure = false;
  static bool simulateVerificationFailure = false;
  static bool simulateRpcLossAfterApply = false;
  static Set<int> mockDiscoveredManagementPorts = {22, 80, 443};
  static final List<FirewallPortForwarding> _mockPortForwards = [];
  static final List<FirewallCustomRule> _mockCustomRules = [];
  static final Map<String, NetworkAccessPolicy> _mockPolicies = {};
  static final Map<String, ClientSpeedLimit> _mockSpeedLimits = {};
  static final Map<String, Map<String, ClientSpeedLimit>>
  _mockSpeedLimitsByRouter = {};
  static final Set<String> _mockDnsmasqBlockedDomains = {
    'ads.example.com',
    'tracker.sample.org',
  };
  static bool simulateDnsmasqFailure = false;
  static int getDnsmasqBlockedDomainsCallCount = 0;
  static int addDnsmasqBlockedDomainCallCount = 0;
  static int removeDnsmasqBlockedDomainCallCount = 0;

  static List<FirewallPortForwarding> get mockPortForwards =>
      List.unmodifiable(_mockPortForwards);
  static List<FirewallCustomRule> get mockCustomRules =>
      List.unmodifiable(_mockCustomRules);
  static NetworkAccessPolicy? getMockPolicy(String mac) =>
      _mockPolicies[ClientNamingHelper.normalizeMac(mac)];
  static ClientSpeedLimit? getMockSpeedLimit(String mac, {String? routerId}) {
    final normMac = ClientNamingHelper.normalizeMac(mac);
    if (routerId != null && _mockSpeedLimitsByRouter.containsKey(routerId)) {
      return _mockSpeedLimitsByRouter[routerId]![normMac];
    }
    return _mockSpeedLimits[normMac];
  }

  static Map<String, ClientSpeedLimit> getMockSpeedLimitsForRouter(
    String routerKey,
  ) {
    return Map.unmodifiable(_mockSpeedLimitsByRouter[routerKey] ?? {});
  }

  static Map<String, ClientSpeedLimit> get allMockSpeedLimits =>
      Map.unmodifiable(_mockSpeedLimits);

  static void resetMockState() {
    _mockHostname = 'MockRouter';
    resetMockFirewallState();
    resetMockDnsmasqState();
    _mockSpeedLimitsByRouter.clear();
    _mockSpeedLimits.clear();
  }

  static void resetMockDnsmasqState() {
    _mockDnsmasqBlockedDomains.clear();
    _mockDnsmasqBlockedDomains.addAll({
      'ads.example.com',
      'tracker.sample.org',
    });
    simulateDnsmasqFailure = false;
    getDnsmasqBlockedDomainsCallCount = 0;
    addDnsmasqBlockedDomainCallCount = 0;
    removeDnsmasqBlockedDomainCallCount = 0;
  }

  static void resetMockFirewallState() {
    _mockPortForwards.clear();
    _mockCustomRules.clear();
    _mockPolicies.clear();
    activeProfile = MockCapabilityProfile.fullModernStack;
    simulateRollbackFailure = false;
    simulateVerificationFailure = false;
    simulateRpcLossAfterApply = false;
    mockDiscoveredManagementPorts = {22, 80, 443};
    mockNetworkModel = NetworkModel.dsa;
    mockPackageEngine = PackageManagerEngine.opkg;
  }

  static void setMockProfile(MockCapabilityProfile profile) {
    activeProfile = profile;
    switch (profile) {
      case MockCapabilityProfile.fullModernStack:
        mockNetworkModel = NetworkModel.dsa;
        mockPackageEngine = PackageManagerEngine.opkg;
        simulateRollbackFailure = false;
        break;
      case MockCapabilityProfile.legacyConstrained:
        mockNetworkModel = NetworkModel.swconfig;
        mockPackageEngine = PackageManagerEngine.opkg;
        simulateRollbackFailure = false;
        break;
      case MockCapabilityProfile.readOnlyLuci:
        mockNetworkModel = NetworkModel.dsa;
        mockPackageEngine = PackageManagerEngine.opkg;
        simulateRollbackFailure = false;
        break;
      case MockCapabilityProfile.constrainedFailure:
        mockNetworkModel = NetworkModel.dsa;
        mockPackageEngine = PackageManagerEngine.none;
        simulateRollbackFailure = true;
        break;
    }
  }

  static RouterCapabilities getRouterCapabilitiesForProfile(
    MockCapabilityProfile profile, {
    String routerId = 'mock_router_id',
  }) {
    switch (profile) {
      case MockCapabilityProfile.fullModernStack:
        return RouterCapabilities(
          routerId: routerId,
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
            'uci': [
              'get',
              'set',
              'add',
              'delete',
              'commit',
              'apply',
              'confirm',
              'revert',
            ],
          },
          uciPermissions: const {
            '*': ['read', 'write'],
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
      case MockCapabilityProfile.legacyConstrained:
        return RouterCapabilities(
          routerId: routerId,
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
            'luci',
          },
          ubusMethods: const {
            'system': ['info', 'board'],
            'luci-rpc': ['getInitList', 'getWirelessDevices'],
            'luci': ['setPassword'],
            'file': ['read', 'stat', 'exec'],
            'uci': [
              'get',
              'set',
              'add',
              'delete',
              'commit',
              'apply',
              'confirm',
              'revert',
            ],
          },
          uciPermissions: const {
            '*': ['read', 'write'],
          },
          packageEngine: PackageManagerEngine.opkg,
          firewallBackend: FirewallBackend.fw3,
          networkModel: NetworkModel.swconfig,
          releaseVersion: 'OpenWrt 21.02.7',
          boardName: 'MediaTek MT7621',
          probedAt: DateTime.now(),
          probeFailed: false,
          hasAdGuardHome: false,
          hasOdhcpd: false,
          hasCron: true,
          hasDropbear: true,
          supportsIpv6InternetFirewall: false,
        );
      case MockCapabilityProfile.readOnlyLuci:
        return RouterCapabilities(
          routerId: routerId,
          ubusObjects: const {
            'system',
            'luci-rpc',
            'network.interface',
            'file',
            'uci',
          },
          ubusMethods: const {
            'system': ['info', 'board'],
            'file': ['read', 'stat'],
            'uci': ['get'],
          },
          uciPermissions: const {
            '*': ['read'],
          },
          packageEngine: PackageManagerEngine.opkg,
          firewallBackend: FirewallBackend.fw4,
          networkModel: NetworkModel.dsa,
          releaseVersion: 'OpenWrt 23.05.3',
          boardName: 'Generic x86',
          probedAt: DateTime.now(),
          probeFailed: false,
          hasAdGuardHome: false,
          hasOdhcpd: true,
          hasCron: false,
          hasDropbear: false,
          supportsIpv6InternetFirewall: true,
        );
      case MockCapabilityProfile.constrainedFailure:
        return RouterCapabilities(
          routerId: routerId,
          ubusObjects: const {'system'},
          ubusMethods: const {
            'system': ['info'],
          },
          uciPermissions: const {},
          packageEngine: PackageManagerEngine.none,
          firewallBackend: FirewallBackend.fw4,
          networkModel: NetworkModel.unknown,
          releaseVersion: 'OpenWrt Unknown',
          boardName: 'Constrained Device',
          probedAt: DateTime.now(),
          probeFailed: true,
          lastProbeError: 'Simulated network timeout/failure',
          hasAdGuardHome: false,
          hasOdhcpd: false,
          hasCron: false,
          hasDropbear: false,
          supportsIpv6InternetFirewall: false,
        );
    }
  }

  @override
  Future<AuthResult> authenticate(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return AuthResult.success(
      'mock_sysauth_token_12345',
      actualUseHttps: useHttps,
    );
  }

  @override
  Future<String> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    final res = await authenticate(
      ipAddress,
      username,
      password,
      useHttps,
      context: context,
    );
    return res.token ?? 'mock_sysauth_token_12345';
  }

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    final endpointKey = '$object.$method';
    try {
      if (object == 'file' && method == 'read') {
        return _handleFileRead(params);
      }
      if (object == 'file' && method == 'exec') {
        final execRes = _handleFileExec(params);
        if (execRes != null) return execRes;
      }

      if (object == 'uci' && method == 'get') {
        final cfg = params?['config']?.toString();
        String? targetFile;
        if (cfg == 'network') {
          targetFile = mockNetworkModel == NetworkModel.swconfig
              ? 'uci_network_swconfig.json'
              : 'uci_network_dsa.json';
        } else if (cfg == 'wireless') {
          targetFile = 'uci_wireless.json';
        } else if (cfg == 'dhcp') {
          targetFile = 'uci_dhcp.json';
        } else if (cfg == 'firewall') {
          targetFile = activeProfile == MockCapabilityProfile.legacyConstrained
              ? 'uci_firewall_fw3.json'
              : 'uci_firewall_fw4.json';
        }
        if (targetFile != null) {
          try {
            final jsonString = await rootBundle.loadString(
              '${AppConfig.mockDataPath}$targetFile',
            );
            return [0, jsonDecode(jsonString)];
          } catch (_) {}
        }
      }

      // Return appropriate mock data based on object and method
      final mockDataFile = _getMockDataFile(object, method);

      if (mockDataFile != null) {
        try {
          final jsonString = await rootBundle.loadString(
            '${AppConfig.mockDataPath}$mockDataFile',
          );
          final jsonData = jsonDecode(jsonString);
          if (jsonData is Map && object == 'system' && method == 'board') {
            jsonData['hostname'] = _mockHostname;
          }
          return [0, jsonData]; // Wrap in standard RPC response format
        } catch (e) {
          // Log file loading error and fall back to default data
          debugPrint(
            'MockApiService: Failed to load mock data file "$mockDataFile" for endpoint "$endpointKey": $e',
          );
          return _getDefaultMockData(object, method);
        }
      }

      // No mock file mapped, use default data
      final defaultData = _getDefaultMockData(object, method);
      if (defaultData[1] is Map && (defaultData[1] as Map).isEmpty) {
        debugPrint(
          'MockApiService: No mock data available for endpoint "$endpointKey", returning empty response',
        );
      }
      return defaultData;
    } catch (e) {
      // Catch-all error handler
      debugPrint(
        'MockApiService: Unexpected error for endpoint "$endpointKey": $e',
      );
      return [1, 'Mock service error: $e']; // Return error response
    }
  }

  // Simplified call method for reviewer mode
  @override
  Future<dynamic> callSimple(
    String object,
    String method,
    Map<String, dynamic> params,
  ) async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(milliseconds: 200));

    final endpointKey = '$object.$method';

    try {
      if (object == 'file' && method == 'read') {
        return _handleFileRead(params);
      }
      if (object == 'file' && method == 'exec') {
        final execRes = _handleFileExec(params);
        if (execRes != null) return execRes;
      }

      if (object == 'file' && method == 'stat') {
        final path = params['path']?.toString() ?? '';
        if (path == '/etc/apk' ||
            path == '/etc/apk/repositories.d/distfeeds.list' ||
            path == '/etc/apk/repositories') {
          if (mockPackageEngine == PackageManagerEngine.apk) {
            return [
              0,
              {'type': 'directory', 'path': path},
            ];
          } else {
            return [
              1,
              {'error': 'No such file or directory'},
            ];
          }
        }
        if (path == '/etc/opkg' ||
            path == '/etc/opkg.conf' ||
            path == '/etc/opkg/distfeeds.conf') {
          if (mockPackageEngine == PackageManagerEngine.opkg) {
            return [
              0,
              {'type': 'directory', 'path': path},
            ];
          } else {
            return [
              1,
              {'error': 'No such file or directory'},
            ];
          }
        }
      }

      if (object == 'file' && method == 'exec') {
        final cmd = params['command']?.toString() ?? '';
        if (cmd == '/sbin/firstboot' ||
            cmd == 'firstboot' ||
            cmd == '/sbin/reboot' ||
            cmd == 'reboot') {
          return [
            0,
            {'code': 0, 'stdout': '', 'stderr': ''},
          ];
        }
        if (cmd == 'opkg') {
          if (mockPackageEngine == PackageManagerEngine.opkg) {
            return [
              0,
              {
                'code': 0,
                'stdout':
                    'luci-base - git-23.330\nwireguard-tools - 1.0.20210914-1\n',
                'stderr': '',
              },
            ];
          } else {
            return [
              0,
              {'code': 127, 'stdout': '', 'stderr': 'opkg: not found'},
            ];
          }
        }
        if (cmd == 'apk') {
          if (mockPackageEngine == PackageManagerEngine.apk) {
            return [
              0,
              {
                'code': 0,
                'stdout':
                    'luci-base-git-23.330\nwireguard-tools-1.0.20210914-1\n',
                'stderr': '',
              },
            ];
          } else {
            return [
              0,
              {'code': 127, 'stdout': '', 'stderr': 'apk: not found'},
            ];
          }
        }
      }

      if (object == 'uci' && method == 'get') {
        final cfg = params['config']?.toString();
        String? targetFile;
        if (cfg == 'network') {
          targetFile = mockNetworkModel == NetworkModel.swconfig
              ? 'uci_network_swconfig.json'
              : 'uci_network_dsa.json';
        } else if (cfg == 'wireless') {
          targetFile = 'uci_wireless.json';
        } else if (cfg == 'dhcp') {
          targetFile = 'uci_dhcp.json';
        } else if (cfg == 'firewall') {
          targetFile = activeProfile == MockCapabilityProfile.legacyConstrained
              ? 'uci_firewall_fw3.json'
              : 'uci_firewall_fw4.json';
        }
        if (targetFile != null) {
          try {
            final jsonString = await rootBundle.loadString(
              '${AppConfig.mockDataPath}$targetFile',
            );
            return [0, jsonDecode(jsonString)];
          } catch (_) {}
        }
      }

      // Return appropriate mock data based on object and method
      final mockDataFile = _getMockDataFile(object, method);

      if (mockDataFile != null) {
        try {
          final jsonString = await rootBundle.loadString(
            '${AppConfig.mockDataPath}$mockDataFile',
          );
          final jsonData = jsonDecode(jsonString);
          if (jsonData is Map && object == 'system' && method == 'board') {
            jsonData['hostname'] = _mockHostname;
          }
          return [0, jsonData]; // Wrap in standard RPC response format
        } catch (e) {
          // Log file loading error and fall back to default data
          debugPrint(
            'MockApiService: Failed to load mock data file "$mockDataFile" for endpoint "$endpointKey": $e',
          );
          return _getDefaultMockData(object, method);
        }
      }

      // No mock file mapped, use default data
      final defaultData = _getDefaultMockData(object, method);
      if (defaultData[1] is Map && (defaultData[1] as Map).isEmpty) {
        debugPrint(
          'MockApiService: No mock data available for endpoint "$endpointKey", returning empty response',
        );
      }
      return defaultData;
    } catch (e) {
      // Catch-all error handler
      debugPrint(
        'MockApiService: Unexpected error for endpoint "$endpointKey": $e',
      );
      return [1, 'Mock service error: $e']; // Return error response
    }
  }

  @override
  Future<bool> reboot(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(seconds: 1));
    // Mock reboot always succeeds
    return true;
  }

  @override
  Future<Map<String, Set<String>>> fetchAssociatedStations() async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final jsonString = await rootBundle.loadString(
        '${AppConfig.mockDataPath}associated_stations.json',
      );
      final jsonData = jsonDecode(jsonString);

      final result = <String, Set<String>>{};
      if (jsonData is Map<String, dynamic>) {
        jsonData.forEach((interface, stations) {
          if (stations is List) {
            result[interface] = stations.map((s) => s.toString()).toSet();
          }
        });
      }
      return result;
    } catch (e) {
      // Log error and return comprehensive default mock data
      // Make sure these MAC addresses match some of the DHCP lease MAC addresses
      debugPrint('MockApiService: Failed to load associated stations data: $e');
      return {
        'wlan0': {
          'aa:bb:cc:11:22:33',
          'aa:bb:cc:44:55:66',
          'aa:bb:cc:77:88:99',
          'bb:cc:dd:11:22:33',
          'bb:cc:dd:44:55:66',
          'bb:cc:dd:77:88:99',
        },
        'wlan1': {
          'aa:bb:cc:aa:bb:cc',
          'aa:bb:cc:dd:ee:ff',
          'aa:bb:cc:12:34:56',
          'bb:cc:dd:aa:bb:cc',
          'bb:cc:dd:dd:ee:ff',
          'aa:bb:cc:65:43:21',
        },
      };
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchWireGuardPeers({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final jsonString = await rootBundle.loadString(
        '${AppConfig.mockDataPath}wireguard_peers.json',
      );
      final jsonData = jsonDecode(jsonString);
      return jsonData as Map<String, dynamic>;
    } catch (e) {
      // Log error and return comprehensive default mock data
      debugPrint('MockApiService: Failed to load WireGuard peers data: $e');
      return {
        interface: {
          'interface': interface,
          'peers': {
            'peer_public_key_1': {
              'public_key': 'peer_public_key_1',
              'endpoint': '192.168.1.100:51820',
              'last_handshake':
                  _getVariedTimestamp() - _random.nextInt(300) - 30,
              'latest_handshake':
                  _getVariedTimestamp() - _random.nextInt(300) - 30,
              'transfer_rx': _random.nextInt(1000000),
              'rx_bytes': _random.nextInt(1000000),
              'transfer_tx': _random.nextInt(500000),
              'tx_bytes': _random.nextInt(500000),
              'persistent_keepalive': 25,
            },
            'peer_public_key_2': {
              'public_key': 'peer_public_key_2',
              'endpoint': '192.168.1.101:51820',
              'last_handshake':
                  _getVariedTimestamp() - _random.nextInt(600) - 60,
              'latest_handshake':
                  _getVariedTimestamp() - _random.nextInt(600) - 60,
              'transfer_rx': _random.nextInt(2000000),
              'rx_bytes': _random.nextInt(2000000),
              'transfer_tx': _random.nextInt(1000000),
              'tx_bytes': _random.nextInt(1000000),
              'persistent_keepalive': 0,
            },
          },
        },
      };
    }
  }

  // No HTTP client creation required for mock service when using Dio

  String? _getMockDataFile(String object, String method) {
    // Map object.method combinations to mock data files
    final key = '$object.$method';

    final mockFileMap = {
      'system.board': 'system_board.json',
      'system.info': 'system_info.json',
      // 'network.device': 'network_devices.json', // Use dynamic data for throughput
      'network.interface': 'interface_dump.json',
      'network.interface.dump': 'interface_dump.json',
      'wireless.devices': 'wireless_devices.json',
      'file.exec': 'dhcp_leases.json',
      'luci.wireguard.getWgInstances': 'wireguard_peers.json',
      'iwinfo.assoclist': 'associated_stations.json',
      'luci-rpc.getNetworkDevices': 'network_devices.json',
      'luci-rpc.getWirelessDevices': 'wireless_devices.json',
      'luci-rpc.getDHCPLeases': 'dhcp_leases.json',
    };

    return mockFileMap[key];
  }

  dynamic _getDefaultMockData(String object, String method) {
    // Return default mock data based on object and method
    switch ('$object.$method') {
      case 'rpc.list':
        final objs = <String, List<String>>{
          'system': ['info', 'board', 'reboot'],
          'luci-rpc': ['getInitList', 'getWirelessDevices', 'getDHCPLeases'],
          'network.interface': ['dump'],
          'wireless.devices': ['get'],
          'file': ['read', 'stat', 'exec'],
          'service': ['list'],
          'rc': ['list'],
          'uci': ['get', 'set', 'commit'],
          'fw4': ['get'],
        };
        if (mockPackageEngine == PackageManagerEngine.opkg) {
          objs['opkg'] = ['list', 'install', 'remove'];
        } else if (mockPackageEngine == PackageManagerEngine.apk) {
          objs['apk'] = ['list', 'add', 'del'];
        }
        return [0, objs];

      case 'system.board':
        return [
          0,
          {
            'hostname': _mockHostname,
            'model': 'Mock Router Model X',
            'release': {
              'distribution': 'OpenWrt',
              'version': '23.05.0',
              'revision': 'r23497-6637af95aa',
              'target': 'mock/generic',
              'description': 'OpenWrt 23.05.0 Mock',
            },
            'kernel': '5.15.134',
            'board_name': 'mock-router-x',
            'system': 'Mock System',
          },
        ];

      case 'system.info':
        final memory = _getVariedMemory();
        return [
          0,
          {
            'uptime': _getVariedUptime(),
            'load': _getVariedLoadAverages(),
            'memory': memory,
            'localtime': _getVariedTimestamp(),
          },
        ];

      case 'network.device':
        final wanStats = _getVariedNetworkStats('eth0');
        final lanStats = _getVariedNetworkStats('br-lan');
        return [
          0,
          {
            'eth0': {'device': 'eth0', 'up': true, 'stats': wanStats},
            'br-lan': {'device': 'br-lan', 'up': true, 'stats': lanStats},
          },
        ];

      case 'network.interface':
        return [
          0,
          [
            {
              'interface': 'wan',
              'up': true,
              'proto': 'dhcp',
              'ipv4-address': [
                {'address': '192.168.1.100', 'mask': 24},
              ],
              'ipv6-address': [],
              'device': 'eth0',
              'dns-server': ['8.8.8.8', '8.8.4.4'],
              'route': [
                {'target': '0.0.0.0', 'mask': 0, 'nexthop': '192.168.1.1'},
              ],
            },
            {
              'interface': 'lan',
              'up': true,
              'proto': 'static',
              'ipv4-address': [
                {'address': '192.168.10.1', 'mask': 24},
              ],
              'ipv6-address': [],
              'device': 'br-lan',
              'dns-server': [],
              'route': [],
            },
          ],
        ];

      case 'wireless.devices':
        return [
          0,
          {
            'radio0': {
              'up': true,
              'channel': 6,
              'frequency': 2437,
              'txpower': 20,
              'country': 'US',
              'interfaces': [
                {
                  'ifname': 'wlan0',
                  'ssid': 'MockWiFi',
                  'encryption': 'psk2',
                  'key': '********',
                  'network': 'lan',
                },
              ],
            },
          },
        ];

      case 'file.exec':
      case 'luci-rpc.getDHCPLeases':
        // DHCP leases data
        return [
          0,
          {'stdout': _getVariedDhcpLeases(), 'stderr': '', 'code': 0},
        ];

      case 'network.interface.dump':
        // Network interface dump - returns flat map of interfaces with names as keys
        return [
          0,
          {
            'interface': [
              {
                'interface': 'wan',
                'up': true,
                'pending': false,
                'available': true,
                'autostart': true,
                'dynamic': false,
                'proto': 'dhcp',
                'device': 'eth0',
                'metric': 0,
                'dns_metric': 0,
                'delegation': true,
                'ipv4-address': [
                  {'address': '100.64.0.123', 'mask': 24, 'ptpaddress': ''},
                ],
                'ipv6-address': [],
                'ipv6-prefix': [],
                'ipv6-prefix-assignment': [],
                'route': [
                  {
                    'target': '0.0.0.0',
                    'mask': 0,
                    'nexthop': '100.64.0.1',
                    'source': '',
                  },
                ],
                'dns-server': ['8.8.8.8', '8.8.4.4'],
                'dns-search': [],
                'inactive': {
                  'ipv4-address': [],
                  'ipv6-address': [],
                  'route': [],
                  'dns-server': [],
                  'dns-search': [],
                },
              },
              {
                'interface': 'wan6',
                'up': true,
                'pending': false,
                'available': true,
                'autostart': true,
                'dynamic': false,
                'proto': 'dhcpv6',
                'device': 'eth0',
                'metric': 0,
                'dns_metric': 0,
                'delegation': true,
                'ipv4-address': [],
                'ipv6-address': [
                  {'address': '2001:db8::1', 'mask': 64, 'ptpaddress': ''},
                ],
                'ipv6-prefix': [],
                'ipv6-prefix-assignment': [],
                'route': [],
                'dns-server': ['2001:4860:4860::8888'],
                'dns-search': [],
                'inactive': {
                  'ipv4-address': [],
                  'ipv6-address': [],
                  'route': [],
                  'dns-server': [],
                  'dns-search': [],
                },
              },
              {
                'interface': 'wanb',
                'up': false,
                'pending': false,
                'available': false,
                'autostart': true,
                'dynamic': false,
                'proto': 'pppoe',
                'device': 'eth1',
                'metric': 0,
                'dns_metric': 0,
                'delegation': true,
                'ipv4-address': [],
                'ipv6-address': [],
                'ipv6-prefix': [],
                'ipv6-prefix-assignment': [],
                'route': [],
                'dns-server': [],
                'dns-search': [],
                'inactive': {
                  'ipv4-address': [],
                  'ipv6-address': [],
                  'route': [],
                  'dns-server': [],
                  'dns-search': [],
                },
              },
              {
                'interface': 'lan',
                'up': true,
                'pending': false,
                'available': true,
                'autostart': true,
                'dynamic': false,
                'proto': 'static',
                'device': 'br-lan',
                'metric': 0,
                'dns_metric': 0,
                'delegation': true,
                'ipv4-address': [
                  {'address': '192.168.1.1', 'mask': 24, 'ptpaddress': ''},
                ],
                'ipv6-address': [],
                'ipv6-prefix': [],
                'ipv6-prefix-assignment': [],
                'route': [],
                'dns-server': [],
                'dns-search': [],
                'inactive': {
                  'ipv4-address': [],
                  'ipv6-address': [],
                  'route': [],
                  'dns-server': [],
                  'dns-search': [],
                },
              },
            ],
          },
        ];

      case 'luci-rpc.getNetworkDevices':
        // Network devices data (same structure as network.device)
        final wanStats = _getVariedNetworkStats('eth0');
        final lanStats = _getVariedNetworkStats('br-lan');
        return [
          0,
          {
            'eth0': {'device': 'eth0', 'up': true, 'stats': wanStats},
            'br-lan': {'device': 'br-lan', 'up': true, 'stats': lanStats},
          },
        ];

      case 'luci-rpc.getWirelessDevices':
        // Wireless devices data (same structure as wireless.devices)
        return [
          0,
          {
            'radio0': {
              'up': true,
              'channel': 6,
              'frequency': 2437,
              'txpower': 20,
              'country': 'US',
              'interfaces': [
                {
                  'ifname': 'wlan0',
                  'ssid': 'MockWiFi',
                  'encryption': 'psk2',
                  'key': '********',
                  'network': 'lan',
                },
              ],
            },
            'radio1': {
              'up': true,
              'channel': 36,
              'frequency': 5180,
              'txpower': 23,
              'country': 'US',
              'interfaces': [
                {
                  'ifname': 'wlan1',
                  'ssid': 'MockWiFi_5G',
                  'encryption': 'psk2',
                  'key': '********',
                  'network': 'lan',
                },
              ],
            },
          },
        ];

      case 'luci.getFeatures':
        return [
          0,
          <String, dynamic>{
            'apk': mockPackageEngine == PackageManagerEngine.apk,
            'opkg': mockPackageEngine == PackageManagerEngine.opkg,
          },
        ];

      case 'luci.wireguard.getWgInstances':
        // WireGuard instances data
        return [
          0,
          {
            'wg0': {
              'interface': 'wg0',
              'peers': {
                'peer_public_key_1': {
                  'public_key': 'peer_public_key_1',
                  'endpoint': '192.168.1.100:51820',
                  'last_handshake':
                      _getVariedTimestamp() - _random.nextInt(300) - 30,
                  'latest_handshake':
                      _getVariedTimestamp() - _random.nextInt(300) - 30,
                  'transfer_rx': _random.nextInt(1000000),
                  'rx_bytes': _random.nextInt(1000000),
                  'transfer_tx': _random.nextInt(500000),
                  'tx_bytes': _random.nextInt(500000),
                  'persistent_keepalive': 25,
                },
                'peer_public_key_2': {
                  'public_key': 'peer_public_key_2',
                  'endpoint': '192.168.1.101:51820',
                  'last_handshake':
                      _getVariedTimestamp() - _random.nextInt(600) - 60,
                  'latest_handshake':
                      _getVariedTimestamp() - _random.nextInt(600) - 60,
                  'transfer_rx': _random.nextInt(2000000),
                  'rx_bytes': _random.nextInt(2000000),
                  'transfer_tx': _random.nextInt(1000000),
                  'tx_bytes': _random.nextInt(1000000),
                  'persistent_keepalive': 0,
                },
              },
            },
          },
        ];

      case 'iwinfo.assoclist':
        // Associated stations data
        return [
          0,
          {
            'wlan0': {
              'aa:bb:cc:dd:ee:01': {
                'signal': -40 - _random.nextInt(20),
                'noise': -95 - _random.nextInt(5),
                'inactive': _random.nextInt(300),
                'rx_packets': _random.nextInt(10000),
                'tx_packets': _random.nextInt(8000),
                'rx_rate': 144000 + _random.nextInt(100000),
                'tx_rate': 72000 + _random.nextInt(50000),
              },
              'aa:bb:cc:dd:ee:02': {
                'signal': -50 - _random.nextInt(15),
                'noise': -92 - _random.nextInt(8),
                'inactive': _random.nextInt(180),
                'rx_packets': _random.nextInt(15000),
                'tx_packets': _random.nextInt(12000),
                'rx_rate': 108000 + _random.nextInt(80000),
                'tx_rate': 54000 + _random.nextInt(30000),
              },
            },
            'wlan1': {
              'aa:bb:cc:dd:ee:03': {
                'signal': -35 - _random.nextInt(10),
                'noise': -98 - _random.nextInt(3),
                'inactive': _random.nextInt(120),
                'rx_packets': _random.nextInt(20000),
                'tx_packets': _random.nextInt(18000),
                'rx_rate': 200000 + _random.nextInt(200000),
                'tx_rate': 150000 + _random.nextInt(100000),
              },
            },
          },
        ];

      case 'service.list':
        return [
          0,
          {
            'dnsmasq': {'running': true, 'enabled': true, 'pid': 1240},
            'firewall': {'running': true, 'enabled': true, 'pid': 890},
            'dropbear': {'running': true, 'enabled': true, 'pid': 1532},
            'uhttpd': {'running': true, 'enabled': true, 'pid': 1620},
            'odhcpd': {'running': true, 'enabled': true, 'pid': 1310},
            'tailscale': {'running': true, 'enabled': true, 'pid': 2045},
            'wireguard': {'running': true, 'enabled': true},
            'nextdns': {'running': true, 'enabled': true, 'pid': 2110},
            'cron': {'running': true, 'enabled': true, 'pid': 780},
          },
        ];

      case 'rc.list':
        return [
          0,
          {
            'boot': {'enabled': true, 'running': false, 'index': 10},
            'network': {'enabled': true, 'running': true, 'index': 20},
            'firewall': {'enabled': true, 'running': true, 'index': 19},
            'dropbear': {'enabled': true, 'running': true, 'index': 50},
            'dnsmasq': {'enabled': true, 'running': true, 'index': 60},
            'odhcpd': {'enabled': true, 'running': true, 'index': 65},
            'uhttpd': {'enabled': true, 'running': true, 'index': 80},
            'tailscale': {'enabled': true, 'running': true, 'index': 90},
            'cron': {'enabled': true, 'running': true, 'index': 95},
          },
        ];

      case 'file.read':
        return [
          0,
          {'data': ''},
        ];

      case 'uci.get':
        return [
          0,
          {
            'wireless': {
              'radio0': {
                '.type': 'wifi-device',
                'type': 'mac80211',
                'channel': '6',
                'hwmode': '11g',
                'path': 'platform/10180000.wmac',
                'htmode': 'HT20',
                'disabled': '0',
              },
              'default_radio0': {
                '.type': 'wifi-iface',
                'device': 'radio0',
                'network': 'lan',
                'mode': 'ap',
                'ssid': 'MockWiFi',
                'encryption': 'psk2',
                'key': 'mock_password',
              },
            },
            'custom_client': {
              '.type': 'openvpn',
              'enabled': '1',
              'running': true,
              'proto': 'udp',
              'port': '1194',
              'dev': 'tun0',
            },
            'settings': {
              '.type': 'tailscale',
              'enabled': '1',
              'running': true,
              'node_name': 'OpenWrt-Router',
              'ip': '100.64.0.15',
              'state': 'Running',
              'tailnet': 'my-tailnet.ts.net',
              'magic_dns': '1',
              'peers_count': 5,
              'is_exit_node': false,
            },
            'main': {
              '.type': 'nextdns',
              'enabled': '1',
              'running': true,
              'profile': 'abcdef',
              'report_client_info': '1',
            },
            'config': {
              '.type': 'cloudflared',
              'enabled': '1',
              'running': true,
              'tunnel_id': '8f92a10b-4c3d-2e1f-0a9b-8c7d6e5f4a3b',
              'tunnel_name': 'home-router-tunnel',
              'token': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
              'connections': 4,
            },
          },
        ];

      case 'system.exec':
        // System execution results
        return [
          0,
          {'stdout': '', 'stderr': '', 'code': 0},
        ];

      default:
        // Return generic success response for unknown endpoints
        return [0, {}];
    }
  }

  // Helper methods for generating dynamic values
  static int _getVariedUptime() {
    _baseUptime += _random.nextInt(30) + 1; // Increment by 1-30 seconds
    return _baseUptime;
  }

  static List<int> _getVariedLoadAverages() {
    return [
      1000 + _random.nextInt(1000), // 1-2 range
      2000 + _random.nextInt(1000), // 2-3 range
      1500 + _random.nextInt(500), // 1.5-2 range
    ];
  }

  static Map<String, int> _getVariedMemory() {
    const int totalMemory = 268435456; // 256MB fixed
    final int usedVariation = _random.nextInt(20971520); // Up to 20MB variation
    final int freeMemory =
        134217728 - usedVariation; // Base 128MB minus variation

    return {
      'total': totalMemory,
      'free': freeMemory,
      'shared': 1048576 + _random.nextInt(524288), // 1-1.5MB
      'buffered': 10485760 + _random.nextInt(2097152), // 10-12MB
      'cached': 20971520 + _random.nextInt(5242880), // 20-25MB
      'available':
          freeMemory +
          20971520 +
          _random.nextInt(10485760), // Free + some cache
    };
  }

  static Map<String, int> _getVariedNetworkStats(String device) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seconds =
        (now ~/ 1000) % 3600; // Reset every hour for predictable patterns

    if (device == 'eth0') {
      // Create realistic throughput patterns with sine waves and random noise
      final timeBasedMultiplier =
          1.0 + 0.5 * sin(seconds * 2 * pi / 300); // 5-minute cycles
      final burstMultiplier = _random.nextBool()
          ? (1.0 + _random.nextDouble() * 2)
          : 1.0; // Random bursts

      // Base rates: 50-500 KB/s for download, 10-100 KB/s for upload
      final rxIncrement =
          ((50000 + _random.nextInt(450000)) *
                  timeBasedMultiplier *
                  burstMultiplier)
              .round();
      final txIncrement =
          ((10000 + _random.nextInt(90000)) *
                  timeBasedMultiplier *
                  burstMultiplier *
                  0.3)
              .round();

      _baseRxBytes += rxIncrement;
      _baseTxBytes += txIncrement;
      _baseRxPackets +=
          (rxIncrement / 1500).round() +
          _random.nextInt(50); // ~1500 bytes per packet
      _baseTxPackets += (txIncrement / 1500).round() + _random.nextInt(20);

      return {
        'rx_bytes': _baseRxBytes,
        'tx_bytes': _baseTxBytes,
        'rx_packets': _baseRxPackets,
        'tx_packets': _baseTxPackets,
        'rx_dropped': _random.nextInt(3),
        'tx_dropped': _random.nextInt(2),
        'rx_errors': _random.nextInt(2),
        'tx_errors': _random.nextInt(2),
      };
    } else {
      // For br-lan (LAN interface), simulate local network activity
      final timeBasedMultiplier =
          1.0 + 0.3 * sin(seconds * 2 * pi / 180); // 3-minute cycles
      final localActivity = _random.nextBool()
          ? (1.0 + _random.nextDouble())
          : 0.5;

      // LAN typically has lower but more consistent throughput
      final rxIncrement =
          ((20000 + _random.nextInt(100000)) *
                  timeBasedMultiplier *
                  localActivity)
              .round();
      final txIncrement =
          ((15000 + _random.nextInt(80000)) *
                  timeBasedMultiplier *
                  localActivity)
              .round();

      _baseLanRxBytes += rxIncrement;
      _baseLanTxBytes += txIncrement;
      _baseLanRxPackets += (rxIncrement / 1500).round() + _random.nextInt(20);
      _baseLanTxPackets += (txIncrement / 1500).round() + _random.nextInt(15);

      return {
        'rx_bytes': _baseLanRxBytes,
        'tx_bytes': _baseLanTxBytes,
        'rx_packets': _baseLanRxPackets,
        'tx_packets': _baseLanTxPackets,
        'rx_dropped': _random.nextInt(2),
        'tx_dropped': _random.nextInt(2),
        'rx_errors': _random.nextInt(2),
        'tx_errors': _random.nextInt(2),
      };
    }
  }

  static int _getVariedTimestamp() {
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  static String _getVariedDhcpLeases() {
    final now = _getVariedTimestamp();
    final devices = [
      'Pixel-9-Pro',
      'MacBook-Pro-16-M3',
      'Sony-Bravia-4K-TV',
      'ASUS-ROG-Gaming-PC',
      'Google-Nest-Thermostat',
      'iPad-Air-M2',
      'Amazon-Echo-Show-10',
      'HP-Color-LaserJet-Pro',
      'Samsung-Galaxy-S24-Ultra',
      'Dell-XPS-15-Workstation',
      'Ring-Video-Doorbell-Pro',
      'PlayStation-5-Console',
      'Philips-Hue-Bridge-V2',
      'Nintendo-Switch-OLED',
      'Sonos-Era-100-Speaker',
      'Tesla-Model-3-EV',
      'LG-C3-OLED-TV',
      'Steam-Deck-OLED',
      'Eufy-Security-Camera',
      'Raspberry-Pi-5-HomeAssistant',
      'Apple-Watch-Ultra-2',
      'Chromecast-with-Google-TV',
      'ThinkPad-X1-Carbon',
    ];
    final macAddresses = [
      'aa:bb:cc:11:22:33',
      'aa:bb:cc:44:55:66',
      'aa:bb:cc:77:88:99',
      'aa:bb:cc:aa:bb:cc',
      'aa:bb:cc:dd:ee:ff',
      'aa:bb:cc:12:34:56',
      'aa:bb:cc:65:43:21',
      'aa:bb:cc:98:76:54',
      'bb:cc:dd:11:22:33',
      'bb:cc:dd:44:55:66',
      'bb:cc:dd:77:88:99',
      'bb:cc:dd:aa:bb:cc',
      'bb:cc:dd:dd:ee:ff',
      'bb:cc:dd:12:34:56',
      'bb:cc:dd:65:43:21',
      'cc:dd:ee:11:22:33',
      'cc:dd:ee:44:55:66',
      'cc:dd:ee:77:88:99',
      'cc:dd:ee:aa:bb:cc',
      'cc:dd:ee:dd:ee:ff',
      'cc:dd:ee:12:34:56',
      'cc:dd:ee:65:43:21',
      'cc:dd:ee:98:76:54',
    ];
    final ipAddresses = [
      '192.168.1.100',
      '192.168.1.101',
      '192.168.1.102',
      '192.168.1.103',
      '192.168.1.104',
      '192.168.1.105',
      '192.168.1.106',
      '192.168.1.107',
      '192.168.1.108',
      '192.168.1.109',
      '192.168.1.110',
      '192.168.1.111',
      '192.168.1.112',
      '192.168.1.113',
      '192.168.1.114',
      '192.168.1.116',
      '192.168.1.117',
      '192.168.1.118',
      '192.168.1.119',
      '192.168.1.120',
      '192.168.1.121',
      '192.168.1.122',
      '192.168.1.123',
    ];

    String leases = '';
    for (int i = 0; i < devices.length; i++) {
      // Vary lease time slightly
      final leaseTime = now + 1800 + _random.nextInt(43200);
      leases +=
          '$leaseTime ${macAddresses[i]} ${ipAddresses[i]} ${devices[i]} 01:${macAddresses[i]}\n';
    }

    return leases;
  }

  @override
  Future<List<String>> fetchAssociatedStationsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Return mock associated stations
    return ['aa:bb:cc:dd:ee:01', 'aa:bb:cc:dd:ee:02', 'aa:bb:cc:dd:ee:03'];
  }

  @override
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, String> values,
    BuildContext? context,
  }) async {
    if (activeProfile == MockCapabilityProfile.readOnlyLuci) {
      return [1, 'Permission denied: Read-only access'];
    }
    await Future.delayed(const Duration(milliseconds: 50));
    return [0, 'success'];
  }

  @override
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    if (activeProfile == MockCapabilityProfile.readOnlyLuci) {
      return [1, 'Permission denied: Read-only access'];
    }
    await Future.delayed(const Duration(milliseconds: 50));
    return [0, 'success'];
  }

  @override
  Future<dynamic> uciRevert(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 50));
    return [0, 'success'];
  }

  @override
  Future<bool> uciApply(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    bool rollback = true,
    int timeout = 30,
  }) async {
    if (activeProfile == MockCapabilityProfile.readOnlyLuci) return false;
    if (activeProfile == MockCapabilityProfile.constrainedFailure ||
        simulateRollbackFailure) {
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    return true;
  }

  @override
  Future<bool> uciConfirm(
    String ipAddress,
    String sysauth,
    bool useHttps,
  ) async {
    if (activeProfile == MockCapabilityProfile.readOnlyLuci) return false;
    if (activeProfile == MockCapabilityProfile.constrainedFailure ||
        simulateRollbackFailure) {
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    return true;
  }

  SetPasswordRpcResponse? mockSetPasswordResponse;

  @override
  Future<SetPasswordRpcResponse> setRouterPassword(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String username = 'root',
    required String newPassword,
  }) async {
    await Future.delayed(const Duration(milliseconds: 50));
    return mockSetPasswordResponse ?? const SetPasswordRpcResponse.success();
  }

  @override
  Future<List<String>> fetchNetworkInterfaces({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return ['lan', 'wan', 'guest'];
  }

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Return success response for mock system exec operation
    return [0, 'success'];
  }

  @override
  bool execSucceeded(dynamic res) {
    if (res == null) return false;
    if (res is List && res.isNotEmpty) return res[0] == 0;
    if (res is Map && res['code'] is int) return res['code'] == 0;
    return res == 0 || res == true;
  }

  @override
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    // For mock service, just delegate to fetchAssociatedStations
    return await fetchAssociatedStations();
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchAllAssociatedWirelessStationsWithDetailsContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    final macMap = await fetchAssociatedStations();
    final result = <String, List<Map<String, dynamic>>>{};

    macMap.forEach((iface, macs) {
      final list = <Map<String, dynamic>>[];
      int i = 0;
      for (final mac in macs) {
        i++;
        final rxBytes = 25000000 * i;
        final txBytes = 120000000 * i;
        list.add({
          'mac': mac,
          'signal': -40 - (i * 3 % 40),
          'noise': -95,
          'thr': 500000,
          'connected_time': 3600 * i,
          'rx': {
            'bytes': rxBytes,
            'packets': (rxBytes / 1000).toInt(),
            'rate': 866700,
          },
          'tx': {
            'bytes': txBytes,
            'packets': (txBytes / 1200).toInt(),
            'rate': 866700,
          },
        });
      }
      result[iface] = list;
    });

    return result;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> fetchHostHintsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    try {
      final jsonString = await rootBundle.loadString(
        '${AppConfig.mockDataPath}host_hints.json',
      );
      final jsonData = jsonDecode(jsonString);
      if (jsonData is Map<String, dynamic>) {
        final result = <String, Map<String, dynamic>>{};
        jsonData.forEach((mac, value) {
          if (value is Map<String, dynamic>) {
            result[mac] = value;
          }
        });
        return result;
      }
    } catch (_) {}

    return {
      'AA:BB:CC:11:22:33': {
        'name': 'Android-nightcodex7',
        'staticLeaseName': 'Pixel-9-Pro',
        'isStaticLease': true,
        'vendor': 'Google LLC',
        'ipaddrs': ['192.168.1.100'],
        'ip6addrs': ['2409:4060:2e81:a102::100', 'fe80::aabb:ccff:fe11:2233'],
      },
      'AA:BB:CC:44:55:66': {
        'name': 'MacBook-Pro-16',
        'vendor': 'Apple Inc.',
        'ipaddrs': ['192.168.1.101'],
        'ip6addrs': ['2409:4060:2e81:a102::101', 'fe80::aabb:ccff:fe44:5566'],
      },
    };
  }

  @override
  Future<bool> disconnectWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  @override
  Future<bool> setSsidEnabled(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String ifaceSection,
    required bool enabled,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  @override
  Future<bool> toggleWirelessRadio(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required bool enabled,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  @override
  Future<bool> setWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required Map<String, List<String>> maclistByIface,
    required Map<String, String> macfilterByIface,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  @override
  Future<bool> confirmWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  @override
  Future<bool> revertWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required Map<String, List<String>> maclistByIface,
    required Map<String, String> macfilterByIface,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  @override
  Future<bool> autoFixPermissions(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }

  @override
  Future<bool> manageServiceAction(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String serviceName,
    required String action,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> pauseClientInternet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    required bool pause,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  @override
  Future<bool> addFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallPortForwarding portForward,
    BuildContext? context,
  }) async {
    if (activeProfile == MockCapabilityProfile.readOnlyLuci) return false;
    if (activeProfile == MockCapabilityProfile.constrainedFailure ||
        simulateRollbackFailure ||
        simulateVerificationFailure ||
        simulateRpcLossAfterApply) {
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    final key = portForward.sectionKey.isNotEmpty
        ? portForward.sectionKey
        : 'redirect_${_mockPortForwards.length + 1}';
    _mockPortForwards.add(portForward.copyWith(sectionKey: key));
    return true;
  }

  @override
  Future<bool> updateFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallPortForwarding portForward,
    BuildContext? context,
  }) async {
    if (activeProfile == MockCapabilityProfile.readOnlyLuci) return false;
    if (activeProfile == MockCapabilityProfile.constrainedFailure ||
        simulateRollbackFailure ||
        simulateVerificationFailure ||
        simulateRpcLossAfterApply) {
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    final idx = _mockPortForwards.indexWhere(
      (p) => p.sectionKey == portForward.sectionKey,
    );
    if (idx != -1) {
      _mockPortForwards[idx] = portForward;
      return true;
    }
    _mockPortForwards.add(portForward);
    return true;
  }

  @override
  Future<bool> deleteFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionKey,
    BuildContext? context,
  }) async {
    if (activeProfile == MockCapabilityProfile.readOnlyLuci) return false;
    if (activeProfile == MockCapabilityProfile.constrainedFailure ||
        simulateRollbackFailure ||
        simulateVerificationFailure ||
        simulateRpcLossAfterApply) {
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    _mockPortForwards.removeWhere((p) => p.sectionKey == sectionKey);
    return true;
  }

  @override
  Future<bool> addFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallCustomRule rule,
    BuildContext? context,
  }) async {
    if (activeProfile == MockCapabilityProfile.readOnlyLuci) return false;
    if (activeProfile == MockCapabilityProfile.constrainedFailure ||
        simulateRollbackFailure ||
        simulateVerificationFailure ||
        simulateRpcLossAfterApply) {
      return false;
    }
    final isLockout = await SelfDeviceGuard.isManagementLockoutRisk(
      target: rule.target,
      srcZone: rule.srcZone,
      destZone: rule.destZone,
      srcMac: rule.srcMac,
      srcIp: rule.srcIp,
      destPort: rule.destPort,
      proto: rule.proto,
      managementPorts: mockDiscoveredManagementPorts,
    );
    if (isLockout) return false;
    await Future.delayed(const Duration(milliseconds: 50));
    final key = rule.sectionKey.isNotEmpty
        ? rule.sectionKey
        : 'rule_${_mockCustomRules.length + 1}';
    _mockCustomRules.add(rule.copyWith(sectionKey: key));
    return true;
  }

  @override
  Future<bool> updateFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallCustomRule rule,
    BuildContext? context,
  }) async {
    if (activeProfile == MockCapabilityProfile.readOnlyLuci) return false;
    if (activeProfile == MockCapabilityProfile.constrainedFailure ||
        simulateRollbackFailure ||
        simulateVerificationFailure ||
        simulateRpcLossAfterApply) {
      return false;
    }
    final isLockout = await SelfDeviceGuard.isManagementLockoutRisk(
      target: rule.target,
      srcZone: rule.srcZone,
      destZone: rule.destZone,
      srcMac: rule.srcMac,
      srcIp: rule.srcIp,
      destPort: rule.destPort,
      proto: rule.proto,
      managementPorts: mockDiscoveredManagementPorts,
    );
    if (isLockout) return false;
    await Future.delayed(const Duration(milliseconds: 50));
    final idx = _mockCustomRules.indexWhere(
      (r) => r.sectionKey == rule.sectionKey,
    );
    if (idx != -1) {
      _mockCustomRules[idx] = rule;
      return true;
    }
    _mockCustomRules.add(rule);
    return true;
  }

  @override
  Future<bool> deleteFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionKey,
    BuildContext? context,
  }) async {
    if (activeProfile == MockCapabilityProfile.readOnlyLuci) return false;
    if (activeProfile == MockCapabilityProfile.constrainedFailure ||
        simulateRollbackFailure ||
        simulateVerificationFailure ||
        simulateRpcLossAfterApply) {
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    _mockCustomRules.removeWhere((r) => r.sectionKey == sectionKey);
    return true;
  }

  @override
  Future<bool> reorderFirewallCustomRules(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String targetSectionKey,
    required String siblingSectionKey,
    required List<String> expectedRuleOrder,
    BuildContext? context,
  }) async {
    if (activeProfile == MockCapabilityProfile.readOnlyLuci) return false;
    if (activeProfile == MockCapabilityProfile.constrainedFailure ||
        simulateRollbackFailure ||
        simulateVerificationFailure ||
        simulateRpcLossAfterApply) {
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    final currentOrder = _mockCustomRules.map((r) => r.sectionKey).toList();
    if (expectedRuleOrder.isNotEmpty &&
        currentOrder.isNotEmpty &&
        !listEquals(currentOrder, expectedRuleOrder)) {
      return false;
    }
    final targetIdx = _mockCustomRules.indexWhere(
      (r) => r.sectionKey == targetSectionKey,
    );
    final siblingIdx = _mockCustomRules.indexWhere(
      (r) => r.sectionKey == siblingSectionKey,
    );
    if (targetIdx == -1 || siblingIdx == -1) return false;
    final temp = _mockCustomRules[targetIdx];
    _mockCustomRules[targetIdx] = _mockCustomRules[siblingIdx];
    _mockCustomRules[siblingIdx] = temp;
    return true;
  }

  @override
  Future<Set<int>> discoverManagementPorts(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    return Set<int>.from(mockDiscoveredManagementPorts);
  }

  @override
  Future<bool> applyPerDeviceNetworkAccessPolicy(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required NetworkAccessPolicy policy,
    required RouterCapabilities capabilities,
    BuildContext? context,
  }) async {
    if (!capabilities.hasUciWriteAccess ||
        activeProfile == MockCapabilityProfile.readOnlyLuci) {
      return false;
    }
    if (activeProfile == MockCapabilityProfile.constrainedFailure ||
        simulateRollbackFailure ||
        simulateVerificationFailure ||
        simulateRpcLossAfterApply) {
      return false;
    }
    final isSelf = await SelfDeviceGuard.isSelfDevice(policy.targetMac);
    if (isSelf) return false;
    final normMac = ClientNamingHelper.normalizeMac(policy.targetMac);
    if (!policy.hasAnyRestriction) {
      _mockPolicies.remove(normMac);
    } else {
      _mockPolicies[normMac] = policy.copyWith(targetMac: normMac);
    }
    return true;
  }

  @override
  Future<bool> applyClientSpeedLimits(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<ClientSpeedLimit> limits,
    required RouterCapabilities capabilities,
    BuildContext? context,
  }) async {
    if (!capabilities.hasUciWriteAccess ||
        activeProfile == MockCapabilityProfile.readOnlyLuci) {
      return false;
    }
    if (activeProfile == MockCapabilityProfile.constrainedFailure) {
      return false;
    }
    final routerKey = '${useHttps ? "https" : "http"}://$ipAddress';
    final routerLimits = _mockSpeedLimitsByRouter.putIfAbsent(
      routerKey,
      () => {},
    );
    routerLimits.clear();
    _mockSpeedLimits.clear();
    for (final limit in limits) {
      if (limit.isEffectivelyRestricted) {
        final normMac = ClientNamingHelper.normalizeMac(limit.targetMac);
        final normalized = limit.copyWith(targetMac: normMac);
        routerLimits[normMac] = normalized;
        _mockSpeedLimits[normMac] = normalized;
      }
    }
    return true;
  }

  @override
  Future<bool> banWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    if (banTimeSeconds > 0) {
      _mockBannedMacs.add(macUpper);
    }
    return true;
  }

  @override
  Future<bool> unbanWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    _mockRestrictedMacs.remove(macUpper);
    _mockBannedMacs.remove(macUpper);
    return true;
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchRestrictedAndBannedClientsLive(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return {
      'restricted': _mockRestrictedMacs
          .map(
            (m) => {
              'mac': m,
              'name': 'Restricted-Tablet',
              'ip': '192.168.1.150',
              'type': 'restricted',
              'source': 'LuCI Firewall Rule "Pause_Internet_112233445566"',
            },
          )
          .toList(),
      'banned': _mockBannedMacs
          .map(
            (m) => {
              'mac': m,
              'name': 'Banned-Guest-Phone',
              'ip': 'N/A',
              'type': 'banned',
              'source': 'Wi-Fi Access Control (macfilter=deny)',
            },
          )
          .toList(),
    };
  }

  @override
  Future<bool> addStaticLease(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    required String targetIp,
    required String hostname,
    String? targetIp6,
    String? duid,
    String? leaseTime,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> deleteStaticLease(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? targetIp,
    String? hostname,
    String? duid,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> refreshClientConnection(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<int> deleteUnusedDhcpLeases(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<String> macsToFlush,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return macsToFlush.length;
  }

  @override
  Future<Map<String, String?>> fetchPublicIps(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return {'ipv4': '203.0.113.195', 'ipv6': '2001:db8:85a3::8a2e:0370:7334'};
  }

  @override
  Future<bool> forceRefreshDhcpLeases(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> saveCronJobs(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<String> cronLines,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> saveDdnsInstance(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required DdnsInstance instance,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> deleteDdnsInstance(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String instanceName,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<DdnsValidationResult> testDdnsConfiguration(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required DdnsInstance instance,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (instance.lookupHost.contains('error') ||
        instance.domain.contains('invalid')) {
      return DdnsValidationResult.failure(
        'Host lookup failed for ${instance.lookupHost}. Host unreachable or unregistered.',
        testOutput: 'nslookup: cant resolve ${instance.lookupHost}',
      );
    }
    return DdnsValidationResult.success(
      testOutput:
          'DNS Lookup Output:\nName: ${instance.lookupHost.isEmpty ? instance.domain : instance.lookupHost}\nAddress: 198.51.100.24 (Public Router IP)',
    );
  }

  @override
  Future<bool> toggleGlobalDdns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required bool enable,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> saveSqmQueue(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required SqmQueue queue,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> deleteSqmQueue(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> toggleSqmService(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required bool enable,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> updateWirelessInterfaceConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> values,
    List<String>? deleteOptions,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> revertWirelessInterfaceConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> priorValues,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> updateWirelessRadioConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> values,
    List<String>? deleteOptions,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> revertWirelessRadioConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> priorValues,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> addWirelessInterface(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    required String network,
    Map<String, String>? extraOptions,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> deleteWirelessInterface(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<bool> updateInterfaceDhcpConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String interface,
    required Map<String, dynamic> values,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  @override
  Future<bool> provisionGuestNetwork(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    String guestIp = '192.168.2.1',
    bool isolateClients = true,
    String network = 'guest',
    // Advanced radio settings
    String? country,
    String? channel,
    String? htMode,
    String? txPower,
    // Fast roaming (802.11r/k/v)
    bool ieee80211r = false,
    bool ftOverDs = false,
    bool ftPskGenerateLocal = false,
    String? mobilityDomain,
    // Wireless advanced settings
    bool wmm = true,
    bool hidden = false,
    int? dtimPeriod,
    int? gtkRekey,
    int? inactivityLimit,
    int? maxListenInterval,
    bool disassocLowAck = true,
    bool multicastToUnicast = false,
    bool wds = false,
    // MAC filtering
    String? macfilter,
    List<String>? maclist,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<Map<String, List<Map<String, String>>>>
  fetchWirelessHardwareCapabilities({
    required String sectionName,
    String? radioName,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    // Return mock hardware capabilities matching the fallback data
    return {
      'encryptions': [
        {'value': 'sae', 'label': 'WPA3-SAE (Personal / Strict)'},
        {'value': 'sae-mixed', 'label': 'WPA2/WPA3 Mixed (Transitional)'},
        {'value': 'psk2', 'label': 'WPA2-PSK (CCMP / AES)'},
        {'value': 'psk', 'label': 'WPA-PSK (Legacy / WPA1)'},
        {'value': 'owe', 'label': 'Enhanced Open (OWE)'},
        {'value': 'none', 'label': 'Open / No Encryption'},
      ],
      'ciphers': [
        {'value': 'auto', 'label': 'Auto (Hardware Default)'},
        {'value': 'ccmp', 'label': 'CCMP (AES)'},
        {'value': 'gcmp256', 'label': 'GCMP-256 (High Security)'},
        {'value': 'gcmp128', 'label': 'GCMP-128'},
        {'value': 'tkip', 'label': 'TKIP (Legacy)'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchWirelessRadioCapabilities({
    required String radioName,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return {
      'countryCodes': [
        {'code': '00', 'label': '00 — World / Global (Universal)'},
        {'code': 'US', 'label': 'US — United States'},
        {'code': 'DE', 'label': 'DE — Germany'},
        {'code': 'GB', 'label': 'GB — United Kingdom'},
        {'code': 'IN', 'label': 'IN — India'},
        {'code': 'JP', 'label': 'JP — Japan'},
        {'code': 'CA', 'label': 'CA — Canada'},
        {'code': 'AU', 'label': 'AU — Australia'},
      ],
      'channels': [
        'auto',
        '1',
        '6',
        '11',
        '36',
        '40',
        '44',
        '48',
        '149',
        '153',
        '157',
        '161',
      ],
      'htModes': [
        'HT20',
        'HT40',
        'VHT20',
        'VHT40',
        'VHT80',
        'HE20',
        'HE40',
        'HE80',
      ],
      'txPowers': ['auto', '30', '23', '20', '17', '14', '10'],
    };
  }

  @override
  Future<int> migrateAnonymousWirelessSections(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    // No anonymous sections exist in mock data — always clean
    return 0;
  }

  @override
  Future<bool> applyParentalProfileDns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String profileId,
    required List<String> macAddresses,
    required List<String>? dnsServers,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  final List<ParentalProfile> _mockParentalProfiles = [
    const ParentalProfile(
      id: 'profile_1',
      name: 'Profile 1',
      icon: '👦',
      color: '#F97316',
      macAddresses: ['AA:BB:CC:11:22:33'],
      contentFilter: ContentFilterDns.openDnsFamilyShield,
    ),
  ];

  @override
  Future<List<ParentalProfile>?> fetchParentalProfiles(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return List<ParentalProfile>.from(_mockParentalProfiles);
  }

  @override
  Future<bool> saveParentalProfile(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required ParentalProfile profile,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    final idx = _mockParentalProfiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      _mockParentalProfiles[idx] = profile;
    } else {
      _mockParentalProfiles.add(profile);
    }
    return true;
  }

  @override
  Future<bool> deleteParentalProfile(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String profileId,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _mockParentalProfiles.removeWhere((p) => p.id == profileId);
    return true;
  }

  dynamic _handleFileRead(Map<String, dynamic>? params) {
    final path = params?['path']?.toString() ?? '';
    if (path.contains('sysinfo/model')) {
      return [
        0,
        {'data': 'OpenWrt Wi-Fi 6 Gateway (GL-AXT1800)\n'},
      ];
    }
    if (path.contains('sysinfo/board_name')) {
      return [
        0,
        {'data': 'mediatek,mt7981-rf-v1\n'},
      ];
    }
    if (path.contains('openwrt_release')) {
      return [
        0,
        {
          'data':
              'DISTRIB_ID=\'OpenWrt\'\nDISTRIB_RELEASE=\'23.05.3\'\nDISTRIB_REVISION=\'r23809-234f0e6\'\nDISTRIB_TARGET=\'mediatek/mt7981\'\nDISTRIB_ARCH=\'aarch64_cortex-a53\'\nDISTRIB_DESCRIPTION=\'OpenWrt 23.05.3 r23809-234f0e6\'\n',
        },
      ];
    }
    if (path.contains('os-release')) {
      return [
        0,
        {
          'data':
              'NAME="OpenWrt"\nVERSION="23.05.3"\nID="openwrt"\nPRETTY_NAME="OpenWrt 23.05.3"\n',
        },
      ];
    }
    if (path.contains('proc/mtd')) {
      return [
        0,
        {
          'data':
              'dev:    size   erasesize  name\nmtd0: 00080000 00020000 "u-boot"\nmtd1: 00080000 00020000 "u-boot-env"\nmtd2: 00040000 00020000 "factory"\nmtd3: 02000000 00020000 "firmware"\nmtd4: 00180000 00020000 "kernel"\nmtd5: 01e80000 00020000 "rootfs"\n',
        },
      ];
    }
    if (path.contains('crontabs/root') ||
        path.contains('crontab') ||
        path == '/etc/crontab') {
      return [
        0,
        {
          'data':
              '0 4 * * * /sbin/reboot\n*/15 * * * * /usr/bin/ping-check.sh\n',
        },
      ];
    }
    if (path.contains('sysupgrade.conf')) {
      return [
        0,
        {'data': '#/etc/sysupgrade.conf\n/etc/config/\n/etc/dropbear/\n'},
      ];
    }
    if (path.contains('thermal') || path.contains('hwmon')) {
      return [
        0,
        {'data': '51500\n'},
      ];
    }
    return [
      0,
      {'data': ''},
    ];
  }

  dynamic _handleFileExec(Map<String, dynamic>? params) {
    final cmd = params?['command']?.toString() ?? '';
    final rawArgs = params?['params'] ?? params?['args'];
    final argsList = (rawArgs is List)
        ? rawArgs.map((e) => e.toString()).toList()
        : <String>[];
    final fullCmd = '$cmd ${argsList.join(" ")}';

    if (cmd == '/sbin/firstboot' ||
        cmd == 'firstboot' ||
        cmd == '/sbin/reboot' ||
        cmd == 'reboot' ||
        fullCmd.contains('firstboot') ||
        fullCmd.contains('reboot')) {
      return [
        0,
        {'code': 0, 'stdout': '', 'stderr': ''},
      ];
    }

    if (fullCmd.contains('thermal_zone') || fullCmd.contains('hwmon')) {
      return [
        0,
        {
          'code': 0,
          'stdout':
              'thermal|cpu-thermal|thermal_zone0|51500\nhwmon|ath10k_hwmon|hwmon0/temp1_input|54000\nhwmon|ath10k_hwmon|hwmon1/temp1_input|48000\n',
          'stderr': '',
        },
      ];
    }

    if (fullCmd.contains('df -k /tmp') || fullCmd.contains('df ')) {
      return [
        0,
        {
          'code': 0,
          'stdout':
              'Filesystem           1K-blocks      Used Available Use% Mounted on\ntmpfs                   124856      1240    123616   1% /tmp\n',
          'stderr': '',
        },
      ];
    }
    if (fullCmd.contains('sysupgrade -l') ||
        fullCmd.contains('--list-backup')) {
      return [
        0,
        {
          'code': 0,
          'stdout':
              '/etc/config/dhcp\n/etc/config/dropbear\n/etc/config/firewall\n/etc/config/network\n/etc/config/system\n/etc/config/wireless\n/etc/dropbear/dropbear_rsa_host_key\n/etc/shadow\n',
          'stderr': '',
        },
      ];
    }
    if (fullCmd.contains('cat /proc/mtd')) {
      return [
        0,
        {
          'code': 0,
          'stdout':
              'dev:    size   erasesize  name\nmtd0: 00080000 00020000 "u-boot"\nmtd1: 00080000 00020000 "u-boot-env"\nmtd2: 00040000 00020000 "factory"\nmtd3: 02000000 00020000 "firmware"\nmtd4: 00180000 00020000 "kernel"\nmtd5: 01e80000 00020000 "rootfs"\n',
          'stderr': '',
        },
      ];
    }
    if (fullCmd.contains('/tmp/sysinfo/model')) {
      return [
        0,
        {
          'code': 0,
          'stdout': 'OpenWrt Wi-Fi 6 Gateway (GL-AXT1800)\n',
          'stderr': '',
        },
      ];
    }
    if (fullCmd.contains('/tmp/sysinfo/board_name')) {
      return [
        0,
        {'code': 0, 'stdout': 'mediatek,mt7981-rf-v1\n', 'stderr': ''},
      ];
    }
    if (fullCmd.contains('/etc/openwrt_release')) {
      return [
        0,
        {
          'code': 0,
          'stdout':
              'DISTRIB_ID=\'OpenWrt\'\nDISTRIB_RELEASE=\'23.05.3\'\nDISTRIB_REVISION=\'r23809-234f0e6\'\nDISTRIB_TARGET=\'mediatek/mt7981\'\nDISTRIB_ARCH=\'aarch64_cortex-a53\'\nDISTRIB_DESCRIPTION=\'OpenWrt 23.05.3 r23809-234f0e6\'\n',
          'stderr': '',
        },
      ];
    }
    if (cmd == 'opkg') {
      if (mockPackageEngine == PackageManagerEngine.opkg) {
        return [
          0,
          {
            'code': 0,
            'stdout':
                'luci-base - git-23.330\nwireguard-tools - 1.0.20210914-1\n',
            'stderr': '',
          },
        ];
      } else {
        return [
          0,
          {'code': 127, 'stdout': '', 'stderr': 'opkg: not found'},
        ];
      }
    }
    if (cmd == 'apk') {
      if (mockPackageEngine == PackageManagerEngine.apk) {
        return [
          0,
          {
            'code': 0,
            'stdout': 'luci-base-git-23.330\nwireguard-tools-1.0.20210914-1\n',
            'stderr': '',
          },
        ];
      } else {
        return [
          0,
          {'code': 127, 'stdout': '', 'stderr': 'apk: not found'},
        ];
      }
    }
    if (cmd == '/usr/libexec/package-manager-call') {
      if (argsList.contains('list-installed')) {
        if (mockPackageEngine == PackageManagerEngine.apk) {
          return [
            0,
            {
              'code': 0,
              'stdout': jsonEncode([
                {
                  'package': 'apk-mbedtls-3.0.5-r2',
                  'name': 'apk-mbedtls',
                  'version': '3.0.5-r2',
                  'description': 'apk package manager (mbedtls)',
                  'arch': 'x86_64',
                  'license': 'GPL-2.0',
                  'installed-size': 19821,
                  'file-size': 9821,
                  'depends': ['libc', 'libmbedtls21', 'zlib'],
                  'status': ['installed'],
                },
                {
                  'package': 'luci-base-git-24.010',
                  'name': 'luci-base',
                  'version': 'git-24.010',
                  'description': 'LuCI core libraries',
                  'arch': 'all',
                  'license': 'Apache-2.0',
                  'installed-size': 145000,
                  'file-size': 65000,
                  'depends': ['rpcd', 'ucode'],
                  'status': ['installed'],
                },
                {
                  'package': 'wireguard-tools-1.0.20210914-1',
                  'name': 'wireguard-tools',
                  'version': '1.0.20210914-1',
                  'description': 'WireGuard tools',
                  'arch': 'x86_64',
                  'license': 'GPL-2.0',
                  'installed-size': 32768,
                  'file-size': 16384,
                  'depends': ['kmod-wireguard'],
                  'status': ['installed'],
                },
              ]),
              'stderr': '',
            },
          ];
        } else {
          return [
            0,
            {
              'code': 0,
              'stdout': '''
Package: base-files
Version: 1570-r23805
Depends: libc, netifd
Status: install ok installed
Architecture: x86_64
Installed-Size: 45000
Description: OpenWrt core base files

Package: luci-app-firewall
Version: 1.0.0-1
Depends: firewall4, luci-base
Status: install ok installed
Architecture: all
Installed-Size: 25000
Description: Firewall configuration user interface
''',
              'stderr': '',
            },
          ];
        }
      } else if (argsList.contains('list-available')) {
        if (mockPackageEngine == PackageManagerEngine.apk) {
          return [
            0,
            {
              'code': 0,
              'stdout': jsonEncode([
                {
                  'package': 'htop-3.3.0',
                  'name': 'htop',
                  'version': '3.3.0',
                  'description': 'Interactive process viewer',
                  'arch': 'x86_64',
                  'license': 'GPL-2.0',
                  'installed-size': 85000,
                  'file-size': 45000,
                  'depends': ['libc', 'libncurses'],
                },
                {
                  'package': 'curl-8.5.0-r0',
                  'name': 'curl',
                  'version': '8.5.0-r0',
                  'description': 'Command line tool for transferring data',
                  'arch': 'x86_64',
                  'license': 'MIT',
                  'installed-size': 450560,
                  'file-size': 250000,
                  'depends': ['libc', 'libcurl'],
                },
              ]),
              'stderr': '',
            },
          ];
        } else {
          return [
            0,
            {
              'code': 0,
              'stdout': '''
Package: htop
Version: 3.3.0
Depends: libc, libncurses
Architecture: x86_64
Size: 45000
Description: Interactive process viewer

Package: curl
Version: 8.5.0-r0
Depends: libc, libcurl
Architecture: x86_64
Size: 250000
Description: Command line tool for transferring data
''',
              'stderr': '',
            },
          ];
        }
      } else {
        return [
          0,
          {
            'code': 0,
            'stdout':
                '{"code":0,"pkmcmd":"${mockPackageEngine.name} ${argsList.join(" ")}","stdout":"Operation completed successfully","stderr":""}',
            'stderr': '',
          },
        ];
      }
    }
    return null;
  }

  bool installNativeTemperatureHandlerReturns = true;

  @override
  Future<bool> installNativeTemperatureHandler(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    return installNativeTemperatureHandlerReturns;
  }

  @override
  Future<PingResult> executePing(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String target,
    int count = 3,
    int timeoutSec = 2,
    bool isIpv6 = false,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return PingResult(
      target: target,
      isSuccess: true,
      packetsTransmitted: count,
      packetsReceived: count,
      packetLossPercent: 0.0,
      minRttMs: 8.5,
      avgRttMs: 9.1,
      maxRttMs: 9.8,
      mdevRttMs: 0.5,
      replies: List.generate(
        count,
        (i) => PingPacketReply(
          seq: i,
          ttl: 57,
          timeMs: 8.5 + (i * 0.4),
          ip: target,
        ),
      ),
      rawOutput:
          'PING $target ($target): 56 data bytes\n'
          '64 bytes from $target: seq=0 ttl=57 time=8.5 ms\n'
          '64 bytes from $target: seq=1 ttl=57 time=8.9 ms\n'
          '64 bytes from $target: seq=2 ttl=57 time=9.8 ms\n'
          '--- $target ping statistics ---\n'
          '$count packets transmitted, $count packets received, 0% packet loss\n'
          'round-trip min/avg/max = 8.5/9.1/9.8 ms\n',
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<TracerouteResult> executeTraceroute(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String target,
    int maxHops = 15,
    int timeoutSec = 1,
    bool isIpv6 = false,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return TracerouteResult(
      target: target,
      isSuccess: true,
      maxHops: maxHops,
      hops: const [
        TracerouteHop(
          hopNumber: 1,
          host: 'gateway',
          ip: '10.0.0.1',
          rttMs: [0.6],
        ),
        TracerouteHop(
          hopNumber: 2,
          host: 'isp-gw',
          ip: '172.16.0.1',
          rttMs: [1.1],
        ),
        TracerouteHop(hopNumber: 3, isTimeout: true),
        TracerouteHop(
          hopNumber: 4,
          host: 'edge.cloudflare.com',
          ip: '1.1.1.1',
          rttMs: [8.9],
        ),
      ],
      rawOutput:
          'traceroute to $target, $maxHops hops max\n'
          ' 1  10.0.0.1  0.6 ms\n'
          ' 2  172.16.0.1  1.1 ms\n'
          ' 3  *\n'
          ' 4  1.1.1.1  8.9 ms\n',
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<DnsLookupResult> executeDnsLookup(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String host,
    String? server,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 250));
    return DnsLookupResult(
      query: host,
      server: server ?? '127.0.0.1',
      serverPort: 53,
      ipv4Addresses: const ['142.251.222.206', '142.251.222.196'],
      ipv6Addresses: const ['2404:6800:4007:81f::200e'],
      isSuccess: true,
      rawOutput:
          'Server: 127.0.0.1\nAddress: 127.0.0.1#53\n\n'
          'Non-authoritative answer:\nName: $host\n'
          'Address: 142.251.222.206\nAddress: 2404:6800:4007:81f::200e\n',
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<InternetReachability> testInternetReachability(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return InternetReachability(
      status: ReachabilityStatus.online,
      isReachable: true,
      wanInterface: 'wan',
      wanIp: '100.64.0.123',
      gatewayIp: '10.0.0.1',
      gatewayReachable: true,
      gatewayLatencyMs: 0.6,
      publicDnsReachable: true,
      publicDnsLatencyMs: 8.9,
      dnsResolving: true,
      statusMessage: 'Connected to Internet (All probes passed)',
      testedAt: DateTime.now(),
    );
  }

  @override
  Future<List<RouteEntry>> fetchRoutingTable(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    return const [
      RouteEntry(
        destination: 'default',
        gateway: '10.0.0.1',
        interface: 'eth1',
        isDefault: true,
      ),
      RouteEntry(
        destination: '10.0.0.0/24',
        interface: 'eth1',
        source: '10.0.0.125',
      ),
      RouteEntry(
        destination: '192.168.1.0/24',
        interface: 'br-lan',
        source: '192.168.1.1',
      ),
    ];
  }

  @override
  Future<List<NeighborEntry>> fetchNeighborTable(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    return const [
      NeighborEntry(
        ip: '10.0.0.1',
        mac: 'e8:9f:80:a5:7d:8c',
        interface: 'eth1',
        state: 'REACHABLE',
      ),
      NeighborEntry(
        ip: '10.0.0.2',
        mac: 'e4:a8:df:ca:41:8c',
        interface: 'eth1',
        state: 'REACHABLE',
      ),
      NeighborEntry(
        ip: '192.168.1.150',
        mac: 'b8:27:eb:12:34:56',
        interface: 'br-lan',
        state: 'STALE',
      ),
    ];
  }

  @override
  Future<ConntrackInfo?> fetchConntrackInfo(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    return const ConntrackInfo(count: 142, max: 16384);
  }

  @override
  Future<DiagnosticReport> generateFullDiagnosticReport(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    final reach = await testInternetReachability(ipAddress, sysauth, useHttps);
    final routes = await fetchRoutingTable(ipAddress, sysauth, useHttps);
    final neighbors = await fetchNeighborTable(ipAddress, sysauth, useHttps);

    return DiagnosticReport(
      hostname: 'OpenWrt-Router',
      model: 'TP-Link Archer C6 v3',
      architecture: 'MediaTek MT7621',
      target: 'ramips/mt7621',
      kernelVersion: '6.6.35',
      firmwareVersion: 'OpenWrt 23.05.3',
      uptime: '3d 14h 22m',
      loadAverage: '0.12, 0.08, 0.02',
      memorySummary: '48.2 MB / 128.0 MB used (38%)',
      temperatureSummary: 'CPU: 52.0°C, Wi-Fi: 49.0°C',
      storageSummary: 'overlay 12.4 MB / 16.0 MB (78%)',
      internetStatus: reach,
      routes: routes,
      neighbors: neighbors,
      conntrack: const ConntrackInfo(count: 142, max: 16384),
      wanInfo: 'wan (IP: 100.64.0.123, Gateway: 10.0.0.1)',
      lanInfo: 'br-lan (192.168.1.1/24)',
      recentSyslog:
          'daemon.info hostapd: phy0-ap0: STA e4:a8:df:ca:41:8c IEEE 802.11: associated\n'
          'daemon.info dnsmasq-dhcp[1]: DHCPACK(br-lan) 192.168.1.150 e4:a8:df:ca:41:8c Pixel-7\n',
      recentDmesg:
          'ath10k_pci 0000:00:00.0: qca9888 hw2.0 target 0x01000000 chip_id 0x00000000\n'
          'br-lan: port 1(eth0.1) entered forwarding state\n',
      generatedAt: DateTime.now(),
    );
  }

  @override
  Future<FlushDnsResult> flushDns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return FlushDnsResult.success(
      flushedResolvers: const ['dnsmasq'],
      message: 'Flushed dnsmasq DNS cache & reloaded 12 local hosts.',
      rawOutput:
          'dnsmasq[1]: read /etc/hosts - 12 names\ndnsmasq[1]: read /tmp/hosts/dhcp - 4 names\n',
    );
  }

  @override
  Future<String?> execDirectCgi(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String>? params,
    int stderr = 0,
    BuildContext? context,
  }) async {
    final execRes = _handleFileExec({
      'command': command,
      'params': params ?? <String>[],
    });
    if (execRes != null && execRes is List && execRes.length > 1) {
      final map = execRes[1];
      if (map is Map && map['stdout'] != null) {
        return map['stdout'].toString();
      }
    }
    return null;
  }

  @override
  Future<List<RealtimeTrafficPoint>> fetchRealtimeStats(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String mode,
    String? device,
    BuildContext? context,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final points = <RealtimeTrafficPoint>[];
    int baseRx = _baseRxBytes;
    int baseTx = _baseTxBytes;
    RealtimeTrafficPoint? prev;
    for (int i = 20; i >= 0; i--) {
      final ts = now - i;
      baseRx += 50000 + _random.nextInt(200000);
      baseTx += 20000 + _random.nextInt(80000);
      final pt = RealtimeTrafficPoint.fromList([
        ts,
        baseRx,
        baseRx ~/ 1000,
        baseTx,
        baseTx ~/ 1000,
      ], previousPoint: prev);
      points.add(pt);
      prev = pt;
    }
    return points;
  }

  @override
  Future<bool> checkNlbwmonInstalled(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    return true;
  }

  @override
  Future<NlbwmonReport?> fetchNlbwmonData(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String groupBy = 'mac',
    String? period,
    BuildContext? context,
  }) async {
    final mockJson = {
      'columns': [
        'mac',
        'ip',
        'conns',
        'rx_bytes',
        'rx_pkts',
        'tx_bytes',
        'tx_pkts',
        'layer7',
      ],
      'data': [
        [
          'AA:BB:CC:DD:EE:01',
          '192.168.1.101',
          42,
          542000000,
          412000,
          89000000,
          112000,
          'HTTPS',
        ],
        [
          'AA:BB:CC:DD:EE:02',
          '192.168.1.102',
          18,
          120000000,
          95000,
          34000000,
          45000,
          'QUIC',
        ],
        [
          'AA:BB:CC:DD:EE:03',
          '192.168.1.103',
          5,
          23000000,
          18000,
          5000000,
          6000,
          'DNS',
        ],
      ],
    };
    return NlbwmonReport.fromJson(mockJson, period ?? '2026-10-01');
  }

  @override
  Future<List<String>> fetchNlbwmonPeriods(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    return const ['2026-10-01', '2026-09-01'];
  }

  @override
  Future<bool> setRouterHostname(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String newHostname, {
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _mockHostname = newHostname;
    return true;
  }

  @override
  Future<List<String>> getDnsmasqBlockedDomains(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    getDnsmasqBlockedDomainsCallCount++;
    if (simulateDnsmasqFailure) {
      throw Exception('Simulated dnsmasq get failure');
    }
    return _mockDnsmasqBlockedDomains.toList()..sort();
  }

  @override
  Future<bool> addDnsmasqBlockedDomain(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String domain, {
    BuildContext? context,
  }) async {
    addDnsmasqBlockedDomainCallCount++;
    if (simulateDnsmasqFailure) return false;
    final normalized = DomainValidator.normalize(domain);
    if (normalized == null || !DomainValidator.isValid(normalized)) {
      return false;
    }
    _mockDnsmasqBlockedDomains.add(normalized);
    return true;
  }

  @override
  Future<bool> removeDnsmasqBlockedDomain(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String domain, {
    BuildContext? context,
  }) async {
    removeDnsmasqBlockedDomainCallCount++;
    if (simulateDnsmasqFailure) return false;
    final normalized = DomainValidator.normalize(domain);
    if (normalized == null || normalized.isEmpty) return false;
    _mockDnsmasqBlockedDomains.remove(normalized);
    return true;
  }

  @override
  Future<DnsmasqServiceResult> reloadDnsmasq(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    if (simulateDnsmasqFailure) {
      return DnsmasqServiceResult.failure('Simulated dnsmasq reload failure');
    }
    return DnsmasqServiceResult.success();
  }

  @override
  Future<LogFetchResult> fetchSyslog(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    int lines = 200,
    BuildContext? context,
  }) async {
    final mockEntries = List.generate(
      lines > 10 ? 10 : lines,
      (i) => LogEntry(
        index: i,
        raw: 'Mock Syslog entry $i',
        level: LogLevel.info,
        message: 'Mock log entry message $i',
      ),
    );
    return LogFetchSuccess(mockEntries);
  }

  @override
  Future<LogFetchResult> fetchKernelLog(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    int lines = 200,
    BuildContext? context,
  }) async {
    final mockEntries = List.generate(
      lines > 10 ? 10 : lines,
      (i) => LogEntry(
        index: i,
        raw: 'Mock Kernel dmesg entry $i',
        level: LogLevel.notice,
        message: 'Mock kernel log entry message $i',
      ),
    );
    return LogFetchSuccess(mockEntries);
  }
}
