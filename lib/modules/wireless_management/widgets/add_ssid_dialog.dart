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

/// Dialog for provisioning a new virtual SSID interface under a physical radio.
/// Applies smart defaults, hardware-capability-aware cipher lists, 802.11r Fast Roaming,
/// WMM QoS, interval controls, and MAC filtering options.
class AddSsidDialog extends ConsumerStatefulWidget {
  final List<WirelessRadio> radios;
  final WirelessRadio targetRadio;

  const AddSsidDialog({
    super.key,
    required this.radios,
    required this.targetRadio,
  });

  @override
  ConsumerState<AddSsidDialog> createState() => _AddSsidDialogState();
}

class _AddSsidDialogState extends ConsumerState<AddSsidDialog> {
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController();
  final _passphraseController = TextEditingController();

  // Advanced Option Controllers
  final _mobilityDomainController = TextEditingController(text: '4f4b');
  final _dtimPeriodController = TextEditingController(text: '2');
  final _gtkRekeyController = TextEditingController(text: '3600');
  final _inactivityLimitController = TextEditingController(text: '300');
  final _maxListenIntervalController = TextEditingController(text: '65535');
  final _maclistController = TextEditingController();

  late WirelessRadio _selectedRadio;

  // Core settings
  String _selectedEncryption = 'sae-mixed';
  String _selectedNetwork = 'lan';
  String _selectedCipher = 'auto';
  String _selectedPmf = '1';
  List<String> _availableNetworks = ['lan', 'guest', 'wan'];

  // Advanced toggles & roaming
  bool _isolateClients = false;
  bool _isHidden = false;
  bool _wmmEnabled = true;
  bool _disassocLowAck = true;
  bool _multicastToUnicast = false;
  bool _wds = false;

  // Fast Roaming (802.11r/k/v)
  bool _ieee80211r = false;
  bool _ftOverDs = false;
  bool _ftPskGenerateLocal = false;

  // MAC Filtering
  String _macfilter = 'disable';

  // UI state
  bool _isSubmitting = false;
  bool _isLoadingCapabilities = false;
  bool _showPassphrase = false;
  bool _showAdvanced = false;

  // Hardware capabilities cache
  List<Map<String, String>> _dynamicEncryptions = [];
  List<Map<String, String>> _dynamicCiphers = [];

  @override
  void initState() {
    super.initState();
    _selectedRadio = widget.targetRadio;
    _fetchAvailableNetworks();
    _fetchHardwareCapabilities();
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passphraseController.dispose();
    _mobilityDomainController.dispose();
    _dtimPeriodController.dispose();
    _gtkRekeyController.dispose();
    _inactivityLimitController.dispose();
    _maxListenIntervalController.dispose();
    _maclistController.dispose();
    super.dispose();
  }

