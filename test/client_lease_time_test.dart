// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';

void main() {
  group('Client formattedLeaseTime tests', () {
    test('null leaseTime returns "No active lease"', () {
      final client = Client(
        ipAddress: '10.0.0.125',
        macAddress: 'C0:06:C3:47:D6:83',
        hostname: 'Sub-Router',
        leaseTime: null,
      );
      expect(client.formattedLeaseTime, equals('No active lease'));
    });

    test('0 leaseTime returns "Unlimited"', () {
      final client = Client(
        ipAddress: '10.0.0.100',
        macAddress: '00:11:22:33:44:55',
        hostname: 'Static-Server',
        leaseTime: 0,
      );
      expect(client.formattedLeaseTime, equals('Unlimited'));
    });

    test('negative leaseTime returns "Expired"', () {
      final client = Client(
        ipAddress: '10.0.0.50',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Old-Guest',
        leaseTime: -15,
      );
      expect(client.formattedLeaseTime, equals('Expired'));
    });

    test('positive leaseTime formats duration correctly', () {
      final client = Client(
        ipAddress: '10.0.0.20',
        macAddress: '11:22:33:44:55:66',
        hostname: 'Active-Phone',
        leaseTime: 3660, // 1 hour 1 minute
      );
      expect(client.formattedLeaseTime, equals('1h 1m'));
    });

    test('isStatic is false when not configured in UCI dhcp host section', () {
      final client = Client(
        ipAddress: '10.0.0.125',
        macAddress: 'C0:06:C3:47:D6:83',
        hostname: 'Sub-Router',
        isStaticLease: false,
        staticLeaseName: null,
      );
      expect(client.isStatic, isFalse);
    });

    test('isStatic is true when configured in UCI dhcp host section', () {
      final client = Client(
        ipAddress: '10.0.0.60',
        macAddress: 'AA:11:22:33:44:55',
        hostname: 'Reserved-Device',
        isStaticLease: true,
        staticLeaseName: 'Reserved-Device',
      );
      expect(client.isStatic, isTrue);
    });

    test(
      'static lease client with null leaseTime returns "Static (Permanent)"',
      () {
        final client = Client(
          ipAddress: '10.0.0.60',
          macAddress: 'AA:11:22:33:44:55',
          hostname: 'Reserved-Device',
          isStaticLease: true,
          leaseTime: null,
        );
        expect(client.formattedLeaseTime, equals('Static (Permanent)'));
      },
    );

    test(
      'Option A retention rule excludes disconnected non-static devices with no active lease',
      () {
        bool shouldRetainClient({
          required bool isConnected,
          required int? leaseTime,
          required bool isStaticLease,
        }) {
          final hasActiveLease = leaseTime != null && leaseTime > 0;
          return isConnected || hasActiveLease || isStaticLease;
        }

        // Disconnected sub-router (no active lease, no static reservation) -> EXCLUDED
        expect(
          shouldRetainClient(
            isConnected: false,
            leaseTime: null,
            isStaticLease: false,
          ),
          isFalse,
        );

        // Disconnected client with expired lease -> EXCLUDED
        expect(
          shouldRetainClient(
            isConnected: false,
            leaseTime: -100,
            isStaticLease: false,
          ),
          isFalse,
        );

        // Connected client -> RETAINED
        expect(
          shouldRetainClient(
            isConnected: true,
            leaseTime: null,
            isStaticLease: false,
          ),
          isTrue,
        );

        // Offline client with active dynamic lease timer -> RETAINED
        expect(
          shouldRetainClient(
            isConnected: false,
            leaseTime: 1800,
            isStaticLease: false,
          ),
          isTrue,
        );

        // Offline client with static lease reservation -> RETAINED
        expect(
          shouldRetainClient(
            isConnected: false,
            leaseTime: null,
            isStaticLease: true,
          ),
          isTrue,
        );
      },
    );
  });
}
