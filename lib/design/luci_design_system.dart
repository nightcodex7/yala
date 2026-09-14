// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Standardized color tokens for throughput and data streams
class LuciColors {
  /// Primary theme color
  static const Color primary = Color(0xFF2563EB);
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);

  /// Download / Receive (RX) throughput color - nightcode Orange (#F97316)
  static const Color rx = Color(0xFFF97316);
  static const Color rxLight = Color(0xFFFB923C);

  /// Upload / Transmit (TX) throughput color - Distinct Blue (#2563EB)
  static const Color tx = Color(0xFF2563EB);
  static const Color txLight = Color(0xFF3B82F6);
}

/// Semantic status colors calibrated for WCAG AA contrast on dark surfaces.
/// All values pass ≥ 4.5:1 on the app's dark scaffold (#0F1523).
/// Use these instead of raw Colors.green / Colors.amber in status indicators.
class LuciStatusColors {
  /// Interface / service active / connected (green-500, 4.54:1 on dark bg)
  static const Color connected = Color(0xFF22C55E);

  /// Warning / reconnecting / amber state (amber-400, 8.9:1 on dark bg)
  static const Color warning = Color(0xFFFBBF24);

  /// Error / disconnected — resolved from colorScheme.error in context;
  /// use this constant only for non-themed containers.
  static const Color error = Color(0xFFEF4444);

  /// Live connection dot (green-400, 6.5:1) — intentionally lighter than
  /// [connected] to distinguish the header dot from interface up/down badges.
  static const Color connectionDot = Color(0xFF4ADE80);

  /// Inactive / disabled state (neutral grey)
  static const Color inactive = Color(0xFF64748B);

  /// Info status color
  static const Color info = Color(0xFF3B82F6);

  static Color successBg(BuildContext context) =>
      const Color(0xFF22C55E).withValues(alpha: 0.15);
  static Color successBorder(BuildContext context) =>
      const Color(0xFF22C55E).withValues(alpha: 0.4);
  static Color successText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF4ADE80)
      : const Color(0xFF15803D);

  static Color errorBg(BuildContext context) =>
      const Color(0xFFEF4444).withValues(alpha: 0.15);
  static Color errorBorder(BuildContext context) =>
      const Color(0xFFEF4444).withValues(alpha: 0.4);
  static Color errorText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFF87171)
      : const Color(0xFFDC2626);

  static Color warningBg(BuildContext context) =>
      const Color(0xFFFBBF24).withValues(alpha: 0.15);
  static Color warningBorder(BuildContext context) =>
      const Color(0xFFFBBF24).withValues(alpha: 0.4);
  static Color warningText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFCD34D)
      : const Color(0xFFB45309);

  static Color infoBg(BuildContext context) =>
      const Color(0xFF3B82F6).withValues(alpha: 0.15);
  static Color infoBorder(BuildContext context) =>
      const Color(0xFF3B82F6).withValues(alpha: 0.4);
  static Color infoText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF60A5FA)
      : const Color(0xFF1D4ED8);
}

/// Standardized spacing constants for consistent layout
class LuciSpacing {
  static const double xs = 4.0; // Micro spacing
  static const double sm = 8.0; // Small spacing
  static const double md = 16.0; // Standard spacing
  static const double lg = 24.0; // Large spacing
  static const double xl = 32.0; // Extra large spacing
  static const double xxl = 48.0; // Section spacing
}

/// Standardized text styles for consistent typography
class LuciTextStyles {
  static TextStyle sectionHeader(BuildContext context) {
    return Theme.of(context).textTheme.titleSmall!.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.8,
    );
  }

  static TextStyle cardTitle(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  static TextStyle cardSubtitle(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall!.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
    );
  }

  static TextStyle detailLabel(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall!.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  static TextStyle detailValue(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontWeight: FontWeight.w500,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  static TextStyle errorText(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: Theme.of(context).colorScheme.onErrorContainer,
    );
  }
}

