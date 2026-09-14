// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/config/app_config.dart';

void main() {
  group('Compile-Time Flavor Gating Unit Tests', () {
    test(
      'AppConfig defaults to Community flavor when FLAVOR environment variable is omitted',
      () {
        expect(AppConfig.flavor, equals(AppFlavor.community));
        expect(AppConfig.isSupportDevEnabled, isFalse);
        expect(AppConfig.flavorName, equals('Community'));
        expect(AppConfig.isOfficialBuild, isFalse);
        expect(AppConfig.isCommunityFlavor, isTrue);
      },
    );
  });
}
