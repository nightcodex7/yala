// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/luci_theme.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/screens/settings_screen.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/session_controller.dart';
import 'package:yet_another_luci_app/utils/http_client_manager.dart';
import 'package:yet_another_luci_app/widgets/theme_router_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LuciTheme Builder Tests', () {
    test(
      'buildLightTheme with default palette produces eye-soothing YALA Amber theme',
      () {
        final theme = LuciTheme.buildLightTheme(dynamicColorScheme: null);

        expect(theme.brightness, Brightness.light);
        expect(theme.colorScheme.primary, LuciTheme.amberPrimaryLight);
        expect(theme.scaffoldBackgroundColor, LuciTheme.neutralLightScaffold);
        expect(theme.cardTheme.color, LuciTheme.neutralLightSurface);
        expect(theme.cardTheme.elevation, 1);

        // Verify WCAG AAA contrast ratio on containers (> 7:1)
        final onPrimaryLum = theme.colorScheme.onPrimaryContainer.computeLuminance();
        final primaryContainerLum = theme.colorScheme.primaryContainer.computeLuminance();
        final primaryRatio = (primaryContainerLum > onPrimaryLum)
            ? (primaryContainerLum + 0.05) / (onPrimaryLum + 0.05)
            : (onPrimaryLum + 0.05) / (primaryContainerLum + 0.05);
        expect(primaryRatio, greaterThan(7.0));

        final onSecondaryLum = theme.colorScheme.onSecondaryContainer.computeLuminance();
        final secondaryContainerLum = theme.colorScheme.secondaryContainer.computeLuminance();
        final secondaryRatio = (secondaryContainerLum > onSecondaryLum)
            ? (secondaryContainerLum + 0.05) / (onSecondaryLum + 0.05)
            : (onSecondaryLum + 0.05) / (secondaryContainerLum + 0.05);
        expect(secondaryRatio, greaterThan(7.0));
      },
    );

    test(
      'buildDarkTheme with default palette produces eye-soothing neutral charcoal amber theme',
      () {
        final theme = LuciTheme.buildDarkTheme(dynamicColorScheme: null);

        expect(theme.brightness, Brightness.dark);
        expect(theme.colorScheme.primary, LuciTheme.amberPrimaryDark);
        expect(theme.scaffoldBackgroundColor, LuciTheme.neutralDarkScaffold);
        expect(theme.cardTheme.color, LuciTheme.neutralDarkSurface);
        expect(theme.cardTheme.elevation, 2);

        // Verify WCAG AAA contrast ratio on containers (> 7:1)
        final onPrimaryLum = theme.colorScheme.onPrimaryContainer.computeLuminance();
        final primaryContainerLum = theme.colorScheme.primaryContainer.computeLuminance();
        final primaryRatio = (onPrimaryLum > primaryContainerLum)
            ? (onPrimaryLum + 0.05) / (primaryContainerLum + 0.05)
            : (primaryContainerLum + 0.05) / (onPrimaryLum + 0.05);
        expect(primaryRatio, greaterThan(7.0));

        final onSecondaryLum = theme.colorScheme.onSecondaryContainer.computeLuminance();
        final secondaryContainerLum = theme.colorScheme.secondaryContainer.computeLuminance();
        final secondaryRatio = (onSecondaryLum > secondaryContainerLum)
            ? (onSecondaryLum + 0.05) / (secondaryContainerLum + 0.05)
            : (secondaryContainerLum + 0.05) / (onSecondaryLum + 0.05);
        expect(secondaryRatio, greaterThan(7.0));
      },
    );

    test('AppThemePalette contains strictly YALA Amber and Material You', () {
      expect(AppThemePalette.values, [
        AppThemePalette.amber,
        AppThemePalette.dynamicTheme,
      ]);
      expect(AppThemePalette.amber.label, 'YALA Amber');
      expect(AppThemePalette.dynamicTheme.label, 'Material You');
    });

    test(
      'buildLightTheme with dynamicColorScheme applies Material You palette',
      () {
        const dynamicPrimary = Color(0xFF006C4C);
        final dynamicScheme = ColorScheme.fromSeed(
          seedColor: dynamicPrimary,
          brightness: Brightness.light,
        );

        final theme = LuciTheme.buildLightTheme(
          dynamicColorScheme: dynamicScheme,
          palette: AppThemePalette.dynamicTheme,
        );

        expect(theme.brightness, Brightness.light);
        expect(theme.colorScheme.primary, dynamicScheme.primary);
        expect(
          theme.scaffoldBackgroundColor,
          dynamicScheme.surfaceContainerLowest,
        );
        expect(theme.cardTheme.color, dynamicScheme.surface);
        expect(
          theme.appBarTheme.titleTextStyle?.color,
          dynamicScheme.onSurface,
        );
      },
    );

    test(
      'buildDarkTheme with dynamicColorScheme applies Material You dark palette',
      () {
        const dynamicPrimary = Color(0xFF80D5AB);
        final dynamicScheme = ColorScheme.fromSeed(
          seedColor: dynamicPrimary,
          brightness: Brightness.dark,
        );

        final theme = LuciTheme.buildDarkTheme(
          dynamicColorScheme: dynamicScheme,
          palette: AppThemePalette.dynamicTheme,
        );

        expect(theme.brightness, Brightness.dark);
        expect(theme.colorScheme.primary, dynamicScheme.primary);
        expect(
          theme.scaffoldBackgroundColor,
          dynamicScheme.surfaceContainerLowest,
        );
        expect(theme.cardTheme.color, dynamicScheme.surfaceContainer);
        expect(
          theme.appBarTheme.titleTextStyle?.color,
          dynamicScheme.onSurface,
        );
      },
    );

    test(
      'fallbackDynamicLight and fallbackDynamicDark are valid and non-null',
      () {
        expect(LuciTheme.fallbackDynamicLight.brightness, Brightness.light);
        expect(LuciTheme.fallbackDynamicDark.brightness, Brightness.dark);
      },
    );
  });

  group('SessionController Dynamic Theming & Palette State Tests', () {
    late SecureStorageService secureStorage;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      secureStorage = SecureStorageService();
    });

    test('themePalette defaults to amber and persists correctly', () async {
      int notifyCount = 0;
      final controller = SessionController(
        apiServiceRef: () => null,
        authServiceRef: () => null,
        routerServiceRef: () => null,
        secureStorageServiceRef: () => secureStorage,
        httpClientManagerRef: () => HttpClientManager(),
        dashboardControllerRef: () => null,
        cancelThroughputTimer: () {},
        startThroughputTimer: () {},
        fetchDashboardData: ({bool force = false}) async {},
        initializeServices: () {},
        setLoadingState: (_) {},
        setErrorState: (_) {},
        notifyListeners: () => notifyCount++,
      );

      expect(controller.themePalette, AppThemePalette.amber);
      expect(controller.useDynamicTheme, isFalse);

      // Select dynamic theme (Material You)
      await controller.setThemePalette(AppThemePalette.dynamicTheme);
      expect(controller.themePalette, AppThemePalette.dynamicTheme);
      expect(controller.useDynamicTheme, isTrue);
      expect(notifyCount, 1);

      // Verify stored value
      final stored = await secureStorage.readValue('appThemePalette');
      expect(stored, 'dynamicTheme');

      // Select amber palette
      await controller.setThemePalette(AppThemePalette.amber);
      expect(controller.themePalette, AppThemePalette.amber);
      expect(controller.useDynamicTheme, isFalse);

      // Verify legacy migration fallback
      await secureStorage.writeValue('appThemePalette', 'emerald');
      final legacyController = SessionController(
        apiServiceRef: () => null,
        authServiceRef: () => null,
        routerServiceRef: () => null,
        secureStorageServiceRef: () => secureStorage,
        httpClientManagerRef: () => HttpClientManager(),
        dashboardControllerRef: () => null,
        cancelThroughputTimer: () {},
        startThroughputTimer: () {},
        fetchDashboardData: ({bool force = false}) async {},
        initializeServices: () {},
        setLoadingState: (_) {},
        setErrorState: (_) {},
        notifyListeners: () {},
      );

      await legacyController.loadDynamicTheme();
      expect(legacyController.themePalette, AppThemePalette.amber);
      expect(legacyController.useDynamicTheme, isFalse);

      // Test setDynamicTheme
      await legacyController.setDynamicTheme(true);
      expect(legacyController.themePalette, AppThemePalette.dynamicTheme);
      expect(legacyController.useDynamicTheme, isTrue);

      await legacyController.setDynamicTheme(false);
      expect(legacyController.themePalette, AppThemePalette.amber);
      expect(legacyController.useDynamicTheme, isFalse);
    });
  });

  group('SettingsScreen Theme Palette Widget Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
      'Renders strictly YALA Amber and Material You and responds to selection',
      (tester) async {
        final appState = AppState.instance;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const MaterialApp(home: SettingsScreen()),
          ),
        );

        await tester.pumpAndSettle();

        // Verify only 2 palettes are rendered
        expect(find.text('YALA Amber'), findsWidgets);
        expect(find.text('Material You'), findsOneWidget);

        // Verify removed palettes are NOT present
        expect(find.text('Nordic Emerald'), findsNothing);
        expect(find.text('Ocean Teal'), findsNothing);
        expect(find.text('Deep Indigo'), findsNothing);

        // Initially palette is amber
        expect(appState.themePalette, AppThemePalette.amber);

        // Tap on 'Material You'
        await tester.tap(find.text('Material You'));
        await tester.pumpAndSettle();
        expect(appState.themePalette, AppThemePalette.dynamicTheme);
        expect(appState.useDynamicTheme, isTrue);

        // Tap on 'YALA Amber'
        await tester.tap(find.text('YALA Amber').last);
        await tester.pumpAndSettle();
        expect(appState.themePalette, AppThemePalette.amber);
        expect(appState.useDynamicTheme, isFalse);
      },
    );
  });

  group('ThemeRouterLogo Dynamic Theming Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
      'ThemeRouterLogo uses colorScheme.primary when dynamic theme is active',
      (tester) async {
        final appState = AppState.instance;
        await appState.setDynamicTheme(true);

        const customDynamicPrimary = Color(0xFF00B4D8);
        final dynamicTheme = ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: customDynamicPrimary,
            brightness: Brightness.dark,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: MaterialApp(
              theme: dynamicTheme,
              home: const Scaffold(
                body: ThemeRouterLogo(width: 80, height: 80),
              ),
            ),
          ),
        );

        final imageWidget = tester.widget<Image>(find.byType(Image));
        expect(imageWidget.color, dynamicTheme.colorScheme.primary);
      },
    );

    testWidgets(
      'ThemeRouterLogo uses classic color when dynamic theme is disabled',
      (tester) async {
        final appState = AppState.instance;
        await appState.setDynamicTheme(false);

        final classicDarkTheme = ThemeData(
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: MaterialApp(
              theme: classicDarkTheme,
              home: const Scaffold(
                body: ThemeRouterLogo(width: 80, height: 80),
              ),
            ),
          ),
        );

        final imageWidget = tester.widget<Image>(find.byType(Image));
        expect(imageWidget.color, Colors.white);
      },
    );

    testWidgets(
      'ThemeRouterLogo respects followDynamicTheme: false even if dynamic theme is active',
      (tester) async {
        final appState = AppState.instance;
        await appState.setDynamicTheme(true);

        final dynamicTheme = ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: MaterialApp(
              theme: dynamicTheme,
              home: const Scaffold(
                body: ThemeRouterLogo(
                  width: 80,
                  height: 80,
                  followDynamicTheme: false,
                ),
              ),
            ),
          ),
        );

        final imageWidget = tester.widget<Image>(find.byType(Image));
        expect(imageWidget.color, Colors.white);
      },
    );
  });
}
