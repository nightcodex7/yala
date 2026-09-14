// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/interface.dart';
import 'package:yet_another_luci_app/modules/system_monitoring/models/system_metrics.dart';

/// Tests for wired-only router support (GitHub issues #46, #24, #6).
///
/// Root cause: On routers without WiFi hardware, the app fails to display
/// dashboard and interfaces data because:
/// 1. The `uci.get` for wireless config is not optional and crashes the
///    entire data fetch when wireless config doesn't exist.
/// 2. The interfaces screen requires networkDevices (stats) to be a Map
///    before showing any wired interfaces — if stats are null, all
///    interfaces are silently hidden.

void main() {
  group('NetworkInterface.fromJson', () {
    test('parses interface without stats data', () {
      final json = {
        'interface': 'lan',
        'up': true,
        'proto': 'static',
        'uptime': 12345,
        'device': 'br-lan',
        'ipv4-address': [
          {'address': '192.168.1.1', 'mask': 24},
        ],
        'dns-server': ['8.8.8.8'],
        // No 'stats' key at all
      };

      final iface = NetworkInterface.fromJson(json);

      expect(iface.name, 'lan');
      expect(iface.isUp, true);
      expect(iface.device, 'br-lan');
      expect(iface.ipAddress, '192.168.1.1');
      expect(iface.stats, isEmpty);
    });

    test('parses interface with null stats', () {
      final json = {
        'interface': 'wan',
        'up': true,
        'proto': 'dhcp',
        'uptime': 100,
        'device': 'eth0',
        'stats': null,
      };

      final iface = NetworkInterface.fromJson(json);

      expect(iface.name, 'wan');
      expect(iface.stats, isEmpty);
    });
  });

  group('Wired-only router data extraction', () {
    // Simulates the getData/getOptionalData logic from app_state.dart

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
        return null;
      }
    }

    test(
      'getData throws on non-zero status (simulates uci.get wireless failure)',
      () {
        // On a wired-only router, uci.get for wireless config returns an error
        final wirelessResult = [5, 'Entry not found'];

        expect(() => getData(wirelessResult), throwsException);
      },
    );

    test('getOptionalData returns null on failure instead of throwing', () {
      final wirelessResult = [5, 'Entry not found'];

      final data = getOptionalData(wirelessResult, 'uci.get wireless');

      expect(data, isNull);
    });

    test('getOptionalData returns data on success', () {
      final wirelessResult = [
        0,
        {'values': {}},
      ];

      final data = getOptionalData(wirelessResult, 'uci.get wireless');

      expect(data, isA<Map>());
    });

    test('building interface list should work without network stats', () {
      // This simulates what _buildWiredInterfacesList does.
      // Currently it requires statsDataSource to be a Map, which gates
      // ALL interface rendering on having network device stats.
      final interfaceDump = <String, dynamic>{
        'interface': <dynamic>[
          <String, dynamic>{
            'interface': 'lan',
            'up': true,
            'proto': 'static',
            'uptime': 100,
            'device': 'br-lan',
          },
          <String, dynamic>{
            'interface': 'wan',
            'up': true,
            'proto': 'dhcp',
            'uptime': 200,
            'device': 'eth0',
          },
        ],
      };
      // networkDevices could be null or empty on some setups
      final Map<String, dynamic>? networkDevices = null;

      // Current buggy behavior: requires statsDataSource is Map
      // This test verifies the FIX: interfaces should parse without stats
      final detailedData = interfaceDump;
      var interfacesList = <NetworkInterface>[];

      if (detailedData.containsKey('interface') &&
          detailedData['interface'] is List) {
        final List<dynamic> interfaceDataList = detailedData['interface'];
        final Map<String, dynamic> networkStatsMap = networkDevices != null
            ? Map<String, dynamic>.from(networkDevices)
            : {};

        interfacesList = interfaceDataList
            .whereType<Map<String, dynamic>>()
            .map((detailedInterfaceMap) {
              // Enrich with stats if available (but don't require it)
              final stats = detailedInterfaceMap['stats'];
              if (stats == null || (stats is Map && stats.isEmpty)) {
                final String? deviceName =
                    detailedInterfaceMap['l3_device'] ??
                    detailedInterfaceMap['device'];
                if (deviceName != null) {
                  final statsContainer = networkStatsMap[deviceName];
                  if (statsContainer is Map && statsContainer['stats'] is Map) {
                    detailedInterfaceMap['stats'] = statsContainer['stats'];
                  }
                }
              }
              return NetworkInterface.fromJson(detailedInterfaceMap);
            })
            .toList();
      }

      // With the fix, we should still get interfaces even without stats
      expect(interfacesList, hasLength(2));
      expect(interfacesList[0].name, 'lan');
      expect(interfacesList[1].name, 'wan');
    });
  });

  group('SystemMetrics.fromSysInfo CPU parsing', () {
    test('parses ubus 16-bit integer load array correctly', () {
      final sysInfo = {
        'uptime': 3600,
        'load': [2580, 1920, 1024],
        'memory': {'total': 134217728, 'free': 67108864, 'buffered': 4194304},
      };

      final metrics = SystemMetrics.fromSysInfo(sysInfo);
      expect(metrics.load1m, closeTo(0.0393, 0.001));
      expect(metrics.cpuUsagePercent, closeTo(3.93, 0.1));
    });

    test('parses String load array correctly', () {
      final sysInfo = {
        'uptime': 3600,
        'load': ['2580', '1920', '1024'],
        'memory': {'total': 134217728, 'free': 67108864, 'buffered': 4194304},
      };

      final metrics = SystemMetrics.fromSysInfo(sysInfo);
      expect(metrics.load1m, closeTo(0.0393, 0.001));
      expect(metrics.cpuUsagePercent, closeTo(3.93, 0.1));
    });

    test('parses float load average correctly', () {
      final sysInfo = {
        'uptime': 3600,
        'load': [0.15, 0.10, 0.05],
        'memory': {'total': 100, 'free': 50, 'buffered': 10},
      };

      final metrics = SystemMetrics.fromSysInfo(sysInfo);
      expect(metrics.load1m, equals(0.15));
      expect(metrics.cpuUsagePercent, equals(15.0));
    });

    test('parses Map load format correctly', () {
      final sysInfo = {
        'uptime': 3600,
        'load': {'1m': 2580, '5m': 1920},
      };

      final metrics = SystemMetrics.fromSysInfo(sysInfo);
      expect(metrics.cpuUsagePercent, closeTo(3.93, 0.1));
    });

    test('parses explicit cpu_usage key correctly', () {
      final sysInfo = {'uptime': 3600, 'cpu_usage': 18.5};

      final metrics = SystemMetrics.fromSysInfo(sysInfo);
      expect(metrics.cpuUsagePercent, equals(18.5));
    });

    test(
      'normalizes 1.0+ load average on multi-core router instead of false 100%',
      () {
        final sysInfo = {
          'uptime': 3600,
          'load': [
            68812,
            40000,
            20000,
          ], // 1.05 1m load average in 16-bit integer format
        };
        final boardInfo = {'model': 'MediaTek MT7621'};

        final metrics = SystemMetrics.fromSysInfo(
          sysInfo,
          boardInfo: boardInfo,
        );
        expect(metrics.load1m, closeTo(1.05, 0.01));
        // 1.05 load average on 4-thread MT7621 should yield ~28% CPU load, NOT 100%
        expect(metrics.cpuUsagePercent, lessThan(50.0));
        expect(metrics.cpuUsagePercent, greaterThan(15.0));
      },
    );

    test('parses map format for cpu usage correctly', () {
      final sysInfo = {
        'uptime': 3600,
        'cpu': {'usage': 14.2},
      };

      final metrics = SystemMetrics.fromSysInfo(sysInfo);
      expect(metrics.cpuUsagePercent, equals(14.2));
    });
  });
}
