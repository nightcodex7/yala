// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';

void main() {
  group('Firewall Module Capability & Topology Unit Tests', () {
    final validFw3Uci = {
      'values': {
        'defaults': {
          '.type': 'defaults',
          'input': 'ACCEPT',
          'output': 'ACCEPT',
          'forward': 'REJECT',
          'syn_flood': '1',
        },
        'lan': {
          '.type': 'zone',
          'name': 'lan',
          'input': 'ACCEPT',
          'output': 'ACCEPT',
          'forward': 'ACCEPT',
          'network': ['lan'],
        },
        'wan': {
          '.type': 'zone',
          'name': 'wan',
          'input': 'REJECT',
          'output': 'ACCEPT',
          'forward': 'REJECT',
          'masq': '1',
          'network': ['wan', 'wan6'],
        },
        'fwd_lan_wan': {'.type': 'forwarding', 'src': 'lan', 'dest': 'wan'},
        'redirect_ssh': {
          '.type': 'redirect',
          'name': 'SSH External',
          'src': 'wan',
          'src_dport': '2222',
          'dest': 'lan',
          'dest_ip': '192.168.1.100',
          'dest_port': '22',
          'proto': 'tcp',
        },
        'rule_icmp': {
          '.type': 'rule',
          'name': 'Allow-Ping',
          'src': 'wan',
          'dest': 'lan',
          'target': 'ACCEPT',
          'enabled': '1',
        },
      },
    };

    final validFw4Uci = {
      'values': {
        'defaults': {
          '.type': 'defaults',
          'input': 'ACCEPT',
          'output': 'ACCEPT',
          'forward': 'REJECT',
          'syn_flood': '1',
          'flow_offloading': '1',
        },
        'lan': {
          '.type': 'zone',
          'name': 'lan',
          'input': 'ACCEPT',
          'output': 'ACCEPT',
          'forward': 'ACCEPT',
          'network': ['lan'],
        },
        'wan': {
          '.type': 'zone',
          'name': 'wan',
          'input': 'REJECT',
          'output': 'ACCEPT',
          'forward': 'REJECT',
          'masq': '1',
          'network': ['wan', 'wan6'],
        },
        'rule_notrack': {
          '.type': 'rule',
          'name': 'Bypass-CT-Local',
          'src': 'lan',
          'dest': 'wan',
          'target': 'NOTRACK',
          'enabled': '1',
        },
        'rule_custom_nft': {
          '.type': 'rule',
          'name': 'Custom-NFT-Set',
          'src': 'wan',
          'dest': 'lan',
          'target': 'NFT_EXPRESSION_SET',
          'enabled': '1',
        },
      },
    };

    test('Fw3FirewallParser correctly parses fw3 UCI rules', () {
      final overview = Fw3FirewallParser.parse(validFw3Uci);

      expect(overview.isAvailable, isTrue);
      expect(overview.backend, equals(FirewallBackend.fw3));
      expect(overview.zones.length, equals(2));
      expect(overview.forwardings.length, equals(1));
      expect(overview.portForwards.length, equals(1));
      expect(overview.customRules.length, equals(1));
      expect(overview.customRules.first.target, equals('ACCEPT'));
      expect(overview.customRules.first.isUnrecognizedTarget, isFalse);
    });

    test(
      'Fw4FirewallParser correctly parses fw4 rules including NOTRACK & unrecognized targets',
      () {
        final overview = Fw4FirewallParser.parse(validFw4Uci);

        expect(overview.isAvailable, isTrue);
        expect(overview.backend, equals(FirewallBackend.fw4));
        expect(overview.customRules.length, equals(2));

        final notrackRule = overview.customRules.firstWhere(
          (r) => r.name == 'Bypass-CT-Local',
        );
        expect(notrackRule.target, equals('NOTRACK'));
        expect(notrackRule.isUnrecognizedTarget, isFalse);

        final customRule = overview.customRules.firstWhere(
          (r) => r.name == 'Custom-NFT-Set',
        );
        expect(customRule.target, equals('NFT_EXPRESSION_SET'));
        expect(customRule.isUnrecognizedTarget, isTrue);
      },
    );

    test(
      'Parser produces distinct empty states: noCustomRules vs unavailable',
      () {
        final validZeroRulesUci = {
          'values': {
            'defaults': {
              '.type': 'defaults',
              'input': 'ACCEPT',
              'output': 'ACCEPT',
              'forward': 'REJECT',
            },
            'lan': {
              '.type': 'zone',
              'name': 'lan',
              'input': 'ACCEPT',
              'output': 'ACCEPT',
              'forward': 'ACCEPT',
              'network': ['lan'],
            },
          },
        };

        final emptyPayloadUci = {'values': {}};

        // 1. Genuine Zero Custom Rules state on valid config
        final zeroRules = Fw4FirewallParser.parse(validZeroRulesUci);
        expect(zeroRules.isAvailable, isTrue);
        expect(zeroRules.isNoCustomRules, isTrue);
        expect(zeroRules.customRules, isEmpty);

        // 2. Empty payload is treated as unavailable, NOT zeroCustomRules
        final emptyParse = Fw4FirewallParser.parse(emptyPayloadUci);
        expect(emptyParse.isAvailable, isFalse);
        expect(emptyParse.isNoCustomRules, isFalse);
        expect(emptyParse.errorMessage, contains('empty or unpopulated'));

        // 3. Capability unavailable state
        final unavailable = FirewallOverview.unavailable(
          FirewallBackend.none,
          'Capability probe failed',
        );
        expect(unavailable.isAvailable, isFalse);
        expect(unavailable.isNoCustomRules, isFalse);
        expect(unavailable.errorMessage, contains('Capability probe failed'));
      },
    );

    test(
      'RpcResult classification handles ubus status branches for firewall fetch',
      () {
        final deniedRpc = [6, 'Access denied'];
        final missingRpc = [3, 'Object not found'];

        final deniedRes = RpcResult.fromUbusResponse<FirewallOverview>(
          deniedRpc,
          (data) => FirewallOverview.unavailable(FirewallBackend.fw4),
        );
        expect(deniedRes.status, equals(RpcCallStatus.permissionDenied));

        final missingRes = RpcResult.fromUbusResponse<FirewallOverview>(
          missingRpc,
          (data) => FirewallOverview.unavailable(FirewallBackend.fw4),
        );
        expect(missingRes.status, equals(RpcCallStatus.methodNotFound));
      },
    );
  });
}
