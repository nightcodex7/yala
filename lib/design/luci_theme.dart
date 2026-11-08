// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    AppThemePalette.amber =>
      isDark ? LuciTheme.amberPrimaryDark : LuciTheme.amberPrimaryLight,
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
      return const ColorScheme.light(
        primary: amberPrimaryLight,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFFFEDD5),
        onPrimaryContainer: Color(0xFF7C2D12),
        secondary: amberSecondaryLight,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFFEF3C7),
        onSecondaryContainer: Color(0xFF78350F),
        tertiary: amberSecondaryLight,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFFEF3C7),
        onTertiaryContainer: Color(0xFF78350F),
        error: Color(0xFFDC2626),
        onError: Colors.white,
        errorContainer: Color(0xFFFEE2E2),
        onErrorContainer: Color(0xFF991B1B),
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
        inverseSurface: Color(0xFF1E293B),
        onInverseSurface: Color(0xFFF8FAFC),
        inversePrimary: amberPrimaryLight,
      );
    }
  }

  /// Helper to build Geist TextTheme with robust international font fallbacks
  /// (Devanagari, Bengali, Cyrillic, Chinese, Arabic, and system glyphs)
  /// so non-Latin scripts never render as missing-glyph boxes.
  static TextTheme _buildGeistTextTheme(Brightness brightness) {
    const fallbacks = ['Noto Sans', 'Roboto', 'Arial', 'sans-serif'];
    final base = GoogleFonts.geistTextTheme(
      ThemeData(brightness: brightness).textTheme,
    );
    return base.apply(fontFamilyFallback: fallbacks);
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
      canvasColor: colorScheme.surfaceContainerHigh,
      textTheme: _buildGeistTextTheme(Brightness.light),
      scaffoldBackgroundColor: isDynamic
          ? colorScheme.surfaceContainerLowest
          : classicLightScaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
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
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return isDynamic ? colorScheme.onPrimary : Colors.white;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return states.contains(WidgetState.selected)
                ? colorScheme.onSurface.withValues(alpha: 0.12)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.12);
          }
          return colorScheme.outline.withValues(alpha: 0.5);
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
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainer
            : classicLightSurface,
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onPrimaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.geist(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            );
          }
          return GoogleFonts.geist(
            fontSize: 11,
            fontWeight: FontWeight.normal,
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainerLowest
            : classicLightScaffold,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: GoogleFonts.geist(
          color: colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: GoogleFonts.geist(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainerLow
            : classicLightSurface,
        indicatorColor: colorScheme.primaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDynamic
            ? colorScheme.surfaceContainerLow
            : classicLightSurfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2.0),
        ),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontSize: 14,
        ),
        labelStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
        ),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: GoogleFonts.geist(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: GoogleFonts.geist(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(color: colorScheme.outlineVariant, width: 1.0),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: GoogleFonts.geist(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 6,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: GoogleFonts.geist(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        thickness: 1.0,
        space: 1.0,
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: colorScheme.primary,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.geist(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        unselectedLabelStyle: GoogleFonts.geist(
          fontWeight: FontWeight.normal,
          fontSize: 14,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        titleTextStyle: GoogleFonts.geist(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: colorScheme.onSurface,
        ),
        subtitleTextStyle: GoogleFonts.geist(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: colorScheme.error,
        textColor: colorScheme.onError,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: colorScheme.onInverseSurface, fontSize: 12),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.geist(
          fontSize: 14,
          color: colorScheme.onSurface,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            colorScheme.surfaceContainerHigh,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          elevation: const WidgetStatePropertyAll(4),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            colorScheme.surfaceContainerHigh,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        ),
        hintStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 13, color: colorScheme.onSurface),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.secondaryContainer;
            }
            return colorScheme.surfaceContainerLow;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onSecondaryContainer;
            }
            return colorScheme.onSurfaceVariant;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
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
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: GoogleFonts.geist(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        contentTextStyle: GoogleFonts.geist(
          fontSize: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 16,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainerLow
            : classicLightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        showDragHandle: true,
        dragHandleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        dragHandleSize: const Size(32, 4),
        constraints: const BoxConstraints(maxWidth: 640),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
      canvasColor: colorScheme.surfaceContainerHigh,
      textTheme: _buildGeistTextTheme(Brightness.dark),
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
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
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
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return isDynamic ? colorScheme.onPrimary : Colors.white;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return states.contains(WidgetState.selected)
                ? colorScheme.onSurface.withValues(alpha: 0.12)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.12);
          }
          return colorScheme.outline.withValues(alpha: 0.5);
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
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainer
            : classicDarkSurface,
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onPrimaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.geist(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            );
          }
          return GoogleFonts.geist(
            fontSize: 11,
            fontWeight: FontWeight.normal,
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainerLowest
            : classicDarkScaffold,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: GoogleFonts.geist(
          color: colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: GoogleFonts.geist(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainerLow
            : classicDarkSurface,
        indicatorColor: colorScheme.primaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDynamic
            ? colorScheme.surfaceContainerLow
            : classicDarkSurfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2.0),
        ),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontSize: 14,
        ),
        labelStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
        ),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: GoogleFonts.geist(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: GoogleFonts.geist(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(color: colorScheme.outlineVariant, width: 1.0),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: GoogleFonts.geist(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 6,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: GoogleFonts.geist(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        thickness: 1.0,
        space: 1.0,
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: colorScheme.primary,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.geist(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        unselectedLabelStyle: GoogleFonts.geist(
          fontWeight: FontWeight.normal,
          fontSize: 14,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        titleTextStyle: GoogleFonts.geist(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: colorScheme.onSurface,
        ),
        subtitleTextStyle: GoogleFonts.geist(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: colorScheme.error,
        textColor: colorScheme.onError,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: colorScheme.onInverseSurface, fontSize: 12),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.geist(
          fontSize: 14,
          color: colorScheme.onSurface,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            colorScheme.surfaceContainerHigh,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          elevation: const WidgetStatePropertyAll(4),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            colorScheme.surfaceContainerHigh,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        ),
        hintStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 13, color: colorScheme.onSurface),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.secondaryContainer;
            }
            return colorScheme.surfaceContainerLow;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onSecondaryContainer;
            }
            return colorScheme.onSurfaceVariant;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: GoogleFonts.geist(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        contentTextStyle: GoogleFonts.geist(
          fontSize: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 16,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDynamic
            ? colorScheme.surfaceContainer
            : classicDarkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        showDragHandle: true,
        dragHandleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        dragHandleSize: const Size(32, 4),
        constraints: const BoxConstraints(maxWidth: 640),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }
}
