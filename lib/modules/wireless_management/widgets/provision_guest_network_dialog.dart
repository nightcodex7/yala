// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/password_strength_meter.dart';
import '../models/wireless_info.dart';

/// Wizard dialog for 1-click creation of an isolated Guest WiFi network
/// spanning network, dhcp, firewall, and wireless configs atomically.
class ProvisionGuestNetworkDialog extends ConsumerStatefulWidget {
  final List<WirelessRadio> radios;

  const ProvisionGuestNetworkDialog({super.key, required this.radios});

  @override
  ConsumerState<ProvisionGuestNetworkDialog> createState() =>
      _ProvisionGuestNetworkDialogState();
}

class _ProvisionGuestNetworkDialogState
    extends ConsumerState<ProvisionGuestNetworkDialog> {
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController(text: 'MyHome_Guest');
  final _passphraseController = TextEditingController();
  final _guestIpController = TextEditingController(text: '192.168.2.1');
  final _mobilityDomainController = TextEditingController();
  final _dtimPeriodController = TextEditingController(text: '2');
  final _gtkRekeyController = TextEditingController(text: '3600');
  final _inactivityLimitController = TextEditingController(text: '300');
  final _maxListenIntervalController = TextEditingController(text: '65535');
  final _maclistController = TextEditingController();

  late WirelessRadio _selectedRadio;
  String _selectedEncryption = 'sae-mixed'; // best-recommended default
  String _selectedPmf = '1'; // optional PMF by default
  bool _isolateClients = true; // always on for guest networks
  bool _isSubmitting = false;
  bool _showPassphrase = false;

  // Network Attachment
  String _selectedNetwork = 'guest';
  List<String> _availableNetworks = ['guest', 'lan', 'wan'];

  // Fast Roaming (802.11r/k/v)
  bool _ieee80211r = false;
  bool _ftOverDs = false;
  bool _ftPskGenerateLocal = false;

  // Wireless Advanced Settings
  bool _wmm = true;
  bool _hidden = false;
  bool _disassocLowAck = true;
  bool _multicastToUnicast = false;
  bool _wds = false;

  // MAC Filtering
  String _macfilter = 'disable';

  bool _showAdvanced = false;

  // Hardware capabilities (fetched live from router)
  List<Map<String, String>> _dynamicEncryptions = [];

  @override
  void initState() {
    super.initState();
    _selectedRadio = widget.radios.isNotEmpty
        ? widget.radios.first
        : const WirelessRadio(
            name: 'radio0',
            isUp: true,
            channel: 'auto',
            country: 'US',
            interfaces: [],
          );
    _fetchAvailableNetworks();
    _fetchHardwareCapabilities();
  }

  Future<void> _fetchAvailableNetworks() async {
    try {
      final appState = ref.read(appStateProvider);
      final networks = await appState.fetchNetworkInterfaces();
      if (mounted && networks.isNotEmpty) {
        setState(() {
          _availableNetworks = networks;
          if (!_availableNetworks.contains(_selectedNetwork)) {
            _selectedNetwork = _availableNetworks.firstWhere(
              (n) => n == 'guest',
              orElse: () => _availableNetworks.first,
            );
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchHardwareCapabilities() async {
    if (!mounted) return;
    final appState = ref.read(appStateProvider);
    try {
      final refIface = _selectedRadio.interfaces.isNotEmpty
          ? _selectedRadio.interfaces.firstWhere(
              (i) => i.mode.toLowerCase() == 'ap',
              orElse: () => _selectedRadio.interfaces.first,
            )
          : null;
      final caps = await appState.fetchWirelessHardwareCapabilities(
        sectionName: refIface?.sectionName ?? _selectedRadio.name,
        radioName: _selectedRadio.name,
      );
      if (mounted) {
        setState(() {
          _dynamicEncryptions = caps['encryptions'] ?? [];
          _applySmartDefaults();
        });
      }
    } catch (_) {}
  }

  /// Guest-optimised smart defaults: prefer sae-mixed for compatibility, always isolate.
  void _applySmartDefaults() {
    if (_dynamicEncryptions.isEmpty) return;
    final supported = _dynamicEncryptions.map((e) => e['value']!).toList();
    for (final preferred in ['sae-mixed', 'psk2', 'psk', 'owe', 'none']) {
      if (supported.contains(preferred)) {
        _selectedEncryption = preferred;
        break;
      }
    }
    _updateCipherAndPmf(_selectedEncryption);
  }

  void _updateCipherAndPmf(String enc) {
    if (enc == 'sae' || enc == 'sae-mixed') {
      _selectedPmf = enc == 'sae' ? '2' : '1';
    } else if (enc == 'psk2') {
      _selectedPmf = '1';
    } else if (enc == 'owe') {
      _selectedPmf = '2';
    } else {
      _selectedPmf = '0';
    }
  }

  bool _requiresPassphrase() =>
      _selectedEncryption != 'none' && _selectedEncryption != 'owe';

  @override
  void dispose() {
    _ssidController.dispose();
    _passphraseController.dispose();
    _guestIpController.dispose();
    _mobilityDomainController.dispose();
    _dtimPeriodController.dispose();
    _gtkRekeyController.dispose();
    _inactivityLimitController.dispose();
    _maxListenIntervalController.dispose();
    _maclistController.dispose();
    super.dispose();
  }

  int get _ssidByteLength => utf8.encode(_ssidController.text).length;

  Future<void> _submitProvisionGuest() async {
    if (!_formKey.currentState!.validate()) return;

    final appState = ref.read(appStateProvider);
    final hasUciWrite =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;

    if (!hasUciWrite) {
      context.showToastError(
        'Read-only session: UCI write permission required to create Guest Wi-Fi.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // Parse MAC list if provided
    List<String>? macList;
    if (_macfilter != 'disable' && _maclistController.text.trim().isNotEmpty) {
      macList = _maclistController.text
          .split(RegExp(r'[\n,;]+'))
          .map((e) => e.trim().toUpperCase())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final success = await appState.provisionGuestNetwork(
      radioName: _selectedRadio.name,
      ssid: _ssidController.text.trim(),
      encryption: _selectedEncryption,
      key: _requiresPassphrase() ? _passphraseController.text.trim() : '',
      guestIp: _guestIpController.text.trim(),
      isolateClients: _isolateClients,
      network: _selectedNetwork,
      country: null,
      channel: null,
      htMode: null,
      txPower: null,
      ieee80211r: _ieee80211r,
      ftOverDs: _ftOverDs,
      ftPskGenerateLocal: _ftPskGenerateLocal,
      mobilityDomain: _mobilityDomainController.text.trim().isNotEmpty
          ? _mobilityDomainController.text.trim().toLowerCase()
          : null,
      wmm: _wmm,
      hidden: _hidden,
      dtimPeriod: int.tryParse(_dtimPeriodController.text.trim()),
      gtkRekey: int.tryParse(_gtkRekeyController.text.trim()),
      inactivityLimit: int.tryParse(_inactivityLimitController.text.trim()),
      maxListenInterval: int.tryParse(_maxListenIntervalController.text.trim()),
      disassocLowAck: _disassocLowAck,
      multicastToUnicast: _multicastToUnicast,
      wds: _wds,
      macfilter: _macfilter == 'disable' ? null : _macfilter,
      maclist: macList,
      context: context,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        Navigator.pop(context, true);
        context.showToastSuccess(
          'New Guest Wi-Fi "${_ssidController.text.trim()}" created successfully!',
        );
      } else {
        final username = appState.sessionUsername;
        if (!hasUciWrite) {
          context.showToastError(
            'Access Denied: Account \'$username\' lacks ubus UCI write authorization.',
          );
        } else {
          context.showToastError(
            'Failed to provision guest network on router.',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needsPass = _requiresPassphrase();
    final appState = ref.watch(appStateProvider);
    final hasUciWrite =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;

    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.shield_moon_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Create New Guest Wi-Fi',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasUciWrite) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_clock_outlined,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Logged in as non-root / read-only session (\'${appState.sessionUsername}\'). UCI write privileges required.',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Physical Radio Target Dropdown
                DropdownButtonFormField<WirelessRadio>(
                  initialValue: _selectedRadio,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Target Physical Radio',
                    prefixIcon: Icon(Icons.cell_tower_rounded, size: 20),
                    border: OutlineInputBorder(),
                  ),
                  items: widget.radios.map((r) {
                    return DropdownMenuItem(
                      value: r,
                      child: Text(
                        '${r.name.toUpperCase()} (${r.bandLabel})',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedRadio = val);
                  },
                ),
                const SizedBox(height: 14),

                // Physical Radio Inherited Hint
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Radio settings (Channel ${_selectedRadio.channel}, Band ${_selectedRadio.bandLabel}) are inherited from physical radio ${_selectedRadio.name.toUpperCase()}.',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Guest SSID Name Input
                TextFormField(
                  controller: _ssidController,
                  decoration: InputDecoration(
                    labelText: 'Guest SSID Name',
                    hintText: 'e.g. MyHome_Guest',
                    helperText: 'UTF-8 Bytes: $_ssidByteLength / 32 max',
                    prefixIcon: const Icon(Icons.wifi_rounded, size: 20),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Guest SSID name cannot be empty';
                    }
                    final bytes = utf8.encode(val.trim()).length;
                    if (bytes > 32) {
                      return 'SSID length exceeds 32 UTF-8 bytes ($bytes bytes)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Network Attachment Dropdown
                DropdownButtonFormField<String>(
                  initialValue: _selectedNetwork,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Network Attachment',
                    prefixIcon: Icon(Icons.router_rounded, size: 20),
                    border: OutlineInputBorder(),
                    helperText: 'Logical network bridge interface',
                  ),
                  items: _availableNetworks.map((network) {
                    return DropdownMenuItem(
                      value: network,
                      child: Text(
                        network,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedNetwork = val);
                  },
                ),
                const SizedBox(height: 14),

                if (_selectedNetwork == 'guest') ...[
                  TextFormField(
                    controller: _guestIpController,
                    decoration: const InputDecoration(
                      labelText: 'Guest Gateway IP Address',
                      hintText: '192.168.2.1',
                      prefixIcon: Icon(Icons.router_outlined, size: 20),
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (_selectedNetwork != 'guest') return null;
                      if (val == null || val.trim().isEmpty) {
                        return 'Guest IP address is required';
                      }
                      final parts = val.trim().split('.');
                      if (parts.length != 4) {
                        return 'Enter a valid IPv4 address (e.g. 192.168.2.1)';
                      }
                      for (final part in parts) {
                        final n = int.tryParse(part);
                        if (n == null || n < 0 || n > 255) {
                          return 'Invalid octet: $part';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],

                // Encryption Selection Dropdown
                DropdownButtonFormField<String>(
                  initialValue: _selectedEncryption,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Security Protocol',
                    prefixIcon: Icon(Icons.security_rounded, size: 20),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'sae-mixed',
                      child: Text(
                        'WPA2/WPA3 Personal (sae-mixed) — Recommended',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'sae',
                      child: Text('WPA3 Personal Only (sae)'),
                    ),
                    DropdownMenuItem(
                      value: 'psk2',
                      child: Text('WPA2 Personal (psk2)'),
                    ),
                    DropdownMenuItem(
                      value: 'owe',
                      child: Text(
                        'Enhanced Open (OWE — No Password, Encrypted)',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('Open (No Encryption / No Password)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedEncryption = val;
                        _updateCipherAndPmf(val);
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),

                // Passphrase Field
                if (needsPass) ...[
                  TextFormField(
                    controller: _passphraseController,
                    obscureText: !_showPassphrase,
                    decoration: InputDecoration(
                      labelText: 'Wi-Fi Passphrase',
                      hintText: 'Minimum 8 characters',
                      prefixIcon: const Icon(Icons.key_rounded, size: 20),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPassphrase
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _showPassphrase = !_showPassphrase),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (val) {
                      if (!needsPass) return null;
                      if (val == null || val.trim().isEmpty) {
                        return 'Passphrase is required for encrypted networks';
                      }
                      if (val.trim().length < 8) {
                        return 'Passphrase must be at least 8 characters';
                      }
                      if (val.trim().length > 63) {
                        return 'Passphrase cannot exceed 63 characters';
                      }
                      return null;
                    },
                  ),
                  PasswordStrengthMeter(password: _passphraseController.text),
                  const SizedBox(height: 14),
                ],

                // Client Isolation Switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Client Isolation',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Prevents connected guest devices from talking to each other',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _isolateClients,
                  onChanged: (val) => setState(() => _isolateClients = val),
                ),
                const SizedBox(height: 8),

                // Advanced Options Expandable Section
                Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Advanced Options',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    onExpansionChanged: (expanded) =>
                        setState(() => _showAdvanced = expanded),
                    initiallyExpanded: _showAdvanced,
                    childrenPadding: const EdgeInsets.only(top: 8),
                    children: [
                      // PMF
                      if (_selectedEncryption != 'none') ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedPmf,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText:
                                'Protected Management Frames (PMF / 802.11w)',
                            prefixIcon: Icon(
                              Icons.verified_user_rounded,
                              size: 20,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: '0',
                              child: Text('Disabled (Not recommended)'),
                            ),
                            DropdownMenuItem(
                              value: '1',
                              child: Text('Optional — recommended default'),
                            ),
                            DropdownMenuItem(
                              value: '2',
                              child: Text('Required (WPA3 / strict mode)'),
                            ),
                          ],
                          onChanged:
                              (_selectedEncryption == 'sae' ||
                                  _selectedEncryption == 'owe')
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setState(() => _selectedPmf = val);
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Hidden SSID
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Hidden SSID',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: const Text(
                          'Do not broadcast SSID in beacon frames',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _hidden,
                        onChanged: (val) => setState(() => _hidden = val),
                      ),

                      // Fast Roaming (802.11r/k/v)
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.directions_run_rounded,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Fast Roaming (802.11r/k/v)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Enable 802.11r Fast BSS Transition',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: const Text(
                          'Seamless roaming between access points',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _ieee80211r,
                        onChanged: (val) =>
                            setState(() => _ieee80211r = val ?? false),
                        dense: true,
                      ),
                      if (_ieee80211r) ...[
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'FT over DS',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: const Text(
                            'Fast transition over Distribution System',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: _ftOverDs,
                          onChanged: (val) =>
                              setState(() => _ftOverDs = val ?? false),
                          dense: true,
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'FT PSK Generate Local',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: const Text(
                            'Generate PSK locally per AP',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: _ftPskGenerateLocal,
                          onChanged: (val) => setState(
                            () => _ftPskGenerateLocal = val ?? false,
                          ),
                          dense: true,
                        ),
                        TextFormField(
                          controller: _mobilityDomainController,
                          decoration: const InputDecoration(
                            labelText: 'Mobility Domain',
                            hintText: '4 hex chars (e.g., a1b2)',
                            prefixIcon: Icon(
                              Icons.confirmation_number_rounded,
                              size: 20,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          maxLength: 4,
                        ),
                        const SizedBox(height: 12),
                      ],

                      // QoS & Wireless Advanced Controls
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'QoS & Wireless Controls',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'WMM / QoS',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: const Text(
                          'Enable Wi-Fi Multimedia quality-of-service',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _wmm,
                        onChanged: (val) => setState(() => _wmm = val ?? true),
                        dense: true,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Disassociate Low-ACK Clients',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: const Text(
                          'Kick weak clients with excessive packet loss',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _disassocLowAck,
                        onChanged: (val) =>
                            setState(() => _disassocLowAck = val ?? true),
                        dense: true,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Multicast to Unicast Conversion',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: const Text(
                          'Improves multicast video/audio streaming reliability',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _multicastToUnicast,
                        onChanged: (val) =>
                            setState(() => _multicastToUnicast = val ?? false),
                        dense: true,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'WDS (Wireless Distribution System)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: const Text(
                          'Transparent bridge mode for multi-AP meshing',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _wds,
                        onChanged: (val) => setState(() => _wds = val ?? false),
                        dense: true,
                      ),
                      const SizedBox(height: 12),

                      // MAC Filtering
                      Row(
                        children: [
                          Icon(
                            Icons.filter_alt_rounded,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'MAC Address Access Control',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _macfilter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'MAC Filter Mode',
                          prefixIcon: Icon(Icons.shield_outlined, size: 20),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'disable',
                            child: Text('Disabled — Allow All MACs'),
                          ),
                          DropdownMenuItem(
                            value: 'allow',
                            child: Text(
                              'Allow List — Only listed MACs can connect',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'deny',
                            child: Text('Deny List — Block listed MACs'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _macfilter = val);
                        },
                      ),
                      if (_macfilter != 'disable') ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _maclistController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'MAC Addresses List',
                            hintText: '00:11:22:33:44:55\nAA:BB:CC:DD:EE:FF',
                            border: OutlineInputBorder(),
                            helperText:
                                'One MAC address per line or separated by spaces/commas',
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: (_isSubmitting || !hasUciWrite)
                ? null
                : _submitProvisionGuest,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add_moderator_rounded, size: 18),
            label: Text(_isSubmitting ? 'Creating…' : 'Create New Guest Wi-Fi'),
          ),
        ],
      ),
    );
  }
}