  Future<void> _fetchAvailableNetworks() async {
    try {
      final appState = ref.read(appStateProvider);
      final networks = await appState.fetchNetworkInterfaces();
      if (mounted && networks.isNotEmpty) {
        setState(() {
          _availableNetworks = networks;
          if (!_availableNetworks.contains(_selectedNetwork)) {
            _selectedNetwork = _availableNetworks.first;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchHardwareCapabilities() async {
    if (!mounted) return;
    setState(() => _isLoadingCapabilities = true);
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
          _dynamicCiphers = caps['ciphers'] ?? [];
          _applySmartDefaults();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingCapabilities = false);
    }
  }

  void _applySmartDefaults() {
    if (_dynamicEncryptions.isEmpty) return;
    final supported = _dynamicEncryptions.map((e) => e['value']!).toList();
    for (final preferred in ['sae-mixed', 'psk2', 'psk', 'none']) {
      if (supported.contains(preferred)) {
        _selectedEncryption = preferred;
        break;
      }
    }
    _updateCipherForEncryption(_selectedEncryption);
  }

  void _updateCipherForEncryption(String enc) {
    if (enc == 'sae' || enc == 'sae-mixed') {
      _selectedCipher = 'ccmp';
      _selectedPmf = enc == 'sae' ? '2' : '1';
    } else if (enc == 'psk2') {
      _selectedCipher = 'ccmp';
      _selectedPmf = '1';
    } else if (enc == 'psk') {
      _selectedCipher = 'auto';
      _selectedPmf = '0';
    } else if (enc == 'owe') {
      _selectedCipher = 'ccmp';
      _selectedPmf = '2';
    } else {
      _selectedCipher = 'auto';
      _selectedPmf = '0';
    }
  }

  bool _requiresPassphrase() =>
      _selectedEncryption != 'none' && _selectedEncryption != 'owe';

  bool _isEncryptionSupported(String v) =>
      _dynamicEncryptions.isEmpty ||
      _dynamicEncryptions.any((e) => e['value'] == v);

  bool _isCipherSupported(String v) =>
      _dynamicCiphers.isEmpty || _dynamicCiphers.any((c) => c['value'] == v);

  int get _ssidByteLength => utf8.encode(_ssidController.text).length;

  String? _validatePassphrase(String? value) {
    if (!_requiresPassphrase()) return null;
    if (value == null || value.trim().isEmpty) return 'Passphrase is required';
    final t = value.trim();
    if (t.length < 8) return 'Passphrase must be at least 8 characters';
    if (t.length > 63) return 'Passphrase must not exceed 63 characters';
    return null;
  }

  bool _isFormValid() {
    if (_isSubmitting || _isLoadingCapabilities) return false;

    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) return false;
    if (utf8.encode(ssid).length > 32) return false;

    final isDuplicate = _selectedRadio.interfaces
        .where((i) => i.mode.toLowerCase() == 'ap')
        .any((i) => i.ssid.trim().toLowerCase() == ssid.toLowerCase());
    if (isDuplicate) return false;

    if (_requiresPassphrase()) {
      final pass = _passphraseController.text.trim();
      if (pass.isEmpty || pass.length < 8 || pass.length > 63) return false;
    }

    if (_ieee80211r) {
      final mob = _mobilityDomainController.text.trim();
      if (mob.isEmpty || mob.length > 4) return false;
    }

    if (_dtimPeriodController.text.trim().isNotEmpty) {
      final dtim = int.tryParse(_dtimPeriodController.text.trim());
      if (dtim == null || dtim < 1 || dtim > 255) return false;
    }

    if (_gtkRekeyController.text.trim().isNotEmpty) {
      final rekey = int.tryParse(_gtkRekeyController.text.trim());
      if (rekey == null || rekey < 0) return false;
    }

    if (_inactivityLimitController.text.trim().isNotEmpty) {
      final inact = int.tryParse(_inactivityLimitController.text.trim());
      if (inact == null || inact < 0) return false;
    }

    if (_maxListenIntervalController.text.trim().isNotEmpty) {
      final listen = int.tryParse(_maxListenIntervalController.text.trim());
      if (listen == null || listen < 0) return false;
    }

    return true;
  }

  Future<void> _submitAddSsid() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    final appState = ref.read(appStateProvider);

    final success = await appState.addWirelessInterface(
      radioName: _selectedRadio.name,
      ssid: _ssidController.text.trim(),
      encryption: _selectedEncryption,
      key: _requiresPassphrase() ? _passphraseController.text.trim() : '',
      network: _selectedNetwork,
      context: context,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        Navigator.pop(context, true);
        context.showToastSuccess(
          'New SSID "${_ssidController.text.trim()}" created successfully.',
        );
      } else {
        final username = appState.sessionUsername;
        if ((appState.capabilities?.hasUciWriteAccess ?? true) == false ||
            !appState.isAdministrativeUser) {
          context.showToastError(
            'Access Denied: Account \'$username\' lacks UCI write authorization.',
          );
        } else {
          context.showToastError(
            'Failed to create wireless interface on router',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final hasUciWrite =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;
    final needsPass = _requiresPassphrase();

    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Add Virtual SSID Interface',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── ACL Warning ──────────────────────────────────────────
                  if (!hasUciWrite)
                    _buildBanner(
                      color: Colors.red,
                      icon: Icons.lock_clock_outlined,
                      text:
                          'Non-root account \'${appState.sessionUsername}\'. Saving requires root/UCI write privileges.',
                    ),

                  // ── Safety notice ────────────────────────────────────────
                  _buildBanner(
                    color: Colors.amber,
                    icon: Icons.shield_outlined,
                    text:
                        'New wireless interface will be committed directly to the router.',
                  ),
                  const SizedBox(height: 16),

                  // ── Target Radio ─────────────────────────────────────────
                  DropdownButtonFormField<WirelessRadio>(
                    initialValue: _selectedRadio,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Target Physical Radio',
                      prefixIcon: Icon(Icons.cell_tower_rounded, size: 20),
                      border: OutlineInputBorder(),
                    ),
                    items: widget.radios
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(
                              '${r.name} (${r.bandLabel})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null && val != _selectedRadio) {
                        setState(() => _selectedRadio = val);
                        _fetchHardwareCapabilities();
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  // ── SSID Name ────────────────────────────────────────────
                  TextFormField(
                    controller: _ssidController,
                    decoration: InputDecoration(
                      labelText: 'SSID Name',
                      hintText: 'e.g. MyHome_IoT or Office_WiFi',
                      helperText: 'UTF-8 bytes: $_ssidByteLength / 32 max',
                      prefixIcon: const Icon(Icons.wifi_rounded, size: 20),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'SSID name cannot be empty';
                      }
                      if (utf8.encode(val.trim()).length > 32) {
                        return 'SSID exceeds 32 UTF-8 bytes';
                      }
                      final dup = _selectedRadio.interfaces
                          .where((i) => i.mode.toLowerCase() == 'ap')
                          .any(
                            (i) =>
                                i.ssid.trim().toLowerCase() ==
                                val.trim().toLowerCase(),
                          );
                      if (dup) {
                        return 'An SSID with this name already exists on ${_selectedRadio.name}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // ── Network Attachment ───────────────────────────────────
                  DropdownButtonFormField<String>(
                    initialValue: _availableNetworks.contains(_selectedNetwork)
                        ? _selectedNetwork
                        : _availableNetworks.first,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Network Attachment',
                      prefixIcon: Icon(Icons.lan_rounded, size: 20),
                      border: OutlineInputBorder(),
                      helperText:
                          'Choose which logical network this SSID bridges to',
                    ),
                    items: _availableNetworks
                        .map(
                          (net) => DropdownMenuItem(
                            value: net,
                            child: Text(net, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedNetwork = val;
                          if (val == 'guest') _isolateClients = true;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  // ── Security Protocol ────────────────────────────────────
                  DropdownButtonFormField<String>(
                    initialValue: _selectedEncryption,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Security Protocol',
                      prefixIcon: const Icon(Icons.security_rounded, size: 20),
                      border: const OutlineInputBorder(),
                      helperText: _isLoadingCapabilities
                          ? 'Loading hardware capabilities…'
                          : _dynamicEncryptions.isNotEmpty
                          ? 'Showing hardware-verified options'
                          : 'Using fallback options',
                      suffixIcon: _isLoadingCapabilities
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                    items: _buildEncryptionItems(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedEncryption = val;
                          _updateCipherForEncryption(val);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  // ── Cipher ──────────────────────────────────────────────
                  if (_selectedEncryption != 'none') ...[
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCipher,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Cipher / Encryption Algorithm',
                        prefixIcon: const Icon(Icons.memory_rounded, size: 20),
                        border: const OutlineInputBorder(),
                        helperText: _dynamicCiphers.isNotEmpty
                            ? 'Hardware-supported ciphers'
                            : 'Using fallback options',
                      ),
                      items: _buildCipherItems(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCipher = val);
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── Passphrase ───────────────────────────────────────────
                  if (needsPass) ...[
                    TextFormField(
                      controller: _passphraseController,
                      obscureText: !_showPassphrase,
                      decoration: InputDecoration(
                        labelText: 'Passphrase / Key',
                        hintText: '8–63 characters',
                        prefixIcon: const Icon(Icons.key_rounded, size: 20),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showPassphrase
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 18,
                          ),
                          onPressed: () => setState(
                            () => _showPassphrase = !_showPassphrase,
                          ),
                          tooltip: _showPassphrase
                              ? 'Hide passphrase'
                              : 'Show passphrase',
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: _validatePassphrase,
                    ),
                    PasswordStrengthMeter(password: _passphraseController.text),
                    const SizedBox(height: 14),
                  ],

                  // ── OWE notice ───────────────────────────────────────────
                  if (_selectedEncryption == 'owe')
                    _buildBanner(
                      color: Colors.blue,
                      icon: Icons.lock_open_rounded,
                      text:
                          'Enhanced Open (OWE) encrypts traffic without a password. No passphrase required.',
                    ),

                  // ── Client Isolation ─────────────────────────────────────
                  _buildSwitch(
                    title: 'Client Isolation',
                    subtitle:
                        'Prevents clients on this SSID from communicating with each other',
                    value: _isolateClients,
                    onChanged: (v) => setState(() => _isolateClients = v),
                  ),

                  // ── Advanced Section ─────────────────────────────────────
                  const SizedBox(height: 8),
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      initiallyExpanded: _showAdvanced,
                      onExpansionChanged: (v) =>
                          setState(() => _showAdvanced = v),
                      title: Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Advanced Options',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      childrenPadding: const EdgeInsets.only(top: 4),
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
                              helperText:
                                  'Management frame protection against deauth attacks',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '0',
                                child: Text(
                                  'Disabled (Not recommended)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: '1',
                                child: Text(
                                  'Optional — recommended default',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: '2',
                                child: Text(
                                  'Required (WPA3 / strict mode)',
                                  overflow: TextOverflow.ellipsis,
                                ),
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
                          const SizedBox(height: 14),
                        ],

                        // Hidden SSID
                        _buildSwitch(
                          title: 'Hidden SSID',
                          subtitle:
                              'Do not broadcast SSID name in beacon frames',
                          value: _isHidden,
                          onChanged: (v) => setState(() => _isHidden = v),
                        ),

                        // Fast Roaming (802.11r/k/v)
                        _buildSubHeader(
                          '802.11r Fast Roaming',
                          Icons.bolt_rounded,
                        ),
                        const SizedBox(height: 4),
                        _buildSwitch(
                          title: '802.11r Fast BSS Transition',
                          subtitle:
                              'Enables fast seamless handoff between access points',
                          value: _ieee80211r,
                          onChanged: (v) => setState(() => _ieee80211r = v),
                        ),
                        if (_ieee80211r) ...[
                          _buildSwitch(
                            title: 'FT over DS',
                            subtitle:
                                'Pre-authenticates over ethernet backbone',
                            value: _ftOverDs,
                            onChanged: (v) => setState(() => _ftOverDs = v),
                          ),
                          _buildSwitch(
                            title: 'Generate Local FT PSK Keys',
                            subtitle: 'Derives roaming keys locally per AP',
                            value: _ftPskGenerateLocal,
                            onChanged: (v) =>
                                setState(() => _ftPskGenerateLocal = v),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _mobilityDomainController,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Mobility Domain ID',
                              hintText: '4f4b',
                              prefixIcon: Icon(Icons.domain_rounded, size: 20),
                              border: OutlineInputBorder(),
                            ),
                            maxLength: 4,
                          ),
                          const SizedBox(height: 12),
                        ],

                        // WMM/QoS
                        _buildSubHeader(
                          'QoS & Connection Parameters',
                          Icons.speed_rounded,
                        ),
                        const SizedBox(height: 4),
                        _buildSwitch(
                          title: 'WMM / QoS',
                          subtitle:
                              'Wi-Fi Multimedia quality-of-service prioritization',
                          value: _wmmEnabled,
                          onChanged: (v) => setState(() => _wmmEnabled = v),
                        ),

                        // Disassoc Low ACK
                        _buildSwitch(
                          title: 'Disassociate Low-ACK Clients',
                          subtitle:
                              'Kick clients with excessive packet loss (improves airtime)',
                          value: _disassocLowAck,
                          onChanged: (v) => setState(() => _disassocLowAck = v),
                        ),

                        // Multicast to Unicast
                        _buildSwitch(
                          title: 'Multicast → Unicast Conversion',
                          subtitle:
                              'Converts multicast frames to unicast for better reliability',
                          value: _multicastToUnicast,
                          onChanged: (v) =>
                              setState(() => _multicastToUnicast = v),
                        ),

                        // WDS
                        _buildSwitch(
                          title: 'WDS (Wireless Distribution System)',
                          subtitle:
                              'Transparent L2 bridge for multi-AP mesh connections',
                          value: _wds,
                          onChanged: (v) => setState(() => _wds = v),
                        ),
                        const SizedBox(height: 12),

                        // Performance & Interval Controls
                        _buildSubHeader(
                          'Performance & Interval Controls',
                          Icons.timer_rounded,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _dtimPeriodController,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'DTIM Period',
                                  border: OutlineInputBorder(),
                                  helperText: '1-255 beacons',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _gtkRekeyController,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'GTK Rekey (s)',
                                  border: OutlineInputBorder(),
                                  helperText: 'Rekey interval',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _inactivityLimitController,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Inactivity Limit (s)',
                                  border: OutlineInputBorder(),
                                  helperText: 'Idle disconnect',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _maxListenIntervalController,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Max Listen Int.',
                                  border: OutlineInputBorder(),
                                  helperText: 'Power-save limit',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // MAC Address Access Control
                        _buildSubHeader(
                          'MAC Address Access Control',
                          Icons.filter_alt_rounded,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _macfilter,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'MAC Filter Mode',
                            prefixIcon: Icon(Icons.security_rounded, size: 20),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'disable',
                              child: Text('Disabled'),
                            ),
                            DropdownMenuItem(
                              value: 'allow',
                              child: Text('Allow List (only listed MACs)'),
                            ),
                            DropdownMenuItem(
                              value: 'deny',
                              child: Text('Deny List (block listed MACs)'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _macfilter = val);
                          },
                        ),
                        const SizedBox(height: 12),
                        if (_macfilter != 'disable') ...[
                          TextFormField(
                            controller: _maclistController,
                            maxLines: 3,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'MAC Address List',
                              hintText: 'AA:BB:CC:DD:EE:FF\n11:22:33:44:55:66',
                              prefixIcon: Icon(
                                Icons.list_alt_rounded,
                                size: 20,
                              ),
                              border: OutlineInputBorder(),
                              helperText:
                                  'One MAC per line or separated by space/comma',
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: _isFormValid() ? _submitAddSsid : null,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded, size: 18),
            label: Text(
              hasUciWrite ? 'Create New SSID' : 'Create New SSID (Non-Root)',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildBanner({
    required Color color,
    required IconData icon,
    required String text,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      value: value,
      onChanged: onChanged,
    );
  }

  List<DropdownMenuItem<String>> _buildEncryptionItems() {
    final static_ = [
      {'value': 'sae-mixed', 'label': 'WPA2/WPA3 Mixed — Recommended default'},
      {'value': 'sae', 'label': 'WPA3-SAE Personal — Strict / Max security'},
      {'value': 'psk2', 'label': 'WPA2-PSK (CCMP/AES) — Legacy compatible'},
      {'value': 'psk', 'label': 'WPA-PSK — Legacy only (WPA1)'},
      {'value': 'owe', 'label': 'Enhanced Open (OWE) — Encrypted, no password'},
      {'value': 'none', 'label': 'Open — No encryption (not recommended)'},
    ];
    final raw = _dynamicEncryptions.isNotEmpty ? _dynamicEncryptions : static_;
    final list = List<Map<String, String>>.from(raw);
    if (!list.any((e) => e['value'] == _selectedEncryption)) {
      list.add({
        'value': _selectedEncryption,
        'label': '${_selectedEncryption.toUpperCase()} (Current)',
      });
    }
    return list.map((opt) {
      final supported = _isEncryptionSupported(opt['value']!);
      return DropdownMenuItem<String>(
        value: opt['value'],
        enabled: supported,
        child: Text(
          '${opt['label'] ?? opt['value']}${!supported ? ' (Unsupported)' : ''}',
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
            color: supported ? null : Theme.of(context).disabledColor,
            fontSize: 13,
          ),
        ),
      );
    }).toList();
  }

  List<DropdownMenuItem<String>> _buildCipherItems() {
    final static_ = [
      {'value': 'auto', 'label': 'Auto — Hardware default'},
      {'value': 'ccmp', 'label': 'CCMP (AES) — Recommended'},
      {'value': 'gcmp256', 'label': 'GCMP-256 — High security (WPA3)'},
      {'value': 'gcmp128', 'label': 'GCMP-128'},
      {'value': 'tkip', 'label': 'TKIP — Legacy only (avoid)'},
    ];
    final raw = _dynamicCiphers.isNotEmpty ? _dynamicCiphers : static_;
    final list = List<Map<String, String>>.from(raw);
    if (!list.any((e) => e['value'] == _selectedCipher)) {
      list.add({
        'value': _selectedCipher,
        'label': '${_selectedCipher.toUpperCase()} (Current)',
      });
    }
    return list.map((opt) {
      final supported = _isCipherSupported(opt['value']!);
      return DropdownMenuItem<String>(
        value: opt['value'],
        enabled: supported,
        child: Text(
          '${opt['label'] ?? opt['value']}${!supported ? ' (Unsupported)' : ''}',
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
            color: supported ? null : Theme.of(context).disabledColor,
            fontSize: 13,
          ),
        ),
      );
    }).toList();
  }
}
