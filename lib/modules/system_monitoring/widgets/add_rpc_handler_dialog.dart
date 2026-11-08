// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/router_temperature.dart';

/// Dialog that guides users in enabling the native OpenWrt temperature RPC handler.
/// Can be invoked from System Monitoring Screen or Dashboard Screen.
class AddRpcHandlerDialog extends ConsumerStatefulWidget {
  final VoidCallback? onDismissPermanently;

  const AddRpcHandlerDialog({super.key, this.onDismissPermanently});

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onDismissPermanently,
  }) {
    return showDialog(
      context: context,
      builder: (context) =>
          AddRpcHandlerDialog(onDismissPermanently: onDismissPermanently),
    );
  }

  @override
  ConsumerState<AddRpcHandlerDialog> createState() =>
      _AddRpcHandlerDialogState();
}

class _AddRpcHandlerDialogState extends ConsumerState<AddRpcHandlerDialog> {
  bool _isInstalling = false;
  bool _showManualCommand = false;
  String? _errorMessage;

  static const String _setupCommand =
      'mkdir -p /usr/libexec/rpcd /usr/share/rpcd/acl.d && '
      'cat << \'EOF\' > /usr/libexec/rpcd/luci.temp-status\n'
      '#!/bin/sh\n'
      'case "\$1" in\n'
      'list) echo \'{"getSensors":{}}\' ;;\n'
      'call) case "\$2" in getSensors)\n'
      'hw=""; for h in /sys/class/hwmon/hwmon*; do [ -d "\$h" ] || continue; n=\$(cat "\$h/name" 2>/dev/null || echo hwmon); s=""; for t in "\$h"/temp*_input; do [ -f "\$t" ] || continue; v=\$(cat "\$t" 2>/dev/null); [ -n "\$v" ] || continue; l=\$(cat "\${t%_input}_label" 2>/dev/null); i="\${t##*/}"; [ -n "\$s" ] && s="\$s," || true; s="\$s{\\"item\\":\\"\$i\\",\\"label\\":\\"\$l\\",\\"temp\\":\$v}"; done; [ -n "\$s" ] && { [ -n "\$hw" ] && hw="\$hw," || true; hw="\$hw{\\"title\\":\\"\$n\\",\\"item\\":\\"\${h##*/}\\",\\"sources\\":[\$s]}"; }; done\n'
      'tz=""; for z in /sys/class/thermal/thermal_zone*; do [ -d "\$z" ] || continue; v=\$(cat "\$z/temp" 2>/dev/null); [ -n "\$v" ] || continue; y=\$(cat "\$z/type" 2>/dev/null || echo tz); [ -n "\$tz" ] && tz="\$tz," || true; tz="\$tz{\\"title\\":\\"\$y\\",\\"item\\":\\"\${z##*/}\\",\\"sources\\":[{\\"item\\":\\"temp\\",\\"label\\":\\"\$y\\",\\"temp\\":\$v}]}"; done\n'
      'printf \'{"sensors":{"0":[%s],"1":[%s]}}\\n\' "\$hw" "\$tz" ;; esac ;; esac\n'
      'EOF\n'
      'chmod +x /usr/libexec/rpcd/luci.temp-status && '
      'cat << \'EOF\' > /usr/share/rpcd/acl.d/luci-app-temp-status.json\n'
      '{"luci-app-temp-status":{"description":"Native Temperature RPC Handler","read":{"ubus":{"luci.temp-status":["getSensors"]}}}}\n'
      'EOF\n'
      '/etc/init.d/rpcd reload';

