// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A non-intrusive, context-aware feature hint banner that displays helpful tips
/// EXACTLY ONCE per app installation.
///
/// Handles extreme screen sizes (320dp to 1200dp+) and high accessibility font scaling
/// using LayoutBuilder and clamped text scaling guardrails.
class LuciContextualHintBanner extends StatefulWidget {
  final String hintId;
  final String title;
  final String message;
  final IconData icon;
  final Color? accentColor;
  final EdgeInsetsGeometry margin;

  const LuciContextualHintBanner({
    super.key,
    required this.hintId,
    required this.title,
    required this.message,
    this.icon = Icons.lightbulb_outline_rounded,
    this.accentColor,
    this.margin = const EdgeInsets.only(bottom: 14.0),
  });

  @override
  State<LuciContextualHintBanner> createState() =>
      _LuciContextualHintBannerState();
}

class _LuciContextualHintBannerState extends State<LuciContextualHintBanner>
    with SingleTickerProviderStateMixin {
  bool _isDismissed = true; // Default to hidden until verified
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _checkDismissStatus();
  }

  Future<void> _checkDismissStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed =
          prefs.getBool('hint_dismissed_${widget.hintId}') ?? false;
      if (mounted) {
        setState(() {
          _isDismissed = dismissed;
          _isLoaded = true;
        });
      }
    } catch (_) {
      // Guardrail: On storage error, fail gracefully without breaking UI
      if (mounted) {
        setState(() {
          _isDismissed = true;
          _isLoaded = true;
        });
      }
    }
  }

  Future<void> _dismiss() async {
    setState(() {
      _isDismissed = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hint_dismissed_${widget.hintId}', true);
    } catch (_) {
      // Guardrail: ignore storage failure
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _isDismissed) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final color = widget.accentColor ?? theme.colorScheme.primary;

    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 0.85,
      maxScaleFactor: 1.4,
      child: Container(
        margin: widget.margin,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 320;
            if (isNarrow) {
              // Compact layout for ultra-narrow screens (e.g. split screen mode)
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: color.withValues(alpha: 0.18),
                        child: Icon(widget.icon, size: 14, color: color),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: color,
                      ),
                      onPressed: _dismiss,
                      child: const Text(
                        'Got it',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: color.withValues(alpha: 0.18),
                  child: Icon(widget.icon, size: 16, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: color,
                  ),
                  onPressed: _dismiss,
                  child: const Text(
                    'Got it',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
