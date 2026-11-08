// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

class AdvancedCustomRuleDialog extends ConsumerStatefulWidget {
  final FirewallCustomRule? initialRule;
  final FirewallOverview overview;

  const AdvancedCustomRuleDialog({
    super.key,
    this.initialRule,
    required this.overview,
  });

  static Future<bool?> show(
    BuildContext context, {
    FirewallCustomRule? initialRule,
    required FirewallOverview overview,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AdvancedCustomRuleDialog(
        initialRule: initialRule,
        overview: overview,
      ),
    );
  }

  @override
  ConsumerState<AdvancedCustomRuleDialog> createState() =>
      _AdvancedCustomRuleDialogState();
}

class _AdvancedCustomRuleDialogState
    extends ConsumerState<AdvancedCustomRuleDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _srcIpController;
  late final TextEditingController _srcMacController;
  late final TextEditingController _destIpController;
  late final TextEditingController _destPortController;

  late String _target;
  late String _srcZone;
  late String _destZone;
  late String _proto;
  late String _family;
  late bool _enabled;

  bool _isSubmitting = false;
  String? _validationError;

  bool get _isEditing => widget.initialRule != null;

  @override
  void initState() {
    super.initState();
    final init = widget.initialRule;
    _nameController = TextEditingController(text: init?.name ?? '');
    _srcIpController = TextEditingController(text: init?.srcIp ?? '');
    _srcMacController = TextEditingController(
      text: init?.srcMac.join(', ') ?? '',
    );
    _destIpController = TextEditingController(text: init?.destIp ?? '');
    _destPortController = TextEditingController(text: init?.destPort ?? '');

    final availableZones = widget.overview.zones.map((z) => z.name).toList();
    if (init != null &&
        (init.srcZone == '*' ||
            init.srcZone == 'any' ||
            availableZones.contains(init.srcZone))) {
      _srcZone = init.srcZone;
    } else if (availableZones.contains('wan')) {
      _srcZone = 'wan';
    } else {
      _srcZone = availableZones.isNotEmpty ? availableZones.first : '*';
    }

    if (init != null &&
        (init.destZone == '*' ||
            init.destZone == 'any' ||
            availableZones.contains(init.destZone))) {
      _destZone = init.destZone;
    } else if (availableZones.contains('lan')) {
      _destZone = 'lan';
    } else {
      _destZone = availableZones.isNotEmpty ? availableZones.first : '*';
    }

    _target = init?.target.toUpperCase() ?? 'DROP';
    if (!['ACCEPT', 'REJECT', 'DROP'].contains(_target)) {
      _target = 'DROP';
    }

    _proto = init?.proto.toLowerCase() ?? 'any';
    if (_proto == 'tcpudp') _proto = 'tcp udp';

    _family = init?.family.toLowerCase() ?? 'any';
    _enabled = init?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _srcIpController.dispose();
    _srcMacController.dispose();
    _destIpController.dispose();
    _destPortController.dispose();
    super.dispose();
  }

  bool _isValidPortSpec(String? portSpec) {
    if (portSpec == null || portSpec.trim().isEmpty) return true;
    final clean = portSpec.trim().toLowerCase();
    if (clean == 'any' || clean == 'all' || clean == '*') return true;
    final parts = clean.split(',');
    for (final part in parts) {
      final token = part.trim();
      if (token.isEmpty) return false;
      if (token.contains('-')) {
        final bounds = token.split('-');
        if (bounds.length != 2) return false;
        final s = int.tryParse(bounds[0].trim());
        final e = int.tryParse(bounds[1].trim());
        if (s == null || e == null || s < 1 || e > 65535 || s > e) return false;
      } else if (token.contains(':')) {
        final bounds = token.split(':');
        if (bounds.length != 2) return false;
        final s = int.tryParse(bounds[0].trim());
        final e = int.tryParse(bounds[1].trim());
        if (s == null || e == null || s < 1 || e > 65535 || s > e) return false;
      } else {
        final p = int.tryParse(token);
        if (p == null || p < 1 || p > 65535) return false;
      }
    }
    return true;
  }

  bool _isValidMac(String mac) {
    final reg = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return reg.hasMatch(mac.trim());
  }

  List<String> _parseMacList(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return const [];
    return clean
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
  }

  Future<void> _handleSubmit() async {
    final loc = AppLocalizations.of(context);
    setState(() => _validationError = null);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final appState = ref.read(appStateProvider);
    final canModify = appState.capabilities?.canModifyFirewall ?? true;
    if (!canModify) {
      setState(() {
        _validationError =
            loc?.firewallReadOnlyNotice ??
            'Read-only access: Changes cannot be applied on this router account.';
      });
      return;
    }

    final name = _nameController.text.trim();
    final srcIp = _srcIpController.text.trim();
    final macList = _parseMacList(_srcMacController.text);
    final destIp = _destIpController.text.trim();
    final destPort = _destPortController.text.trim();

    // SelfDeviceGuard check: prevent dropping/rejecting managing device or management path
    final isLockoutRisk = await SelfDeviceGuard.isManagementLockoutRisk(
      target: _target,
      srcZone: _srcZone,
      destZone: _destZone,
      srcMac: macList,
      srcIp: srcIp,
      destPort: destPort,
      proto: _proto,
      routerId:
          appState.selectedRouter?.id ?? appState.selectedRouter?.ipAddress,
    );
    if (isLockoutRisk) {
      setState(() {
        _validationError =
            'Safety guard blocked rule: This DROP/REJECT rule affects the managing device or router management path and would cause network lockout.';
      });
      return;
    }

    final preservedRawValues = Map<String, dynamic>.from(
      widget.initialRule?.rawUciValues ?? const {},
    );

    final candidate = FirewallCustomRule(
      sectionKey: widget.initialRule?.sectionKey ?? '',
      name: name,
      srcZone: _srcZone,
      destZone: _destZone,
      target: _target,
      enabled: _enabled,
      isUnrecognizedTarget: false,
      proto: _proto,
      srcMac: macList,
      srcIp: srcIp.isNotEmpty ? srcIp : null,
      destIp: destIp.isNotEmpty ? destIp : null,
      destPort: destPort.isNotEmpty ? destPort : null,
      family: _family,
      position: widget.initialRule?.position,
      rawUciValues: preservedRawValues,
    );

    setState(() => _isSubmitting = true);
    try {
      final bool success;
      if (_isEditing) {
        success = await appState.updateFirewallCustomRule(
          candidate,
          context: mounted ? context : null,
        );
      } else {
        success = await appState.addFirewallCustomRule(
          candidate,
          context: mounted ? context : null,
        );
      }

      if (!mounted) return;

      if (success) {
        LuciToastManager.showSuccess(
          context,
          _isEditing
              ? 'Security rule "$name" updated successfully.'
              : 'Security rule "$name" created successfully.',
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSubmitting = false;
          _validationError = 'Failed to save security rule configuration.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _validationError = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final appState = ref.watch(appStateProvider);
    final capabilities = appState.capabilities;
    final supportsIpv6 = capabilities?.supportsIpv6InternetFirewall ?? false;

    final availableZones = widget.overview.zones.map((z) => z.name).toList();
    final zoneOptions = ['*', ...availableZones];
    if (!zoneOptions.contains(_srcZone) && zoneOptions.isNotEmpty) {
      _srcZone = zoneOptions.first;
    }
    if (!zoneOptions.contains(_destZone) && zoneOptions.isNotEmpty) {
      _destZone = zoneOptions.first;
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isEditing ? Icons.edit_outlined : Icons.add_moderator_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isEditing
                  ? (l10n?.firewallEditRuleTitle ?? 'Edit Security Rule')
                  : (l10n?.firewallAddRuleTitle ?? 'Add Security Rule'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_validationError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _validationError!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Name & Target
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText:
                              l10n?.firewallRuleNameLabel ?? 'Rule Name *',
                          hintText:
                              l10n?.firewallRuleNameHint ??
                              'e.g. Block IoT to WAN',
                          prefixIcon: const Icon(Icons.label_outline),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return l10n?.firewallRuleNameRequired ??
                                'Please enter rule name.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<String>(
                        initialValue: _target,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        dropdownColor: theme.colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        menuMaxHeight: 360,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        decoration: InputDecoration(
                          labelText:
                              l10n?.firewallRuleActionLabel ??
                              'Action / Target',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'ACCEPT',
                            child: Text(
                              'ACCEPT',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'REJECT',
                            child: Text(
                              'REJECT',
                              style: TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'DROP',
                            child: Text(
                              'DROP',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _target = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Source Zone & Destination Zone
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _srcZone,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        dropdownColor: theme.colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        menuMaxHeight: 360,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        decoration: InputDecoration(
                          labelText:
                              l10n?.firewallSourceZoneLabel ?? 'Source Zone',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: zoneOptions.map((z) {
                          return DropdownMenuItem(
                            value: z,
                            child: Text(
                              z == '*'
                                  ? (l10n?.firewallZoneAny ?? 'Any (*)')
                                  : z.toUpperCase(),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _srcZone = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _destZone,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        dropdownColor: theme.colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        menuMaxHeight: 360,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        decoration: InputDecoration(
                          labelText:
                              l10n?.firewallDestinationZoneLabel ??
                              'Destination Zone',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: zoneOptions.map((z) {
                          return DropdownMenuItem(
                            value: z,
                            child: Text(
                              z == '*'
                                  ? (l10n?.firewallZoneAny ?? 'Any (*)')
                                  : z.toUpperCase(),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _destZone = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Source IP & Source MAC
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _srcIpController,
                        decoration: InputDecoration(
                          labelText:
                              l10n?.firewallSourceIpLabel ?? 'Source IP / CIDR',
                          hintText:
                              l10n?.firewallSourceIpHint ??
                              'e.g. 192.168.1.50 or /24',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v != null &&
                              v.trim().isNotEmpty &&
                              !FirewallValidator.isValidIpOrCidr(v)) {
                            return 'Invalid IP or CIDR.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _srcMacController,
                        decoration: InputDecoration(
                          labelText:
                              l10n?.firewallSourceMacLabel ?? 'Source MAC',
                          hintText: 'e.g. AA:BB:CC:DD:EE:FF',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v != null && v.trim().isNotEmpty) {
                            final macs = _parseMacList(v);
                            for (final m in macs) {
                              if (!_isValidMac(m)) {
                                return 'Invalid MAC: $m';
                              }
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Destination IP & Destination Port
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _destIpController,
                        decoration: InputDecoration(
                          labelText:
                              l10n?.firewallDestIpLabel ??
                              'Destination IP / CIDR',
                          hintText: 'e.g. 10.0.0.1 or /24',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v != null &&
                              v.trim().isNotEmpty &&
                              !FirewallValidator.isValidIpOrCidr(v)) {
                            return 'Invalid IP or CIDR.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _destPortController,
                        decoration: InputDecoration(
                          labelText:
                              l10n?.firewallDestPortLabel ?? 'Destination Port',
                          hintText: 'e.g. 80, 443, 8000-8080',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v != null &&
                              v.trim().isNotEmpty &&
                              !_isValidPortSpec(v)) {
                            return 'Invalid port format.';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Protocol & Family
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _proto,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        dropdownColor: theme.colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        menuMaxHeight: 360,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        decoration: InputDecoration(
                          labelText: l10n?.firewallProtocolLabel ?? 'Protocol',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'any', child: Text('Any')),
                          DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                          DropdownMenuItem(value: 'udp', child: Text('UDP')),
                          DropdownMenuItem(
                            value: 'tcp udp',
                            child: Text('TCP + UDP'),
                          ),
                          DropdownMenuItem(value: 'icmp', child: Text('ICMP')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _proto = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _family,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        dropdownColor: theme.colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        menuMaxHeight: 360,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        decoration: InputDecoration(
                          labelText: l10n?.firewallIpFamilyLabel ?? 'IP Family',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          helperText: !supportsIpv6
                              ? (l10n?.firewallIpv6NotSupported ??
                                    'IPv6 not supported')
                              : null,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'any',
                            child: Text(
                              l10n?.firewallFamilyAny ?? 'Any (IPv4+IPv6)',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'ipv4',
                            child: Text(
                              l10n?.firewallFamilyIpv4Only ?? 'IPv4 only',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'ipv6',
                            enabled: supportsIpv6,
                            child: Text(
                              l10n?.firewallFamilyIpv6Only ?? 'IPv6 only',
                              style: TextStyle(
                                color: !supportsIpv6 ? Colors.grey : null,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _family = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Enabled Switch
                SwitchListTile.adaptive(
                  title: Text(l10n?.firewallRuleEnabledLabel ?? 'Rule Enabled'),
                  subtitle: Text(
                    l10n?.firewallRuleEnabledSubtitle ??
                        'Activate this security rule immediately',
                  ),
                  value: _enabled,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setState(() => _enabled = val),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n?.firewallBtnCancel ?? 'Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _handleSubmit,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_isEditing ? Icons.save : Icons.add_moderator),
          label: Text(
            _isEditing
                ? (l10n?.firewallBtnSaveChanges ?? 'Save Changes')
                : (l10n?.firewallBtnCreateRule ?? 'Create Rule'),
          ),
        ),
      ],
    );
  }
}
