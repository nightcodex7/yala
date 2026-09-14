// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'luci_toast.dart';
import '../models/rpc_result.dart';
import '../state/app_state.dart';

class RpcResultUiHelper {
  /// Canonical RPCD ACL remediation command supporting both APK (OpenWrt 25.x+) and OPKG (OpenWrt 24.10 and earlier)
  static const String kRpcdAclRemediationCommand =
      '# OpenWrt 25.x / snapshot (APK):\n'
      'apk update && apk add luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status && /etc/init.d/rpcd restart\n\n'
      '# OpenWrt 24.10 and earlier (OPKG):\n'
      'opkg update && opkg install luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status && /etc/init.d/rpcd restart';

  /// Displays appropriate user feedback (toasts or dialogs) based on RpcResult status.
  static void handleRpcResult<T>(
    BuildContext context,
    RpcResult<T> result,
    String actionLabel,
  ) {
    if (!context.mounted) return;

    if (result.isSuccess) {
      context.showToastSuccess('$actionLabel completed successfully.');
      return;
    }

    if (result.isPermissionDenied) {
      showPermissionDeniedDialog(context, actionLabel);
      return;
    }

    if (result.isMethodNotFound) {
      context.showToastWarning(
        'Action "$actionLabel" is unavailable on this router capabilities profile.',
      );
      return;
    }

    if (result.status == RpcCallStatus.networkError) {
      context.showToastError(
        'Network Error',
        subtitle: 'Network connection failed during $actionLabel.',
      );
      return;
    }

    // Generic RPC or command execution failure
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 36),
        title: Text('Failed: $actionLabel'),
        content: SingleChildScrollView(
          child: Text(
            result.errorMessage ??
                'An unknown error occurred on the router during operation.',
            style: GoogleFonts.geistMono(fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Displays standard RPCD ACL permission remediation guidance dialog with optional automatic fix button.
  static void showPermissionDeniedDialog(
    BuildContext context,
    String actionLabel,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _PermissionDeniedDialog(actionLabel: actionLabel),
    );
  }
}

class _PermissionDeniedDialog extends StatefulWidget {
  final String actionLabel;

  const _PermissionDeniedDialog({required this.actionLabel});

  @override
  State<_PermissionDeniedDialog> createState() =>
      _PermissionDeniedDialogState();
}

class _PermissionDeniedDialogState extends State<_PermissionDeniedDialog> {
  bool _isFixing = false;
  String? _errorMessage;

  Future<void> _handleAutoFix() async {
    setState(() {
      _isFixing = true;
      _errorMessage = null;
    });

    try {
      final success = await AppState.instance.autoFixPermissions(
        context: context,
      );
      if (!mounted) return;
      if (success) {
        final parentContext = Navigator.of(context).context;
        Navigator.pop(context);
        if (parentContext.mounted) {
          parentContext.showToastSuccess(
            'Permissions fixed successfully!',
            subtitle: 'Capabilities re-probed.',
          );
        }
      } else {
        setState(() {
          _isFixing = false;
          _errorMessage =
              'Automatic fix failed (session lacks file.exec rights). Please run the manual SSH command below.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFixing = false;
        _errorMessage = 'Automatic fix encountered an error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.security_rounded, color: Colors.amber, size: 36),
      title: const Text('Permission Denied (RPCD ACL)'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your router\'s LuCI RPC user does not have permission to execute "${widget.actionLabel}".',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'To grant access, log in to your router via SSH and install/configure the RPCD ACL modules:\n\n'
              '${RpcResultUiHelper.kRpcdAclRemediationCommand}\n\n'
              'Then restart rpcd or re-log into this app.',
              style: GoogleFonts.geistMono(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        if (_isFixing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          FilledButton.icon(
            onPressed: _handleAutoFix,
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: const Text('Fix Automatically'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel / Close'),
        ),
      ],
    );
  }
}
