// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/services/update_checker_service.dart';
import 'package:yet_another_luci_app/widgets/ban_wireless_client_dialog.dart';

void main() {
  group('LuciBreakpoints Multi-Window & Freeform Sizing Tests', () {
    testWidgets(
      'Evaluates correctly on narrow phone split-view (360x360)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 360);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late bool isTabletResult;
        late bool isExpandedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletResult = LuciBreakpoints.isTablet(context);
                isExpandedResult = LuciBreakpoints.isExpanded(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(isTabletResult, isFalse);
        expect(isExpandedResult, isFalse);
      },
    );

    testWidgets(
      'Correctly prevents vertical rail collapse in short landscape split-screen (720x340)',
      (WidgetTester tester) async {
        // In landscape multi-window split view, width may exceed 600, but height < 400.
        // It must cleanly fall back to bottom navigation instead of overflowing.
        tester.view.physicalSize = const Size(720, 340);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late bool isTabletResult;
        late bool isExpandedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletResult = LuciBreakpoints.isTablet(context);
                isExpandedResult = LuciBreakpoints.isExpanded(context);
                return const SizedBox();
              },
            ),
          ),
        );

        // Height is 340 (< 400), so isTablet should be false
        expect(isTabletResult, isFalse);
        expect(isExpandedResult, isFalse);
      },
    );

    testWidgets(
      'Activates tablet mode only when both width >= 600 and height >= 400',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late bool isTabletResult;
        late bool isExpandedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletResult = LuciBreakpoints.isTablet(context);
                isExpandedResult = LuciBreakpoints.isExpanded(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(isTabletResult, isTrue);
        expect(isExpandedResult, isFalse);
      },
    );

    testWidgets(
      'Activates expanded layout on wide tablet/desktop viewports (1280x800)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late bool isTabletResult;
        late bool isExpandedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletResult = LuciBreakpoints.isTablet(context);
                isExpandedResult = LuciBreakpoints.isExpanded(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(isTabletResult, isTrue);
        expect(isExpandedResult, isTrue);
      },
    );
  });

  group('Dialog Responsive Viewport Resilience Tests', () {
    testWidgets(
      'Update Available dialog renders without overflow in narrow 300dp popup view',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(300, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    UpdateCheckerService.showUpdateAvailableDialog(
                      context,
                      currentVersion: '2.0.0',
                      latestVersion: '2.1.0',
                      releaseNotes: 'Bug fixes and performance improvements.',
                      downloadUrl: 'https://github.com/example/releases',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Update Available'), findsOneWidget);
        expect(find.text('v2.0.0'), findsOneWidget);
        expect(find.text('v2.1.0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Pre-Release build dialog renders without overflow in short 320dp split screen',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 320);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    UpdateCheckerService.showAheadOfReleaseDialog(
                      context,
                      currentVersion: '2.2.0',
                      latestGithubVersion: '2.0.0',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Pre-Release Build'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Up to date dialog renders without overflow in very small popup (260x360)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(260, 360);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    UpdateCheckerService.showUpToDateDialog(
                      context,
                      currentVersion: '2.0.0',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Up to Date'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'BanWirelessClientDialog renders without overflow in narrow 320x500 popup view',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => BanWirelessClientDialog(
                        macAddress: '11:22:33:44:55:66',
                        displayName: 'Galaxy-S24-Ultra',
                        onBanConfirmed: (sec) async {},
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(BanWirelessClientDialog), findsOneWidget);
        expect(find.text('Ban Client from Wi-Fi'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
