// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';

/// Universal Guardrails & Confirmation Dialog Manager.
/// Provides highly customizable, situational-aware guardrail dialogs with
/// parameter flexibility (strip-down minimal or fully customized options)
/// to reduce code duplication and enforce safety across the application.
class LuciGuardrail {
  /// Confirms pending 25-second auto-revert staged changes before screen exit.
  /// Handles atomic revert or confirmation with situational context awareness.
  static Future<bool> confirmStagedChangesOrExit(
    BuildContext context,
    AppState appState, {
    String title = 'Staged Changes Pending',
    String? subtitle,
    String revertLabel = 'Revert Changes',
    String confirmLabel = 'Confirm & Save',
  }) async {
    if (!appState.isAccessControlPendingConfirmation) return true;

    final remaining = appState.accessControlCountdownSeconds;
    final message =
        subtitle ??
        'You have staged high-risk wireless configuration changes counting down '
            '(${remaining}s remaining).\n\nWhat would you like to do before leaving this screen?';

    await OsPlatformIntegration.triggerHaptic(OsHapticType.heavy);
    if (!context.mounted) return false;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.amber,
          size: 36,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'revert'),
            child: Text(revertLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'confirm'),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    if (action == 'revert') {
      if (context.mounted) {
        await appState.revertWifiAccessControlChanges(context: context);
      }
      return true;
    } else if (action == 'confirm') {
      await appState.confirmWifiAccessControlChanges();
      return true;
    }
    return false;
  }

  /// Displays a flexible, universal confirmation dialog with full parameter customization:
  /// - Minimal: `title` + `confirmLabel`
  /// - Full: `subtitle`, `icon`, `iconColor`, `confirmLabel`, `cancelLabel`, `isDestructive`, `hapticType`
  static Future<bool> showConfirmation(
    BuildContext context, {
    required String title,
    String? subtitle,
    Widget? customContent,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    IconData icon = Icons.shield_rounded,
    Color? iconColor,
    bool isDestructive = false,
    OsHapticType hapticType = OsHapticType.medium,
    bool barrierDismissible = true,
  }) async {
    if (!context.mounted) return false;

    await OsPlatformIntegration.triggerHaptic(hapticType);
    if (!context.mounted) return false;

    final theme = Theme.of(context);
    final effectiveIconColor =
        iconColor ??
        (isDestructive ? theme.colorScheme.error : theme.colorScheme.primary);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, color: effectiveIconColor, size: 32),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: customContent != null
            ? SingleChildScrollView(child: customContent)
            : (subtitle != null
                  ? SingleChildScrollView(
                      child: Text(
                        subtitle,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    )
                  : null),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Displays a situational guardrail toast or dialog when an operation is blocked by missing UCI write privileges.
  static void handleReadOnlyRestriction(
    BuildContext context,
    AppState appState, {
    String actionName = 'This action',
    bool showAsDialog = false,
  }) {
    final username = appState.sessionUsername;
    final message =
        "Account '$username' lacks UCI write access authorization required for $actionName.";

    if (showAsDialog) {
      showConfirmation(
        context,
        title: 'Access Restricted',
        subtitle: message,
        confirmLabel: 'Understood',
        cancelLabel: '',
        icon: Icons.lock_outline_rounded,
        iconColor: Colors.amber,
      );
    } else {
      context.showToastError('Access Denied', subtitle: message);
    }
  }

  /// Confirms self-device disconnection/lockout hazard when modifying wireless SSIDs or MAC filtering.
  static Future<bool> confirmSelfDeviceHazard(
    BuildContext context, {
    required String actionDescription,
    String? connectedMac,
  }) async {
    final macInfo = connectedMac != null
        ? '\n\nActive device MAC: $connectedMac'
        : '';
    return showConfirmation(
      context,
      title: 'Self-Device Safety Warning',
      subtitle:
          'Changing $actionDescription may disconnect your current mobile device from the router Wi-Fi network.$macInfo\n\n'
          'Changes will be applied directly to the router.',
      confirmLabel: 'Proceed with Caution',
      cancelLabel: 'Cancel',
      icon: Icons.signal_wifi_off_rounded,
      iconColor: Colors.orange,
      isDestructive: true,
      hapticType: OsHapticType.heavy,
    );
  }

  /// Universal dialog to prompt confirmation for discarding or saving unsaved changes on any screen.
  static Future<bool> confirmUnsavedChanges(
    BuildContext context, {
    required int unsavedCount,
    String itemLabel = 'change(s)',
    String title = 'Unsaved Changes',
    String? customSubtitle,
  }) async {
    final subtitle =
        customSubtitle ??
        'You have $unsavedCount unsaved $itemLabel. Discarding will undo all staged modifications.';

    return showConfirmation(
      context,
      title: title,
      subtitle: subtitle,
      confirmLabel: 'Discard Changes',
      cancelLabel: 'Keep Editing',
      icon: Icons.edit_off_rounded,
      iconColor: Colors.orange,
      isDestructive: true,
      hapticType: OsHapticType.medium,
    );
  }

  /// Displays a tri-action dialog (Save & Exit, Discard & Leave, Cancel) for staged changes.
  /// Returns 'save', 'discard', or null (cancel).
  static Future<String?> confirmSaveOrDiscardChanges(
    BuildContext context, {
    required int count,
    String itemLabel = 'change(s)',
    String title = 'Unsaved Changes',
    String? subtitle,
  }) async {
    if (!context.mounted) return null;

    await OsPlatformIntegration.triggerHaptic(OsHapticType.medium);
    if (!context.mounted) return null;

    final theme = Theme.of(context);
    final message =
        subtitle ??
        'You have $count unsaved $itemLabel. Would you like to save them before leaving?';

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.edit_note_rounded,
          color: theme.colorScheme.primary,
          size: 32,
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(message, style: const TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard & Leave'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save & Exit'),
          ),
        ],
      ),
    );
  }
}
