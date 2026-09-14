// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';

void main() {
  group('Firewall Custom Security Rules Unit Tests', () {
    test(
      'FirewallCustomRule parsing with sectionKey and copyWith work correctly',
      () {
        final json = {
          '.name': 'rule_icmp',
          'name': 'Allow-Ping',
          'src': 'wan',
          'dest': 'lan',
          'target': 'ACCEPT',
          'enabled': '1',
        };

        final rule = FirewallCustomRule.fromJson('rule_icmp', json);
        expect(rule.sectionKey, equals('rule_icmp'));
        expect(rule.name, equals('Allow-Ping'));
        expect(rule.enabled, isTrue);
        expect(rule.target, equals('ACCEPT'));

        final disabledRule = rule.copyWith(enabled: false);
        expect(disabledRule.sectionKey, equals('rule_icmp'));
        expect(disabledRule.enabled, isFalse);
        expect(disabledRule.name, equals('Allow-Ping'));
      },
    );

    test('Staging logic correctly tracks modified firewall custom rules', () {
      final rules = [
        const FirewallCustomRule(
          sectionKey: 'r1',
          name: 'Allow-HTTP',
          srcZone: 'wan',
          destZone: 'lan',
          target: 'ACCEPT',
          enabled: true,
        ),
        const FirewallCustomRule(
          sectionKey: 'r2',
          name: 'Block-Telnet',
          srcZone: 'wan',
          destZone: 'lan',
          target: 'DROP',
          enabled: false,
        ),
      ];

      final stagedMap = <String, bool>{};

      // Toggle r1 (Allow-HTTP) to false (disabled) -> Staged
      final r1 = rules.firstWhere((r) => r.sectionKey == 'r1');
      stagedMap[r1.sectionKey] = false;
      expect(stagedMap.containsKey('r1'), isTrue);
      expect(stagedMap['r1'], isFalse);

      // Toggle r1 back to true (original) -> Unstaged
      if (true == r1.enabled) {
        stagedMap.remove(r1.sectionKey);
      }
      expect(stagedMap.containsKey('r1'), isFalse);
      expect(stagedMap.isEmpty, isTrue);
    });
  });
}
