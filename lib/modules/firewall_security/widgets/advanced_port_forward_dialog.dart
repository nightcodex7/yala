// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

class AdvancedPortForwardDialog extends ConsumerStatefulWidget {
  final FirewallPortForwarding? initialPortForward;
  final FirewallOverview overview;

  const AdvancedPortForwardDialog({
    super.key,
    this.initialPortForward,
    required this.overview,
  });

  static Future<bool?> show(
    BuildContext context, {
    FirewallPortForwarding? initialPortForward,
    required FirewallOverview overview,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AdvancedPortForwardDialog(
        initialPortForward: initialPortForward,
        overview: overview,
      ),
    );
  }

  @override
  ConsumerState<AdvancedPortForwardDialog> createState() =>
      _AdvancedPortForwardDialogState();
}

class _AdvancedPortForwardDialogState
    extends ConsumerState<AdvancedPortForwardDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _srcPortController;
  late final TextEditingController _destIpController;
  late final TextEditingController _destPortController;
  late final TextEditingController _srcIpController;

  late String _srcZone;
  late String _destZone;
  late String _proto;
  late String _family;
  late bool _enabled;
  late bool _reflection;

  bool _isSubmitting = false;
  String? _validationError;

  bool get _isEditing => widget.initialPortForward != null;

  @override
  void initState() {
    super.initState();
    final init = widget.initialPortForward;
    _nameController = TextEditingController(text: init?.name ?? '');
    _srcPortController = TextEditingController(text: init?.srcPort ?? '');
    _destIpController = TextEditingController(text: init?.destIp ?? '');
    _destPortController = TextEditingController(text: init?.destPort ?? '');
    _srcIpController = TextEditingController(text: init?.srcIp ?? '');

    // Source zone default: 'wan' if exists, otherwise first zone
    final availableZones = widget.overview.zones.map((z) => z.name).toList();
    if (init != null && availableZones.contains(init.srcZone)) {
      _srcZone = init.srcZone;
    } else if (availableZones.contains('wan')) {
      _srcZone = 'wan';
    } else {
      _srcZone = availableZones.isNotEmpty ? availableZones.first : 'wan';
    }

    // Destination zone default: 'lan' or primary LAN
    final lanCandidate = widget.overview.primaryLanZoneName ?? 'lan';
    if (init != null && availableZones.contains(init.destZone)) {
      _destZone = init.destZone;
    } else if (availableZones.contains(lanCandidate)) {
      _destZone = lanCandidate;
    } else if (availableZones.contains('lan')) {
      _destZone = 'lan';
    } else {
      _destZone = availableZones.isNotEmpty ? availableZones.first : 'lan';
    }

    _proto = init?.proto.toLowerCase() ?? 'tcp';
    if (_proto == 'tcpudp') _proto = 'tcp udp';

    _family = init?.family.toLowerCase() ?? 'any';
    _enabled = init?.enabled ?? true;
    _reflection = init?.reflection ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _srcPortController.dispose();
    _destIpController.dispose();
    _destPortController.dispose();
    _srcIpController.dispose();
    super.dispose();
  }

  bool _isValidPortSpec(String? portSpec) {
    if (portSpec == null || portSpec.trim().isEmpty) return false;
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

  NatReflectionCapabilityResult _evaluateReflection() {
    final appState = ref.read(appStateProvider);
    final rawDump = appState.dashboardData?['interfaceDump'];
    final rawDevices = appState.dashboardData?['networkDevices'];
    FirewallTopologyFacts? topologyFacts;
    if (rawDump is Map<String, dynamic>) {
      topologyFacts = FirewallTopologyFacts.fromNetworkDump(
        rawDump,
        networkDevices: rawDevices is Map<String, dynamic> ? rawDevices : null,
      );
    }

    final rawUci = widget.initialPortForward?.rawUciValues;
    final rawRz = rawUci?['reflection_zone'];
    final List<String> rzList = [];
    if (rawRz is List) {
      rzList.addAll(rawRz.map((e) => e.toString()));
    } else if (rawRz is String && rawRz.trim().isNotEmpty) {
      rzList.addAll(rawRz.trim().split(RegExp(r'\s+')));
    }

    final redirectCtx = NatReflectionRedirectContext(
      srcZone: _srcZone,
      destZone: _destZone,
      destIp: _destIpController.text.trim(),
      family: _family,
      existingReflection: widget.initialPortForward?.rawUciValues['reflection']
          ?.toString(),
      existingReflectionSrc: rawUci?['reflection_src']?.toString(),
      existingReflectionZones: rzList,
    );

    return FirewallValidator.evaluateNatReflectionCapability(
      overview: widget.overview,
      capabilities: appState.capabilities,
      redirectContext: redirectCtx,
      topologyFacts: topologyFacts,
    );
  }

  void _pickClientIp(List<Client> clients) async {
    final validClients = clients
        .where((c) => c.ipAddress.trim().isNotEmpty && c.ipAddress != 'N/A')
        .toList();
    if (validClients.isEmpty) return;

    final selected = await showDialog<Client>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Select Connected Client'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: validClients.length,
              itemBuilder: (cCtx, idx) {
                final client = validClients[idx];
                return ListTile(
                  leading: const Icon(Icons.devices),
                  title: Text(client.displayName),
                  subtitle: Text('${client.ipAddress} (${client.macAddress})'),
                  onTap: () => Navigator.of(cCtx).pop(client),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selected != null) {
      setState(() {
        _destIpController.text = selected.ipAddress;
      });
    }
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
    final srcPort = _srcPortController.text.trim();
    final destIp = _destIpController.text.trim();
    final destPort = _destPortController.text.trim().isNotEmpty
        ? _destPortController.text.trim()
        : srcPort;
    final srcIp = _srcIpController.text.trim();

    // Check reflection capability gating
    final reflectionEval = _evaluateReflection();
    final effectiveReflection =
        reflectionEval.status == NatReflectionStatus.supported
        ? _reflection
        : false;

    // Build rawUciValues preserving unmanaged UCI keys if editing
    final preservedRawValues = Map<String, dynamic>.from(
      widget.initialPortForward?.rawUciValues ?? const {},
    );

    final candidate = FirewallPortForwarding(
      sectionKey: widget.initialPortForward?.sectionKey ?? '',
      name: name,
      srcZone: _srcZone,
      srcPort: srcPort,
      destZone: _destZone,
      destIp: destIp,
      destPort: destPort,
      proto: _proto,
      srcIp: srcIp.isNotEmpty ? srcIp : null,
      reflection: effectiveReflection,
      enabled: _enabled,
      family: _family,
      target: 'DNAT',
      rawUciValues: preservedRawValues,
    );

    // 1. Conflict check against existing port forwards
    final conflict = FirewallValidator.checkPortForwardConflict(
      candidate,
      widget.overview.portForwards,
    );
    if (conflict.hasConflict) {
      setState(() {
        _validationError = loc?.firewallConflictPortInUse ?? conflict.reason;
      });
      return;
    }

    // 2. Safety check against router management ports
    final customMgmtPorts = SelfDeviceGuard.getDiscoveredManagementPorts(
      appState.selectedRouter?.id ?? appState.selectedRouter?.ipAddress,
    );
    final safety = FirewallValidator.checkManagementPortSafety(
      candidate,
      routerLanIp: appState.selectedRouter?.ipAddress,
      customManagementPorts: customMgmtPorts,
    );
    if (safety.isUnsafe) {
      setState(() {
        _validationError =
            loc?.firewallConflictManagementPort ??
            'This port is reserved for router administration. Exposing it externally is not permitted.';
      });
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final bool success;
      if (_isEditing) {
        success = await appState.updateFirewallPortForward(
          candidate,
          context: mounted ? context : null,
        );
      } else {
        success = await appState.addFirewallPortForward(
          candidate,
          context: mounted ? context : null,
        );
      }

      if (!mounted) return;

      if (success) {
        LuciToastManager.showSuccess(
          context,
          _isEditing
              ? 'Port forward "$name" updated successfully.'
              : 'Port forward "$name" created successfully.',
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSubmitting = false;
          _validationError = 'Failed to save port forwarding configuration.';
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
    final appState = ref.watch(appStateProvider);
    final capabilities = appState.capabilities;
    final supportsIpv6 = capabilities?.supportsIpv6InternetFirewall ?? false;
    final availableZones = widget.overview.zones.map((z) => z.name).toList();
    if (!availableZones.contains(_srcZone) && availableZones.isNotEmpty) {
      _srcZone = availableZones.first;
    }
    if (!availableZones.contains(_destZone) && availableZones.isNotEmpty) {
      _destZone = availableZones.first;
    }

    final reflectionEval = _evaluateReflection();
    final canUseReflection =
        reflectionEval.status == NatReflectionStatus.supported;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isEditing ? Icons.edit_outlined : Icons.add_circle_outline,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isEditing ? 'Edit Port Forward' : 'Add Port Forward',
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

                // Name field
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Rule Name *',
                    hintText: 'e.g. Web Server, Plex',
                    prefixIcon: Icon(Icons.label_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter a rule name.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Source Zone & External Port
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<String>(
                        initialValue: _srcZone,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        dropdownColor: theme.colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        menuMaxHeight: 360,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        decoration: InputDecoration(
                          labelText: 'Source Zone',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: availableZones.map((z) {
                          return DropdownMenuItem(
                            value: z,
                            child: Text(z.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _srcZone = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: TextFormField(
                        controller: _srcPortController,
                        decoration: const InputDecoration(
                          labelText: 'External Port *',
                          hintText: 'e.g. 80, 80,443',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Enter port or range.';
                          }
                          if (!_isValidPortSpec(v)) {
                            return 'Invalid port format.';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Destination Zone & Destination Port
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<String>(
                        initialValue: _destZone,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        dropdownColor: theme.colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        menuMaxHeight: 360,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        decoration: InputDecoration(
                          labelText: 'Dest Zone',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: availableZones.map((z) {
                          return DropdownMenuItem(
                            value: z,
                            child: Text(z.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _destZone = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: TextFormField(
                        controller: _destPortController,
                        decoration: const InputDecoration(
                          labelText: 'Internal Port',
                          hintText: 'Defaults to external port',
                          border: OutlineInputBorder(),
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

                // Destination IP
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _destIpController,
                        decoration: const InputDecoration(
                          labelText: 'Internal Destination IP *',
                          hintText: 'e.g. 192.168.1.100',
                          prefixIcon: Icon(Icons.computer_outlined),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Please enter destination IP.';
                          }
                          final clean = v.trim();
                          final isV4 = FirewallValidator.isValidIpv4(clean);
                          final isV6 = Ipv6AddressUtil.tryParse(clean) != null;
                          if (!isV4 && !isV6) {
                            return 'Please enter a valid IPv4 or IPv6 address.';
                          }
                          if (_family == 'ipv4' && !isV4) {
                            return 'Destination IP must be IPv4 for IPv4 family.';
                          }
                          if (_family == 'ipv6' && !isV6) {
                            return 'Destination IP must be IPv6 for IPv6 family.';
                          }
                          return null;
                        },
                      ),
                    ),
                    if (appState.clients.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Select connected client',
                        icon: const Icon(Icons.devices),
                        onPressed: () => _pickClientIp(appState.clients),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // Protocol & IP Family
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
                          labelText: 'Protocol',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                          DropdownMenuItem(value: 'udp', child: Text('UDP')),
                          DropdownMenuItem(
                            value: 'tcp udp',
                            child: Text('TCP + UDP'),
                          ),
                          DropdownMenuItem(value: 'any', child: Text('Any')),
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
                          labelText: 'IP Family',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          helperText: !supportsIpv6
                              ? 'IPv6 not supported'
                              : null,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'any',
                            child: Text('Any (IPv4+IPv6)'),
                          ),
                          const DropdownMenuItem(
                            value: 'ipv4',
                            child: Text('IPv4 only'),
                          ),
                          DropdownMenuItem(
                            value: 'ipv6',
                            enabled: supportsIpv6,
                            child: Text(
                              'IPv6 only',
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

                // Source IP Filter
                TextFormField(
                  controller: _srcIpController,
                  decoration: const InputDecoration(
                    labelText: 'Source IP Filter (Optional)',
                    hintText: 'e.g. 203.0.113.50 or 203.0.113.0/24',
                    prefixIcon: Icon(Icons.filter_alt_outlined),
                    border: OutlineInputBorder(),
                    helperText: 'Leave empty to allow from any external IP.',
                  ),
                  validator: (v) {
                    if (v != null &&
                        v.trim().isNotEmpty &&
                        !FirewallValidator.isValidIpOrCidr(v)) {
                      return 'Must be a valid IP or CIDR.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // NAT Reflection / Loopback Switch
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: canUseReflection
                          ? theme.colorScheme.outlineVariant
                          : theme.colorScheme.error.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    color: canUseReflection
                        ? null
                        : theme.colorScheme.errorContainer.withValues(
                            alpha: 0.1,
                          ),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        title: const Text(
                          'NAT Loopback / Reflection',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          canUseReflection
                              ? 'Allows LAN devices to connect using the external WAN address.'
                              : reflectionEval.userFacingReason,
                          style: TextStyle(
                            fontSize: 12,
                            color: canUseReflection
                                ? theme.textTheme.bodySmall?.color
                                : theme.colorScheme.error,
                          ),
                        ),
                        value: canUseReflection ? _reflection : false,
                        onChanged: canUseReflection
                            ? (val) => setState(() => _reflection = val)
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Enabled Toggle
                SwitchListTile.adaptive(
                  title: const Text('Rule Enabled'),
                  subtitle: const Text(
                    'Activate this port forward rule immediately',
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
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _handleSubmit,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_isEditing ? Icons.save : Icons.add),
          label: Text(_isEditing ? 'Save Changes' : 'Add Port Forward'),
        ),
      ],
    );
  }
}
