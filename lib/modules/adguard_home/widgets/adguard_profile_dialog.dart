// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';

/// Modal dialog for adding or configuring an external AdGuard Home instance profile.
///
/// Features:
/// - Real-time pre-save connection probing via [AdGuardController.testProfileConnection].
/// - Host, port, HTTPS protocol, and HTTP Basic Authentication credential configuration.
/// - Unsaved credential testing with explicit status feedback.
class AdGuardProfileDialog extends StatefulWidget {
  final AdGuardController controller;
  final AdGuardInstanceProfile? initialProfile;

  const AdGuardProfileDialog({
    super.key,
    required this.controller,
    this.initialProfile,
  });

  static Future<AdGuardInstanceProfile?> show(
    BuildContext context, {
    required AdGuardController controller,
    AdGuardInstanceProfile? initialProfile,
  }) {
    return showDialog<AdGuardInstanceProfile>(
      context: context,
      builder: (context) => AdGuardProfileDialog(
        controller: controller,
        initialProfile: initialProfile,
      ),
    );
  }

  @override
  State<AdGuardProfileDialog> createState() => _AdGuardProfileDialogState();
}

class _AdGuardProfileDialogState extends State<AdGuardProfileDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  bool _useHttps = false;
  bool _obscurePassword = true;
  bool _isTesting = false;
  bool _isSaving = false;
  bool _testCredsProvided = false;
  AdGuardConnectionStatus? _testStatus;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _nameController = TextEditingController(text: p?.name ?? '');
    _hostController = TextEditingController(text: p?.host ?? '');
    _portController = TextEditingController(text: '${p?.port ?? 3000}');
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _useHttps = p?.useHttps ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Sanitizes raw host input, extracting protocol, host, and port if present.
  static ({String host, int? port, bool? useHttps}) sanitizeHostInput(
    String input,
  ) {
    var raw = input.trim();
    bool? useHttps;
    if (raw.startsWith('https://')) {
      useHttps = true;
      raw = raw.substring(8);
    } else if (raw.startsWith('http://')) {
      useHttps = false;
      raw = raw.substring(7);
    }

    // Strip trailing path/slashes
    final slashIdx = raw.indexOf('/');
    if (slashIdx != -1) {
      raw = raw.substring(0, slashIdx);
    }
    raw = raw.trim();

    int? port;
    String host = raw;

    // Check bracketed IPv6: [2001:db8::1]:3000 or [2001:db8::1]
    if (raw.startsWith('[')) {
      final closeBracket = raw.indexOf(']');
      if (closeBracket != -1) {
        final inside = raw.substring(1, closeBracket);
        final after = raw.substring(closeBracket + 1);
        host = inside;
        if (after.startsWith(':')) {
          final p = int.tryParse(after.substring(1));
          if (p != null && p > 0 && p <= 65535) {
            port = p;
          }
        }
      }
    } else if (raw.contains(':')) {
      final parts = raw.split(':');
      if (parts.length == 2) {
        final p = int.tryParse(parts[1]);
        if (p != null && p > 0 && p <= 65535) {
          host = parts[0];
          port = p;
        }
      }
    }

    return (host: host.trim(), port: port, useHttps: useHttps);
  }

  /// Validates whether a host is a well-formed IPv4, IPv6, or hostname.
  static bool isValidHost(String host) {
    if (host.isEmpty) return false;
    // Check IPv4
    final ipv4Regex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (ipv4Regex.hasMatch(host)) {
      final octets = host.split('.').map(int.tryParse);
      return octets.every((o) => o != null && o >= 0 && o <= 255);
    }
    // Check IPv6 (strip optional brackets)
    final cleanIpv6 = host.replaceAll('[', '').replaceAll(']', '');
    if (cleanIpv6.contains(':')) {
      final ipv6Regex = RegExp(r'^[0-9a-fA-F:]+$');
      return ipv6Regex.hasMatch(cleanIpv6);
    }
    // Check hostname / FQDN (RFC 1123)
    final hostnameRegex = RegExp(
      r'^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$',
    );
    return hostnameRegex.hasMatch(host);
  }

  Future<void> _runConnectionTest() async {
    final parsed = sanitizeHostInput(_hostController.text);
    if (parsed.port != null) {
      _portController.text = '${parsed.port}';
    }
    if (parsed.useHttps != null) {
      setState(() {
        _useHttps = parsed.useHttps!;
      });
    }
    _hostController.text = parsed.host;

    if (!_formKey.currentState!.validate()) return;

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 3000;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isTesting = true;
      _testStatus = null;
      _testMessage = null;
    });

    try {
      final status = await widget.controller.testProfileConnection(
        host: host,
        port: port,
        useHttps: _useHttps,
        username: username.isNotEmpty ? username : null,
        password: password.isNotEmpty ? password : null,
      );

      if (!mounted) return;

      final hasCreds = username.isNotEmpty || password.isNotEmpty;
      _testCredsProvided = hasCreds;

      setState(() {
        _isTesting = false;
        _testStatus = status;
        switch (status) {
          case AdGuardConnectionStatus.authenticated:
            _testMessage = 'Connection successful!';
            break;
          case AdGuardConnectionStatus.authRequired:
            _testMessage = hasCreds
                ? 'Authentication failed. Invalid username or password.'
                : 'Authentication required. Enter username & password.';
            break;
          case AdGuardConnectionStatus.apiUnreachable:
            _testMessage = 'Unreachable. Check host, port, and network.';
            break;
          case AdGuardConnectionStatus.invalidEndpoint:
            _testMessage = 'Endpoint responded, but is not AdGuard Home.';
            break;
          default:
            _testMessage = 'Connection test failed.';
            break;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _testStatus = AdGuardConnectionStatus.apiUnreachable;
        _testMessage = 'Error testing connection: $e';
      });
    }
  }

  Future<void> _save() async {
    final parsed = sanitizeHostInput(_hostController.text);
    if (parsed.port != null) {
      _portController.text = '${parsed.port}';
    }
    if (parsed.useHttps != null) {
      setState(() {
        _useHttps = parsed.useHttps!;
      });
    }
    _hostController.text = parsed.host;

    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 3000;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isSaving = true;
    });

    try {
      final profileId =
          widget.initialProfile?.id ??
          'ext_${DateTime.now().millisecondsSinceEpoch}';
      final profile = AdGuardInstanceProfile.external(
        id: profileId,
        name: name,
        host: host,
        port: port,
        useHttps: _useHttps,
      );

      if (widget.initialProfile != null) {
        await widget.controller.updateProfile(
          profile,
          username: username.isNotEmpty ? username : null,
          password: password.isNotEmpty ? password : null,
        );
      } else {
        await widget.controller.addExternalProfile(
          profile,
          username: username.isNotEmpty ? username : null,
          password: password.isNotEmpty ? password : null,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(profile);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        LuciToastManager.safeShowError(
          context,
          'Failed to save profile',
          subtitle: LuciToastManager.parseErrorReason(e),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEditing = widget.initialProfile != null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.dns_rounded, color: colorScheme.primary, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEditing ? 'Edit AdGuard Profile' : 'Add External AdGuard Home',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile Name
                TextFormField(
                  key: const Key('agh_profile_name_field'),
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Instance Name *',
                    hintText: 'e.g. Raspberry Pi, Mini-PC',
                    prefixIcon: Icon(Icons.label_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Host and Port Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        key: const Key('agh_profile_host_field'),
                        controller: _hostController,
                        decoration: const InputDecoration(
                          labelText: 'Host / IP *',
                          hintText: '192.168.1.129',
                          prefixIcon: Icon(Icons.computer_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Host is required';
                          }
                          final sanitized = sanitizeHostInput(value).host;
                          if (!isValidHost(sanitized)) {
                            return 'Enter a valid IP address or hostname';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        key: const Key('agh_profile_port_field'),
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port *',
                          hintText: '3000',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final port = int.tryParse(value?.trim() ?? '');
                          if (port == null || port < 1 || port > 65535) {
                            return '1-65535';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // HTTPS Switch
                SwitchListTile(
                  key: const Key('agh_profile_https_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use HTTPS'),
                  value: _useHttps,
                  onChanged: (val) {
                    setState(() {
                      _useHttps = val;
                    });
                  },
                ),
                const Divider(height: 20),

                Text(
                  'Authentication (Optional)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Username
                TextFormField(
                  key: const Key('agh_profile_username_field'),
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Password
                TextFormField(
                  key: const Key('agh_profile_password_field'),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Test Connection Button & Result
                OutlinedButton.icon(
                  key: const Key('agh_test_connection_button'),
                  onPressed: _isTesting ? null : _runConnectionTest,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.electrical_services_rounded),
                  label: Text(
                    _isTesting ? 'Testing Connection...' : 'Test Connection',
                  ),
                ),

                if (_testStatus != null && _testMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    key: const Key('agh_test_status_indicator'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _getTestStatusColor(
                        _testStatus!,
                      ).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getTestStatusColor(
                          _testStatus!,
                        ).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getTestStatusIcon(_testStatus!),
                          size: 18,
                          color: _getTestStatusColor(_testStatus!),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _getTestStatusColor(_testStatus!),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('agh_cancel_profile_button'),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n?.actionCancel ?? 'Cancel'),
        ),
        FilledButton(
          key: const Key('agh_save_profile_button'),
          onPressed: (_isTesting || _isSaving) ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n?.actionSave ?? 'Save'),
        ),
      ],
    );
  }

  Color _getTestStatusColor(AdGuardConnectionStatus status) {
    switch (status) {
      case AdGuardConnectionStatus.authenticated:
        return Colors.green;
      case AdGuardConnectionStatus.authRequired:
        return _testCredsProvided ? Colors.red.shade700 : Colors.amber.shade800;
      case AdGuardConnectionStatus.apiUnreachable:
      case AdGuardConnectionStatus.invalidEndpoint:
      case AdGuardConnectionStatus.error:
        return Colors.red.shade700;
      default:
        return Colors.grey;
    }
  }

  IconData _getTestStatusIcon(AdGuardConnectionStatus status) {
    switch (status) {
      case AdGuardConnectionStatus.authenticated:
        return Icons.check_circle_outline_rounded;
      case AdGuardConnectionStatus.authRequired:
        return _testCredsProvided
            ? Icons.error_outline_rounded
            : Icons.lock_outline_rounded;
      case AdGuardConnectionStatus.apiUnreachable:
        return Icons.cloud_off_rounded;
      case AdGuardConnectionStatus.invalidEndpoint:
        return Icons.warning_amber_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }
}