/// Centralized typography helpers for Geist and Geist Mono.
///
/// Use [LuciTypography.monoStyle] anywhere a monospace font is needed
/// (IP addresses, config values, RPC output, SSH logs, etc.) instead of
/// raw `fontFamily: 'monospace'` strings.
class LuciTypography {
  /// Returns a [TextStyle] using Geist Mono with optional overrides.
  /// This is the single source of truth for all mono text in the app.
  static TextStyle monoStyle({
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.geistMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Returns a [TextStyle] using Geist (UI font) with optional overrides.
  static TextStyle uiStyle({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.geist(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }
}

/// Standardized animation constants for consistent motion
class LuciAnimations {
  // Standard durations
  static const Duration fast = Duration(
    milliseconds: 200,
  ); // Micro interactions
  static const Duration standard = Duration(
    milliseconds: 400,
  ); // Card expansions
  static const Duration slow = Duration(milliseconds: 600); // Page transitions
  static const Duration chart = Duration(
    milliseconds: 800,
  ); // Data visualizations

  // Standard curves
  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
  static const Curve elastic = Curves.easeOutCubic;
}

/// Standardized card design system
class LuciCardStyles {
  static BorderRadius standardRadius = BorderRadius.circular(16.0);
  static BorderRadius largeRadius = BorderRadius.circular(20.0);

  static BoxDecoration standardCard(
    BuildContext context, {
    bool isElevated = false,
    bool isSelected = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: colorScheme.surface,
      borderRadius: standardRadius,
      border: Border.all(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.3)
            : colorScheme.outlineVariant.withValues(alpha: 0.2),
        width: isSelected ? 2 : 1,
      ),
      boxShadow: isElevated
          ? [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
    );
  }

  static Widget standardCardWrapper({
    required BuildContext context,
    required Widget child,
    bool isElevated = false,
    bool isSelected = false,
    VoidCallback? onTap,
    EdgeInsets? margin,
    EdgeInsets? padding,
  }) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: LuciSpacing.sm),
      decoration: standardCard(
        context,
        isElevated: isElevated,
        isSelected: isSelected,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: standardRadius,
        child: InkWell(
          borderRadius: standardRadius,
          onTap: onTap,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(LuciSpacing.md),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Standardized status indicators
class LuciStatusIndicators {
  static Widget statusDot(
    BuildContext context,
    bool isActive, {
    double size = 10.0,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isActive ? LuciStatusColors.connected : colorScheme.error,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.surface, width: 1.5),
      ),
    );
  }

  static Widget statusChip(BuildContext context, String label, bool isActive) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: isActive ? colorScheme.onPrimary : colorScheme.onError,
      ),
      backgroundColor: isActive
          ? colorScheme.primary.withValues(alpha: 0.8)
          : colorScheme.error.withValues(alpha: 0.7),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

/// Material 3 Window Size Class breakpoints for adaptive layouts.
///
/// Compact  < 600dp  — phones in portrait, narrow foldables
/// Medium   < 840dp  — tablets in portrait, large phones landscape, Chromebooks in app window
/// Expanded >= 840dp — tablets in landscape, Chromebooks fullscreen, DeX
///
/// Usage:
/// ```dart
/// final isTablet = LuciBreakpoints.isTablet(context);
/// final isExpanded = LuciBreakpoints.isExpanded(context);
/// ```
class LuciBreakpoints {
  /// Compact: phone-sized screen (< 600dp). Use single-column layouts.
  static const double compact = 600.0;

  /// Medium: tablet portrait / large phone landscape (600dp–839dp).
  /// Use NavigationRail, optional 2-column layouts.
  static const double medium = 840.0;

  /// Expanded: tablet landscape / Chromebook (>= 840dp).
  /// Use NavigationDrawer or persistent NavigationRail, 2+ column grids.
  static const double expanded = 840.0;

  /// Returns true when the layout width is in the Medium or Expanded window class
  /// and the available height is sufficient for vertical navigation rail display (≥ 600dp width & ≥ 400dp height).
  static bool isTablet(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= compact && size.height >= 400.0;
  }

  /// Returns true only for the Expanded window class (>= 840dp).
  /// Use for full two-pane or wide-grid layouts.
  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expanded;

  /// Content max-width for centered layouts on very wide screens (e.g. landscape tablet).
  static const double contentMaxWidth = 960.0;

  /// Horizontal padding: scales up on wider screens.
  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= expanded) return 24.0;
    if (width >= compact) return 20.0;
    return 16.0;
  }
}
