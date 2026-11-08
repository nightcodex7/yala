// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../../../design/luci_design_system.dart';
import '../models/log_entry.dart';

class LogLevelBadge extends StatelessWidget {
  final LogLevel level;

  const LogLevelBadge({super.key, required this.level});

  Color _badgeColor(BuildContext context) {
    final theme = Theme.of(context);
    switch (level) {
      case LogLevel.emergency:
      case LogLevel.alert:
      case LogLevel.critical:
      case LogLevel.error:
        return theme.colorScheme.error;
      case LogLevel.warning:
        return LuciStatusColors.warningColor(context);
      case LogLevel.notice:
      case LogLevel.info:
        return theme.colorScheme.primary;
      case LogLevel.debug:
      case LogLevel.unknown:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _badgeColor(context);
    final label = level.name.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
