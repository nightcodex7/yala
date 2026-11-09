// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/design/luci_theme.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/screens/login_screen.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/screens/settings_screen.dart';
import 'package:yet_another_luci_app/screens/splash_screen.dart';
import 'package:yet_another_luci_app/screens/onboarding_screen.dart';

import 'package:yet_another_luci_app/models/router_capabilities.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Prevent runtime font fetching from Google servers (e.g. fonts.gstatic.com)
  // Ensures 100% offline self-containment for F-Droid and reproducible builds.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Modern Android Edge-to-Edge System Bar Integration
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Register all open-source licenses and upstream attributions
  registerOpenSourceLicenses();

  // Low-RAM & Smooth Scrolling Optimization: Cap image memory cache (30MB max, 100 entries max)
  PaintingBinding.instance.imageCache.maximumSizeBytes = 30 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;

  // Global Flutter error boundary:
  // In release mode, the default RenderErrorBox inflates to 100,000 pixels on unbounded constraints
  // (such as inside a SingleChildScrollView / Column), causing infinite scrolling blank grey voids.
  // Instead, gracefully log the exception and render a collapsed fallback box.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    Logger.exception(
      'Flutter framework captured widget build exception',
      details.exception,
      details.stack ?? StackTrace.current,
    );
    bool isDebug = false;
    assert(() {
      isDebug = true;
      return true;
    }());
    if (isDebug) {
      return ErrorWidget.withDetails(
        message: details.exception.toString(),
        error: details.exception is FlutterError
            ? details.exception as FlutterError
            : null,
      );
    }
    return const SizedBox.shrink();
  };

  // Enable semantics early so AccessibilityNodeInfo reports scrollable to OEM screenshot engines immediately
  SemanticsBinding.instance.ensureSemantics();

  // Pre-hydrate app preferences and Monet dynamic colors before building Frame 1 to eliminate theme flicker
  try {
    final prefs = await SharedPreferences.getInstance();
    await AppState.preHydrate(prefs: prefs);
  } catch (e, stack) {
    Logger.exception('Pre-hydration failed in main()', e, stack);
  }

  runApp(const ProviderScope(child: LuCIApp()));
}

/// Standardized scroll behavior ensuring native long/autoscroll screenshot engine compatibility
/// across all Android OEMs (Xiaomi MIUI/HyperOS, Samsung OneUI, Oppo ColorOS, Vivo FuntouchOS, Stock Android 12+).
class LuciScrollBehavior extends MaterialScrollBehavior {
  const LuciScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Disable stretching overscroll effect so OEM screenshot stitching engines
    // (Xiaomi HyperOS/MIUI, Samsung OneUI, ColorOS) do not encounter pixel warping/distortion at boundaries.
    return child;
  }
}

final appStateProvider = ChangeNotifierProvider<AppState>(
  (ref) => AppState.instance,
);

final routerCapabilitiesProvider = Provider<RouterCapabilities?>((ref) {
  return ref.watch(appStateProvider).capabilities;
});

