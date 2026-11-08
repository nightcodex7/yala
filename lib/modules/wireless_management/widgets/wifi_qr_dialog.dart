// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../models/wireless_info.dart';

import 'package:yet_another_luci_app/l10n/app_localizations.dart';

/// Modal dialog displaying a standardized WIFI: URI QR code for rapid mobile quick-connect
/// with automatic passphrase prefetching and quick copy controls.
class WifiQrDialog extends ConsumerStatefulWidget {
  final WirelessInterface interface;

  const WifiQrDialog({super.key, required this.interface});

  @override
  ConsumerState<WifiQrDialog> createState() => _WifiQrDialogState();
}

class _WifiQrDialogState extends ConsumerState<WifiQrDialog> {
  bool _showPassword = false;
  String? _passphrase;
  bool _isFetchingPassphrase = false;

  @override
  void initState() {
    super.initState();
    _passphrase = widget.interface.key;
    if ((_passphrase == null || _passphrase!.isEmpty) &&
        widget.interface.securityMode != WifiSecurityMode.open) {
      _fetchPassphraseLive();
    }
  }

  Future<void> _fetchPassphraseLive() async {
    if (!mounted) return;
    setState(() => _isFetchingPassphrase = true);
    try {
      final appState = ref.read(appStateProvider);
      final values = await appState.fetchWirelessSectionConfig(
        widget.interface.sectionName,
      );
      if (mounted && values != null) {
        final liveKey =
            values['key']?.toString() ??
            values['passphrase']?.toString() ??
            values['sae_password']?.toString() ??
            values['psk']?.toString();
        if (liveKey != null && liveKey.isNotEmpty) {
          setState(() {
            _passphrase = liveKey;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isFetchingPassphrase = false);
      }
    }
  }

  String get _qrPayload {
    if (widget.interface.securityMode == WifiSecurityMode.open) {
      return 'WIFI:S:${widget.interface.ssid};T:nopass;;';
    }
    final keyToUse = _passphrase ?? widget.interface.key ?? '';
    final secType = switch (widget.interface.securityMode) {
      WifiSecurityMode.saeOnly => 'SAE',
      WifiSecurityMode.wep => 'WEP',
      _ => 'WPA',
    };
    final hiddenTag = widget.interface.isHidden ? 'H:true;' : '';
    return 'WIFI:S:${widget.interface.ssid};T:$secType;P:$keyToUse;$hiddenTag;';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final iface = widget.interface;
    final payload = _qrPayload;
    final hasPassword =
        iface.securityMode != WifiSecurityMode.open &&
        _passphrase != null &&
        _passphrase!.isNotEmpty;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.qr_code_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n?.wifiQuickConnectTitle ?? 'Wi-Fi Quick Connect',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // High-contrast container to guarantee QR scanning in Dark/Light themes
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: payload));
                          context.showToastSuccess(
                            l10n?.toastPayloadCopied ??
                                'WIFI QR Payload copied to clipboard',
                          );
                        },
                        child: Tooltip(
                          message:
                              l10n?.tapQrCodeToCopyPayload ??
                              'Tap QR code to copy full WIFI payload',
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: QrImageView(
                              data: payload,
                              version: QrVersions.auto,
                              size: 200.0,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Colors.black,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        iface.ssid,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: iface.securityMode.badgeColor.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              iface.securityMode.shortBadgeLabel,
                              style: TextStyle(
                                color: iface.securityMode.badgeColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (iface.isHidden)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                l10n?.hiddenNetworkBadge ?? 'Hidden Network',
                                style: const TextStyle(
                                  color: Colors.purple,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Passphrase card or action button
                      if (hasPassword) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.key_rounded, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _showPassword ? _passphrase! : '••••••••••••',
                                  style: _showPassword
                                      ? GoogleFonts.geistMono(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        )
                                      : const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18,
                                ),
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                                tooltip: _showPassword
                                    ? (l10n?.btnHidePassphrase ??
                                          'Hide Passphrase')
                                    : (l10n?.btnShowPassphrase ??
                                          'Show Passphrase'),
                              ),
                            ],
                          ),
                        ),
                      ] else if (iface.securityMode ==
                          WifiSecurityMode.open) ...[
                        Text(
                          l10n?.openWifiNoPassword ??
                              'Open Wi-Fi Network (No Passphrase Required)',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            children: [
                              if (_isFetchingPassphrase) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        l10n?.wifiFetchingPassphrase ??
                                            'Fetching passphrase from router…',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final currentContext = context;
                                    await _fetchPassphraseLive();
                                    if (_passphrase != null &&
                                        _passphrase!.isNotEmpty) {
                                      await Clipboard.setData(
                                        ClipboardData(text: _passphrase!),
                                      );
                                      if (mounted && currentContext.mounted) {
                                        currentContext.showToastSuccess(
                                          l10n?.wifiPassphraseCopied ??
                                              'Passphrase copied to clipboard',
                                        );
                                      }
                                    } else if (mounted &&
                                        currentContext.mounted) {
                                      currentContext.showToastError(
                                        'Passphrase unavailable in router config',
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    l10n?.wifiFetchAndCopyPassphrase ??
                                        'Fetch & Copy Passphrase',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (hasPassword)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: _passphrase!),
                                  );
                                  context.showToastSuccess(
                                    l10n?.wifiPassphraseCopied ??
                                        'Passphrase copied to clipboard',
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: Text(
                                  l10n?.wifiCopyPassword ?? 'Copy Password',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: payload));
                                context.showToastSuccess(
                                  l10n?.wifiPayloadCopied ??
                                      'WIFI QR Payload copied to clipboard',
                                );
                              },
                              icon: const Icon(
                                Icons.qr_code_2_rounded,
                                size: 16,
                              ),
                              label: Text(
                                l10n?.wifiCopyQrPayload ?? 'Copy QR Payload',
                                style: const TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n?.actionClose ?? 'Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
