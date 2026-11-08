// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import 'package:yet_another_luci_app/widgets/password_strength_meter.dart';
import '../models/wireless_info.dart';

/// Dialog providing live-validated editable security & advanced wireless settings on existing SSIDs
/// with prefetch support, 802.11r/k/v Fast Roaming, WMM QoS, interval controls, MAC filtering,
/// and IP/DHCP subnet controls with progressive disclosure.
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

  // Controllers for Subnet / DHCP Settings
  late TextEditingController _dhcpStartController;
  late TextEditingController _dhcpLimitController;
  late TextEditingController _dhcpLeaseController;
  late TextEditingController _dnsServersController;
  String _ipv6Ra = 'server';
  String _dhcpv6Mode = 'server';

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
  bool _ieee80211k = false;
  bool _ieee80211v = false;

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

    _dhcpStartController = TextEditingController(text: '100');
    _dhcpLimitController = TextEditingController(text: '150');
    _dhcpLeaseController = TextEditingController(text: '12h');
    _dnsServersController = TextEditingController();

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

    _loadSubnetDhcpDefaults();
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
      'ieee80211k': _ieee80211k,
      'ieee80211v': _ieee80211v,
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
      'dhcpStart': _dhcpStartController.text.trim(),
      'dhcpLimit': _dhcpLimitController.text.trim(),
      'dhcpLease': _dhcpLeaseController.text.trim(),
      'dnsServers': _dnsServersController.text.trim(),
      'ipv6Ra': _ipv6Ra,
      'dhcpv6Mode': _dhcpv6Mode,
    };
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

  Future<void> _fetchAvailableNetworks() async {
    try {
      final appState = ref.read(appStateProvider);
      final networks = await appState.fetchNetworkInterfaces();
      if (mounted && networks.isNotEmpty) {
        setState(() {
          _availableNetworks = networks;
          if (!_availableNetworks.contains(_selectedNetwork)) {
            _availableNetworks.insert(0, _selectedNetwork);
          }
        });
        _loadSubnetDhcpDefaults();
      }
    } catch (_) {}
  }

  Future<void> _prefetchLiveUciConfig() async {
    if (!mounted) return;
    setState(() => _isPrefetching = true);
    final appState = ref.read(appStateProvider);

    try {
      final caps = await appState.fetchWirelessHardwareCapabilities(
        sectionName: widget.interface.sectionName,
        radioName: widget.radio.name,
      );
      if (mounted) {
        setState(() {
          _dynamicEncryptions = caps['encryptions'] ?? [];
          _dynamicCiphers = caps['ciphers'] ?? [];
        });
      }

      final values = await appState.fetchWirelessSectionConfig(
        widget.interface.sectionName,
      );

      if (mounted && values != null && values.isNotEmpty) {
        if (values.isNotEmpty) {
          final liveKey =
              values['key']?.toString() ??
              values['password']?.toString() ??
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
          final liveK = values['ieee80211k']?.toString();
          final liveV = values['ieee80211v']?.toString();
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
            if (liveK != null) _ieee80211k = liveK == '1';
            if (liveV != null) _ieee80211v = liveV == '1';
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
      if (activeSessionMac != null &&
          activeSessionMac.isNotEmpty &&
          st.macAddress.toUpperCase() == activeSessionMac) {
        isConnectedToThisSsid = true;
        break;
      }
    }

    final isSsidNameChanged =
        _ssidController.text.trim() != widget.interface.ssid;
    final isPassphraseChanged =
        _passphraseController.text != _initialPassphrase;
    final isEncryptionChanged =
        _selectedEncryption !=
        _mapEncryptionToUci(
          widget.interface.securityMode,
          widget.interface.encryption,
        );

    if (_isSecurityDowngrade()) {
      if (!mounted) return;
      final proceed = await LuciGuardrail.showConfirmation(
        context,
        title: 'Security Downgrade Warning',
        subtitle:
            'You are lowering the Wi-Fi security standard from ${widget.interface.securityMode.displayName} to ${_selectedEncryption.toUpperCase()}. This weakens encryption protection for connecting clients.',
        confirmLabel: 'Proceed with Downgrade',
        cancelLabel: 'Cancel',
        icon: Icons.shield_outlined,
        iconColor: Colors.amber.shade800,
        isDestructive: false,
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
      'ieee80211k': _ieee80211k ? '1' : '0',
      'ieee80211v': _ieee80211v ? '1' : '0',
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

    final deleteOptions = <String>[];
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
      // In OpenWrt 21+, validate.uc validates macfilter enum: ['allow', 'deny'].
      // Writing 'none' causes validate.uc to die and crashes netifd/wifi.
      // To disable MAC filtering, delete only the 'macfilter' option from UCI.
      // We explicitly PRESERVE 'maclist' (never delete it) so previously configured
      // MAC addresses remain saved in UCI for when filtering is re-enabled.
      deleteOptions.add('macfilter');
      if (_maclistController.text.trim().isNotEmpty) {
        final macs = _maclistController.text
            .split(RegExp(r'[\n,;]+'))
            .map((e) => e.trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .join(' ');
        newValues['maclist'] = macs;
      }
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
      'network': iface.networkBridge ?? 'lan',
      'ieee80211r': iface.fastTransitionEnabled ? '1' : '0',
    };
    if (iface.key != null && iface.key!.isNotEmpty) {
      priorSnapshot['key'] = iface.key!;
    }

    try {
      final success = await appState.applyWirelessInterfaceConfig(
        sectionName: iface.sectionName,
        newValues: newValues,
        priorValuesSnapshot: priorSnapshot,
        deleteOptions: deleteOptions,
        targetRadio: widget.radio,
        targetInterface: widget.interface,
        context: mounted ? context : null,
      );

      bool dhcpSuccess = true;
      // Subnet DHCP updates
      if (success &&
          (_dhcpStartController.text.trim() != _initialBaseline['dhcpStart'] ||
              _dhcpLimitController.text.trim() !=
                  _initialBaseline['dhcpLimit'] ||
              _dhcpLeaseController.text.trim() !=
                  _initialBaseline['dhcpLease'] ||
              _dnsServersController.text.trim() !=
                  _initialBaseline['dnsServers'] ||
              _ipv6Ra != _initialBaseline['ipv6Ra'] ||
              _dhcpv6Mode != _initialBaseline['dhcpv6Mode'])) {
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

      final l10n = mounted ? AppLocalizations.of(context) : null;
      if (mounted) {
        if (success && dhcpSuccess) {
          Navigator.pop(context, true);
          context.showToastSuccess(
            l10n?.toastSsidUpdateSuccess ??
                'SSID settings applied directly to router.',
          );
        } else if (success && !dhcpSuccess) {
          Navigator.pop(context, true);
          context.showToastWarning(
            'SSID updated, but subnet DHCP configuration could not be applied.',
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
              l10n?.toastSsidUpdateFailed ??
                  'Failed to update wireless section in UCI.',
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        context.showToastError(
          'Failed to update wireless SSID',
          subtitle: LuciToastManager.parseErrorReason(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
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
    if (_ieee80211k != _initialBaseline['ieee80211k']) return true;
    if (_ieee80211v != _initialBaseline['ieee80211v']) return true;
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
    if (_dhcpStartController.text.trim() != _initialBaseline['dhcpStart']) {
      return true;
    }
    if (_dhcpLimitController.text.trim() != _initialBaseline['dhcpLimit']) {
      return true;
    }
    if (_dhcpLeaseController.text.trim() != _initialBaseline['dhcpLease']) {
      return true;
    }
    if (_dnsServersController.text.trim() != _initialBaseline['dnsServers']) {
      return true;
    }
    if (_ipv6Ra != _initialBaseline['ipv6Ra']) return true;
    if (_dhcpv6Mode != _initialBaseline['dhcpv6Mode']) return true;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final hasWriteAccess =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;

    return PopScope(
      canPop: !_isSubmitting,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
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
                        l10n?.editSsidTitle ?? 'Edit SSID & Advanced Settings',
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
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ACL Warning Banner
                          if (!hasWriteAccess)
                            _buildBanner(
                              color: Colors.red,
                              icon: Icons.lock_clock_outlined,
                              text:
                                  'Logged in as non-root user \'${appState.sessionUsername}\'. Saving requires root/UCI write privileges.',
                            ),

                          // Safety Notice Banner
                          _buildBanner(
                            color: Colors.amber,
                            icon: Icons.shield_outlined,
                            text:
                                l10n?.changesDirectRouterWarning ??
                                'Changes will be applied directly to the router.',
                          ),
                          const SizedBox(height: 12),

                          // ── ESSENTIAL QUICK SETTINGS ─────────────────────

                          // SSID Name Field
                          TextFormField(
                            controller: _ssidController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: l10n?.ssidNameLabel ?? 'SSID Name',
                              hintText:
                                  l10n?.ssidNameHint ?? 'e.g. MyHomeNetwork',
                              helperText:
                                  l10n?.ssidByteCountHelper(_ssidByteLength) ??
                                  '$_ssidByteLength / 32 UTF-8 bytes',
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
                                return l10n?.ssidErrorEmpty ??
                                    'SSID cannot be empty or whitespace only';
                              }
                              final bytes = utf8.encode(val);
                              if (bytes.length > 32) {
                                return l10n?.ssidErrorExceedsBytes(
                                      bytes.length,
                                    ) ??
                                    'SSID exceeds maximum 32 bytes (${bytes.length} bytes)';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Security Mode Dropdown
                          DropdownButtonFormField<String>(
                            initialValue: _selectedEncryption,
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(16),
                            dropdownColor:
                                theme.colorScheme.surfaceContainerHigh,
                            elevation: 4,
                            menuMaxHeight: 360,
                            icon: const Icon(Icons.arrow_drop_down_rounded),
                            decoration: InputDecoration(
                              labelText:
                                  l10n?.encryptionSecurityModeLabel ??
                                  'Encryption / Security Mode',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 20,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                          const SizedBox(height: 14),

                          // Passphrase Field
                          if (!isNone) ...[
                            TextFormField(
                              controller: _passphraseController,
                              obscureText: !_showPassphrase,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText:
                                    l10n?.passphraseKeyLabel ??
                                    'Passphrase / Key',
                                helperText: _initialPassphrase.isEmpty
                                    ? (l10n?.passphraseLeaveBlankRetain ??
                                          'Leave blank to retain existing router passphrase')
                                    : (l10n?.passphraseLengthHelper ??
                                          '8–63 characters or 64 hex characters'),
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
                                  return l10n?.passphraseValidationRange ??
                                      'Passphrase must be between 8 and 64 characters';
                                }
                                return null;
                              },
                            ),
                            PasswordStrengthMeter(
                              password: _passphraseController.text,
                            ),
                            const SizedBox(height: 14),
                          ],

                          if (_selectedEncryption == 'none') ...[
                            _buildBanner(
                              color: Colors.amber,
                              icon: Icons.warning_amber_rounded,
                              text:
                                  l10n?.openNetworkWarningBody ??
                                  'An open Wi-Fi network transmits data without encryption. Anyone within range can connect and monitor unencrypted traffic.',
                            ),
                            const SizedBox(height: 10),
                          ],

                          // ── PROGRESSIVE DISCLOSURE: Advanced Settings ─────
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
                                      l10n?.advancedSettingsTitle ??
                                          'Advanced Settings',
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
                                // ── Group 1: Security & Privacy ───────────
                                _buildSubHeader(
                                  l10n?.secGroupSecurityPrivacy ??
                                      'Security & Privacy',
                                  Icons.shield_rounded,
                                ),
                                const SizedBox(height: 6),

                                // Client Isolation
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    l10n?.isolateWirelessClientsLabel ??
                                        'Isolate Wireless Clients',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    l10n?.isolateWirelessClientsSubtitle ??
                                        'Blocks direct peer-to-peer traffic between connected stations',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  value: _isolateClients,
                                  onChanged: (val) =>
                                      setState(() => _isolateClients = val),
                                ),

                                // PMF
                                if (_selectedEncryption != 'none') ...[
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedPmf,
                                    isExpanded: true,
                                    borderRadius: BorderRadius.circular(16),
                                    dropdownColor:
                                        theme.colorScheme.surfaceContainerHigh,
                                    elevation: 4,
                                    menuMaxHeight: 360,
                                    icon: const Icon(
                                      Icons.arrow_drop_down_rounded,
                                    ),
                                    decoration: InputDecoration(
                                      labelText:
                                          l10n?.pmfLabel ??
                                          'Protected Management Frames (802.11w)',
                                      prefixIcon: const Icon(
                                        Icons.security_rounded,
                                        size: 20,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: '0',
                                        child: Text(
                                          l10n?.pmfDisabledDesc ??
                                              'Disabled — Maximum legacy client compatibility',
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: '1',
                                        child: Text(
                                          l10n?.pmfOptionalDesc ??
                                              'Optional — Preferred default for WPA2/WPA3 mixed',
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: '2',
                                        child: Text(
                                          l10n?.pmfRequiredDesc ??
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
                                              setState(
                                                () => _selectedPmf = val,
                                              );
                                            }
                                          },
                                  ),
                                  const SizedBox(height: 12),

                                  // Cipher
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedCipher,
                                    isExpanded: true,
                                    borderRadius: BorderRadius.circular(16),
                                    dropdownColor:
                                        theme.colorScheme.surfaceContainerHigh,
                                    elevation: 4,
                                    menuMaxHeight: 360,
                                    icon: const Icon(
                                      Icons.arrow_drop_down_rounded,
                                    ),
                                    decoration: InputDecoration(
                                      labelText:
                                          l10n?.cipherAlgorithmLabel ??
                                          'Cipher Algorithm',
                                      prefixIcon: const Icon(
                                        Icons.memory_rounded,
                                        size: 20,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    items: _buildCipherDropdownItems(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedCipher = val);
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                ],

                                // Hidden SSID
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    l10n?.hideBroadcastSsidLabel ??
                                        'Hide Broadcast SSID',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    l10n?.hideBroadcastSsidSubtitle ??
                                        'Suppresses beacon SSID broadcast to hide network from scanner lists',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  value: _isHidden,
                                  onChanged: (val) =>
                                      setState(() => _isHidden = val),
                                ),

                                // MAC Filtering
                                DropdownButtonFormField<String>(
                                  initialValue: _macfilter,
                                  isExpanded: true,
                                  borderRadius: BorderRadius.circular(16),
                                  dropdownColor:
                                      theme.colorScheme.surfaceContainerHigh,
                                  elevation: 4,
                                  menuMaxHeight: 360,
                                  icon: const Icon(
                                    Icons.arrow_drop_down_rounded,
                                  ),
                                  decoration: InputDecoration(
                                    labelText:
                                        l10n?.macFilterModeLabel ??
                                        'MAC Filter Mode',
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
                                        l10n?.macFilterDisabled ?? 'Disabled',
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'allow',
                                      child: Text(
                                        l10n?.macFilterAllowOnly ??
                                            'Allow List (only listed MACs)',
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'deny',
                                      child: Text(
                                        l10n?.macFilterBlock ??
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
                                if (_macfilter != 'disable') ...[
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    controller: _maclistController,
                                    maxLines: 3,
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                      labelText:
                                          l10n?.macListLabel ??
                                          'MAC Address List',
                                      hintText:
                                          l10n?.macListHint ??
                                          'AA:BB:CC:DD:EE:FF\n11:22:33:44:55:66',
                                      prefixIcon: const Icon(
                                        Icons.list_alt_rounded,
                                        size: 20,
                                      ),
                                      border: const OutlineInputBorder(),
                                      helperText:
                                          'One MAC per line or separated by space/comma',
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),

                                // ── Group 2: Network Assignment ───────────
                                _buildSubHeader(
                                  l10n?.secGroupNetworkAssignment ??
                                      'Network Assignment',
                                  Icons.alt_route_rounded,
                                ),
                                const SizedBox(height: 6),

                                DropdownButtonFormField<String>(
                                  initialValue:
                                      _availableNetworks.contains(
                                        _selectedNetwork,
                                      )
                                      ? _selectedNetwork
                                      : _availableNetworks.first,
                                  isExpanded: true,
                                  borderRadius: BorderRadius.circular(16),
                                  dropdownColor:
                                      theme.colorScheme.surfaceContainerHigh,
                                  elevation: 4,
                                  menuMaxHeight: 360,
                                  icon: const Icon(
                                    Icons.arrow_drop_down_rounded,
                                  ),
                                  decoration: InputDecoration(
                                    labelText:
                                        l10n?.attachedNetworkBridgeLabel ??
                                        'Attached Network Bridge',
                                    prefixIcon: const Icon(
                                      Icons.alt_route_rounded,
                                      size: 20,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    helperText: _getNetworkDescription(
                                      _selectedNetwork,
                                      l10n,
                                    ),
                                    helperMaxLines: 2,
                                  ),
                                  items: _availableNetworks.map((net) {
                                    return DropdownMenuItem(
                                      value: net,
                                      child: Text(
                                        _getNetworkLabel(net),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedNetwork = val);
                                      _loadSubnetDhcpDefaults();
                                    }
                                  },
                                ),
                                const SizedBox(height: 10),

                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    l10n?.multicastToUnicastLabel ??
                                        'Multicast → Unicast Conversion',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    l10n?.multicastToUnicastSubtitle ??
                                        'Converts multicast frames to unicast on air interface for reliability',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  value: _multicastToUnicast,
                                  onChanged: (val) =>
                                      setState(() => _multicastToUnicast = val),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    l10n?.wdsLabel ??
                                        'WDS (Wireless Distribution System)',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    l10n?.wdsSubtitle ??
                                        'Transparent L2 bridge for multi-AP mesh connections',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  value: _wds,
                                  onChanged: (val) =>
                                      setState(() => _wds = val),
                                ),
                                const SizedBox(height: 16),

                                // ── Group 3: Fast Roaming & Performance ───
                                _buildSubHeader(
                                  l10n?.secGroupFastRoaming ??
                                      'Fast Roaming & Performance',
                                  Icons.bolt_rounded,
                                ),
                                const SizedBox(height: 6),

                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    l10n?.fastBssTransitionLabel ??
                                        '802.11r Fast BSS Transition (FT)',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    l10n?.fastBssTransitionSubtitle ??
                                        'Enables fast seamless handoff between access points',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  value: _ieee80211r,
                                  onChanged: (val) =>
                                      setState(() => _ieee80211r = val),
                                ),
                                if (_ieee80211r) ...[
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      l10n?.ftOverDsLabel ?? 'FT over DS',
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                    subtitle: Text(
                                      l10n?.ftOverDsSubtitle ??
                                          'Pre-authenticates over ethernet backbone',
                                      style: const TextStyle(fontSize: 10.5),
                                    ),
                                    value: _ftOverDs,
                                    onChanged: (val) =>
                                        setState(() => _ftOverDs = val),
                                  ),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      l10n?.ftGeneratePskLocalLabel ??
                                          'Generate Local FT PSK Keys',
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                    subtitle: Text(
                                      l10n?.ftGeneratePskLocalSubtitle ??
                                          'Derives roaming keys locally per AP',
                                      style: const TextStyle(fontSize: 10.5),
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

                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    l10n?.fastTransition80211kLabel ??
                                        '802.11k Radio Resource Management',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    l10n?.fastTransition80211kSubtitle ??
                                        'Provides radio measurement reports to accelerate AP roaming decisions',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  value: _ieee80211k,
                                  onChanged: (val) =>
                                      setState(() => _ieee80211k = val),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    l10n?.fastTransition80211vLabel ??
                                        '802.11v BSS Transition Management',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    l10n?.fastTransition80211vSubtitle ??
                                        'Allows AP to guide stations to transition to optimal radios',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  value: _ieee80211v,
                                  onChanged: (val) =>
                                      setState(() => _ieee80211v = val),
                                ),

                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    l10n?.wmmQosLabel ??
                                        'WMM / QoS Prioritization',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    l10n?.wmmQosSubtitle ??
                                        'Wi-Fi Multimedia quality-of-service traffic prioritization',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  value: _wmmEnabled,
                                  onChanged: (val) =>
                                      setState(() => _wmmEnabled = val),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    l10n?.disassocLowAckLabel ??
                                        'Disassociate Low-ACK Clients',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    l10n?.disassocLowAckSubtitle ??
                                        'Kick clients with excessive packet loss to conserve airtime',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  value: _disassocLowAck,
                                  onChanged: (val) =>
                                      setState(() => _disassocLowAck = val),
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

                                // ── Group 4: IP & DHCP Settings ───────────
                                _buildSubHeader(
                                  l10n?.secGroupIpDhcp ?? 'IP & DHCP Settings',
                                  Icons.settings_ethernet_rounded,
                                ),
                                const SizedBox(height: 6),

                                // MANDATORY NETWORK-WIDE WARNING
                                _buildBanner(
                                  color: Colors.amber,
                                  icon: Icons.warning_amber_rounded,
                                  text:
                                      l10n?.networkWideWarning(
                                        _selectedNetwork,
                                      ) ??
                                      'These settings apply to all devices connected to the $_selectedNetwork network, not only this Wi-Fi network.',
                                ),
                                const SizedBox(height: 10),

                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _dhcpStartController,
                                        onChanged: (_) => setState(() {}),
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
                                        onChanged: (_) => setState(() {}),
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
                                        onChanged: (_) => setState(() {}),
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
                                        onChanged: (_) => setState(() {}),
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
                                        dropdownColor: theme
                                            .colorScheme
                                            .surfaceContainerHigh,
                                        elevation: 4,
                                        menuMaxHeight: 360,
                                        icon: const Icon(
                                          Icons.arrow_drop_down_rounded,
                                        ),
                                        decoration: InputDecoration(
                                          labelText:
                                              l10n?.ipv6RaLabel ?? 'IPv6 RA',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
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
                                            setState(() => _ipv6Ra = v);
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
                                        dropdownColor: theme
                                            .colorScheme
                                            .surfaceContainerHigh,
                                        elevation: 4,
                                        menuMaxHeight: 360,
                                        icon: const Icon(
                                          Icons.arrow_drop_down_rounded,
                                        ),
                                        decoration: InputDecoration(
                                          labelText:
                                              l10n?.dhcpv6ModeLabel ?? 'DHCPv6',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
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
                                            setState(() => _dhcpv6Mode = v);
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
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                      child: Text(l10n?.actionCancel ?? 'Cancel'),
                    ),
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
                            hasWriteAccess
                                ? (l10n?.btnSaveAndApply ?? 'Save & Apply')
                                : (l10n?.btnAttemptSaveNonRoot ??
                                      'Save (Non-Root)'),
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

  Widget _buildSubHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Row(
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
    );
  }

  List<DropdownMenuItem<String>> _buildEncryptionDropdownItems(
    AppState appState,
  ) {
    final l10n = AppLocalizations.of(context);
    final staticItems = [
      DropdownMenuItem(
        value: 'sae-mixed',
        child: Text(
          l10n?.wifiSecMixedRecommended ??
              'WPA2/WPA3 Mixed — Recommended default',
        ),
      ),
      DropdownMenuItem(
        value: 'sae',
        child: Text(
          l10n?.wifiSecWpa3Strict ??
              'WPA3-SAE Personal — Strict / Max security',
        ),
      ),
      DropdownMenuItem(
        value: 'psk2',
        child: Text(
          l10n?.wifiSecWpa2Legacy ?? 'WPA2-PSK (CCMP/AES) — Legacy compatible',
        ),
      ),
      DropdownMenuItem(
        value: 'psk',
        child: Text(l10n?.wifiSecWpa1Legacy ?? 'WPA-PSK — Legacy only (WPA1)'),
      ),
      DropdownMenuItem(
        value: 'owe',
        child: Text(
          l10n?.wifiSecOwe ?? 'Enhanced Open (OWE) — Encrypted, no password',
        ),
      ),
      DropdownMenuItem(
        value: 'none',
        child: Text(
          l10n?.wifiSecNone ?? 'Open / None — Unencrypted public network',
        ),
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
    final l10n = AppLocalizations.of(context);
    final staticItems = [
      DropdownMenuItem(
        value: 'auto',
        child: Text(
          l10n?.wifiCipherAuto ?? 'Auto — Router auto-selects best cipher',
        ),
      ),
      DropdownMenuItem(
        value: 'ccmp',
        child: Text(l10n?.wifiCipherCcmp ?? 'CCMP (AES) — Recommended default'),
      ),
      DropdownMenuItem(
        value: 'gcmp256',
        child: Text(
          l10n?.wifiCipherGcmp256 ?? 'GCMP-256 — High security / Wi-Fi 6',
        ),
      ),
      DropdownMenuItem(
        value: 'tkip',
        child: Text(l10n?.wifiCipherTkip ?? 'TKIP — Legacy (Not recommended)'),
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
