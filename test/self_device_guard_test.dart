// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';

void main() {
  group('SelfDeviceGuard Tests', () {
    test('normalizeMac formats MAC address consistently', () {
      expect(
        SelfDeviceGuard.normalizeMac('aa-bb-cc-dd-ee-ff'),
        equals('AA:BB:CC:DD:EE:FF'),
      );
      expect(
        SelfDeviceGuard.normalizeMac('AA:BB:CC:DD:EE:FF'),
        equals('AA:BB:CC:DD:EE:FF'),
      );
    });

    test(
      'getLocalDeviceAddresses returns a non-null set of strings without throwing',
      () async {
        final addrs = await SelfDeviceGuard.getLocalDeviceAddresses();
        expect(addrs, isA<Set<String>>());
      },
    );

    test('isSelfDevice handles null or invalid inputs gracefully', () async {
      expect(await SelfDeviceGuard.isSelfDevice(null, null), isFalse);
      expect(await SelfDeviceGuard.isSelfDevice('', ''), isFalse);
      expect(await SelfDeviceGuard.isSelfDevice('N/A', 'N/A'), isFalse);
    });

    test('isSelfDevice matches loopback or local address if present', () async {
      final addrs = await SelfDeviceGuard.getLocalDeviceAddresses();
      if (addrs.isNotEmpty) {
        final firstAddr = addrs.first;
        expect(await SelfDeviceGuard.isSelfDevice(null, firstAddr), isTrue);
      }
    });
  });
}
