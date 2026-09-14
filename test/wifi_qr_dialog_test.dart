// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/wifi_qr_dialog.dart';

void main() {
  testWidgets(
    'WifiQrDialog renders without intrinsic dimension assertion error',
    (WidgetTester tester) async {
      const mockIface = WirelessInterface(
        ifName: 'wlan0',
        sectionName: 'default_radio0',
        ssid: 'Test_Network',
        mode: 'ap',
        encryption: 'psk2',
        securityMode: WifiSecurityMode.wpa2Psk,
        pmfState: PmfState.disabled,
        channel: '6',
        isEnabled: true,
        stations: [],
        key: 'SecretPassword123',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: WifiQrDialog(interface: mockIface)),
          ),
        ),
      );

      expect(find.text('Wi-Fi Quick Connect'), findsOneWidget);
      expect(find.text('Test_Network'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    },
  );
}
