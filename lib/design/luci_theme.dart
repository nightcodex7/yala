// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Available curated color palettes for Yet Another LuCI App (YALA).
enum AppThemePalette {
  amber,
  dynamicTheme;

  String get label => switch (this) {
    AppThemePalette.amber => 'YALA Amber',
    AppThemePalette.dynamicTheme => 'Material You',
  };

  String get subtitle => switch (this) {
    AppThemePalette.amber => 'Warm terracotta & rich amber',
    AppThemePalette.dynamicTheme => 'Wallpaper extracted palette',
  };

  IconData get icon => switch (this) {
    AppThemePalette.amber => Icons.palette_rounded,
    AppThemePalette.dynamicTheme => Icons.auto_awesome_rounded,
  };

  Color swatchColor(bool isDark) => switch (this) {
    AppThemePalette.amber => isDark
        ? LuciTheme.amberPrimaryDark
        : LuciTheme.amberPrimaryLight,
    AppThemePalette.dynamicTheme => const Color(0xFF3B82F6),
  };
}

/// Centralized theme provider for Yet Another LuCI App (YALA).
///
/// Supports YALA Amber (signature theme) and Dynamic (Material You) for Light and Dark modes.
class LuciTheme {
  LuciTheme._();

  // YALA Amber (Warm terracotta / soft amber, eye-soothing brand signature)
  static const Color amberPrimaryLight = Color(0xFFC2410C);
  static const Color amberSecondaryLight = Color(0xFFB45309);
  static const Color amberPrimaryDark = Color(0xFFFB923C);
  static const Color amberSecondaryDark = Color(0xFFFBBF24);

  // Backward compatibility brand aliases
  static const Color orangePrimary = Color(0xFFF97316);
  static const Color orangeSecondary = Color(0xFFFB923C);

  // Classic Tertiary
  static const Color classicTertiary = Color(0xFFF59E0B);
  static const Color classicTertiaryLightContainer = Color(0xFFFEF3C7);
  static const Color classicTertiaryDarkContainer = Color(0xFF2C221A);

  // Soft Daylight Light Surfaces (Gentle paper off-white, zero glare)
  static const Color classicLightScaffold = Color(0xFFF8F9FA);
  static const Color classicLightSurface = Color(0xFFFFFFFF);
  static const Color classicLightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color classicLightSurfaceContainerLow = Color(0xFFF3F4F6);
  static const Color classicLightSurfaceContainer = Color(0xFFECEEF1);
  static const Color classicLightSurfaceContainerHigh = Color(0xFFE4E7EB);
  static const Color classicLightSurfaceContainerHighest = Color(0xFFDCDFE4);
  static const Color classicLightOutline = Color(0xFFB0B5BF);
  static const Color classicLightOutlineVariant = Color(0xFFE2E4E8);
  static const Color classicLightOnSurface = Color(0xFF111827);
  static const Color classicLightOnSurfaceVariant = Color(0xFF4B5563);

  // Neutral Charcoal Dark Surfaces (Calming, velvety, zero blue-light eye strain)
  static const Color classicDarkScaffold = Color(0xFF111318);
  static const Color classicDarkSurface = Color(0xFF181A20);
  static const Color classicDarkSurfaceContainerLowest = Color(0xFF0E1014);
  static const Color classicDarkSurfaceContainerLow = Color(0xFF14161B);
  static const Color classicDarkSurfaceContainer = Color(0xFF1E2128);
  static const Color classicDarkSurfaceContainerHigh = Color(0xFF252932);
  static const Color classicDarkSurfaceContainerHighest = Color(0xFF2C313B);
  static const Color classicDarkOutline = Color(0xFF3E4450);
  static const Color classicDarkOutlineVariant = Color(0xFF292D37);
  static const Color classicDarkOnSurface = Color(0xFFE5E7EB);
  static const Color classicDarkOnSurfaceVariant = Color(0xFF9CA3AF);

  // Modern naming aliases
  static const Color neutralLightScaffold = classicLightScaffold;
  static const Color neutralLightSurface = classicLightSurface;
  static const Color neutralDarkScaffold = classicDarkScaffold;
  static const Color neutralDarkSurface = classicDarkSurface;

