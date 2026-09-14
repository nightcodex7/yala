// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/screens/login_screen.dart';

void main() {
  testWidgets(
    'LoginScreen renders smoothly on small screens (Redmi Note 4X) without overflow and is fully scrollable',
    (WidgetTester tester) async {
      // Set small screen dimensions (360x520) resembling Redmi Note 4X with virtual keyboard/navigation bar active
      tester.view.physicalSize = const Size(360, 520);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginScreen())),
      );

      await tester.pumpAndSettle();

      // Verify form fields are rendered
      expect(find.byKey(const ValueKey('login_ip_field')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('login_profile_name_field')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('login_pass_field')), findsOneWidget);

      // Verify no render overflow exception occurred
      expect(tester.takeException(), isNull);

      // Verify the screen is scrollable and "CONNECT TO ROUTER" button can be reached via scroll
      final connectButtonFinder = find.widgetWithText(
        FilledButton,
        'CONNECT TO ROUTER',
      );
      await tester.scrollUntilVisible(
        connectButtonFinder,
        200.0,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.pumpAndSettle();
      expect(connectButtonFinder, findsOneWidget);
    },
  );

  testWidgets(
    'LoginScreen renders responsive dual-pane layout on tablet landscape (1280x800) without overflow',
    (WidgetTester tester) async {
      // Set tablet landscape screen dimensions (1280x800)
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginScreen())),
      );

      await tester.pumpAndSettle();

      // Verify form fields are rendered
      expect(find.byKey(const ValueKey('login_ip_field')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('login_profile_name_field')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('login_pass_field')), findsOneWidget);

      // Verify no render overflow exception occurred
      expect(tester.takeException(), isNull);

      // Verify "CONNECT TO ROUTER" button is visible
      final connectButtonFinder = find.widgetWithText(
        FilledButton,
        'CONNECT TO ROUTER',
      );
      expect(connectButtonFinder, findsOneWidget);

      // Verify Direct LAN Connection badge and brand identity are rendered
      expect(find.text('DIRECT LAN CONNECTION'), findsOneWidget);
      expect(find.text('Yet Another LuCI App'), findsOneWidget);
    },
  );
}
