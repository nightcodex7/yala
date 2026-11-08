// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

enum PortForwardPreset { plex, minecraft, webServer, custom }

/// Simple "Open a Port" wizard dialog.
class AddPortForwardDialog extends ConsumerStatefulWidget {
  const AddPortForwardDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AddPortForwardDialog(),
    );
  }

  @override
  ConsumerState<AddPortForwardDialog> createState() =>
      _AddPortForwardDialogState();
}

class _AddPortForwardDialogState extends ConsumerState<AddPortForwardDialog> {
  final _formKey = GlobalKey<FormState>();

  PortForwardPreset _selectedPreset = PortForwardPreset.plex;
  bool _useManualIp = false;

  Client? _selectedClient;
  final _manualIpController = TextEditingController();
  final _customServiceNameController = TextEditingController();
  final _customExternalPortController = TextEditingController();
  final _customInternalPortController = TextEditingController();
  String _customProto = 'tcp';

  bool _isSubmitting = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final appState = ref.read(appStateProvider);
    final clients = appState.clients;
    final validClients = clients
        .where((c) => FirewallValidator.isValidIpv4(c.ipAddress))
        .toList();

    if (validClients.isNotEmpty) {
      _selectedClient = validClients.first;
      _useManualIp = false;
    } else {
      _useManualIp = true;
    }
  }

  @override
  void dispose() {
    _manualIpController.dispose();
    _customServiceNameController.dispose();
    _customExternalPortController.dispose();
    _customInternalPortController.dispose();
    super.dispose();
  }

  String _getPresetName(AppLocalizations? loc, PortForwardPreset preset) {
    switch (preset) {
      case PortForwardPreset.plex:
        return loc?.firewallWizardPresetPlex ?? 'Plex Media Server';
      case PortForwardPreset.minecraft:
        return loc?.firewallWizardPresetMinecraft ?? 'Minecraft Server';
      case PortForwardPreset.webServer:
        return loc?.firewallWizardPresetWebServer ?? 'Web Server (HTTP/HTTPS)';
      case PortForwardPreset.custom:
        return loc?.firewallWizardPresetCustom ?? 'Custom Service';
    }
  }

  String _getServiceName(AppLocalizations? loc) {
    if (_selectedPreset == PortForwardPreset.custom) {
      final customName = _customServiceNameController.text.trim();
      return customName.isNotEmpty
          ? customName
          : (loc?.firewallWizardPresetCustom ?? 'Custom Service');
    }
    return _getPresetName(loc, _selectedPreset);
  }

  String _getExternalPort() {
    switch (_selectedPreset) {
      case PortForwardPreset.plex:
        return '32400';
      case PortForwardPreset.minecraft:
        return '25565';
      case PortForwardPreset.webServer:
        return '80,443';
      case PortForwardPreset.custom:
        return _customExternalPortController.text.trim();
    }
  }

  String _getInternalPort() {
    switch (_selectedPreset) {
      case PortForwardPreset.plex:
        return '32400';
      case PortForwardPreset.minecraft:
        return '25565';
      case PortForwardPreset.webServer:
        return '80,443';
      case PortForwardPreset.custom:
        final internal = _customInternalPortController.text.trim();
        return internal.isNotEmpty
            ? internal
            : _customExternalPortController.text.trim();
    }
  }

  String _getProtocol() {
    switch (_selectedPreset) {
      case PortForwardPreset.plex:
        return 'tcp';
      case PortForwardPreset.minecraft:
        return 'tcp udp';
      case PortForwardPreset.webServer:
        return 'tcp';
      case PortForwardPreset.custom:
        return _customProto;
    }
  }

  String? _getTargetIp() {
    if (_useManualIp) {
      return _manualIpController.text.trim();
    }
    return _selectedClient?.ipAddress.trim();
  }

  String _getTargetDeviceDisplayName() {
    if (_useManualIp) {
      return _manualIpController.text.trim();
    }
    if (_selectedClient != null) {
      return _selectedClient!.displayName;
    }
    return 'Device';
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

    final targetIp = _getTargetIp();
    if (targetIp == null || !FirewallValidator.isValidIpv4(targetIp)) {
      setState(() {
        _validationError = 'Please select or enter a valid IPv4 address.';
      });
      return;
    }

    final externalPort = _getExternalPort();
    final internalPort = _getInternalPort();
    final proto = _getProtocol();
    final serviceName = _getServiceName(loc);

    final overview = FirewallOverview.fromUciData(
      appState.dashboardData?['uciFirewallConfig'],
      backend: appState.capabilities?.firewallBackend ?? FirewallBackend.fw4,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final destZone = overview.primaryLanZoneName ?? 'lan';

    final candidate = FirewallPortForwarding(
      name: serviceName,
      srcZone: 'wan',
      srcPort: externalPort,
      destZone: destZone,
      destIp: targetIp,
      destPort: internalPort,
      proto: proto,
      target: 'DNAT',
      enabled: true,
    );

    // 1. Conflict check against active port forwards
    final conflict = FirewallValidator.checkPortForwardConflict(
      candidate,
      overview.portForwards,
    );
    if (conflict.hasConflict) {
      setState(() {
        _validationError =
            loc?.firewallConflictPortInUse ??
            'This port is already being used by another rule.';
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

    // Submit mutation
    setState(() => _isSubmitting = true);
    try {
      final success = await appState.addFirewallPortForward(candidate);
      if (!mounted) return;

      if (success) {
        final deviceName = _getTargetDeviceDisplayName();
        LuciToastManager.showSuccess(
          context,
          loc?.firewallSuccessPortOpened(
                candidate.srcPort,
                candidate.name,
                deviceName,
              ) ??
              'Port ${candidate.srcPort} is now open for ${candidate.name} on $deviceName.',
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSubmitting = false;
          _validationError = 'Failed to apply port forwarding rule.';
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
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final clients = appState.clients;
    final validClients = clients
        .where((c) => FirewallValidator.isValidIpv4(c.ipAddress))
        .toList();

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.door_sliding_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loc?.firewallOpenPortTitle ?? 'Open a Port',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc?.firewallWizardChoosePreset ?? 'Select a Service',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Presets Dropdown
                DropdownButtonFormField<PortForwardPreset>(
                  initialValue: _selectedPreset,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: theme.colorScheme.surfaceContainerHigh,
                  elevation: 4,
                  menuMaxHeight: 360,
                  icon: const Icon(Icons.arrow_drop_down_rounded),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: PortForwardPreset.plex,
                      child: Text(_getPresetName(loc, PortForwardPreset.plex)),
                    ),
                    DropdownMenuItem(
                      value: PortForwardPreset.minecraft,
                      child: Text(
                        _getPresetName(loc, PortForwardPreset.minecraft),
                      ),
                    ),
                    DropdownMenuItem(
                      value: PortForwardPreset.webServer,
                      child: Text(
                        _getPresetName(loc, PortForwardPreset.webServer),
                      ),
                    ),
                    DropdownMenuItem(
                      value: PortForwardPreset.custom,
                      child: Text(
                        _getPresetName(loc, PortForwardPreset.custom),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedPreset = val;
                        _validationError = null;
                      });
                    }
                  },
                ),

                // Web Server Security Warning
                if (_selectedPreset == PortForwardPreset.webServer) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade700),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber.shade900,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                loc?.firewallWizardWebServerWarning ??
                                    'This will make your web server accessible to anyone on the Internet.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          loc?.firewallOpensTcpBothPorts ??
                              'Opens TCP ports 80 and 443',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Custom Service Fields
                if (_selectedPreset == PortForwardPreset.custom) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customServiceNameController,
                    decoration: InputDecoration(
                      labelText:
                          loc?.firewallWizardServiceName ?? 'Service Name',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter a service name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _customExternalPortController,
                          decoration: InputDecoration(
                            labelText:
                                loc?.firewallWizardExternalPort ??
                                'External Port',
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.text,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Enter port';
                            }
                            final ranges = FirewallValidator.parsePortRanges(
                              val,
                            );
                            if (ranges.isEmpty) {
                              return 'Invalid port';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _customInternalPortController,
                          decoration: InputDecoration(
                            labelText:
                                loc?.firewallWizardInternalPort ??
                                'Internal Port',
                            hintText: 'Same as external',
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _customProto,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(16),
                    dropdownColor: theme.colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    menuMaxHeight: 360,
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    decoration: InputDecoration(
                      labelText: loc?.firewallWizardProtocol ?? 'Protocol',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
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
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _customProto = val);
                      }
                    },
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // Device Selection Header
                Text(
                  loc?.firewallWizardInternalDevice ?? 'Internal Device',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Device Selection Mode Segment
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment<bool>(
                        value: false,
                        icon: const Icon(Icons.devices_outlined, size: 18),
                        label: Text(
                          loc?.firewallWizardSelectDevice ?? 'Connected Device',
                        ),
                        enabled: validClients.isNotEmpty,
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(loc?.firewallWizardManualIp ?? 'Manual IP'),
                      ),
                    ],
                    selected: {_useManualIp},
                    onSelectionChanged: (newSelection) {
                      if (newSelection.isNotEmpty) {
                        setState(() => _useManualIp = newSelection.first);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // Connected Devices Dropdown
                if (!_useManualIp) ...[
                  if (validClients.isEmpty)
                    Text(
                      'No connected devices with active IPv4 addresses found. Please enter IP manually.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    )
                  else
                    DropdownButtonFormField<Client>(
                      initialValue:
                          _selectedClient != null &&
                              validClients.contains(_selectedClient)
                          ? _selectedClient
                          : validClients.first,
                      decoration: InputDecoration(
                        labelText: 'Select Connected Device',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(16),
                      dropdownColor: theme.colorScheme.surfaceContainerHigh,
                      elevation: 4,
                      menuMaxHeight: 360,
                      icon: const Icon(Icons.arrow_drop_down_rounded),
                      items: validClients.map((c) {
                        final name = ClientNamingHelper.getDisplayName(
                          c.macAddress,
                          appState: appState,
                          client: c,
                        );
                        final isWifi =
                            c.connectionType == ConnectionType.wireless;
                        return DropdownMenuItem(
                          value: c,
                          child: Row(
                            children: [
                              Icon(
                                isWifi
                                    ? Icons.wifi_rounded
                                    : Icons.lan_outlined,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                c.ipAddress,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (client) {
                        setState(() => _selectedClient = client);
                      },
                    ),
                ] else ...[
                  TextFormField(
                    controller: _manualIpController,
                    decoration: InputDecoration(
                      labelText:
                          loc?.firewallWizardManualIpLabel ??
                          'Internal Device IP',
                      hintText: '192.168.1.100',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.datetime,
                    validator: (val) {
                      if (_useManualIp) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter IP address';
                        }
                        if (!FirewallValidator.isValidIpv4(val.trim())) {
                          return 'Invalid IPv4 address';
                        }
                      }
                      return null;
                    },
                  ),
                ],

                // Validation / Error Banner
                if (_validationError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _validationError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w500,
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
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(loc?.btnCancel ?? 'Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(loc?.firewallOpenPortTitle ?? 'Open a Port'),
        ),
      ],
    );
  }
}
