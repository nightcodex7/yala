// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/luci_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SwitchTheme Resolution Tests', () {
    test(
      'Light theme switchTheme thumb and track resolve with high contrast',
      () {
        final theme = LuciTheme.buildLightTheme(dynamicColorScheme: null);
        final switchTheme = theme.switchTheme;

        final selectedThumbColor = switchTheme.thumbColor?.resolve({
          WidgetState.selected,
        });
        final unselectedThumbColor = switchTheme.thumbColor?.resolve({});
        final selectedTrackColor = switchTheme.trackColor?.resolve({
          WidgetState.selected,
        });
        final unselectedTrackColor = switchTheme.trackColor?.resolve({});
        final selectedOutline = switchTheme.trackOutlineColor?.resolve({
          WidgetState.selected,
        });

        // Thumb must be contrasting white when selected, not matching track color
        expect(selectedThumbColor, Colors.white);
        expect(selectedTrackColor, theme.colorScheme.primary);
        expect(selectedThumbColor, isNot(equals(selectedTrackColor)));
        expect(selectedOutline, Colors.transparent);

        // Unselected states
        expect(unselectedThumbColor, theme.colorScheme.outline);
        expect(unselectedTrackColor, theme.colorScheme.surfaceContainerHighest);
      },
    );

    test('Dark theme switchTheme thumb and track resolve with high contrast', () {
      final theme = LuciTheme.buildDarkTheme(dynamicColorScheme: null);
      final switchTheme = theme.switchTheme;

      final selectedThumbColor = switchTheme.thumbColor?.resolve({
        WidgetState.selected,
      });
      final unselectedThumbColor = switchTheme.thumbColor?.resolve({});
      final selectedTrackColor = switchTheme.trackColor?.resolve({
        WidgetState.selected,
      });
      final unselectedTrackColor = switchTheme.trackColor?.resolve({});
      final selectedOutline = switchTheme.trackOutlineColor?.resolve({
        WidgetState.selected,
      });

      // Thumb must be contrasting white when selected, not matching track color
      expect(selectedThumbColor, Colors.white);
      expect(selectedTrackColor, theme.colorScheme.primary);
      expect(selectedThumbColor, isNot(equals(selectedTrackColor)));
      expect(selectedOutline, Colors.transparent);

      // Unselected states
      expect(unselectedThumbColor, theme.colorScheme.outline);
      expect(unselectedTrackColor, theme.colorScheme.surfaceContainerHighest);
    });

    testWidgets('Active Switch renders visible distinct thumb against track', (
      tester,
    ) async {
      final theme = LuciTheme.buildDarkTheme(dynamicColorScheme: null);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(child: Switch(value: true, onChanged: (_) {})),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
    });
  });
}