  /// Fallback dynamic palette for platforms or test environments where
  /// wallpaper color extraction is unavailable.
  static final ColorScheme fallbackDynamicLight = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3B82F6),
    brightness: Brightness.light,
  );

  /// Fallback dynamic dark palette for platforms or test environments where
  /// wallpaper color extraction is unavailable.
  static final ColorScheme fallbackDynamicDark = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3B82F6),
    brightness: Brightness.dark,
  );

  static ColorScheme _buildPaletteColorScheme(
    Brightness brightness,
    AppThemePalette palette,
  ) {
    final isDark = brightness == Brightness.dark;

    if (palette == AppThemePalette.dynamicTheme) {
      return isDark ? fallbackDynamicDark : fallbackDynamicLight;
    }

    if (isDark) {
      return ColorScheme.dark(
        primary: amberPrimaryDark,
        onPrimary: const Color(0xFF1E1B18),
        primaryContainer: const Color(0xFF431407),
        onPrimaryContainer: const Color(0xFFFED7AA),
        secondary: amberSecondaryDark,
        onSecondary: const Color(0xFF1E1B18),
        secondaryContainer: const Color(0xFF451A03),
        onSecondaryContainer: const Color(0xFFFDE68A),
        tertiary: amberSecondaryDark,
        onTertiary: const Color(0xFF1E1B18),
        tertiaryContainer: const Color(0xFF451A03),
        onTertiaryContainer: const Color(0xFFFDE68A),
        error: const Color(0xFFF87171),
        onError: const Color(0xFF450A0A),
        errorContainer: const Color(0xFF7F1D1D).withValues(alpha: 0.3),
        onErrorContainer: const Color(0xFFFECACA),
        surface: classicDarkSurface,
        onSurface: classicDarkOnSurface,
        surfaceContainerLowest: classicDarkSurfaceContainerLowest,
        surfaceContainerLow: classicDarkSurfaceContainerLow,
        surfaceContainer: classicDarkSurfaceContainer,
        surfaceContainerHigh: classicDarkSurfaceContainerHigh,
        surfaceContainerHighest: classicDarkSurfaceContainerHighest,
        onSurfaceVariant: classicDarkOnSurfaceVariant,
        outline: classicDarkOutline,
        outlineVariant: classicDarkOutlineVariant,
        inverseSurface: const Color(0xFFF8FAFC),
        onInverseSurface: const Color(0xFF0F172A),
        inversePrimary: amberPrimaryDark,
      );
    } else {
      return ColorScheme.light(
        primary: amberPrimaryLight,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFFFEDD5),
        onPrimaryContainer: const Color(0xFF7C2D12),
        secondary: amberSecondaryLight,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFFEF3C7),
        onSecondaryContainer: const Color(0xFF78350F),
        tertiary: amberSecondaryLight,
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFFEF3C7),
        onTertiaryContainer: const Color(0xFF78350F),
        error: const Color(0xFFDC2626),
        onError: Colors.white,
        errorContainer: const Color(0xFFFEE2E2),
        onErrorContainer: const Color(0xFF991B1B),
        surface: classicLightSurface,
        onSurface: classicLightOnSurface,
        surfaceContainerLowest: classicLightSurfaceContainerLowest,
        surfaceContainerLow: classicLightSurfaceContainerLow,
        surfaceContainer: classicLightSurfaceContainer,
        surfaceContainerHigh: classicLightSurfaceContainerHigh,
        surfaceContainerHighest: classicLightSurfaceContainerHighest,
        onSurfaceVariant: classicLightOnSurfaceVariant,
        outline: classicLightOutline,
        outlineVariant: classicLightOutlineVariant,
        inverseSurface: const Color(0xFF1E293B),
        onInverseSurface: const Color(0xFFF8FAFC),
        inversePrimary: amberPrimaryLight,
      );
    }
  }

  /// Builds the light [ThemeData].
  ///
  /// If [dynamicColorScheme] is provided, applies a Material You dynamic scheme
  /// with harmonized surfaces and text colors. If null, applies the selected
  /// [palette] (defaults to [AppThemePalette.amber] for classic compatibility).
  static ThemeData buildLightTheme({
    ColorScheme? dynamicColorScheme,
    AppThemePalette palette = AppThemePalette.amber,
  }) {
    final isDynamic =
        dynamicColorScheme != null || palette == AppThemePalette.dynamicTheme;
    final colorScheme = dynamicColorScheme != null
        ? dynamicColorScheme.harmonized()
        : _buildPaletteColorScheme(Brightness.light, palette);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.geistTextTheme(
        ThemeData(brightness: Brightness.light).textTheme,
      ),
      scaffoldBackgroundColor: isDynamic
          ? colorScheme.surfaceContainerLowest
          : classicLightScaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.geist(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1.0,
          ),
        ),
        color: isDynamic ? colorScheme.surface : classicLightSurface,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primaryContainer;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onPrimaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainerHigh
            : classicLightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainerLow
            : classicLightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  /// Builds the dark [ThemeData].
  ///
  /// If [dynamicColorScheme] is provided, applies a Material You dynamic scheme
  /// with harmonized surfaces and text colors. If null, applies the selected
  /// [palette] (defaults to [AppThemePalette.amber] for classic compatibility).
  static ThemeData buildDarkTheme({
    ColorScheme? dynamicColorScheme,
    AppThemePalette palette = AppThemePalette.amber,
  }) {
    final isDynamic =
        dynamicColorScheme != null || palette == AppThemePalette.dynamicTheme;
    final colorScheme = dynamicColorScheme != null
        ? dynamicColorScheme.harmonized()
        : _buildPaletteColorScheme(Brightness.dark, palette);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.geistTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ),
      scaffoldBackgroundColor: isDynamic
          ? colorScheme.surfaceContainerLowest
          : classicDarkScaffold,
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.geist(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1.0,
          ),
        ),
        color: isDynamic ? colorScheme.surfaceContainer : classicDarkSurface,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primaryContainer;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onPrimaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainerHigh
            : classicDarkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainer
            : classicDarkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}
