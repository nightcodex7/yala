// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';

void main() {
  group('Wireless Client Disconnection & Interface Mapping Tests', () {
    test('Client model preserves wirelessIface and ssid parameters', () {
      final client = Client.fromWirelessStation(
        '48:EF:1C:23:B8:7C',
        ssid: 'Titanic',
        wirelessIface: 'phy1-ap0',
      );

      expect(client.macAddress, '48:EF:1C:23:B8:7C');
      expect(client.ssid, 'Titanic');
      expect(client.wirelessIface, 'phy1-ap0');
      expect(client.connectionType, ConnectionType.wireless);
    });

    test('Client.copyWith updates wirelessIface correctly', () {
      final client = Client(
        ipAddress: '10.0.0.4',
        macAddress: '48:EF:1C:23:B8:7C',
        hostname: 'ncxS24',
        connectionType: ConnectionType.wireless,
        ssid: 'Titanic',
      );

      final updated = client.copyWith(wirelessIface: 'phy1-ap0');

      expect(updated.ssid, 'Titanic');
      expect(updated.wirelessIface, 'phy1-ap0');
      expect(updated.macAddress, '48:EF:1C:23:B8:7C');
    });

    test(
      'MockApiService disconnectWirelessClient succeeds with physical interface or SSID',
      () async {
        final mockApi = MockApiService();

        final resultIface = await mockApi.disconnectWirelessClient(
          '10.0.0.1',
          'sysauth_token',
          false,
          macAddress: '48:EF:1C:23:B8:7C',
          iface: 'phy1-ap0',
        );

        expect(resultIface, isTrue);

        final resultFallback = await mockApi.disconnectWirelessClient(
          '10.0.0.1',
          'sysauth_token',
          false,
          macAddress: '48:EF:1C:23:B8:7C',
          iface: 'Titanic',
        );

        expect(resultFallback, isTrue);
      },
    );
  });
}
