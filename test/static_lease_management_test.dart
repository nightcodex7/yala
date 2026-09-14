// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/state/controllers/network_actions_controller.dart';

void main() {
  group('Static Lease Deletion & Robustness Tests', () {
    test('MockApiService.deleteStaticLease accepts all optional match parameters', () async {
      final mockApi = MockApiService();

      final successMacOnly = await mockApi.deleteStaticLease(
        '192.168.1.1',
        'token_123',
        false,
        macAddress: 'AA:BB:CC:DD:EE:FF',
      );
      expect(successMacOnly, isTrue);

      final successAllParams = await mockApi.deleteStaticLease(
        '192.168.1.1',
        'token_123',
        false,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        targetIp: '192.168.1.100',
        hostname: 'my-desktop',
        duid: '00:01:00:01:aa:bb',
      );
      expect(successAllParams, isTrue);
    });

    test('NetworkActionsController.deleteStaticLease in Reviewer Mode updates hostHints non-destructively and cleans uciDhcpConfig', () async {
      final mockDashboardData = <String, dynamic>{
        'hostHints': <String, dynamic>{
          'AA:BB:CC:DD:EE:FF': <String, dynamic>{
            'name': 'Living-Room-TV',
            'ipaddrs': ['192.168.1.55'],
            'isStaticLease': true,
            'staticLeaseName': 'Living-Room-TV',
            'staticLeaseIp': '192.168.1.55',
            'staticLeaseTime': '12h',
          },
        },
        'dhcpLeases': <dynamic>[
          <String, dynamic>{
            'macaddr': 'AA:BB:CC:DD:EE:FF',
            'ipaddr': '192.168.1.55',
            'hostname': 'Living-Room-TV',
          },
        ],
        'uciDhcpConfig': <String, dynamic>{
          'values': <String, dynamic>{
            'cfg01host': <String, dynamic>{
              '.type': 'host',
              'name': 'Living-Room-TV',
              'mac': 'aa:bb:cc:dd:ee:ff',
              'ip': '192.168.1.55',
            },
          },
        },
      };

      bool notified = false;
      bool refreshed = false;

      final controller = NetworkActionsController(
        apiServiceRef: () => MockApiService(),
        authServiceRef: () => null,
        routerServiceRef: () => null,
        reviewerModeRef: () => true,
        dashboardDataRef: () => mockDashboardData,
        refreshDashboard: () async => refreshed = true,
        redetectCapabilities: () async {},
        notifyListeners: () => notified = true,
      );

      final result = await controller.deleteStaticLease(
        macAddress: 'AA:BB:CC:DD:EE:FF',
        targetIp: '192.168.1.55',
        hostname: 'Living-Room-TV',
      );

      expect(result, isTrue);
      expect(notified, isTrue);
      expect(refreshed, isTrue);

      // Verify hostHint is preserved and only static flags were cleared
      final hints = mockDashboardData['hostHints'] as Map<String, dynamic>;
      expect(hints.containsKey('AA:BB:CC:DD:EE:FF'), isTrue);
      final clientHint = hints['AA:BB:CC:DD:EE:FF'] as Map<String, dynamic>;
      expect(clientHint['isStaticLease'], isFalse);
      expect(clientHint.containsKey('staticLeaseName'), isFalse);
      expect(clientHint.containsKey('staticLeaseIp'), isFalse);

      // Verify dynamic dhcpLeases was NOT purged
      final leases = mockDashboardData['dhcpLeases'] as List<dynamic>;
      expect(leases, hasLength(1));

      // Verify uciDhcpConfig entry was deleted
      final uciValues = (mockDashboardData['uciDhcpConfig'] as Map)['values'] as Map;
      expect(uciValues.containsKey('cfg01host'), isFalse);
    });

    test('NetworkActionsController.deleteStaticLease matches section by IP when MAC is N/A', () async {
      final mockDashboardData = <String, dynamic>{
        'hostHints': <String, dynamic>{},
        'uciDhcpConfig': <String, dynamic>{
          'values': <String, dynamic>{
            'cfg02host': <String, dynamic>{
              '.type': 'host',
              'name': 'IPv6-Device',
              'mac': 'N/A',
              'ip': '192.168.1.120',
              'duid': '00010001aabbccdd',
            },
          },
        },
      };

      final controller = NetworkActionsController(
        apiServiceRef: () => MockApiService(),
        authServiceRef: () => null,
        routerServiceRef: () => null,
        reviewerModeRef: () => true,
        dashboardDataRef: () => mockDashboardData,
        refreshDashboard: () async {},
        redetectCapabilities: () async {},
        notifyListeners: () {},
      );

      final result = await controller.deleteStaticLease(
        macAddress: 'N/A',
        targetIp: '192.168.1.120',
        hostname: 'IPv6-Device',
        duid: '00010001aabbccdd',
      );

      expect(result, isTrue);
      final uciValues = (mockDashboardData['uciDhcpConfig'] as Map)['values'] as Map;
      expect(uciValues.containsKey('cfg02host'), isFalse);
    });
  });
}
