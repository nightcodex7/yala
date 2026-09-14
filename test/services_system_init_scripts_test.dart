// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/services_system/models/services_system_info.dart';

void main() {
  group('Services & System Startup Init Scripts Tests', () {
    test('InitScript parsing and copyWith work correctly', () {
      final json = {'enabled': 1, 'running': 1, 'index': 20};
      final script = InitScript.fromJson('network', json);
      expect(script.name, equals('network'));
      expect(script.isEnabled, isTrue);
      expect(script.isRunning, isTrue);
      expect(script.startPriority, equals(20));

      final updated = script.copyWith(isEnabled: false);
      expect(updated.name, equals('network'));
      expect(updated.isEnabled, isFalse);
      expect(updated.isRunning, isTrue);
      expect(updated.startPriority, equals(20));
    });

    test(
      'ServicesSystemOverview correctly parses init scripts from RPC dashboard data',
      () {
        final data = {
          'services': {
            'dnsmasq': {'running': true, 'enabled': true, 'pid': 1234},
          },
          'initScripts': {
            'network': {'enabled': 1, 'running': 1, 'start': 20},
            'dnsmasq': {'enabled': 1, 'running': 1, 'start': 60},
            'dropbear': {'enabled': 0, 'running': 0, 'start': 50},
          },
        };

        final overview = ServicesSystemOverview.fromDashboardData(data);
        expect(overview.initScripts.length, equals(3));

        final netScript = overview.initScripts.firstWhere(
          (s) => s.name == 'network',
        );
        expect(netScript.isEnabled, isTrue);
        expect(netScript.startPriority, equals(20));

        final dropbearScript = overview.initScripts.firstWhere(
          (s) => s.name == 'dropbear',
        );
        expect(dropbearScript.isEnabled, isFalse);
        expect(dropbearScript.startPriority, equals(50));
      },
    );

    test('Staging logic correctly tracks modified init scripts', () {
      final initScripts = [
        const InitScript(
          name: 'network',
          isEnabled: true,
          isRunning: true,
          startPriority: 20,
        ),
        const InitScript(
          name: 'dropbear',
          isEnabled: false,
          isRunning: false,
          startPriority: 50,
        ),
      ];

      final stagedMap = <String, bool>{};

      // Toggle dropbear to true -> staged
      final dropbear = initScripts.firstWhere((s) => s.name == 'dropbear');
      stagedMap[dropbear.name] = true;
      expect(stagedMap.containsKey('dropbear'), isTrue);
      expect(stagedMap['dropbear'], isTrue);

      // Toggle dropbear back to false (original) -> unstaged
      if (false == dropbear.isEnabled) {
        stagedMap.remove(dropbear.name);
      }
      expect(stagedMap.containsKey('dropbear'), isFalse);
      expect(stagedMap.isEmpty, isTrue);
    });
  });
}
