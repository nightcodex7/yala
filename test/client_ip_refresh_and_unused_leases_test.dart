// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';

void main() {
  group('Client IP Refresh and Discard Unused Leases Guardrails Tests', () {
    late MockApiService mockApi;

    setUp(() {
      mockApi = MockApiService();
    });

    test('refreshClientConnection returns true in MockApiService', () async {
      final res = await mockApi.refreshClientConnection(
        '192.168.1.1',
        'mock_sysauth',
        false,
        macAddress: 'AA:BB:CC:DD:EE:FF',
      );
      expect(res, isTrue);
    });

    test('deleteUnusedDhcpLeases flushes only specified MAC list', () async {
      final count = await mockApi.deleteUnusedDhcpLeases(
        '192.168.1.1',
        'mock_sysauth',
        false,
        macsToFlush: ['AA:BB:CC:DD:EE:11', 'AA:BB:CC:DD:EE:22'],
      );
      expect(count, equals(2));
    });

    test(
      'Flush Guardrails: only disconnected temporary leases with timers are eligible',
      () {
        final activeConnectedClient = Client(
          ipAddress: '192.168.1.10',
          macAddress: '11:22:33:44:55:66',
          hostname: 'Connected-Phone',
          isConnected: true,
          isStaticLease: false,
          leaseTime: 3600,
        );

        final staticClient = Client(
          ipAddress: '192.168.1.50',
          macAddress: '22:33:44:55:66:77',
          hostname: 'Static-Server',
          isConnected: false,
          isStaticLease: true,
          leaseTime: 3600,
        );

        final unlimitedClient = Client(
          ipAddress: '192.168.1.60',
          macAddress: '33:44:55:66:77:88',
          hostname: 'Unlimited-Lease-Device',
          isConnected: false,
          isStaticLease: false,
          leaseTime: 0, // Unlimited
        );

        final eligibleDisconnectedClient = Client(
          ipAddress: '192.168.1.100',
          macAddress: '44:55:66:77:88:99',
          hostname: 'Guest-Phone',
          isConnected: false,
          isStaticLease: false,
          leaseTime: 1800, // Active lease timer
        );

        final clients = [
          activeConnectedClient,
          staticClient,
          unlimitedClient,
          eligibleDisconnectedClient,
        ];

        final eligibleForFlush = clients.where((c) {
          return !c.isConnected &&
              !c.isStatic &&
              c.leaseTime != null &&
              c.leaseTime! > 0;
        }).toList();

        expect(eligibleForFlush.length, equals(1));
        expect(eligibleForFlush.first.macAddress, equals('44:55:66:77:88:99'));
      },
    );
  });
}
