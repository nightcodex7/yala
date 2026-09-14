// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/services/client_fingerprint_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClientFingerprintService Tests', () {
    test('Service initializes and parses default asset', () async {
      final service = ClientFingerprintService.instance;
      await service.initialize();

      expect(service.isInitialized, isTrue);
      expect(service.activeEdition, isNotNull);
    });

    test('MAC lookup returns correct FingerprintMatch', () async {
      final service = ClientFingerprintService.instance;
      await service.initialize();

      // Test Raspberry Pi MAC prefix: B8:27:EB
      final match = service.lookupByMac('B8:27:EB:11:22:33');
      expect(match, isNotNull);
      expect(match?.vendor.toLowerCase(), contains('raspberry pi'));
    });

    test('Hostname lookup returns correct FingerprintMatch', () async {
      final service = ClientFingerprintService.instance;
      await service.initialize();

      final match = service.lookupByHostname('espressif-32890a');
      expect(match, isNotNull);
      expect(match?.iconHint, equals('memory'));
    });
  });
}
