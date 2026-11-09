// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'sqm_queue.dart';
import 'sqm_telemetry.dart';

/// Aggregated overview of Smart Queue Management state on the connected router.
class SqmOverview {
  final bool isInstalled;
  final bool isServiceRunning;
  final bool isServiceEnabled;
  final List<SqmQueue> queues;
  final List<String> availableQdiscs;
  final List<String> availableScripts;
  final List<String> networkInterfaces;
  final String? primaryWanInterface;
  final bool isFlowOffloadingEnabled;
  final bool isHardwareFlowOffloadingEnabled;

  const SqmOverview({
    required this.isInstalled,
    this.isServiceRunning = false,
    this.isServiceEnabled = false,
    this.queues = const [],
    this.availableQdiscs = const ['cake', 'fq_codel'],
    this.availableScripts = const [
      'piece_of_cake.qos',
      'layer_cake.qos',
      'simple.qos',
      'simplest.qos',
      'simplest_tbf.qos',
    ],
    this.networkInterfaces = const [],
    this.primaryWanInterface,
    this.isFlowOffloadingEnabled = false,
    this.isHardwareFlowOffloadingEnabled = false,
  });

  /// Returns true if either software or hardware flow offloading is active on the router.
  bool get hasAnyFlowOffloading =>
      isFlowOffloadingEnabled || isHardwareFlowOffloadingEnabled;

  /// Returns true if at least one queue instance is active and enabled
  bool get hasActiveQueue => queues.any((q) => q.enabled);

  /// Primary or first configured queue instance
  SqmQueue? get primaryQueue => queues.isNotEmpty ? queues.first : null;

  /// Returns the router's existing template queue from /etc/config/sqm, if present
  SqmQueue? get defaultTemplateQueue {
    if (queues.isEmpty) return null;
    return queues.firstWhere(
      (q) => q.isDefaultTemplate,
      orElse: () => queues.first,
    );
  }

  /// True if /etc/config/sqm has at least one queue template already present in the router
  bool get hasExistingTemplate => queues.isNotEmpty;

  /// Formats an interface name with an intelligent role indicator for dropdowns and badges
  String interfaceLabel(String iface) {
    if (iface == primaryWanInterface) {
      if (iface.startsWith('pppoe')) {
        return '$iface • Active PPPoE WAN (Recommended)';
      }
      return '$iface • Active WAN (Recommended)';
    }
    if (iface == 'pppoe-wan') return '$iface • PPPoE Tunnel';
    if (iface == 'wan') return '$iface • WAN Port';
    if (iface.startsWith('wan')) return '$iface • Secondary WAN';
    if (iface == 'br-lan') return '$iface • LAN / Dumb AP Bridge';
    if (iface.startsWith('br-')) return '$iface • Network Bridge';
    if (iface.startsWith('eth')) return '$iface • Physical Ethernet';
    if (iface.startsWith('wlan') ||
        iface.startsWith('phy') ||
        iface.startsWith('sta')) {
      return '$iface • Wireless Client / Repeater';
    }
    if (iface.startsWith('wwan') ||
        iface.startsWith('usb') ||
        iface.startsWith('cdc')) {
      return '$iface • Cellular / USB Modem';
    }
    return iface;
  }

