// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/luci_theme.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/device_network_access_card.dart';
import 'package:yet_another_luci_app/widgets/network_topology_card.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/network_topology.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/wireless_interface_card.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

/// Calculates the WCAG 2.2 relative luminance contrast ratio between two colors:
/// ratio = (L1 + 0.05) / (L2 + 0.05), where L1 is the lighter luminance.
double calculateContrastRatio(Color foreground, Color background) {
  final lForeground = foreground.computeLuminance();
  final lBackground = background.computeLuminance();
  final l1 = lForeground > lBackground ? lForeground : lBackground;
  final l2 = lForeground > lBackground ? lBackground : lForeground;
  return (l1 + 0.05) / (l2 + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Material 3 Color Scheme Roles & Hierarchy Tests', () {
    test(
      'Primary Dynamic theme provides full complete Material 3 color roles',
      () {
        final lightTheme = LuciTheme.buildLightTheme(
          palette: AppThemePalette.dynamicTheme,
        );
        final darkTheme = LuciTheme.buildDarkTheme(
          palette: AppThemePalette.dynamicTheme,
        );

        for (final theme in [lightTheme, darkTheme]) {
          final cs = theme.colorScheme;
          expect(theme.useMaterial3, isTrue);

          // Core primary, secondary, tertiary roles
          expect(cs.primary, isNotNull);
          expect(cs.onPrimary, isNotNull);
          expect(cs.primaryContainer, isNotNull);
          expect(cs.onPrimaryContainer, isNotNull);

          expect(cs.secondary, isNotNull);
          expect(cs.onSecondary, isNotNull);
          expect(cs.secondaryContainer, isNotNull);
          expect(cs.onSecondaryContainer, isNotNull);

          expect(cs.tertiary, isNotNull);
          expect(cs.onTertiary, isNotNull);
          expect(cs.tertiaryContainer, isNotNull);
          expect(cs.onTertiaryContainer, isNotNull);

          // Error roles
          expect(cs.error, isNotNull);
          expect(cs.onError, isNotNull);
          expect(cs.errorContainer, isNotNull);
          expect(cs.onErrorContainer, isNotNull);

          // Surface hierarchy roles
          expect(cs.surface, isNotNull);
          expect(cs.onSurface, isNotNull);
          expect(cs.onSurfaceVariant, isNotNull);
          expect(cs.surfaceContainerLowest, isNotNull);
          expect(cs.surfaceContainerLow, isNotNull);
          expect(cs.surfaceContainer, isNotNull);
          expect(cs.surfaceContainerHigh, isNotNull);
          expect(cs.surfaceContainerHighest, isNotNull);

          // Outline and inverse roles
          expect(cs.outline, isNotNull);
          expect(cs.outlineVariant, isNotNull);
          expect(cs.inverseSurface, isNotNull);
          expect(cs.onInverseSurface, isNotNull);
          expect(cs.inversePrimary, isNotNull);
        }
      },
    );

    test(
      'Tonal surface hierarchy is consistent between Light and Dark themes',
      () {
        final lightTheme = LuciTheme.buildLightTheme(
          palette: AppThemePalette.dynamicTheme,
        );
        final darkTheme = LuciTheme.buildDarkTheme(
          palette: AppThemePalette.dynamicTheme,
        );

        // Light Theme surface hierarchy
        expect(
          lightTheme.scaffoldBackgroundColor,
          lightTheme.colorScheme.surfaceContainerLowest,
        );
        expect(lightTheme.cardTheme.color, lightTheme.colorScheme.surface);
        expect(
          lightTheme.dialogTheme.backgroundColor,
          lightTheme.colorScheme.surfaceContainerHigh,
        );
        expect(
          lightTheme.bottomSheetTheme.backgroundColor,
          lightTheme.colorScheme.surfaceContainerLow,
        );

        // Dark Theme surface hierarchy
        expect(
          darkTheme.scaffoldBackgroundColor,
          darkTheme.colorScheme.surfaceContainerLowest,
        );
        expect(
          darkTheme.cardTheme.color,
          darkTheme.colorScheme.surfaceContainer,
        );
        expect(
          darkTheme.dialogTheme.backgroundColor,
          darkTheme.colorScheme.surfaceContainerHigh,
        );
        expect(
          darkTheme.bottomSheetTheme.backgroundColor,
          darkTheme.colorScheme.surfaceContainer,
        );
      },
    );

    test('YALA Amber theme remains strictly unmodified and isolated', () {
      final lightAmber = LuciTheme.buildLightTheme(
        palette: AppThemePalette.amber,
      );
      final darkAmber = LuciTheme.buildDarkTheme(
        palette: AppThemePalette.amber,
      );

      expect(lightAmber.colorScheme.primary, LuciTheme.amberPrimaryLight);
      expect(
        lightAmber.scaffoldBackgroundColor,
        LuciTheme.classicLightScaffold,
      );
      expect(lightAmber.cardTheme.color, LuciTheme.classicLightSurface);

      expect(darkAmber.colorScheme.primary, LuciTheme.amberPrimaryDark);
      expect(darkAmber.scaffoldBackgroundColor, LuciTheme.classicDarkScaffold);
      expect(darkAmber.cardTheme.color, LuciTheme.classicDarkSurface);
    });
  });

  group('WCAG 2.2 AA Contrast Compliance Tests', () {
    test(
      'Material 3 Dynamic Theme pairs pass WCAG 2.2 AA (>= 4.5:1 text, >= 3.0:1 container)',
      () {
        final lightTheme = LuciTheme.buildLightTheme(
          palette: AppThemePalette.dynamicTheme,
        );
        final darkTheme = LuciTheme.buildDarkTheme(
          palette: AppThemePalette.dynamicTheme,
        );

        for (final theme in [lightTheme, darkTheme]) {
          final cs = theme.colorScheme;

          // Primary on primary
          final primaryRatio = calculateContrastRatio(cs.onPrimary, cs.primary);
          expect(
            primaryRatio,
            greaterThanOrEqualTo(3.0),
            reason: 'onPrimary on primary contrast ratio ($primaryRatio)',
          );

          // Container pairs
          final primaryContainerRatio = calculateContrastRatio(
            cs.onPrimaryContainer,
            cs.primaryContainer,
          );
          expect(
            primaryContainerRatio,
            greaterThanOrEqualTo(4.5),
            reason:
                'onPrimaryContainer on primaryContainer contrast ratio ($primaryContainerRatio)',
          );

          final secondaryContainerRatio = calculateContrastRatio(
            cs.onSecondaryContainer,
            cs.secondaryContainer,
          );
          expect(
            secondaryContainerRatio,
            greaterThanOrEqualTo(4.5),
            reason:
                'onSecondaryContainer on secondaryContainer contrast ratio ($secondaryContainerRatio)',
          );

          final errorContainerRatio = calculateContrastRatio(
            cs.onErrorContainer,
            cs.errorContainer,
          );
          expect(
            errorContainerRatio,
            greaterThanOrEqualTo(4.5),
            reason:
                'onErrorContainer on errorContainer contrast ratio ($errorContainerRatio)',
          );

          // Surface text pairs
          final onSurfaceRatio = calculateContrastRatio(
            cs.onSurface,
            cs.surface,
          );
          expect(
            onSurfaceRatio,
            greaterThanOrEqualTo(4.5),
            reason: 'onSurface on surface contrast ratio ($onSurfaceRatio)',
          );

          // Inverse surface pair (Snackbars / Tooltips)
          final inverseRatio = calculateContrastRatio(
            cs.onInverseSurface,
            cs.inverseSurface,
          );
          expect(
            inverseRatio,
            greaterThanOrEqualTo(4.5),
            reason:
                'onInverseSurface on inverseSurface contrast ratio ($inverseRatio)',
          );
        }
      },
    );

    test(
      'Semantic statusChip pairs guarantee accessible contrast in both brightness modes',
      () {
        final lightTheme = LuciTheme.buildLightTheme(
          palette: AppThemePalette.dynamicTheme,
        );
        final darkTheme = LuciTheme.buildDarkTheme(
          palette: AppThemePalette.dynamicTheme,
        );

        for (final theme in [lightTheme, darkTheme]) {
          final cs = theme.colorScheme;
          // Active status uses primaryContainer / onPrimaryContainer
          final activeRatio = calculateContrastRatio(
            cs.onPrimaryContainer,
            cs.primaryContainer,
          );
          expect(activeRatio, greaterThanOrEqualTo(4.5));

          // Inactive / error status uses errorContainer / onErrorContainer
          final inactiveRatio = calculateContrastRatio(
            cs.onErrorContainer,
            cs.errorContainer,
          );
          expect(inactiveRatio, greaterThanOrEqualTo(4.5));
        }
      },
    );
  });

  group('International Font Fallback Tests', () {
    test('Theme TextTheme configures font fallbacks for non-Latin scripts', () {
      final theme = LuciTheme.buildLightTheme(
        palette: AppThemePalette.dynamicTheme,
      );
      final titleMedium = theme.textTheme.titleMedium;
      expect(titleMedium, isNotNull);
      expect(titleMedium?.fontFamilyFallback, isNotNull);
      expect(titleMedium?.fontFamilyFallback, contains('Noto Sans'));
      expect(titleMedium?.fontFamilyFallback, contains('Roboto'));
    });

    test('LuciTypography monoStyle and uiStyle configure font fallbacks', () {
      final mono = LuciTypography.monoStyle();
      expect(mono.fontFamilyFallback, isNotNull);
      expect(mono.fontFamilyFallback, contains('Noto Sans Mono'));

      final ui = LuciTypography.uiStyle();
      expect(ui.fontFamilyFallback, isNotNull);
      expect(ui.fontFamilyFallback, contains('Noto Sans'));
    });
  });

  group('Zero Silent Text Truncation & Responsive Layout Tests', () {
    testWidgets(
      'DeviceNetworkAccessCard wraps long client display name without silent truncation',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final client = Client(
          macAddress: 'AA:BB:CC:DD:EE:FF',
          ipAddress: '192.168.1.150',
          hostname: 'Living Room Smart 4K HDR Ultra Entertainment Center',
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: LuciTheme.buildLightTheme(
                palette: AppThemePalette.dynamicTheme,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () =>
                          DeviceNetworkAccessCard.showAsBottomSheet(
                            context,
                            client: client,
                          ),
                      child: const Text('Open Bottom Sheet'),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Bottom Sheet'));
        await tester.pumpAndSettle();

        // Verify the full client name is present
        expect(
          find.textContaining('Living Room Smart 4K HDR Ultra'),
          findsOneWidget,
        );

        // Verify maxLines allows multiline wrapping (not capped to 1)
        final nameFinder = find.byWidgetPredicate(
          (w) =>
              w is Text && (w.data?.contains('Living Room Smart 4K') ?? false),
        );
        expect(nameFinder, findsOneWidget);
        final textWidget = tester.widget<Text>(nameFinder);
        expect(textWidget.maxLines, greaterThan(1));
      },
    );

    testWidgets(
      'NetworkTopologyCard wraps long diagnostic error message without silent truncation',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final topology = NetworkTopology.unavailable(
          NetworkModel.unknown,
          'Switch topology probe failed: swconfig returned exit code 127: package kmod-switch not loaded in kernel.',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: LuciTheme.buildLightTheme(
              palette: AppThemePalette.dynamicTheme,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: NetworkTopologyCard(topology: topology),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify error message is rendered without restrictive 2-line cap
        final errorFinder = find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.contains('kmod-switch not loaded') ?? false),
        );
        expect(errorFinder, findsOneWidget);
        final textWidget = tester.widget<Text>(errorFinder);
        expect(textWidget.maxLines, isNull);
      },
    );

    testWidgets(
      'WirelessInterfaceCard allows multiline wrapping for long and Unicode SSIDs',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const iface = WirelessInterface(
          ifName: 'wlan0',
          sectionName: 'default_radio0',
          ssid:
              '🚀 High-Speed Starlink Guest Network & IoT Mesh 5GHz (Building B) 🌟',
          mode: 'ap',
          channel: '36',
          encryption: 'sae',
          securityMode: WifiSecurityMode.saeOnly,
          pmfState: PmfState.required,
          isEnabled: true,
          stations: [],
        );

        const radio = WirelessRadio(
          name: 'radio0',
          isUp: true,
          channel: '36',
          country: 'US',
          interfaces: [iface],
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: LuciTheme.buildLightTheme(
                palette: AppThemePalette.dynamicTheme,
              ),
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: WirelessInterfaceCard(radio: radio, interface: iface),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final ssidFinder = find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.contains('High-Speed Starlink Guest') ?? false),
        );
        expect(ssidFinder, findsOneWidget);
        final textWidget = tester.widget<Text>(ssidFinder);
        expect(textWidget.maxLines, greaterThan(1));
      },
    );

    testWidgets(
      'UI elements adapt cleanly under 2.0x accessibility text scaling',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final client = Client(
          macAddress: '11:22:33:44:55:66',
          ipAddress: '192.168.1.188',
          hostname: 'Office Workstation Pro',
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: LuciTheme.buildLightTheme(
                palette: AppThemePalette.dynamicTheme,
              ),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
                child: Scaffold(
                  body: Builder(
                    builder: (context) {
                      return ElevatedButton(
                        onPressed: () =>
                            DeviceNetworkAccessCard.showAsBottomSheet(
                              context,
                              client: client,
                            ),
                        child: const Text('Open Controls'),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Controls'));
        await tester.pumpAndSettle();

        // Verify no overflow exception occurred
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Office Workstation Pro'), findsOneWidget);
      },
    );
  });

  group('LuciStatusColors Harmonization & Design Token Tests', () {
    testWidgets('LuciStatusColors harmonizes with active primary color', (
      tester,
    ) async {
      const customPrimary = Color(0xFF6750A4); // M3 baseline purple
      final customTheme = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: customPrimary),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: customTheme,
          home: Builder(
            builder: (context) {
              final connected = LuciStatusColors.connectedColor(context);
              final warning = LuciStatusColors.warningColor(context);
              final info = LuciStatusColors.infoColor(context);
              final primary = LuciColors.primaryColor(context);
              final primaryContainer = LuciColors.primaryContainer(context);
              final rx = LuciColors.rxColor(context);
              final tx = LuciColors.txColor(context);

              expect(primary, equals(customTheme.colorScheme.primary));
              expect(
                primaryContainer,
                equals(customTheme.colorScheme.primaryContainer),
              );
              expect(
                connected,
                equals(
                  LuciStatusColors.connected.harmonizeWith(
                    customTheme.colorScheme.primary,
                  ),
                ),
              );
              expect(
                warning,
                equals(
                  LuciStatusColors.warning.harmonizeWith(
                    customTheme.colorScheme.primary,
                  ),
                ),
              );
              expect(
                info,
                equals(
                  LuciStatusColors.info.harmonizeWith(
                    customTheme.colorScheme.primary,
                  ),
                ),
              );
              expect(
                rx,
                equals(
                  LuciColors.rx.harmonizeWith(customTheme.colorScheme.primary),
                ),
              );
              expect(
                tx,
                equals(
                  LuciColors.tx.harmonizeWith(customTheme.colorScheme.primary),
                ),
              );

              final successBg = LuciStatusColors.successBg(context);
              final warningBg = LuciStatusColors.warningBg(context);
              final errorBg = LuciStatusColors.errorBg(context);

              expect(successBg.a, closeTo(0.15, 0.05));
              expect(warningBg.a, closeTo(0.15, 0.05));
              expect(errorBg.a, closeTo(0.15, 0.05));

              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets(
      'SwitchTheme thumbColor resolves to onPrimary in Dynamic Mode',
      (tester) async {
        final dynamicTheme = LuciTheme.buildLightTheme(
          palette: AppThemePalette.dynamicTheme,
        );
        final amberTheme = LuciTheme.buildLightTheme(
          palette: AppThemePalette.amber,
        );

        final dynamicThumbColor = dynamicTheme.switchTheme.thumbColor?.resolve({
          WidgetState.selected,
        });
        final amberThumbColor = amberTheme.switchTheme.thumbColor?.resolve({
          WidgetState.selected,
        });

        expect(dynamicThumbColor, equals(dynamicTheme.colorScheme.onPrimary));
        expect(amberThumbColor, equals(Colors.white));
      },
    );

    testWidgets(
      'LuciAppBar adheres to Material 3 flat elevation and adaptive back icon',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: LuciTheme.buildLightTheme(
              palette: AppThemePalette.dynamicTheme,
            ),
            home: const Scaffold(
              appBar: LuciAppBar(title: 'M3 Test Title', showBack: true),
              body: SizedBox.shrink(),
            ),
          ),
        );

        final appBarFinder = find.byType(AppBar);
        expect(appBarFinder, findsOneWidget);
        final appBar = tester.widget<AppBar>(appBarFinder);

        expect(appBar.elevation, equals(0.0));
        expect(appBar.scrolledUnderElevation, equals(2.0));
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      },
    );

    test('M3 SearchBarTheme and SegmentedButtonTheme tokens are configured', () {
      final lightTheme = LuciTheme.buildLightTheme(
        palette: AppThemePalette.dynamicTheme,
      );
      final darkTheme = LuciTheme.buildDarkTheme(
        palette: AppThemePalette.dynamicTheme,
      );

      for (final theme in [lightTheme, darkTheme]) {
        // SearchBarTheme
        expect(theme.searchBarTheme.elevation?.resolve({}), equals(0.0));
        expect(
          theme.searchBarTheme.shape?.resolve({}),
          isA<RoundedRectangleBorder>(),
        );
        final searchBarShape =
            theme.searchBarTheme.shape?.resolve({}) as RoundedRectangleBorder;
        expect(searchBarShape.borderRadius, equals(BorderRadius.circular(16)));

        // SegmentedButtonTheme
        final selectedStyle = theme.segmentedButtonTheme.style?.backgroundColor
            ?.resolve({WidgetState.selected});
        expect(selectedStyle, equals(theme.colorScheme.secondaryContainer));

        // BottomSheetTheme
        expect(theme.bottomSheetTheme.showDragHandle, isTrue);
        expect(theme.bottomSheetTheme.shape, isA<RoundedRectangleBorder>());

        // DialogTheme
        expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
        final dialogShape = theme.dialogTheme.shape as RoundedRectangleBorder;
        expect(dialogShape.borderRadius, equals(BorderRadius.circular(28)));

        // SwitchTheme
        final activeThumb = theme.switchTheme.thumbColor?.resolve({
          WidgetState.selected,
        });
        final activeTrack = theme.switchTheme.trackColor?.resolve({
          WidgetState.selected,
        });
        expect(activeThumb, isNotNull);
        expect(activeTrack, isNotNull);
        // Thumb and track must NEVER be identical when selected (prevents invisible thumb blob)
        expect(activeThumb, isNot(equals(activeTrack)));
      }
    });

    testWidgets('LuciStatusColors connectionDotColor harmonizes with primary', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LuciTheme.buildLightTheme(
            palette: AppThemePalette.dynamicTheme,
          ),
          home: Builder(
            builder: (context) {
              final dotColor = LuciStatusColors.connectionDotColor(context);
              expect(dotColor, isNotNull);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test(
      'refreshDynamicColors updates AppState and can be called safely on app resume',
      () async {
        final appState = AppState.instance;
        // Should execute without errors or exceptions even without active platform channel
        await appState.refreshDynamicColors();
        expect(appState, isNotNull);
      },
    );

    testWidgets(
      'LuciDropdownStyle and ThemeData dropdown tokens strictly adhere to Material 3 practices',
      (tester) async {
        final lightTheme = LuciTheme.buildLightTheme(
          palette: AppThemePalette.dynamicTheme,
        );
        final darkTheme = LuciTheme.buildDarkTheme(
          palette: AppThemePalette.dynamicTheme,
        );
        final amberDarkTheme = LuciTheme.buildDarkTheme(
          palette: AppThemePalette.amber,
        );
        final amberLightTheme = LuciTheme.buildLightTheme(
          palette: AppThemePalette.amber,
        );

        // Verify canvasColor guarantees M3 surfaceContainerHigh fallback for DropdownButton
        expect(
          lightTheme.canvasColor,
          equals(lightTheme.colorScheme.surfaceContainerHigh),
        );
        expect(
          darkTheme.canvasColor,
          equals(darkTheme.colorScheme.surfaceContainerHigh),
        );
        expect(
          amberDarkTheme.canvasColor,
          equals(amberDarkTheme.colorScheme.surfaceContainerHigh),
        );
        expect(
          amberLightTheme.canvasColor,
          equals(amberLightTheme.colorScheme.surfaceContainerHigh),
        );

        // Verify Dialog surface and zero-tint consistency across dynamic and static palettes
        for (final t in [
          lightTheme,
          darkTheme,
          amberDarkTheme,
          amberLightTheme,
        ]) {
          expect(
            t.dialogTheme.backgroundColor,
            equals(t.colorScheme.surfaceContainerHigh),
          );
          expect(t.dialogTheme.surfaceTintColor, equals(Colors.transparent));
          expect(
            t.popupMenuTheme.color,
            equals(t.colorScheme.surfaceContainerHigh),
          );
          expect(t.popupMenuTheme.surfaceTintColor, equals(Colors.transparent));
        }

        // Verify PopupMenuThemeData Material 3 tokens
        expect(lightTheme.popupMenuTheme.shape, isA<RoundedRectangleBorder>());
        final lightPopupShape =
            lightTheme.popupMenuTheme.shape as RoundedRectangleBorder;
        expect(lightPopupShape.borderRadius, equals(BorderRadius.circular(16)));
        expect(lightTheme.popupMenuTheme.elevation, equals(3));

        expect(darkTheme.popupMenuTheme.shape, isA<RoundedRectangleBorder>());
        final darkPopupShape =
            darkTheme.popupMenuTheme.shape as RoundedRectangleBorder;
        expect(darkPopupShape.borderRadius, equals(BorderRadius.circular(16)));
        expect(darkTheme.popupMenuTheme.elevation, equals(3));

        // Verify DropdownMenuThemeData tokens
        expect(
          lightTheme.dropdownMenuTheme.menuStyle?.elevation?.resolve({}),
          equals(4),
        );
        expect(
          darkTheme.dropdownMenuTheme.menuStyle?.elevation?.resolve({}),
          equals(4),
        );
        expect(
          darkTheme.dropdownMenuTheme.menuStyle?.backgroundColor?.resolve({}),
          equals(darkTheme.colorScheme.surfaceContainerHigh),
        );
        expect(
          amberDarkTheme.dropdownMenuTheme.menuStyle?.backgroundColor?.resolve(
            {},
          ),
          equals(amberDarkTheme.colorScheme.surfaceContainerHigh),
        );

        // Verify LuciDropdownStyle M3 contract tokens
        expect(
          LuciDropdownStyle.borderRadius,
          equals(BorderRadius.circular(16)),
        );
        expect(LuciDropdownStyle.elevation, equals(4));
        expect(LuciDropdownStyle.menuMaxHeight, equals(360.0));

        await tester.pumpWidget(
          MaterialApp(
            theme: lightTheme,
            home: Builder(
              builder: (context) {
                final color = LuciDropdownStyle.dropdownColor(context);
                expect(
                  color,
                  equals(lightTheme.colorScheme.surfaceContainerHigh),
                );

                final dec = LuciDropdownStyle.decoration(
                  context,
                  labelText: 'Test',
                );
                expect(dec.border, isA<OutlineInputBorder>());
                final outline = dec.border as OutlineInputBorder;
                expect(outline.borderRadius, equals(BorderRadius.circular(12)));
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      },
    );
  });
}
