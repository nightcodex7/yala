// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/modules/wireless_management/screens/guest_wifi_management_screen.dart';

void main() {
  testWidgets(
    'GuestWifiManagementScreen renders successfully with header, quick actions and security card',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: GuestWifiManagementScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Verify screen title
      expect(find.text('Guest Wi-Fi Dashboard'), findsOneWidget);

      // Verify central control card
      expect(find.text('Guest Wi-Fi Master Control'), findsOneWidget);

      // Verify guest button
      expect(find.text('New Guest Wi-Fi'), findsWidgets);

      // Scroll down to reveal security section
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      // Verify guest security card
      expect(find.text('Guest Security & Firewall Guardrails'), findsOneWidget);
    },
  );
}