  factory SqmOverview.fromDashboardData(
    Map<String, dynamic>? data, {
    bool isReviewerMode = false,
  }) {
    if (isReviewerMode) {
      return const SqmOverview(
        isInstalled: true,
        isServiceRunning: true,
        isServiceEnabled: true,
        primaryWanInterface: 'pppoe-wan',
        networkInterfaces: ['pppoe-wan', 'eth1', 'br-lan'],
        queues: [
          SqmQueue(
            name: 'eth1',
            enabled: true,
            interface: 'pppoe-wan',
            download: 100000, // 100 Mbps
            upload: 20000, // 20 Mbps
            qdisc: 'cake',
            script: 'piece_of_cake.qos',
            linklayer: 'ethernet',
            overhead: 44,
            qdiscAdvanced: true,
            squashDscp: true,
            squashIngress: true,
          ),
        ],
      );
    }

    if (data == null) {
      return const SqmOverview(isInstalled: false);
    }

    // 1. Detect interfaces from interfaceDump, wan, wan6, networkDevices, and existing SQM configs
    final ifaceList = <String>{};
    String? detectedWan;

    // A. Check explicit 'wan' dictionary if available
    final dynamic wanRaw = data['wan'];
    final wanDict = wanRaw is Map ? wanRaw : null;
    if (wanDict != null) {
      final wanL3 = wanDict['l3_device']?.toString().trim();
      final wanDev = wanDict['device']?.toString().trim();
      final wanIf = wanDict['interface']?.toString().trim();
      if (wanL3 != null && wanL3.isNotEmpty) {
        detectedWan ??= wanL3;
        ifaceList.add(wanL3);
      }
      if (wanDev != null && wanDev.isNotEmpty) {
        detectedWan ??= wanDev;
        ifaceList.add(wanDev);
      }
      if (wanIf != null && wanIf.isNotEmpty) {
        ifaceList.add(wanIf);
      }
    }

    // B. Check explicit 'wan6' dictionary
    final dynamic wan6Raw = data['wan6'];
    final wan6Dict = wan6Raw is Map ? wan6Raw : null;
    if (wan6Dict != null) {
      final w6L3 = wan6Dict['l3_device']?.toString().trim();
      final w6Dev = wan6Dict['device']?.toString().trim();
      if (w6L3 != null && w6L3.isNotEmpty) ifaceList.add(w6L3);
      if (w6Dev != null && w6Dev.isNotEmpty) ifaceList.add(w6Dev);
    }

    // C. Scan interfaceDump for routes and active L3 interfaces
    final dynamic ifDumpRaw = data['interfaceDump'];
    final interfaceDump = ifDumpRaw is Map ? ifDumpRaw : null;
    if (interfaceDump != null && interfaceDump['interface'] is List) {
      for (final item in interfaceDump['interface']) {
        if (item is Map) {
          final l3Dev = item['l3_device']?.toString().trim();
          final dev = item['device']?.toString().trim();
          final ifname = item['interface']?.toString().trim();

          if (l3Dev != null && l3Dev.isNotEmpty) ifaceList.add(l3Dev);
          if (dev != null && dev.isNotEmpty) ifaceList.add(dev);
          if (ifname != null && ifname.isNotEmpty) ifaceList.add(ifname);

          // Detect WAN via default IPv4 route (0.0.0.0/0)
          if (item['route'] is List) {
            for (final r in item['route']) {
              if (r is Map && r['target'] == '0.0.0.0' && r['mask'] == 0) {
                // Prioritize L3 device (e.g. pppoe-wan) over underlying hardware (e.g. eth1)
                final candidate = l3Dev ?? dev ?? ifname;
                if (candidate != null && candidate.isNotEmpty) {
                  detectedWan = candidate;
                }
                break;
              }
            }
          }
        }
      }
    }

    // D. Scan physical/logical devices from networkDevices list
    final netDevices = data['networkDevices'];
    if (netDevices is List) {
      for (final dev in netDevices) {
        if (dev is Map && dev['name'] != null) {
          final name = dev['name'].toString().trim();
          if (name.isNotEmpty &&
              !name.startsWith('lo') &&
              !name.startsWith('sit')) {
            ifaceList.add(name);
          }
        } else if (dev is String && dev.isNotEmpty) {
          if (!dev.startsWith('lo') && !dev.startsWith('sit')) {
            ifaceList.add(dev.trim());
          }
        }
      }
    }

    // E. Extract existing interfaces configured in /etc/config/sqm
    final dynamic rawSqmRaw = data['sqm'];
    final rawSqmData = rawSqmRaw is Map ? rawSqmRaw : null;
    if (rawSqmData != null && rawSqmData.isNotEmpty) {
      for (final val in rawSqmData.values) {
        if (val is Map && val['interface'] != null) {
          final existingIf = val['interface'].toString().trim();
          if (existingIf.isNotEmpty) {
            ifaceList.add(existingIf);
            detectedWan ??= existingIf;
          }
        }
      }
    }

    // Default fallback interface list if empty
    if (ifaceList.isEmpty) {
      ifaceList.addAll(['wan', 'eth1', 'eth0', 'pppoe-wan', 'br-lan']);
    }

    // Robust fallback for WAN detection across all router topologies
    detectedWan ??= ifaceList.contains('pppoe-wan')
        ? 'pppoe-wan'
        : ifaceList.contains('wan')
        ? 'wan'
        : ifaceList.contains('br-lan')
        ? 'br-lan' // Dumb AP fallback
        : ifaceList.contains('eth1')
        ? 'eth1'
        : ifaceList.contains('eth0')
        ? 'eth0'
        : ifaceList.first;

    // 2. Check service status from initScripts or services
    bool serviceRunning = false;
    bool serviceEnabled = false;
    bool servicePresent = false;

    final dynamic initRaw = data['initScripts'];
    final dynamic srvRaw = data['services'];
    final initScripts = initRaw is Map ? initRaw : null;
    final services = srvRaw is Map ? srvRaw : null;

    if (initScripts != null && initScripts['sqm'] is Map) {
      final sqmInit = initScripts['sqm'] as Map;
      servicePresent = true;
      serviceRunning =
          sqmInit['running'] == true ||
          sqmInit['running'] == 1 ||
          sqmInit['running'] == '1';
      serviceEnabled =
          sqmInit['enabled'] == true ||
          sqmInit['enabled'] == 1 ||
          sqmInit['enabled'] == '1';
    } else if (services != null && services['sqm'] is Map) {
      final sqmSvc = services['sqm'] as Map;
      servicePresent = true;
      serviceRunning =
          sqmSvc['running'] == true ||
          sqmSvc['running'] == 1 ||
          sqmSvc['running'] == '1';
      serviceEnabled =
          sqmSvc['enabled'] == true ||
          sqmSvc['enabled'] == 1 ||
          sqmSvc['enabled'] == '1';
    }

    // 3. Check installed packages
    final rawPkgs = data['installedPackages'];
    bool packagePresent = false;
    if (rawPkgs is List) {
      packagePresent = rawPkgs.any(
        (p) =>
            p.toString().contains('sqm-scripts') ||
            p.toString().contains('luci-app-sqm'),
      );
    } else if (rawPkgs is String) {
      packagePresent =
          rawPkgs.contains('sqm-scripts') || rawPkgs.contains('luci-app-sqm');
    }

    // 4. Parse UCI queues from data['sqm']
    final parsedQueues = <SqmQueue>[];
    final dynamic sqmDataRaw = data['sqm'];
    final sqmData = sqmDataRaw is Map ? sqmDataRaw : null;

    if (sqmData != null && sqmData.isNotEmpty) {
      sqmData.forEach((key, value) {
        if (value is Map) {
          final isQueue =
              value['.type'] == 'queue' ||
              value['interface'] != null ||
              value['download'] != null ||
              value['qdisc'] != null;
          if (isQueue) {
            parsedQueues.add(
              SqmQueue.fromUci(key, Map<String, dynamic>.from(value)),
            );
          }
        }
      });
    }

    final bool isInstalled =
        servicePresent ||
        packagePresent ||
        parsedQueues.isNotEmpty ||
        (sqmData != null && sqmData.isNotEmpty);

    // 5. Parse flow offloading from data['uciFirewallConfig']
    bool flowOffload = false;
    bool hwFlowOffload = false;

    final uciFirewall = data['uciFirewallConfig'] as Map<String, dynamic>?;
    if (uciFirewall != null) {
      final rawVals = uciFirewall['values'];
      final Map<String, dynamic> uciValues = (rawVals is Map)
          ? Map<String, dynamic>.from(rawVals)
          : uciFirewall;

      for (final entry in uciValues.values) {
        if (entry is Map) {
          final type = entry['.type']?.toString();
          if (type == 'defaults') {
            flowOffload =
                entry['flow_offloading'] == '1' ||
                entry['flow_offloading'] == 1 ||
                entry['flow_offloading'] == true ||
                entry['flow_offloading'] == 'true';
            hwFlowOffload =
                entry['flow_offloading_hw'] == '1' ||
                entry['flow_offloading_hw'] == 1 ||
                entry['flow_offloading_hw'] == true ||
                entry['flow_offloading_hw'] == 'true';
            break;
          }
        }
      }
    }

    return SqmOverview(
      isInstalled: isInstalled,
      isServiceRunning: serviceRunning,
      isServiceEnabled: serviceEnabled,
      queues: parsedQueues,
      networkInterfaces: ifaceList.toList()..sort(),
      primaryWanInterface: detectedWan,
      isFlowOffloadingEnabled: flowOffload,
      isHardwareFlowOffloadingEnabled: hwFlowOffload,
    );
  }

  /// Creates a SqmOverview bridge representation from immutable [SqmState].
  factory SqmOverview.fromSqmState(SqmState state) {
    return SqmOverview(
      isInstalled: state.isInstalled,
      isServiceRunning: state.isServiceRunning,
      isServiceEnabled: state.isServiceEnabled,
      queues: state.queues,
      networkInterfaces: state.networkInterfaces,
      primaryWanInterface: state.primaryWanInterface,
      isFlowOffloadingEnabled: state.hasSoftwareFlowOffload,
      isHardwareFlowOffloadingEnabled: state.hasHardwareFlowOffload,
    );
  }
}