class LuCIApp extends ConsumerWidget {
  const LuCIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appStateProvider.select((s) => s.themeMode));
    final themePalette = ref.watch(
      appStateProvider.select((s) => s.themePalette),
    );
    final appLocale = ref.watch(appStateProvider.select((s) => s.locale));
    final preloadedLight = ref.watch(
      appStateProvider.select((s) => s.preloadedLightDynamic),
    );
    final preloadedDark = ref.watch(
      appStateProvider.select((s) => s.preloadedDarkDynamic),
    );
    final useDynamicTheme = themePalette == AppThemePalette.dynamicTheme;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final effectiveLightDynamic =
            preloadedLight ?? lightDynamic ?? LuciTheme.fallbackDynamicLight;
        final effectiveDarkDynamic =
            preloadedDark ?? darkDynamic ?? LuciTheme.fallbackDynamicDark;

        final lightTheme = LuciTheme.buildLightTheme(
          dynamicColorScheme: useDynamicTheme ? effectiveLightDynamic : null,
          palette: themePalette,
        );
        final darkTheme = LuciTheme.buildDarkTheme(
          dynamicColorScheme: useDynamicTheme ? effectiveDarkDynamic : null,
          palette: themePalette,
        );

        return MaterialApp(
          navigatorKey: LuciToastManager.navigatorKey,
          title: 'Yet Another LuCI App',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const LuciScrollBehavior(),
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            // Accessibility large font support: Clamping minimum to 0.85 to avoid microscopic text,
            // while supporting full Android accessibility scaling (up to 2.5x+) without arbitrary low caps.
            final effectiveTextScaler = mediaQuery.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 2.5,
            );
            return MediaQuery(
              data: mediaQuery.copyWith(textScaler: effectiveTextScaler),
              child: child ?? const SizedBox.shrink(),
            );
          },
          locale: appLocale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          localeResolutionCallback: (locale, supportedLocales) {
            if (locale == null) return const Locale('en');
            if (locale.languageCode == 'pt') {
              if (locale.countryCode == 'BR') {
                return const Locale('pt', 'BR');
              }
              return const Locale('pt');
            }
            if (locale.languageCode == 'zh') {
              return const Locale('zh');
            }
            for (final supported in supportedLocales) {
              if (supported.languageCode == locale.languageCode &&
                  supported.countryCode == null) {
                return supported;
              }
            }
            // English is the fallback as well as base
            return const Locale('en');
          },
          initialRoute: '/splash',
          routes: {
            '/splash': (context) => const SplashScreen(),
            '/onboarding': (context) => const OnboardingScreen(),
            '/login': (context) => const LoginScreen(),
            '/': (context) => const MainScreen(),
            '/settings': (context) => const SettingsScreen(),
          },
        );
      },
    );
  }
}

/// Registers all open-source licenses, copyleft notices, and third-party attributions
/// with Flutter's LicenseRegistry.
void registerOpenSourceLicenses() {
  // Register SIL Open Font License (OFL) for bundled Geist and Geist Mono fonts
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks([
      'google_fonts',
      'Geist',
      'Geist Mono',
    ], license);
  });

  // Register YALA's GPLv3 copyleft license and copyright attributions in Flutter LicenseRegistry
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['yet_another_luci_app (yala)'],
      '''Yet Another LuCI App (yala)
Original work Copyright (C) 2025-2026 cogwheel0
Modifications Copyright (C) 2026 @nightcodex7

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.''',
    );
  });

  // Register OpenWrt luci-app-advanced-reboot attribution and GPLv3 license in Flutter LicenseRegistry
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['luci-app-advanced-reboot (OpenWrt)'],
      '''luci-app-advanced-reboot
Copyright (C) 2017-2024 Stan Grishin <stangri@melmac.ca>
Copyright (C) OpenWrt Contributors
Repository: https://github.com/openwrt/luci/tree/main/applications/luci-app-advanced-reboot

Dual-firmware partition discovery, bootloader environment inspection (boot_part, boot_part_ready, DualImageFlag), and read-only alternate partition mounting techniques adapted from luci-app-advanced-reboot for YALA's Advanced Reboot subsystem.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.''',
    );
  });

  // Register dartssh2 MIT license — SSH client library used by SSH Console and background SSH service
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['dartssh2'],
      '''MIT License

Copyright (c) 2022 xuty (TerminalStudio)
https://github.com/TerminalStudio/dartssh2

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''',
    );
  });

  // Register xterm MIT license — terminal emulator widget used by the SSH Console screen
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['xterm'],
      '''MIT License

Copyright (c) 2020 xuty
https://github.com/TerminalStudio/xterm.dart

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''',
    );
  });

  // Register dynamic_color Apache-2.0 license — Google Material dynamic color extraction package
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['dynamic_color'],
      '''Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/

Copyright (c) Google LLC
https://github.com/material-foundation/flutter-packages/tree/main/packages/dynamic_color

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.''',
    );
  });
}
