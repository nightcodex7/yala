// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// Modern Material 3 styled profile avatar for Parental Controls.
/// Features a refined squircle geometry, tonal gradients, soft glow,
/// and contextual status badge overlays.
class ParentalProfileAvatar extends StatelessWidget {
  final String icon;
  final String colorHex;
  final double size;
  final bool isPaused;
  final bool isBypassed;
  final bool? isEnabled;
  final bool isBedtime;
  final bool showStatusBadge;

  const ParentalProfileAvatar({
    super.key,
    required this.icon,
    required this.colorHex,
    this.size = 46,
    this.isPaused = false,
    this.isBypassed = false,
    this.isEnabled,
    this.isBedtime = false,
    this.showStatusBadge = true,
  });

  static Color parseColor(String hex) {
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return const Color(0xFFF97316);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = parseColor(colorHex);
    final borderRadius = BorderRadius.circular(size * 0.30);
    final iconSize = size * 0.50;
    final effectiveBypassed = isBypassed || (isEnabled != null && !isEnabled!);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Main Squircle Container ──────────────────────────────────────
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: effectiveBypassed ? 0.12 : 0.24),
                  accent.withValues(alpha: effectiveBypassed ? 0.04 : 0.08),
                ],
              ),
              borderRadius: borderRadius,
              border: Border.all(
                color: effectiveBypassed
                    ? Colors.grey.withValues(alpha: 0.3)
                    : accent.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(
                    alpha: effectiveBypassed ? 0.05 : 0.16,
                  ),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                icon,
                style: TextStyle(fontSize: iconSize, height: 1),
              ),
            ),
          ),

          // ── Contextual Status Badge ─────────────────────────────────────
          if (showStatusBadge && (isPaused || isBedtime || effectiveBypassed))
            Positioned(right: -2, bottom: -2, child: _buildBadge(theme)),
        ],
      ),
    );
  }

  Widget _buildBadge(ThemeData theme) {
    final double badgeSize = size * 0.40;
    final double badgeIconSize = badgeSize * 0.65;
    final effectiveBypassed = isBypassed || (isEnabled != null && !isEnabled!);

    Color badgeBg;
    Color badgeIconColor;
    IconData badgeIcon;

    if (isPaused) {
      badgeBg = Colors.amber.shade700;
      badgeIconColor = Colors.white;
      badgeIcon = Icons.pause_rounded;
    } else if (isBedtime) {
      badgeBg = Colors.indigo.shade600;
      badgeIconColor = Colors.white;
      badgeIcon = Icons.bedtime_rounded;
    } else if (effectiveBypassed) {
      badgeBg = theme.colorScheme.surfaceContainerHighest;
      badgeIconColor = theme.colorScheme.onSurfaceVariant;
      badgeIcon = Icons.shield_outlined;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: badgeBg,
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.surface, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Icon(badgeIcon, size: badgeIconSize, color: badgeIconColor),
      ),
    );
  }
}
