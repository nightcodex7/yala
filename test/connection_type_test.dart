// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

/// Tests for connection type classification (GitHub issue #5).
///
/// Root cause: When a WiFi device disconnects but keeps its DHCP lease,
/// it's no longer in iwinfo.assoclist. The app then classifies it as "Wired"
/// instead of "Unknown", giving misleading information.

void main() {
  group('Connection type classification', () {
    test('device in wireless assoclist should be wireless', () {
      final lease = {
        'macaddr': 'aa:bb:cc:11:22:33',
        'ipaddr': '192.168.1.100',
        'hostname': 'iPhone-John',
      };
      final wirelessMacs = {'AA:BB:CC:11:22:33'};

      final client = Client.fromLease(lease);
      final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
      final isWireless = wirelessMacs.contains(macNorm);

      // If in assoclist, should be wireless regardless of heuristic
      final classified = client.copyWith(
        connectionType: isWireless
            ? ConnectionType.wireless
            : client.connectionType,
      );

      expect(classified.connectionType, ConnectionType.wireless);
    });

    test(
      'device NOT in assoclist should keep heuristic type, not forced wired',
      () {
        // A phone that disconnected from WiFi — hostname says "iphone"
        final lease = {
          'macaddr': 'aa:bb:cc:11:22:33',
          'ipaddr': '192.168.1.100',
          'hostname': 'iPhone-John',
        };
        final wirelessMacs = <String>{}; // empty — device left WiFi

        final client = Client.fromLease(lease);
        final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
        final isWireless = wirelessMacs.contains(macNorm);

        // OLD behavior: would force ConnectionType.wired (BUG)
        // NEW behavior: keep the heuristic from _determineConnectionType
        final classified = client.copyWith(
          connectionType: isWireless
              ? ConnectionType.wireless
              : client.connectionType,
        );

        // "iPhone" in hostname triggers wireless heuristic in _determineConnectionType
        expect(classified.connectionType, ConnectionType.wireless);
      },
    );

    test(
      'device with no wireless indicators and not in assoclist should be unknown',
      () {
        final lease = {
          'macaddr': '11:22:33:44:55:66',
          'ipaddr': '192.168.1.200',
          'hostname': 'generic-device',
        };
        final wirelessMacs = <String>{};

        final client = Client.fromLease(lease);
        final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
        final isWireless = wirelessMacs.contains(macNorm);

        final classified = client.copyWith(
          connectionType: isWireless
              ? ConnectionType.wireless
              : client.connectionType,
        );

        // No wireless indicators, not in assoclist → heuristic says unknown
        expect(classified.connectionType, ConnectionType.unknown);
      },
    );

    test('device with ethernet interface should stay wired', () {
      final lease = {
        'macaddr': '11:22:33:44:55:66',
        'ipaddr': '192.168.1.200',
        'hostname': 'Desktop-PC',
        'ifname': 'eth0',
      };
      final wirelessMacs = <String>{};

      final client = Client.fromLease(lease);
      final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
      final isWireless = wirelessMacs.contains(macNorm);

      final classified = client.copyWith(
        connectionType: isWireless
            ? ConnectionType.wireless
            : client.connectionType,
      );

      expect(classified.connectionType, ConnectionType.wired);
    });

    test(
      'disconnected wireless client tracked via knownWirelessMacs remains wireless and disconnected',
      () {
        final knownWirelessMacs = {'AA:BB:CC:11:22:33'};
        final macNorm = 'AA:BB:CC:11:22:33';
        final isWirelessActive = false; // Left Wi-Fi

        final isWirelessClient =
            isWirelessActive || knownWirelessMacs.contains(macNorm);
        final isConnected = isWirelessClient ? isWirelessActive : false;
        final connType = isWirelessClient
            ? ConnectionType.wireless
            : ConnectionType.wired;

        expect(isWirelessClient, isTrue);
        expect(isConnected, isFalse);
        expect(connType, ConnectionType.wireless);
      },
    );
  });

  group('Active Neighbor Probing & Scoped IP Resolution', () {
    test('identifies absent or incomplete wired IPs needing probe', () {
      final dhcp4Leases = [
        {
          'ipaddr': '10.0.0.2',
          'macaddr': 'E4:A8:DF:CA:41:8C',
        }, // Wired (REACHABLE)
        {'ipaddr': '10.0.0.4', 'macaddr': '48:EF:1C:23:B8:7C'}, // Wireless
        {
          'ipaddr': '10.0.0.62',
          'macaddr': 'AC:5D:5C:B3:ED:7C',
        }, // Wired (Absent from neigh)
        {
          'ipaddr': '10.0.0.63',
          'macaddr': 'A8:A0:92:1A:77:24',
        }, // Wired (INCOMPLETE)
      ];
      final wirelessMacs = {'48:EF:1C:23:B8:7C'};
      final currentNeigh = [
        {
          'ipaddr': '10.0.0.2',
          'macaddr': 'E4:A8:DF:CA:41:8C',
          'nud_state': 'REACHABLE',
        },
        {
          'ipaddr': '10.0.0.63',
          'macaddr': 'A8:A0:92:1A:77:24',
          'nud_state': 'INCOMPLETE',
        },
      ];

      final targets = selectNeighborProbeTargets(
        dhcp4Leases,
        wirelessMacs,
        currentNeigh,
        routerIp: '10.0.0.1',
      );

      // Wireless (10.0.0.4) and REACHABLE wired (10.0.0.2) must be excluded.
      // Absent wired (10.0.0.62) and INCOMPLETE wired (10.0.0.63) must be selected for probe.
      expect(targets, containsAll(['10.0.0.62', '10.0.0.63']));
      expect(targets, isNot(contains('10.0.0.2')));
      expect(targets, isNot(contains('10.0.0.4')));
    });

    test(
      'caps batch size to max 10 probe targets via selectNeighborProbeTargets',
      () {
        final dhcp4Leases = List.generate(
          25,
          (i) => {
            'ipaddr': '10.0.0.${i + 10}',
            'macaddr':
                '11:22:33:44:55:${(i + 10).toRadixString(16).padLeft(2, '0')}',
          },
        );
        final wirelessMacs = <String>{};
        final currentNeigh = <Map<String, dynamic>>[]; // All absent

        final targets = selectNeighborProbeTargets(
          dhcp4Leases,
          wirelessMacs,
          currentNeigh,
          routerIp: '10.0.0.1',
          maxBatch: 10,
        );

        expect(targets.length, 10);
        expect(targets.first, '10.0.0.10');
        expect(targets.last, '10.0.0.19');
      },
    );
  });
}
