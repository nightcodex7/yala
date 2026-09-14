// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import 'package:yet_another_luci_app/widgets/password_strength_meter.dart';
import '../models/wireless_info.dart';

/// Dialog providing live-validated editable security & advanced wireless settings on existing SSIDs
/// with prefetch support, 802.11r Fast Roaming, WMM, intervals, and MAC filtering.
class EditSsidDialog extends ConsumerStatefulWidget {
  final WirelessRadio radio;
  final WirelessInterface interface;

  const EditSsidDialog({
    super.key,
    required this.radio,
    required this.interface,
  });

  @override
  ConsumerState<EditSsidDialog> createState() => _EditSsidDialogState();
}

class _EditSsidDialogState extends ConsumerState<EditSsidDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _ssidController;
  late TextEditingController _passphraseController;

  // Controllers for Advanced Settings
  late TextEditingController _mobilityDomainController;
  late TextEditingController _dtimPeriodController;
  late TextEditingController _gtkRekeyController;
  late TextEditingController _inactivityLimitController;
  late TextEditingController _maxListenIntervalController;
  late TextEditingController _maclistController;

  late String _initialPassphrase;
  late String _selectedEncryption;
  late String _selectedCipher;
  late String _selectedPmf;
  late bool _isolateClients;
  late bool _isHidden;

  // Network Attachment & Bridge
  String _selectedNetwork = 'lan';
  List<String> _availableNetworks = ['lan', 'guest', 'wan'];

  // Fast Roaming (802.11r/k/v)
  bool _ieee80211r = false;
  bool _ftOverDs = false;
  bool _ftPskGenerateLocal = false;

  // Wireless Advanced Toggles
  bool _wmmEnabled = true;
  bool _disassocLowAck = true;
  bool _multicastToUnicast = false;
  bool _wds = false;

  // MAC Address Access Control
  String _macfilter = 'disable';

  List<Map<String, String>> _dynamicEncryptions = [];
  List<Map<String, String>> _dynamicCiphers = [];

  bool _showPassphrase = false;
  bool _isSubmitting = false;
  bool _isPrefetching = false;
  bool _showAdvanced = false;

  /// Whether the selected encryption is 'none' (open) or 'owe' (Enhanced Open - no passphrase needed)
  bool get isNone =>
      _selectedEncryption == 'none' || _selectedEncryption == 'owe';

  @override
  void initState() {
    super.initState();
    final iface = widget.interface;
    _ssidController = TextEditingController(text: iface.ssid);
    _initialPassphrase = iface.key ?? '';
    _passphraseController = TextEditingController(text: _initialPassphrase);

    _mobilityDomainController = TextEditingController(
      text: iface.mobilityDomain ?? '4f4b',
    );
    _dtimPeriodController = TextEditingController(text: '2');
    _gtkRekeyController = TextEditingController(text: '3600');
    _inactivityLimitController = TextEditingController(text: '300');
    _maxListenIntervalController = TextEditingController(text: '65535');
    _maclistController = TextEditingController();

    _selectedEncryption = _mapEncryptionToUci(
      iface.securityMode,
      iface.encryption,
    );
    _selectedCipher = _sanitizeCipher(iface.cipher);
    _selectedPmf = iface.pmfState == PmfState.required
        ? '2'
        : (iface.pmfState == PmfState.optional ? '1' : '0');
    _isolateClients = iface.isolateClients;
    _isHidden = iface.isHidden;
    _ieee80211r = iface.fastTransitionEnabled;
    _selectedNetwork = iface.networkBridge ?? 'lan';

    if (_selectedEncryption == 'sae') {
      _selectedPmf = '2';
    } else if (_selectedEncryption == 'none') {
      _selectedPmf = '0';
    }

    _captureBaseline();
    _fetchAvailableNetworks();
    _prefetchLiveUciConfig();
  }

  Map<String, dynamic> _initialBaseline = {};

  void _captureBaseline() {
    _initialBaseline = {
      'ssid': _ssidController.text.trim(),
      'passphrase': _passphraseController.text,
      'encryption': _selectedEncryption,
      'cipher': _selectedCipher,
      'pmf': _selectedPmf,
      'isolate': _isolateClients,
      'hidden': _isHidden,
      'network': _selectedNetwork,
      'ieee80211r': _ieee80211r,
      'ftOverDs': _ftOverDs,
      'ftPskGenerateLocal': _ftPskGenerateLocal,
      'mobilityDomain': _mobilityDomainController.text.trim(),
      'wmm': _wmmEnabled,
      'disassocLowAck': _disassocLowAck,
      'multicastToUnicast': _multicastToUnicast,
      'wds': _wds,
      'dtimPeriod': _dtimPeriodController.text.trim(),
      'gtkRekey': _gtkRekeyController.text.trim(),
      'inactivityLimit': _inactivityLimitController.text.trim(),
      'maxListenInterval': _maxListenIntervalController.text.trim(),
      'macfilter': _macfilter,
      'maclist': _maclistController.text.trim(),
    };
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

  /// Live-prefetches section configuration directly from router UCI to ensure full accuracy
  Future<void> _prefetchLiveUciConfig() async {
    final appState = ref.read(appStateProvider);
    final sectionName = widget.interface.sectionName;

    setState(() => _isPrefetching = true);
    try {
      final values = await appState.fetchWirelessSectionConfig(sectionName);
      final caps = await appState.fetchWirelessHardwareCapabilities(
        sectionName: sectionName,
        radioName: widget.interface.rawConfig['device']?.toString(),
      );

      if (mounted) {
        _dynamicEncryptions = caps['encryptions'] ?? [];
        _dynamicCiphers = caps['ciphers'] ?? [];

        if (values != null) {
          final liveKey =
              values['key']?.toString() ??
              values['passphrase']?.toString() ??
              values['sae_password']?.toString() ??
              values['psk']?.toString();
          final liveSsid = values['ssid']?.toString();
          final liveCipher = values['cipher']?.toString();
          final liveEnc = values['encryption']?.toString();
          final livePmf = values['ieee80211w']?.toString();
          final liveNetwork = values['network']?.toString();

          // Advanced prefetched fields
          final liveFt = values['ieee80211r']?.toString();
          final liveFtDs = values['ft_over_ds']?.toString();
          final liveFtLocal = values['ft_psk_generate_local']?.toString();
          final liveMobility = values['mobility_domain']?.toString();
          final liveWmm = values['wmm']?.toString();
          final liveLowAck = values['disassoc_low_ack']?.toString();
          final liveMcast2Ucast = values['multicast_to_unicast']?.toString();
          final liveWds = values['wds']?.toString();
          final liveDtim = values['dtim_period']?.toString();
          final liveRekey = values['gtk_rekey']?.toString();
          final liveInactivity = values['inactivity_limit']?.toString();
          final liveMaxListen = values['max_listen_interval']?.toString();
          final liveMacFilter = values['macfilter']?.toString();
          final liveMacList = values['maclist'];

          setState(() {
            if (liveKey != null && liveKey.isNotEmpty) {
              if (_passphraseController.text.isEmpty ||
                  _passphraseController.text == _initialPassphrase) {
                _passphraseController.text = liveKey;
                _initialPassphrase = liveKey;
              }
            }
            if (liveSsid != null &&
                liveSsid.isNotEmpty &&
                _ssidController.text == widget.interface.ssid) {
              _ssidController.text = liveSsid;
            }
            if (liveCipher != null && liveCipher.isNotEmpty) {
              _selectedCipher = _sanitizeCipher(liveCipher);
            }
            if (liveEnc != null && liveEnc.isNotEmpty) {
              _selectedEncryption = _mapRawEncryptionStringToUci(liveEnc);
            }
            if (livePmf != null && livePmf.isNotEmpty) {
              if (livePmf == '2' || livePmf == '1' || livePmf == '0') {
                _selectedPmf = livePmf;
              }
            }
            if (liveNetwork != null && liveNetwork.isNotEmpty) {
              if (_availableNetworks.contains(liveNetwork)) {
                _selectedNetwork = liveNetwork;
              }
            }
            if (liveFt != null) _ieee80211r = liveFt == '1';
            if (liveFtDs != null) _ftOverDs = liveFtDs == '1';
            if (liveFtLocal != null) _ftPskGenerateLocal = liveFtLocal == '1';
            if (liveMobility != null && liveMobility.isNotEmpty) {
              _mobilityDomainController.text = liveMobility;
            }
            if (liveWmm != null) _wmmEnabled = liveWmm == '1';
            if (liveLowAck != null) _disassocLowAck = liveLowAck == '1';
            if (liveMcast2Ucast != null) {
              _multicastToUnicast = liveMcast2Ucast == '1';
            }
            if (liveWds != null) _wds = liveWds == '1';
            if (liveDtim != null && liveDtim.isNotEmpty) {
              _dtimPeriodController.text = liveDtim;
            }
            if (liveRekey != null && liveRekey.isNotEmpty) {
              _gtkRekeyController.text = liveRekey;
            }
            if (liveInactivity != null && liveInactivity.isNotEmpty) {
              _inactivityLimitController.text = liveInactivity;
            }
            if (liveMaxListen != null && liveMaxListen.isNotEmpty) {
              _maxListenIntervalController.text = liveMaxListen;
            }
            if (liveMacFilter != null &&
                liveMacFilter.isNotEmpty &&
                liveMacFilter != 'none') {
              _macfilter = liveMacFilter;
            }
            if (liveMacList != null) {
              if (liveMacList is List) {
                _maclistController.text = liveMacList.join('\n');
              } else if (liveMacList is String) {
                _maclistController.text = liveMacList;
              }
            }
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        _captureBaseline();
        setState(() => _isPrefetching = false);
      }
    }
  }

  String _sanitizeCipher(String? cipher) {
    if (cipher == null) return 'auto';
    final c = cipher.toLowerCase();
    if (c.contains('gcmp256') || c.contains('gcmp-256')) return 'gcmp256';
    if (c.contains('ccmp') || c.contains('aes')) return 'ccmp';
    if (c.contains('tkip')) return 'tkip';
    return 'auto';
  }

  String _mapRawEncryptionStringToUci(String rawEnc) {
    final raw = rawEnc.toLowerCase();
    if (raw.contains('sae') && raw.contains('psk')) return 'sae-mixed';
    if (raw.contains('sae')) return 'sae';
    if (raw.contains('psk2') || raw.contains('wpa2')) return 'psk2';
    if (raw.contains('psk')) return 'psk';
    if (raw.contains('none') || raw.contains('open')) return 'none';
    return 'psk2';
  }

  String _mapEncryptionToUci(WifiSecurityMode secMode, String rawEnc) {
    switch (secMode) {
      case WifiSecurityMode.saeOnly:
        return 'sae';
      case WifiSecurityMode.saeMixed:
        return 'sae-mixed';
      case WifiSecurityMode.wpa2Psk:
        return 'psk2';
      case WifiSecurityMode.wpaPsk:
        return 'psk';
      case WifiSecurityMode.open:
        return 'none';
      default:
        return _mapRawEncryptionStringToUci(rawEnc);
    }
  }

  int get _ssidByteLength => utf8.encode(_ssidController.text).length;

  Future<void> _submitChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final appState = ref.read(appStateProvider);
    final iface = widget.interface;

    bool isConnectedToThisSsid = false;
    final activeSessionMac = appState.dashboardData?['activeSessionMac']
        ?.toString()
        .toUpperCase();
    for (final st in iface.stations) {
      if (st.macAddress.toUpperCase() == activeSessionMac) {
        isConnectedToThisSsid = true;
        break;
      }
    }

    final isSsidNameChanged = _ssidController.text.trim() != iface.ssid;
    final isPassphraseChanged =
        _passphraseController.text.trim().isNotEmpty &&
        _passphraseController.text.trim() != _initialPassphrase;
    final isEncryptionChanged =
        _selectedEncryption !=
        _mapEncryptionToUci(iface.securityMode, iface.encryption);

    // Security downgrade warning
    if (isEncryptionChanged && _isSecurityDowngrade()) {
      if (!mounted) return;
      final proceed = await LuciGuardrail.showConfirmation(
        context,
        title: 'Security Downgrade Warning',
        subtitle:
            'You are changing encryption from "${widget.interface.securityMode.displayName}" to "${_mapUciToSecurityMode(_selectedEncryption).displayName}". This reduces security and may expose your network to attacks.',
        confirmLabel: 'Proceed Anyway',
        cancelLabel: 'Cancel',
        icon: Icons.security_update_warning_rounded,
        iconColor: Colors.red,
        isDestructive: true,
      );
      if (!proceed) return;
    }

    if (isConnectedToThisSsid &&
        (isSsidNameChanged || isPassphraseChanged || isEncryptionChanged)) {
      if (!mounted) return;
      final proceed = await LuciGuardrail.showConfirmation(
        context,
        title: 'Self-Disconnection Warning',
        subtitle:
            'You are currently connected via Wi-Fi network "${iface.ssid}". Modifying its name, security mode, or passphrase will sever your active session.',
        confirmLabel: 'Proceed & Disconnect',
        cancelLabel: 'Cancel',
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.orange,
        isDestructive: true,
      );
      if (!proceed) return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = true);

    final String resolvedPmf =
        (_selectedEncryption == 'sae' || _selectedEncryption == 'owe')
        ? '2'
        : (_selectedEncryption == 'none' ? '0' : _selectedPmf);

    final newValues = <String, String>{
      'ssid': _ssidController.text.trim(),
      'encryption': _selectedEncryption,
      'cipher': _selectedCipher,
      'ieee80211w': resolvedPmf,
      'isolate': _isolateClients ? '1' : '0',
      'hidden': _isHidden ? '1' : '0',
      'network': _selectedNetwork,
      'ieee80211r': _ieee80211r ? '1' : '0',
      'ft_over_ds': _ftOverDs ? '1' : '0',
      'ft_psk_generate_local': _ftPskGenerateLocal ? '1' : '0',
      'wmm': _wmmEnabled ? '1' : '0',
      'disassoc_low_ack': _disassocLowAck ? '1' : '0',
      'multicast_to_unicast': _multicastToUnicast ? '1' : '0',
      'wds': _wds ? '1' : '0',
    };

    if (_mobilityDomainController.text.trim().isNotEmpty) {
      newValues['mobility_domain'] = _mobilityDomainController.text
          .trim()
          .toLowerCase();
    }
    if (_dtimPeriodController.text.trim().isNotEmpty) {
      newValues['dtim_period'] = _dtimPeriodController.text.trim();
    }
    if (_gtkRekeyController.text.trim().isNotEmpty) {
      newValues['gtk_rekey'] = _gtkRekeyController.text.trim();
    }
    if (_inactivityLimitController.text.trim().isNotEmpty) {
      newValues['inactivity_limit'] = _inactivityLimitController.text.trim();
    }
    if (_maxListenIntervalController.text.trim().isNotEmpty) {
      newValues['max_listen_interval'] = _maxListenIntervalController.text
          .trim();
    }

    if (_macfilter != 'disable') {
      newValues['macfilter'] = _macfilter;
      if (_maclistController.text.trim().isNotEmpty) {
        final macs = _maclistController.text
            .split(RegExp(r'[\n,;]+'))
            .map((e) => e.trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .join(' ');
        newValues['maclist'] = macs;
      }
    } else {
      newValues['macfilter'] = 'none';
    }

    if (_selectedEncryption != 'none') {
      final enteredPass = _passphraseController.text.trim();
      if (enteredPass.isNotEmpty) {
        newValues['key'] = enteredPass;
      } else if (_initialPassphrase.isNotEmpty) {
        newValues['key'] = _initialPassphrase;
      }
    }

    final priorSnapshot = <String, String>{
      'ssid': iface.ssid,
      'encryption': _mapEncryptionToUci(iface.securityMode, iface.encryption),
      'cipher': _sanitizeCipher(iface.cipher),
      'ieee80211w': iface.pmfState == PmfState.required
          ? '2'
          : (iface.pmfState == PmfState.optional ? '1' : '0'),
      'isolate': iface.isolateClients ? '1' : '0',
      'hidden': iface.isHidden ? '1' : '0',
    };
    if (_initialPassphrase.isNotEmpty) {
      priorSnapshot['key'] = _initialPassphrase;
    }

    final success = await appState.applyWirelessInterfaceConfig(
      sectionName: iface.sectionName,
      newValues: newValues,
      priorValuesSnapshot: priorSnapshot,
      targetRadio: widget.radio,
      targetInterface: widget.interface,
      context: context,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        Navigator.pop(context, true);
        context.showToastSuccess(
          'Wireless SSID settings updated directly to router.',
        );
      } else {
        final username = appState.sessionUsername;
        if ((appState.capabilities?.hasUciWriteAccess ?? true) == false ||
            !appState.isAdministrativeUser) {
          context.showToastError(
            'Access Denied: Account \'$username\' lacks UCI write authorization.',
          );
        } else {
          context.showToastError('Failed to update wireless section in UCI.');
        }
      }
    }
  }

  bool _hasChanges() {
    if (_initialBaseline.isEmpty) return false;
    if (_ssidController.text.trim() != _initialBaseline['ssid']) return true;
    if (_passphraseController.text != _initialBaseline['passphrase']) {
      return true;
    }
    if (_selectedEncryption != _initialBaseline['encryption']) return true;
    if (_selectedCipher != _initialBaseline['cipher']) return true;
    if (_selectedPmf != _initialBaseline['pmf']) return true;
    if (_isolateClients != _initialBaseline['isolate']) return true;
    if (_isHidden != _initialBaseline['hidden']) return true;
    if (_selectedNetwork != _initialBaseline['network']) return true;
    if (_ieee80211r != _initialBaseline['ieee80211r']) return true;
    if (_ftOverDs != _initialBaseline['ftOverDs']) return true;
    if (_ftPskGenerateLocal != _initialBaseline['ftPskGenerateLocal']) {
      return true;
    }
    if (_mobilityDomainController.text.trim() !=
        _initialBaseline['mobilityDomain']) {
      return true;
    }
    if (_wmmEnabled != _initialBaseline['wmm']) return true;
    if (_disassocLowAck != _initialBaseline['disassocLowAck']) return true;
    if (_multicastToUnicast != _initialBaseline['multicastToUnicast']) {
      return true;
    }
    if (_wds != _initialBaseline['wds']) return true;
    if (_dtimPeriodController.text.trim() != _initialBaseline['dtimPeriod']) {
      return true;
    }
    if (_gtkRekeyController.text.trim() != _initialBaseline['gtkRekey']) {
      return true;
    }
    if (_inactivityLimitController.text.trim() !=
        _initialBaseline['inactivityLimit']) {
      return true;
    }
    if (_maxListenIntervalController.text.trim() !=
        _initialBaseline['maxListenInterval']) {
      return true;
    }
    if (_macfilter != _initialBaseline['macfilter']) return true;
    if (_maclistController.text.trim() != _initialBaseline['maclist']) {
      return true;
    }
    return false;
  }

  bool _isFormValid() {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) return false;
    if (utf8.encode(ssid).length > 32) return false;

    if (!isNone) {
      final pass = _passphraseController.text;
      if (pass.isNotEmpty) {
        if (pass.length < 8 || pass.length > 64) return false;
      } else {
        final String initPass =
            _initialBaseline['passphrase'] ?? _initialPassphrase;
        if (initPass.isEmpty) return false;
      }
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

  bool _isSecurityDowngrade() {
    final curRank = _securityRank(
      _mapEncryptionToUci(
        widget.interface.securityMode,
        widget.interface.encryption,
      ),
    );
    final newRank = _securityRank(_selectedEncryption);
    return newRank < curRank;
  }

  int _securityRank(String enc) {
    switch (enc) {
      case 'sae':
        return 4;
      case 'sae-mixed':
        return 3;
      case 'psk2':
        return 2;
      case 'psk':
        return 1;
      case 'owe':
        return 1;
      case 'none':
      default:
        return 0;
    }
  }

  WifiSecurityMode _mapUciToSecurityMode(String uci) {
    switch (uci) {
      case 'sae':
        return WifiSecurityMode.saeOnly;
      case 'sae-mixed':
        return WifiSecurityMode.saeMixed;
      case 'psk2':
        return WifiSecurityMode.wpa2Psk;
      case 'psk':
        return WifiSecurityMode.wpaPsk;
      case 'owe':
        return WifiSecurityMode.open;
      case 'none':
      default:
        return WifiSecurityMode.open;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final hasWriteAccess =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;

    return PopScope(
      canPop: !_isSubmitting,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Edit SSID & Advanced Settings',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_isPrefetching) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (_isPrefetching) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ACL Warning Banner
                          if (!hasWriteAccess) ...[
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
                                      'Logged in as non-root user \'${appState.sessionUsername}\'. Saving requires root/UCI write privileges.',
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
                          // Safety Notice Banner
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.shield_outlined,
                                  color: Colors.amber,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Changes will be applied directly to the router.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // SSID Name Field
                          TextFormField(
                            controller: _ssidController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'SSID Name',
                              hintText: 'e.g. MyHomeNetwork',
                              helperText: '$_ssidByteLength / 32 UTF-8 bytes',
                              helperStyle: TextStyle(
                                color: _ssidByteLength > 32 ? Colors.red : null,
                                fontWeight: _ssidByteLength > 32
                                    ? FontWeight.bold
                                    : null,
                              ),
                              prefixIcon: const Icon(Icons.wifi, size: 20),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'SSID cannot be empty or whitespace only';
                              }
                              final bytes = utf8.encode(val);
                              if (bytes.length > 32) {
                                return 'SSID exceeds maximum 32 bytes (${bytes.length} bytes)';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Security Mode Dropdown
                          DropdownButtonFormField<String>(
                            initialValue: _selectedEncryption,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Encryption / Security Mode',
                              prefixIcon: Icon(
                                Icons.lock_outline_rounded,
                                size: 20,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            items: _buildEncryptionDropdownItems(appState),
                            onChanged: (val) {
                              if (val == null) return;
                              setState(() {
                                _selectedEncryption = val;
                                if (val == 'sae') {
                                  _selectedPmf = '2';
                                } else if (val == 'none') {
                                  _selectedPmf = '0';
                                } else if (_selectedPmf == '0' &&
                                    val == 'sae-mixed') {
                                  _selectedPmf = '1';
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 16),

                          // Passphrase Field
                          if (!isNone) ...[
                            TextFormField(
                              controller: _passphraseController,
                              obscureText: !_showPassphrase,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Passphrase / Key',
                                helperText: _initialPassphrase.isEmpty
                                    ? 'Leave blank to retain existing router passphrase'
                                    : '8–63 characters or 64 hex characters',
                                prefixIcon: const Icon(
                                  Icons.key_rounded,
                                  size: 20,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _showPassphrase
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () => setState(
                                    () => _showPassphrase = !_showPassphrase,
                                  ),
                                ),
                                border: const OutlineInputBorder(),
                              ),
                              validator: (val) {
                                if (val == null || val.isEmpty) {
                                  return null; // allow empty to retain existing
                                }
                                if (val.length < 8 || val.length > 64) {
                                  return 'Passphrase must be between 8 and 64 characters';
                                }
                                return null;
                              },
                            ),
                            PasswordStrengthMeter(
                              password: _passphraseController.text,
                            ),
                            const SizedBox(height: 16),
                          ],

                          // PMF Dropdown
                          DropdownButtonFormField<String>(
                            initialValue: _selectedPmf,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText:
                                  'Protected Management Frames (802.11w)',
                              prefixIcon: Icon(
                                Icons.security_rounded,
                                size: 20,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '0',
                                child: Text(
                                  'Disabled — Maximum legacy client compatibility',
                                ),
                              ),
                              DropdownMenuItem(
                                value: '1',
                                child: Text(
                                  'Optional — Preferred default for WPA2/WPA3 mixed',
                                ),
                              ),
                              DropdownMenuItem(
                                value: '2',
                                child: Text(
                                  'Required — Mandated for strict WPA3-SAE',
                                ),
                              ),
                            ],
                            onChanged:
                                (_selectedEncryption == 'sae' ||
                                    _selectedEncryption == 'none')
                                ? null
                                : (val) {
                                    if (val != null) {
                                      setState(() => _selectedPmf = val);
                                    }
                                  },
                          ),
                          const SizedBox(height: 16),

                          // Cipher Dropdown
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCipher,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Cipher Algorithm',
                              prefixIcon: Icon(Icons.memory_rounded, size: 20),
                              border: OutlineInputBorder(),
                            ),
                            items: _buildCipherDropdownItems(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedCipher = val);
                              }
                            },
                          ),
                          const SizedBox(height: 12),

                          // Isolate Clients Switch
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Isolate Wireless Clients',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: const Text(
                              'Blocks direct peer-to-peer traffic between connected stations',
                              style: TextStyle(fontSize: 11.5),
                            ),
                            value: _isolateClients,
                            onChanged: (val) =>
                                setState(() => _isolateClients = val),
                          ),

                          // Hidden SSID Switch
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Hide Broadcast SSID',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: const Text(
                              'Suppresses beacon SSID broadcast to hide network from scanner lists',
                              style: TextStyle(fontSize: 11.5),
                            ),
                            value: _isHidden,
                            onChanged: (val) => setState(() => _isHidden = val),
                          ),
                          const SizedBox(height: 12),

                          // ── Expandable Advanced Wireless & Network Settings ──
                          Theme(
                            data: theme.copyWith(
                              dividerColor: Colors.transparent,
                            ),
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
                                  Expanded(
                                    child: Text(
                                      'Advanced Network & Roaming Settings',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              onExpansionChanged: (exp) =>
                                  setState(() => _showAdvanced = exp),
                              initiallyExpanded: _showAdvanced,
                              childrenPadding: const EdgeInsets.only(top: 8),
                              children: [
                                // Network Attachment Dropdown
                                DropdownButtonFormField<String>(
                                  initialValue:
                                      _availableNetworks.contains(
                                        _selectedNetwork,
                                      )
                                      ? _selectedNetwork
                                      : _availableNetworks.first,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Attached Network Bridge',
                                    prefixIcon: Icon(
                                      Icons.alt_route_rounded,
                                      size: 20,
                                    ),
                                    border: OutlineInputBorder(),
                                    helperText:
                                        'Select network interface (lan, guest, wan, etc.)',
                                  ),
                                  items: _availableNetworks.map((net) {
                                    return DropdownMenuItem(
                                      value: net,
                                      child: Text(
                                        net,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedNetwork = val);
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Fast Roaming Section
                                _buildSubHeader(
                                  '802.11r / 802.11k / 802.11v Fast Roaming',
                                  Icons.bolt_rounded,
                                ),
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    '802.11r Fast BSS Transition (FT)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'Enables fast seamless handoff between access points',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  value: _ieee80211r,
                                  onChanged: (val) =>
                                      setState(() => _ieee80211r = val),
                                ),
                                if (_ieee80211r) ...[
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'FT over DS (Distributed System)',
                                      style: TextStyle(fontSize: 12.5),
                                    ),
                                    subtitle: const Text(
                                      'Pre-authenticates over ethernet backbone',
                                      style: TextStyle(fontSize: 10.5),
                                    ),
                                    value: _ftOverDs,
                                    onChanged: (val) =>
                                        setState(() => _ftOverDs = val),
                                  ),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Generate Local FT PSK Keys',
                                      style: TextStyle(fontSize: 12.5),
                                    ),
                                    subtitle: const Text(
                                      'Derives roaming keys locally per AP',
                                      style: TextStyle(fontSize: 10.5),
                                    ),
                                    value: _ftPskGenerateLocal,
                                    onChanged: (val) => setState(
                                      () => _ftPskGenerateLocal = val,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _mobilityDomainController,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: 'Mobility Domain ID',
                                      hintText: '4f4b',
                                      prefixIcon: Icon(
                                        Icons.domain_rounded,
                                        size: 20,
                                      ),
                                      border: OutlineInputBorder(),
                                      helperText:
                                          '4-character hex identifier (must match across all APs)',
                                    ),
                                    maxLength: 4,
                                  ),
                                  const SizedBox(height: 12),
                                ],

                                // QoS & Performance Toggles
                                _buildSubHeader(
                                  'QoS & Wireless Connection Parameters',
                                  Icons.speed_rounded,
                                ),
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'WMM (Wi-Fi Multimedia QoS)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'Prioritizes voice and video traffic queues',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  value: _wmmEnabled,
                                  onChanged: (val) =>
                                      setState(() => _wmmEnabled = val),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Disassociate on Low ACK Rates',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'Disconnects weak clients failing packet ACKs to preserve airtime',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  value: _disassocLowAck,
                                  onChanged: (val) =>
                                      setState(() => _disassocLowAck = val),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Multicast to Unicast Conversion',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  subtitle: const Text(
                                    'Converts multicast frames to unicast for reliable reception',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  value: _multicastToUnicast,
                                  onChanged: (val) =>
                                      setState(() => _multicastToUnicast = val),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'WDS (Wireless Distribution System)',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  subtitle: const Text(
                                    'Transparent L2 bridge for multi-AP mesh connections',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  value: _wds,
                                  onChanged: (val) =>
                                      setState(() => _wds = val),
                                ),
                                const SizedBox(height: 12),

                                // Intervals & Limits
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
                                        controller:
                                            _maxListenIntervalController,
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

                                // MAC Address Filtering
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
                                    prefixIcon: Icon(
                                      Icons.security_rounded,
                                      size: 20,
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'disable',
                                      child: Text('Disabled'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'allow',
                                      child: Text(
                                        'Allow List (only listed MACs)',
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'deny',
                                      child: Text(
                                        'Deny List (block listed MACs)',
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _macfilter = val);
                                    }
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
                                      hintText:
                                          'AA:BB:CC:DD:EE:FF\n11:22:33:44:55:66',
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
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final canSave =
                            !_isSubmitting &&
                            !_isPrefetching &&
                            _hasChanges() &&
                            _isFormValid();
                        return ElevatedButton.icon(
                          onPressed: canSave ? _submitChanges : null,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(
                            hasWriteAccess ? 'Save & Apply' : 'Save (Non-Root)',
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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

  List<DropdownMenuItem<String>> _buildEncryptionDropdownItems(
    AppState appState,
  ) {
    final staticItems = [
      const DropdownMenuItem(
        value: 'sae-mixed',
        child: Text('WPA2/WPA3 Mixed — Recommended default'),
      ),
      const DropdownMenuItem(
        value: 'sae',
        child: Text('WPA3-SAE Personal — Strict / Max security'),
      ),
      const DropdownMenuItem(
        value: 'psk2',
        child: Text('WPA2-PSK (CCMP/AES) — Legacy compatible'),
      ),
      const DropdownMenuItem(
        value: 'psk',
        child: Text('WPA-PSK — Legacy only (WPA1)'),
      ),
      const DropdownMenuItem(
        value: 'owe',
        child: Text('Enhanced Open (OWE) — Encrypted, no password'),
      ),
      const DropdownMenuItem(
        value: 'none',
        child: Text('Open / None — Unencrypted public network'),
      ),
    ];

    if (_dynamicEncryptions.isEmpty) return staticItems;

    final items = <DropdownMenuItem<String>>[];
    for (final enc in _dynamicEncryptions) {
      final val = enc['value']!;
      final label = enc['label']!;
      items.add(
        DropdownMenuItem(
          value: val,
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    return items;
  }

  List<DropdownMenuItem<String>> _buildCipherDropdownItems() {
    final staticItems = [
      const DropdownMenuItem(
        value: 'auto',
        child: Text('Auto — Router auto-selects best cipher'),
      ),
      const DropdownMenuItem(
        value: 'ccmp',
        child: Text('CCMP (AES) — Recommended default'),
      ),
      const DropdownMenuItem(
        value: 'gcmp256',
        child: Text('GCMP-256 — High security / Wi-Fi 6'),
      ),
      const DropdownMenuItem(
        value: 'tkip',
        child: Text('TKIP — Legacy (Not recommended)'),
      ),
    ];

    if (_dynamicCiphers.isEmpty) return staticItems;

    final items = <DropdownMenuItem<String>>[];
    for (final cipher in _dynamicCiphers) {
      final val = cipher['value']!;
      final label = cipher['label']!;
      items.add(
        DropdownMenuItem(
          value: val,
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    return items;
  }
}