  Future<void> _handleAutomaticInstall() async {
    setState(() {
      _isInstalling = true;
      _errorMessage = null;
    });

    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);
    try {
      final success = await appState.installNativeTemperatureHandler(
        context: mounted ? context : null,
      );

      if (!mounted) return;

      if (success) {
        context.showToastSuccess(
          l10n?.addRpcHandlerSuccess ??
              'Native RPC handler installed successfully!',
        );
        Navigator.of(context).pop();
        await appState.fetchDashboardData();
      } else {
        setState(() {
          _isInstalling = false;
          _showManualCommand = true;
          _errorMessage =
              l10n?.addRpcHandlerPermDenied ??
              'The router\'s RPC execution policy restricts remote script installation. '
                  'You can easily enable it by running this 1-line command once via SSH:';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _showManualCommand = true;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _handleVerifyAndRefresh() async {
    setState(() => _isInstalling = true);
    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);
    try {
      await appState.fetchDashboardData();
    } catch (_) {}

    if (!mounted) return;

    final temp = appState.dashboardData?['temperature'];
    final tempObj = temp is RouterTemperature
        ? temp
        : (temp != null ? RouterTemperature.parse(temp) : null);

    if (tempObj != null &&
        tempObj.isSupported &&
        tempObj.mainTemperature != null) {
      context.showToastSuccess(
        l10n?.addRpcHandlerTempActive ??
            'Temperature monitoring is now active!',
      );
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isInstalling = false;
        _errorMessage =
            l10n?.addRpcHandlerNotDetectedLong ??
            'Temperature handler not detected yet. Ensure the command finished and rpcd reloaded.';
      });
      context.showToastError(
        l10n?.addRpcHandlerNotDetected ??
            'Temperature handler not detected yet.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      actionsOverflowButtonSpacing: 8,
      actionsOverflowDirection: VerticalDirection.down,
      icon: Icon(
        Icons.thermostat_outlined,
        color: theme.colorScheme.primary,
        size: 32,
      ),
      title: Text(l10n?.addRpcHandlerTitle ?? 'Enable Temperature'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_showManualCommand) ...[
              Text(
                l10n?.addRpcHandlerDescription ??
                    'This router contains physical hardware thermal sensors. '
                        'To read them without extra third-party packages, Yala can configure a lightweight native OpenWrt RPC handler.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFeatureBullet(
                      context,
                      l10n?.addRpcHandlerFeature1 ??
                          '100% native POSIX shell script (0 extra feeds required)',
                    ),
                    const SizedBox(height: 6),
                    _buildFeatureBullet(
                      context,
                      l10n?.addRpcHandlerFeature2 ??
                          'Uses less than 1 KB of flash storage',
                    ),
                    const SizedBox(height: 6),
                    _buildFeatureBullet(
                      context,
                      l10n?.addRpcHandlerFeature3 ??
                          'Reads kernel /sys/class/hwmon directly',
                    ),
                  ],
                ),
              ),
              if (_isInstalling) ...[
                const SizedBox(height: 16),
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ],
            ] else ...[
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.85,
                      ),
                    ),
                  ),
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: SelectableText(
                  _setupCommand,
                  style: LuciTypography.monoStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: _setupCommand));
                    context.showToastSuccess(
                      l10n?.addRpcHandlerCommandCopied ??
                          'Command copied to clipboard!',
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text(l10n?.addRpcHandlerCopyCommand ?? 'Copy Command'),
                ),
              ),
              if (_isInstalling) ...[
                const SizedBox(height: 12),
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (widget.onDismissPermanently != null && !_isInstalling)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDismissPermanently!();
            },
            child: Text(l10n?.addRpcHandlerDontShowAgain ?? "Don't Show Again"),
          ),
        if (!_showManualCommand) ...[
          TextButton(
            onPressed: _isInstalling ? null : () => Navigator.of(context).pop(),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton.icon(
            onPressed: _isInstalling ? null : _handleAutomaticInstall,
            icon: const Icon(Icons.flash_on_rounded, size: 18),
            label: Text(
              l10n?.addRpcHandlerInstallAuto ?? 'Install Automatically',
            ),
          ),
        ] else ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n?.actionClose ?? 'Close'),
          ),
          FilledButton.icon(
            onPressed: _isInstalling ? null : _handleVerifyAndRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n?.addRpcHandlerVerify ?? 'Verify & Refresh'),
          ),
        ],
      ],
    );
  }

  Widget _buildFeatureBullet(BuildContext context, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
