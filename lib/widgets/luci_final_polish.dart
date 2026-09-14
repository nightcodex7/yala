// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../design/luci_design_system.dart';

/// Final polish components for enhanced user experience
/// Part of Phase 4: Final Polish & Accessibility
class LuciFinalPolish {
  /// Enhanced Material 3 SegmentedButton for router selection
  static Widget routerSelector({
    required BuildContext context,
    required List<dynamic> routers,
    required dynamic selectedRouter,
    required Function(String) onRouterChanged,
  }) {
    if (routers.length <= 3) {
      return SegmentedButton<String>(
        segments: routers
            .map<ButtonSegment<String>>(
              (router) => ButtonSegment<String>(
                value: router.id,
                label: Text(
                  router.lastKnownHostname ?? router.ipAddress,
                  style: const TextStyle(fontSize: 12),
                ),
                icon: const Icon(Icons.router, size: 16),
              ),
            )
            .toList(),
        selected: {selectedRouter?.id ?? ''},
        onSelectionChanged: (Set<String> selection) {
          if (selection.isNotEmpty && selection.first != selectedRouter?.id) {
            onRouterChanged(selection.first);
          }
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
      );
    }

    // Return a Material 3 styled dropdown for more routers
    return Container(
      padding: EdgeInsets.symmetric(horizontal: LuciSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(LuciSpacing.sm),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: DropdownButton<String>(
        value: selectedRouter?.id,
        hint: const Text('Select Router'),
        underline: const SizedBox(),
        borderRadius: BorderRadius.circular(LuciSpacing.sm),
        items: routers
            .map<DropdownMenuItem<String>>(
              (router) => DropdownMenuItem<String>(
                value: router.id,
                child: Row(
                  children: [
                    Icon(
                      Icons.router,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    SizedBox(width: LuciSpacing.sm),
                    Text(router.lastKnownHostname ?? router.ipAddress),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (String? value) {
          if (value != null && value != selectedRouter?.id) {
            onRouterChanged(value);
          }
        },
      ),
    );
  }

  /// Enhanced empty state with consistent styling
  static Widget emptyState({
    required BuildContext context,
    required String title,
    required String message,
    IconData icon = Icons.inbox_outlined,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(LuciSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            SizedBox(height: LuciSpacing.md),
            Text(
              title,
              style: LuciTextStyles.cardTitle(
                context,
              ).copyWith(color: Theme.of(context).colorScheme.outline),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: LuciSpacing.sm),
            Text(
              message,
              style: LuciTextStyles.cardSubtitle(
                context,
              ).copyWith(color: Theme.of(context).colorScheme.outline),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: LuciSpacing.lg),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Enhanced status chip with consistent styling
  static Widget statusChip({
    required BuildContext context,
    required String label,
    required bool isActive,
    IconData? icon,
    Color? activeColor,
    Color? inactiveColor,
  }) {
    final theme = Theme.of(context);
    final color = isActive
        ? (activeColor ?? theme.colorScheme.primary)
        : (inactiveColor ?? theme.colorScheme.outline);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: LuciSpacing.sm,
        vertical: LuciSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LuciSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            SizedBox(width: LuciSpacing.xs),
          ],
          Text(
            label,
            style: LuciTextStyles.detailValue(
              context,
            ).copyWith(color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  /// Enhanced connection type indicator
  static Widget connectionTypeIndicator({
    required BuildContext context,
    required String type,
    required bool isConnected,
  }) {
    IconData icon;
    String label;

    switch (type.toLowerCase()) {
      case 'wireless':
      case 'wifi':
        icon = Icons.wifi;
        label = 'WiFi';
        break;
      case 'wired':
      case 'ethernet':
        icon = Icons.cable;
        label = 'Wired';
        break;
      case 'mobile':
      case 'cellular':
        icon = Icons.signal_cellular_alt;
        label = 'Mobile';
        break;
      default:
        icon = Icons.device_unknown;
        label = 'Unknown';
    }

    return statusChip(
      context: context,
      label: label,
      isActive: isConnected,
      icon: icon,
      activeColor: Theme.of(context).colorScheme.primary,
      inactiveColor: Theme.of(context).colorScheme.outline,
    );
  }

  /// Enhanced data usage formatter
  static String formatDataUsage(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Enhanced time duration formatter
  static String formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  /// Enhanced MAC address formatter
  static String formatMacAddress(String mac) {
    // Remove any existing separators and convert to uppercase
    final cleanMac = mac.replaceAll(RegExp(r'[:-]'), '').toUpperCase();

    // Add colons every 2 characters
    if (cleanMac.length == 12) {
      return cleanMac
          .replaceAllMapped(RegExp(r'(.{2})'), (match) => '${match.group(1)}:')
          .substring(0, 17); // Remove trailing colon
    }

    return mac; // Return original if not standard length
  }

  /// Enhanced IP address validation
  static bool isValidIPAddress(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;

    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
    }

    return true;
  }

  /// Enhanced accessibility label generator
  static String generateAccessibilityLabel({
    required String type,
    required String name,
    required bool isActive,
    String? additionalInfo,
  }) {
    final status = isActive ? 'active' : 'inactive';
    final base = '$type $name is $status';

    if (additionalInfo != null && additionalInfo.isNotEmpty) {
      return '$base, $additionalInfo';
    }

    return base;
  }
}
