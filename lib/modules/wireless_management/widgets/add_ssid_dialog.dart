// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/password_strength_meter.dart';
import '../models/wireless_info.dart';

/// Guided dialog for fast, beginner-friendly provisioning of a new Wi-Fi network.
/// Essential settings are presented immediately with safe, capability-aware defaults.
/// Advanced settings are progressively disclosed under a collapsed section organized
/// into 4 distinct groups: Security & Privacy, Network Assignment, Fast Roaming & Performance,
/// and IP & DHCP Settings (with network-wide warning).
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

  // Subnet / DHCP Option Controllers
  final _dhcpStartController = TextEditingController(text: '100');
  final _dhcpLimitController = TextEditingController(text: '150');
  final _dhcpLeaseController = TextEditingController(text: '12h');
  final _dnsServersController = TextEditingController();
  String _ipv6Ra = 'server';
  String _dhcpv6Mode = 'server';
  bool _dhcpSettingsModified = false;

  late WirelessRadio _selectedRadio;

  // Core settings
  String _selectedEncryption = 'sae-mixed';
  String _selectedNetwork = 'lan';
  String _selectedCipher = 'auto';
  String _selectedPmf = '1';
  List<String> _availableNetworks = ['lan', 'guest', 'wan'];

  // Open network safety confirmation
  bool _confirmOpenNetwork = false;

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
  bool _ieee80211k = false;
  bool _ieee80211v = false;

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
    _loadSubnetDhcpDefaults();
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
    _dhcpStartController.dispose();
    _dhcpLimitController.dispose();
    _dhcpLeaseController.dispose();
    _dnsServersController.dispose();
    super.dispose();
  }

  void _loadSubnetDhcpDefaults() {
    try {
      final appState = ref.read(appStateProvider);
      final rawDhcp =
          appState.dashboardData?['uciDhcpConfig'] ??
          appState.dashboardData?['dhcp'];
      if (rawDhcp is Map) {
        final values = (rawDhcp['values'] is Map)
            ? rawDhcp['values'] as Map
            : rawDhcp;
        values.forEach((k, v) {
          if (v is Map &&
              v['.type'] == 'dhcp' &&
              (v['interface'] == _selectedNetwork || k == _selectedNetwork)) {
            if (v['start'] != null) {
              _dhcpStartController.text = v['start'].toString();
            }
            if (v['limit'] != null) {
              _dhcpLimitController.text = v['limit'].toString();
            }
            if (v['leasetime'] != null) {
              _dhcpLeaseController.text = v['leasetime'].toString();
            }
            if (v['ra'] != null) _ipv6Ra = v['ra'].toString();
            if (v['dhcpv6'] != null) _dhcpv6Mode = v['dhcpv6'].toString();
            if (v['dns'] != null) {
              final dnsVal = v['dns'];
              _dnsServersController.text = dnsVal is List
                  ? dnsVal.join(', ')
                  : dnsVal.toString();
            }
          }
        });
      }
    } catch (_) {}
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
        _loadSubnetDhcpDefaults();
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

    if (_selectedEncryption == 'none' && !_confirmOpenNetwork) {
      return false;
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

  String _getNetworkLabel(String net) {
    switch (net.toLowerCase()) {
      case 'lan':
        return 'Home Network (lan)';
      case 'guest':
        return 'Guest Network (guest)';
      case 'wan':
        return 'WAN (wan)';
      default:
        return '$net ($net)';
    }
  }

  String _getNetworkDescription(String net, AppLocalizations? l10n) {
    switch (net.toLowerCase()) {
      case 'lan':
        return l10n?.netHomeDesc ??
            'Home Network (lan) — Primary local network bridged with Ethernet ports';
      case 'guest':
        return l10n?.netGuestDesc ??
            'Guest Network (guest) — Isolated network for visitors';
      case 'wan':
        return l10n?.netWanDesc ?? 'WAN (wan) — Internet uplink interface';
      default:
        return 'Bridges this Wi-Fi network to the \'$net\' logical interface';
    }
  }

  String _getEncryptionLabel(String enc, AppLocalizations? l10n) {
    switch (enc) {
      case 'sae-mixed':
        return l10n?.wifiSecMixedRecommended ?? 'WPA2/WPA3 Mixed';
      case 'sae':
        return l10n?.wifiSecWpa3Strict ?? 'WPA3-SAE Personal';
      case 'psk2':
        return l10n?.wifiSecWpa2Legacy ?? 'WPA2-PSK (CCMP/AES)';
      case 'psk':
        return l10n?.wifiSecWpa1Legacy ?? 'WPA-PSK';
      case 'owe':
        return l10n?.wifiSecOwe ?? 'Enhanced Open (OWE)';
      case 'none':
        return l10n?.wifiSecNone ?? 'Open / None';
      default:
        return enc.toUpperCase();
    }
  }

  Future<void> _submitAddSsid() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    final appState = ref.read(appStateProvider);

    try {
      final extraOptions = <String, String>{
        'cipher': _selectedCipher,
        'ieee80211w': _selectedPmf,
        'isolate': _isolateClients ? '1' : '0',
        'hidden': _isHidden ? '1' : '0',
        'wmm': _wmmEnabled ? '1' : '0',
        'disassoc_low_ack': _disassocLowAck ? '1' : '0',
        'multicast_to_unicast': _multicastToUnicast ? '1' : '0',
        'wds': _wds ? '1' : '0',
        'ieee80211r': _ieee80211r ? '1' : '0',
      };

      if (_ieee80211r) {
        extraOptions['ft_over_ds'] = _ftOverDs ? '1' : '0';
        extraOptions['ft_psk_generate_local'] = _ftPskGenerateLocal ? '1' : '0';
        if (_mobilityDomainController.text.trim().isNotEmpty) {
          extraOptions['mobility_domain'] = _mobilityDomainController.text
              .trim()
              .toLowerCase();
        }
      }
      if (_ieee80211k) {
        extraOptions['ieee80211k'] = '1';
      }
      if (_ieee80211v) {
        extraOptions['ieee80211v'] = '1';
      }
      if (_dtimPeriodController.text.trim().isNotEmpty) {
        extraOptions['dtim_period'] = _dtimPeriodController.text.trim();
      }
      if (_gtkRekeyController.text.trim().isNotEmpty) {
        extraOptions['gtk_rekey'] = _gtkRekeyController.text.trim();
      }
      if (_inactivityLimitController.text.trim().isNotEmpty) {
        extraOptions['inactivity_limit'] = _inactivityLimitController.text
            .trim();
      }
      if (_maxListenIntervalController.text.trim().isNotEmpty) {
        extraOptions['max_listen_interval'] = _maxListenIntervalController.text
            .trim();
      }
      if (_macfilter != 'disable') {
        extraOptions['macfilter'] = _macfilter;
        if (_maclistController.text.trim().isNotEmpty) {
          final macs = _maclistController.text
              .split(RegExp(r'[\n,;]+'))
              .map((e) => e.trim().toUpperCase())
              .where((e) => e.isNotEmpty)
              .join(' ');
          extraOptions['maclist'] = macs;
        }
      }

      final success = await appState.addWirelessInterface(
        radioName: _selectedRadio.name,
        ssid: _ssidController.text.trim(),
        encryption: _selectedEncryption,
        key: _requiresPassphrase() ? _passphraseController.text.trim() : '',
        network: _selectedNetwork,
        extraOptions: extraOptions,
        context: mounted ? context : null,
      );

      bool dhcpSuccess = true;
      if (success && _dhcpSettingsModified) {
        final dhcpValues = <String, dynamic>{
          'start': _dhcpStartController.text.trim(),
          'limit': _dhcpLimitController.text.trim(),
          'leasetime': _dhcpLeaseController.text.trim(),
          'ra': _ipv6Ra,
          'dhcpv6': _dhcpv6Mode,
        };
        if (_dnsServersController.text.trim().isNotEmpty) {
          dhcpValues['dns'] = _dnsServersController.text
              .split(RegExp(r'[\s,]+'))
              .where((s) => s.isNotEmpty)
              .toList();
        }
        dhcpSuccess = await appState.updateInterfaceDhcpConfig(
          interface: _selectedNetwork,
          values: dhcpValues,
          context: mounted ? context : null,
        );
      }

      if (mounted) {
        if (success && dhcpSuccess) {
          Navigator.pop(context, true);
          context.showToastSuccess(
            'New SSID "${_ssidController.text.trim()}" created successfully.',
          );
        } else if (success && !dhcpSuccess) {
          Navigator.pop(context, true);
          context.showToastWarning(
            'New SSID "${_ssidController.text.trim()}" created, but subnet DHCP configuration could not be applied.',
            subtitle:
                'You can review or reapply DHCP settings via Edit SSID or Network settings.',
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
    } catch (e) {
      if (mounted) {
        context.showToastError(
          'Failed to create wireless interface',
          subtitle: LuciToastManager.parseErrorReason(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final hasUciWrite =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;
    final needsPass = _requiresPassphrase();

    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n?.tooltipAddVirtualSsid ?? 'Add Virtual SSID Interface',
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
                        'New wireless network will be committed directly to router configuration.',
                  ),
                  const SizedBox(height: 14),

                  // ── QUICK SETUP: Essential inputs ────────────────────────

                  // 1. Target Radio
                  if (widget.radios.length > 1) ...[
                    DropdownButtonFormField<WirelessRadio>(
                      initialValue: _selectedRadio,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(16),
                      dropdownColor: theme.colorScheme.surfaceContainerHigh,
                      elevation: 4,
                      menuMaxHeight: 360,
                      icon: const Icon(Icons.arrow_drop_down_rounded),
                      decoration: InputDecoration(
                        labelText: 'Target Physical Radio',
                        prefixIcon: const Icon(
                          Icons.cell_tower_rounded,
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                  ],

                  // 2. SSID Name
                  TextFormField(
                    controller: _ssidController,
                    decoration: InputDecoration(
                      labelText: l10n?.ssidNameLabel ?? 'SSID Name',
                      hintText: 'e.g. MyHome_WiFi or Guest_Network',
                      helperText: '$_ssidByteLength / 32 UTF-8 bytes',
                      helperStyle: TextStyle(
                        color: _ssidByteLength > 32 ? Colors.red : null,
                        fontWeight: _ssidByteLength > 32
                            ? FontWeight.bold
                            : null,
                      ),
                      prefixIcon: const Icon(Icons.wifi_rounded, size: 20),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return l10n?.ssidErrorEmpty ??
                            'SSID name cannot be empty';
                      }
                      if (utf8.encode(val.trim()).length > 32) {
                        return l10n?.ssidErrorExceedsBytes(
                              utf8.encode(val.trim()).length,
                            ) ??
                            'SSID exceeds 32 UTF-8 bytes';
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

                  // 3. Network Attachment
                  DropdownButtonFormField<String>(
                    initialValue: _availableNetworks.contains(_selectedNetwork)
                        ? _selectedNetwork
                        : _availableNetworks.first,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(16),
                    dropdownColor: theme.colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    menuMaxHeight: 360,
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    decoration: InputDecoration(
                      labelText:
                          l10n?.wifiDetailNetworkBridge ?? 'Network Attachment',
                      prefixIcon: const Icon(Icons.lan_rounded, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      helperText: _getNetworkDescription(
                        _selectedNetwork,
                        l10n,
                      ),
                      helperMaxLines: 2,
                    ),
                    items: _availableNetworks
                        .map(
                          (net) => DropdownMenuItem(
                            value: net,
                            child: Text(
                              _getNetworkLabel(net),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedNetwork = val;
                          if (val == 'guest') _isolateClients = true;
                        });
                        _loadSubnetDhcpDefaults();
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  // 4. Security Protocol
                  DropdownButtonFormField<String>(
                    initialValue: _selectedEncryption,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(16),
                    dropdownColor: theme.colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    menuMaxHeight: 360,
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    decoration: InputDecoration(
                      labelText:
                          l10n?.encryptionSecurityModeLabel ??
                          'Security Protocol',
                      prefixIcon: const Icon(Icons.security_rounded, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      helperText: _isLoadingCapabilities
                          ? 'Loading hardware capabilities…'
                          : _dynamicEncryptions.isNotEmpty
                          ? 'Showing hardware-verified options'
                          : 'Standard compatibility defaults',
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
                          _confirmOpenNetwork = false;
                          _updateCipherForEncryption(val);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  // 5. Passphrase
                  if (needsPass) ...[
                    TextFormField(
                      controller: _passphraseController,
                      obscureText: !_showPassphrase,
                      decoration: InputDecoration(
                        labelText:
                            l10n?.passphraseKeyLabel ?? 'Passphrase / Key',
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

                  // 6. Open Network Warning & Explicit Confirmation Checkbox
                  if (_selectedEncryption == 'none') ...[
                    _buildBanner(
                      color: Colors.amber,
                      icon: Icons.warning_amber_rounded,
                      text:
                          l10n?.openNetworkWarningBody ??
                          'An open Wi-Fi network transmits data without encryption. Anyone within range can connect and monitor unencrypted traffic.',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _confirmOpenNetwork,
                      onChanged: (v) =>
                          setState(() => _confirmOpenNetwork = v ?? false),
                      title: Text(
                        l10n?.openNetworkConfirmCheckbox ??
                            'I understand this network will be public and unencrypted',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 10),
                  ],

                  // 7. OWE Notice
                  if (_selectedEncryption == 'owe') ...[
                    _buildBanner(
                      color: Colors.blue,
                      icon: Icons.lock_open_rounded,
                      text:
                          'Enhanced Open (OWE) encrypts wireless frames without a shared password. Supported client devices connect securely automatically.',
                    ),
                    const SizedBox(height: 10),
                  ],

                  // 8. Setup Summary Card
                  _buildSetupSummaryCard(l10n, theme),
                  const SizedBox(height: 12),

                  // ── PROGRESSIVE DISCLOSURE: Advanced Settings ─────────────
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
                              l10n?.advancedSettingsTitle ??
                                  'Advanced Settings',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      childrenPadding: const EdgeInsets.only(top: 8),
                      children: [
                        // ── Group 1: Security & Privacy ───────────────────
                        _buildGroupHeader(
                          l10n?.secGroupSecurityPrivacy ?? 'Security & Privacy',
                          Icons.shield_rounded,
                        ),
                        const SizedBox(height: 6),

                        _buildSwitch(
                          title:
                              l10n?.isolateWirelessClientsLabel ??
                              l10n?.wifiDetailClientIsolation ??
                              'Client Isolation',
                          subtitle:
                              l10n?.wifiClientIsolationSubtitle ??
                              l10n?.isolateWirelessClientsSubtitle ??
                              'Prevents connected Wi-Fi stations from directly communicating with each other',
                          value: _isolateClients,
                          onChanged: (v) => setState(() => _isolateClients = v),
                        ),

                        if (_selectedEncryption != 'none') ...[
                          DropdownButtonFormField<String>(
                            initialValue: _selectedPmf,
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(16),
                            dropdownColor:
                                theme.colorScheme.surfaceContainerHigh,
                            elevation: 4,
                            menuMaxHeight: 360,
                            icon: const Icon(Icons.arrow_drop_down_rounded),
                            decoration: InputDecoration(
                              labelText:
                                  l10n?.pmfLabel ??
                                  'Protected Management Frames (PMF / 802.11w)',
                              prefixIcon: const Icon(
                                Icons.verified_user_rounded,
                                size: 20,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              helperText:
                                  l10n?.wifiPmfHelperText ??
                                  'Protection against deauthentication attacks',
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '0',
                                child: Text(
                                  l10n?.wifiPmfDisabled ??
                                      'Disabled (Not recommended)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: '1',
                                child: Text(
                                  l10n?.wifiPmfOptional ??
                                      'Optional — recommended default',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: '2',
                                child: Text(
                                  l10n?.wifiPmfRequired ??
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
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCipher,
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(16),
                            dropdownColor:
                                theme.colorScheme.surfaceContainerHigh,
                            elevation: 4,
                            menuMaxHeight: 360,
                            icon: const Icon(Icons.arrow_drop_down_rounded),
                            decoration: InputDecoration(
                              labelText:
                                  l10n?.cipherAlgorithmLabel ??
                                  'Cipher / Encryption Algorithm',
                              prefixIcon: const Icon(
                                Icons.memory_rounded,
                                size: 20,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              helperText: _dynamicCiphers.isNotEmpty
                                  ? (l10n?.wifiCipherHwSupported ??
                                        'Hardware-supported ciphers')
                                  : (l10n?.wifiCipherAutoSelection ??
                                        'Auto hardware selection'),
                            ),
                            items: _buildCipherItems(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedCipher = val);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                        ],

                        _buildSwitch(
                          title: l10n?.hideBroadcastSsidLabel ?? 'Hidden SSID',
                          subtitle:
                              l10n?.hideBroadcastSsidSubtitle ??
                              'Do not broadcast SSID name in periodic 802.11 beacon frames',
                          value: _isHidden,
                          onChanged: (v) => setState(() => _isHidden = v),
                        ),

                        DropdownButtonFormField<String>(
                          initialValue: _macfilter,
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(16),
                          dropdownColor: theme.colorScheme.surfaceContainerHigh,
                          elevation: 4,
                          menuMaxHeight: 360,
                          icon: const Icon(Icons.arrow_drop_down_rounded),
                          decoration: InputDecoration(
                            labelText:
                                l10n?.macFilterModeLabel ?? 'MAC Filter Mode',
                            prefixIcon: const Icon(
                              Icons.filter_alt_rounded,
                              size: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'disable',
                              child: Text(
                                l10n?.wifiMacFilterDisabled ?? 'Disabled',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'allow',
                              child: Text(
                                l10n?.wifiMacFilterAllowList ??
                                    'Allow List (only listed MACs)',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'deny',
                              child: Text(
                                l10n?.wifiMacFilterDenyListAlt ??
                                    'Deny List (block listed MACs)',
                              ),
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
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText:
                                  l10n?.macListLabel ?? 'MAC Address List',
                              hintText: 'AA:BB:CC:DD:EE:FF\n11:22:33:44:55:66',
                              prefixIcon: const Icon(
                                Icons.list_alt_rounded,
                                size: 20,
                              ),
                              border: const OutlineInputBorder(),
                              helperText:
                                  l10n?.macListHelperText ??
                                  'One MAC per line or separated by comma/space',
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // ── Group 2: Network Assignment ───────────────────
                        _buildGroupHeader(
                          l10n?.secGroupNetworkAssignment ??
                              'Network Assignment',
                          Icons.alt_route_rounded,
                        ),
                        const SizedBox(height: 6),
                        _buildSwitch(
                          title:
                              l10n?.multicastToUnicastLabel ??
                              'Multicast → Unicast Conversion',
                          subtitle:
                              l10n?.multicastToUnicastSubtitle ??
                              'Converts multicast frames to unicast on air interface for reliability',
                          value: _multicastToUnicast,
                          onChanged: (v) =>
                              setState(() => _multicastToUnicast = v),
                        ),
                        _buildSwitch(
                          title:
                              l10n?.wdsLabel ??
                              'WDS (Wireless Distribution System)',
                          subtitle:
                              l10n?.wdsSubtitle ??
                              'Transparent L2 bridge for multi-AP wireless mesh connections',
                          value: _wds,
                          onChanged: (v) => setState(() => _wds = v),
                        ),
                        const SizedBox(height: 16),

                        // ── Group 3: Fast Roaming & Performance ───────────
                        _buildGroupHeader(
                          l10n?.secGroupFastRoaming ??
                              'Fast Roaming & Performance',
                          Icons.bolt_rounded,
                        ),
                        const SizedBox(height: 6),
                        _buildSwitch(
                          title:
                              l10n?.fastBssTransitionLabel ??
                              '802.11r Fast BSS Transition',
                          subtitle:
                              l10n?.fastBssTransitionSubtitle ??
                              'Enables seamless client handoff between access points',
                          value: _ieee80211r,
                          onChanged: (v) => setState(() => _ieee80211r = v),
                        ),
                        if (_ieee80211r) ...[
                          _buildSwitch(
                            title: l10n?.ftOverDsLabel ?? 'FT over DS',
                            subtitle:
                                l10n?.ftOverDsSubtitle ??
                                'Pre-authenticates over Ethernet backbone',
                            value: _ftOverDs,
                            onChanged: (v) => setState(() => _ftOverDs = v),
                          ),
                          _buildSwitch(
                            title:
                                l10n?.ftGeneratePskLocalLabel ??
                                'Generate Local FT PSK Keys',
                            subtitle:
                                l10n?.ftGeneratePskLocalSubtitle ??
                                'Derives roaming keys locally per AP',
                            value: _ftPskGenerateLocal,
                            onChanged: (v) =>
                                setState(() => _ftPskGenerateLocal = v),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _mobilityDomainController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText:
                                  l10n?.mobilityDomainLabel ??
                                  'Mobility Domain ID',
                              hintText: '4f4b',
                              prefixIcon: const Icon(
                                Icons.domain_rounded,
                                size: 20,
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            maxLength: 4,
                          ),
                          const SizedBox(height: 8),
                        ],
                        _buildSwitch(
                          title:
                              l10n?.fastTransition80211kLabel ??
                              '802.11k Radio Resource Management',
                          subtitle:
                              l10n?.fastTransition80211kSubtitle ??
                              'Provides radio measurement reports to accelerate AP roaming decisions',
                          value: _ieee80211k,
                          onChanged: (v) => setState(() => _ieee80211k = v),
                        ),
                        _buildSwitch(
                          title:
                              l10n?.fastTransition80211vLabel ??
                              '802.11v BSS Transition Management',
                          subtitle:
                              l10n?.fastTransition80211vSubtitle ??
                              'Allows AP to guide stations to transition to optimal radios',
                          value: _ieee80211v,
                          onChanged: (v) => setState(() => _ieee80211v = v),
                        ),
                        _buildSwitch(
                          title:
                              l10n?.wmmQosLabel ?? 'WMM / QoS Prioritization',
                          subtitle:
                              l10n?.wmmQosSubtitle ??
                              'Wi-Fi Multimedia quality-of-service traffic prioritization',
                          value: _wmmEnabled,
                          onChanged: (v) => setState(() => _wmmEnabled = v),
                        ),
                        _buildSwitch(
                          title:
                              l10n?.disassocLowAckLabel ??
                              'Disassociate Low-ACK Clients',
                          subtitle:
                              l10n?.disassocLowAckSubtitle ??
                              'Disassociates clients with excessive packet loss to conserve airtime',
                          value: _disassocLowAck,
                          onChanged: (v) => setState(() => _disassocLowAck = v),
                        ),
                        const SizedBox(height: 10),
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
                            const SizedBox(width: 10),
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
                        const SizedBox(height: 10),
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
                            const SizedBox(width: 10),
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
                        const SizedBox(height: 16),

                        // ── Group 4: IP & DHCP Settings ───────────────────
                        _buildGroupHeader(
                          l10n?.secGroupIpDhcp ?? 'IP & DHCP Settings',
                          Icons.settings_ethernet_rounded,
                        ),
                        const SizedBox(height: 6),

                        // MANDATORY NETWORK-WIDE WARNING
                        _buildBanner(
                          color: Colors.amber,
                          icon: Icons.warning_amber_rounded,
                          text:
                              l10n?.networkWideWarning(_selectedNetwork) ??
                              'These settings apply to all devices connected to the $_selectedNetwork network, not only this Wi-Fi network.',
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _dhcpStartController,
                                onChanged: (_) => setState(
                                  () => _dhcpSettingsModified = true,
                                ),
                                decoration: InputDecoration(
                                  labelText:
                                      l10n?.dhcpPoolStartLabel ??
                                      'DHCP Pool Start',
                                  border: const OutlineInputBorder(),
                                  helperText: 'e.g. 100',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _dhcpLimitController,
                                onChanged: (_) => setState(
                                  () => _dhcpSettingsModified = true,
                                ),
                                decoration: InputDecoration(
                                  labelText:
                                      l10n?.dhcpPoolLimitLabel ??
                                      'DHCP Pool Limit',
                                  border: const OutlineInputBorder(),
                                  helperText: 'e.g. 150',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _dhcpLeaseController,
                                onChanged: (_) => setState(
                                  () => _dhcpSettingsModified = true,
                                ),
                                decoration: InputDecoration(
                                  labelText:
                                      l10n?.dhcpLeaseDurationLabel ??
                                      'DHCP Lease Duration',
                                  border: const OutlineInputBorder(),
                                  helperText: 'e.g. 12h or 86400',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _dnsServersController,
                                onChanged: (_) => setState(
                                  () => _dhcpSettingsModified = true,
                                ),
                                decoration: InputDecoration(
                                  labelText:
                                      l10n?.dnsServersLabel ??
                                      'Custom DNS Servers',
                                  border: const OutlineInputBorder(),
                                  helperText: 'e.g. 1.1.1.1, 8.8.8.8',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _ipv6Ra,
                                isExpanded: true,
                                borderRadius: BorderRadius.circular(16),
                                dropdownColor:
                                    theme.colorScheme.surfaceContainerHigh,
                                elevation: 4,
                                menuMaxHeight: 360,
                                icon: const Icon(Icons.arrow_drop_down_rounded),
                                decoration: InputDecoration(
                                  labelText: l10n?.ipv6RaLabel ?? 'IPv6 RA',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'server',
                                    child: Text('Server'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'relay',
                                    child: Text('Relay'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'disabled',
                                    child: Text('Disabled'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() {
                                      _ipv6Ra = v;
                                      _dhcpSettingsModified = true;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _dhcpv6Mode,
                                isExpanded: true,
                                borderRadius: BorderRadius.circular(16),
                                dropdownColor:
                                    theme.colorScheme.surfaceContainerHigh,
                                elevation: 4,
                                menuMaxHeight: 360,
                                icon: const Icon(Icons.arrow_drop_down_rounded),
                                decoration: InputDecoration(
                                  labelText: l10n?.dhcpv6ModeLabel ?? 'DHCPv6',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'server',
                                    child: Text('Server'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'relay',
                                    child: Text('Relay'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'disabled',
                                    child: Text('Disabled'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() {
                                      _dhcpv6Mode = v;
                                      _dhcpSettingsModified = true;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
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
            child: Text(l10n?.actionCancel ?? 'Cancel'),
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
              hasUciWrite
                  ? (l10n?.createWifiNetwork ?? 'Create Wi-Fi Network')
                  : (l10n?.createWifiNetworkNonRoot ??
                        'Create Wi-Fi Network (Non-Root)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupSummaryCard(AppLocalizations? l10n, ThemeData theme) {
    final ssidText = _ssidController.text.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                l10n?.setupSummaryTitle ?? 'Setup Summary',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  icon: Icons.wifi,
                  label: l10n?.setupSummarySsid ?? 'SSID',
                  value: ssidText.isEmpty ? '—' : ssidText,
                  theme: theme,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  icon: Icons.cell_tower,
                  label: l10n?.setupSummaryRadio ?? 'Radio',
                  value: '${_selectedRadio.name} (${_selectedRadio.bandLabel})',
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  icon: Icons.lock_outline,
                  label: l10n?.setupSummarySecurity ?? 'Security',
                  value: _getEncryptionLabel(_selectedEncryption, l10n),
                  theme: theme,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  icon: Icons.lan_outlined,
                  label: l10n?.setupSummaryNetwork ?? 'Network',
                  value: _getNetworkLabel(_selectedNetwork),
                  theme: theme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Expanded(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
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
    final l10n = AppLocalizations.of(context);
    final static_ = [
      {
        'value': 'sae-mixed',
        'label':
            l10n?.wifiSecMixedRecommended ??
            'WPA2/WPA3 Mixed — Recommended default',
      },
      {
        'value': 'sae',
        'label':
            l10n?.wifiSecWpa3Strict ??
            'WPA3-SAE Personal — Strict / Max security',
      },
      {
        'value': 'psk2',
        'label':
            l10n?.wifiSecWpa2Legacy ??
            'WPA2-PSK (CCMP/AES) — Legacy compatible',
      },
      {
        'value': 'psk',
        'label': l10n?.wifiSecWpa1Legacy ?? 'WPA-PSK — Legacy only (WPA1)',
      },
      {
        'value': 'owe',
        'label':
            l10n?.wifiSecOwe ?? 'Enhanced Open (OWE) — Encrypted, no password',
      },
      {
        'value': 'none',
        'label': l10n?.wifiSecNone ?? 'Open — No encryption (not recommended)',
      },
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
    final l10n = AppLocalizations.of(context);
    final static_ = [
      {
        'value': 'auto',
        'label': l10n?.wifiCipherAuto ?? 'Auto — Hardware default',
      },
      {
        'value': 'ccmp',
        'label': l10n?.wifiCipherCcmp ?? 'CCMP (AES) — Recommended',
      },
      {
        'value': 'gcmp256',
        'label': l10n?.wifiCipherGcmp256 ?? 'GCMP-256 — High security (WPA3)',
      },
      {'value': 'gcmp128', 'label': 'GCMP-128'},
      {
        'value': 'tkip',
        'label': l10n?.wifiCipherTkip ?? 'TKIP — Legacy only (avoid)',
      },
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
