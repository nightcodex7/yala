// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

void main() {
  group('LuciToast Dynamic Material Theming Tests', () {
    test(
      'getLuciToastStyle derives M3 tonal elevation and tokens when dynamicColorScheme is supplied',
      () {
        final colorScheme = ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        );

        final successStyle = getLuciToastStyle(
          LuciToastType.success,
          true,
          dynamicColorScheme: colorScheme,
        );
        expect(successStyle.accent, colorScheme.primary);
        expect(successStyle.icon, Icons.check_circle_rounded);

        final errorStyle = getLuciToastStyle(
          LuciToastType.error,
          true,
          dynamicColorScheme: colorScheme,
        );
        expect(errorStyle.accent, colorScheme.error);
        expect(errorStyle.icon, Icons.error_rounded);

        final warningStyle = getLuciToastStyle(
          LuciToastType.warning,
          true,
          dynamicColorScheme: colorScheme,
        );
        expect(warningStyle.accent, colorScheme.tertiary);
        expect(warningStyle.icon, Icons.warning_amber_rounded);

        final infoStyle = getLuciToastStyle(
          LuciToastType.info,
          true,
          dynamicColorScheme: colorScheme,
        );
        expect(infoStyle.accent, colorScheme.secondary);
        expect(infoStyle.icon, Icons.info_rounded);
      },
    );

    test(
      'getLuciToastStyle uses classic brand colors when dynamicColorScheme is null',
      () {
        final successLight = getLuciToastStyle(LuciToastType.success, false);
        expect(successLight.background, const Color(0xF2F0FDF4));

        final successDark = getLuciToastStyle(LuciToastType.success, true);
        expect(successDark.background, const Color(0xF0142A1D));

        final errorDark = getLuciToastStyle(LuciToastType.error, true);
        expect(errorDark.background, const Color(0xF0341718));
      },
    );
  });

  group('LuciToast Widget & Interaction Tests', () {
    testWidgets(
      '_LuciToastWidget renders inside Overlay without ParentData exception',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      LuciToastManager.show(
                        context,
                        title: 'Test Notification',
                        subtitle: 'Test Subtitle',
                        type: LuciToastType.info,
                        duration: const Duration(seconds: 2),
                        useNativeOs: false,
                      );
                    },
                    child: const Text('Show Toast'),
                  );
                },
              ),
            ),
          ),
        );

        // Tap button to show toast
        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify toast title and subtitle are present
        expect(find.text('Test Notification'), findsOneWidget);
        expect(find.text('Test Subtitle'), findsOneWidget);

        // Verify no exception was thrown
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'LuciToast renders at Alignment.topCenter by default to avoid blocking bottom controls',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      LuciToastManager.show(
                        context,
                        title: 'Top Toast',
                        useNativeOs: false,
                      );
                    },
                    child: const Text('Show Toast'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify that Align widget has Alignment.topCenter
        final alignWidgets = tester.widgetList<Align>(find.byType(Align));
        final toastAlign = alignWidgets.firstWhere(
          (w) => w.alignment == Alignment.topCenter,
        );
        expect(toastAlign.alignment, Alignment.topCenter);
      },
    );

    testWidgets('LuciToast dismisses immediately when tapped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    LuciToastManager.show(
                      context,
                      title: 'Dismissible Toast',
                      duration: const Duration(seconds: 10),
                      useNativeOs: false,
                    );
                  },
                  child: const Text('Show Toast'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Dismissible Toast'), findsOneWidget);

      // Tap directly on the toast to dismiss it
      await tester.tap(find.text('Dismissible Toast'));
      await tester.pump();
      // Advance animation past the dismiss duration
      await tester.pump(const Duration(milliseconds: 300));

      // Toast should now be removed from tree
      expect(find.text('Dismissible Toast'), findsNothing);
    });

    testWidgets('LuciToast dismisses when swiped horizontally', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    LuciToastManager.show(
                      context,
                      title: 'Swipeable Toast',
                      duration: const Duration(seconds: 10),
                      useNativeOs: false,
                    );
                  },
                  child: const Text('Show Toast'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Swipeable Toast'), findsOneWidget);

      // Swipe the toast horizontally
      await tester.drag(find.text('Swipeable Toast'), const Offset(500, 0));
      await tester.pumpAndSettle();

      // Toast should be removed
      expect(find.text('Swipeable Toast'), findsNothing);
    });

    testWidgets('LuciToast sanitizes file errors to file guidance instead of network', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    context.showToastError(
                      'Import Error',
                      subtitle: 'FileSystemException: Cannot open file #0 /path/to.dart:42',
                      useNativeOs: false,
                    );
                  },
                  child: const Text('Show Error Toast'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Import Error'), findsOneWidget);
      expect(
        find.text('Unable to process selected file. Please verify file format and storage permissions.'),
        findsOneWidget,
      );
      // Ensures network error string was NOT shown for file error
      expect(find.textContaining('network connection'), findsNothing);
    });
  });
}
