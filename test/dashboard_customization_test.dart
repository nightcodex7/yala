// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/state/controllers/throughput_controller.dart';

void main() {
  group('DashboardPreferences Customization Tests', () {
    test(
      'Default DashboardPreferences initializes with expected layout defaults',
      () {
        final prefs = DashboardPreferences();

        expect(prefs.cardOrder.length, equals(8));
        expect(prefs.cardOrder.first, equals('quick_actions'));
        expect(prefs.showQuickActions, isFalse);
        expect(prefs.showDeviceInfo, isTrue);
        expect(prefs.showRealtimeTraffic, isTrue);
        expect(prefs.showSystemVitals, isTrue);
        expect(prefs.showConnectedClients, isTrue);
        expect(prefs.showWirelessNetworks, isTrue);
        expect(prefs.showNetworkInterfaces, isTrue);
        expect(prefs.showSystemModules, isTrue);

        expect(prefs.showCpuLoad, isTrue);
        expect(prefs.showRamUsage, isTrue);
        expect(prefs.showLoadAverage, isTrue);
        expect(prefs.showUptime, isTrue);

        expect(prefs.speedUnit, equals('bits'));
        expect(prefs.showInactiveInterfaces, isTrue);
        expect(prefs.maskPublicIp, isFalse);
      },
    );

    test('isSectionVisible returns accurate status for each card ID', () {
      final prefs = DashboardPreferences(
        showQuickActions: false,
        showSystemVitals: false,
      );

      expect(prefs.isSectionVisible('quick_actions'), isFalse);
      expect(prefs.isSectionVisible('system_vitals'), isFalse);
      expect(prefs.isSectionVisible('device_info'), isTrue);
      expect(prefs.isSectionVisible('realtime_traffic'), isTrue);
    });

    test(
      'Serialization to/from JSON round-trip preserves custom preferences',
      () {
        final customPrefs = DashboardPreferences(
          showQuickActions: false,
          showCpuLoad: false,
          speedUnit: 'bytes',
          maskPublicIp: true,
          showInactiveInterfaces: false,
          enabledQuickActions: {'reboot', 'flush_dns'},
          cardOrder: [
            'system_vitals',
            'quick_actions',
            'device_info',
            'realtime_traffic',
            'connected_clients',
            'wireless_networks',
            'network_interfaces',
            'system_modules',
          ],
        );

        final json = customPrefs.toJson();
        final restored = DashboardPreferences.fromJson(json);

        expect(restored.showQuickActions, isFalse);
        expect(restored.showCpuLoad, isFalse);
        expect(restored.speedUnit, equals('bytes'));
        expect(restored.maskPublicIp, isTrue);
        expect(restored.showInactiveInterfaces, isFalse);
        expect(
          restored.enabledQuickActions,
          containsAll(['reboot', 'flush_dns']),
        );
        expect(restored.cardOrder.first, equals('system_vitals'));
      },
    );

    test('copyWith properly updates individual preference fields', () {
      final prefs = DashboardPreferences();
      final updated = prefs.copyWith(
        speedUnit: 'bytes',
        showRamUsage: false,
        cardOrder: ['device_info', 'quick_actions'],
      );

      expect(updated.speedUnit, equals('bytes'));
      expect(updated.showRamUsage, isFalse);
      expect(updated.showCpuLoad, isTrue);
      expect(updated.cardOrder.first, equals('device_info'));
    });

    test(
      'resolveSpecificInterface correctly resolves logical lan interface to Linux device br-lan',
      () {
        final prefs = DashboardPreferences(
          showAllThroughput: false,
          primaryThroughputInterface: 'lan',
        );

        final resolved = ThroughputController.resolveSpecificInterface(
          prefs,
          deviceNameResolver: (iface) {
            if (iface == 'lan') return 'br-lan';
            return iface;
          },
        );

        expect(resolved, equals('br-lan'));
      },
    );
  });
}
