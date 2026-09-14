// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';

void main() {
  group('Client Access Control & Live Router Query Tests', () {
    late MockApiService mockApiService;

    setUp(() {
      mockApiService = MockApiService();
    });

    test('pauseClientInternet succeeds in mock service', () async {
      final success = await mockApiService.pauseClientInternet(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'AA:BB:CC:11:22:33',
        pause: true,
      );
      expect(success, isTrue);
    });

    test('resumeClientInternet succeeds in mock service', () async {
      final success = await mockApiService.pauseClientInternet(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'AA:BB:CC:11:22:33',
        pause: false,
      );
      expect(success, isTrue);
    });

    test('banWirelessClient succeeds in mock service', () async {
      final success = await mockApiService.banWirelessClient(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'DD:EE:FF:44:55:66',
        iface: 'wlan0',
      );
      expect(success, isTrue);
    });

    test('unbanWirelessClient succeeds in mock service', () async {
      final success = await mockApiService.unbanWirelessClient(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'DD:EE:FF:44:55:66',
      );
      expect(success, isTrue);
    });

    test(
      'fetchRestrictedAndBannedClientsLive returns direct router status',
      () async {
        final data = await mockApiService.fetchRestrictedAndBannedClientsLive(
          '192.168.1.1',
          'mock-sysauth',
          false,
        );

        expect(data, contains('restricted'));
        expect(data, contains('banned'));
        expect(data['restricted'], isNotEmpty);
        expect(data['banned'], isNotEmpty);
        expect(data['restricted']!.first['mac'], equals('11:22:33:44:55:66'));
        expect(data['banned']!.first['mac'], equals('99:88:77:66:55:44'));
      },
    );
  });
}
