// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import '../models/wireless_info.dart';

/// Dialog providing live-validated configuration controls for physical wireless radios (radio0, radio1)
/// with dynamic hardware capability filtering, role-based ACL permission checking, and atomic UCI committing.
class EditRadioDialog extends ConsumerStatefulWidget {
  final WirelessRadio radio;

  const EditRadioDialog({super.key, required this.radio});

  @override
  ConsumerState<EditRadioDialog> createState() => _EditRadioDialogState();
}

class _EditRadioDialogState extends ConsumerState<EditRadioDialog> {
  final _formKey = GlobalKey<FormState>();

  late bool _isDisabled;
  late String _selectedChannel;
  late String _selectedHtMode;
  late String _selectedTxPower;
  late String _selectedCountry;

  bool _isSubmitting = false;
  bool _isPrefetching = false;
  List<Map<String, String>> _dynamicCountryCodes = [];
  List<String> _dynamicChannels = [];
  List<String> _dynamicHtModes = [];
  List<String> _dynamicTxPowers = [];

  @override
  void initState() {
    super.initState();
    final radio = widget.radio;
    _selectedCountry = radio.country.toUpperCase();
    if (_selectedCountry.isEmpty) _selectedCountry = '00';
    _isDisabled = radio.isDisabled;
    _selectedChannel = radio.channel;
    _selectedHtMode = radio.htMode ?? _defaultHtModeForBand(radio.bandLabel);
    _selectedTxPower = radio.txPowerDbm?.toString() ?? 'auto';
    _prefetchRadioCapabilities();
  }

  Future<void> _prefetchRadioCapabilities() async {
    setState(() => _isPrefetching = true);
    try {
      final appState = ref.read(appStateProvider);
      final caps = await appState.fetchWirelessRadioCapabilities(
        radioName: widget.radio.name,
        context: context,
      );
      if (!mounted) return;
      setState(() {
        final cCodes = caps['countryCodes'];
        if (cCodes is List && cCodes.isNotEmpty) {
          _dynamicCountryCodes = List<Map<String, String>>.from(
            cCodes.map((e) => Map<String, String>.from(e as Map)),
          );
        }
        final chs = caps['channels'];
        if (chs is List && chs.isNotEmpty) {
          _dynamicChannels = List<String>.from(chs.map((e) => e.toString()));
        }
        final hts = caps['htModes'];
        if (hts is List && hts.isNotEmpty) {
          _dynamicHtModes = List<String>.from(hts.map((e) => e.toString()));
        }
        final txs = caps['txPowers'];
        if (txs is List && txs.isNotEmpty) {
          _dynamicTxPowers = List<String>.from(txs.map((e) => e.toString()));
        }
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isPrefetching = false);
    }
  }

  String _defaultHtModeForBand(String bandLabel) {
    if (bandLabel.contains('5 GHz') || bandLabel.contains('6 GHz')) {
      return 'VHT80';
    }
    return 'HT20';
  }

  bool _hasChanges() {
    final radio = widget.radio;
    final initCountry = radio.country.toUpperCase().isEmpty
        ? '00'
        : radio.country.toUpperCase();
    final initChannel = radio.channel;
    final initHtMode = radio.htMode ?? _defaultHtModeForBand(radio.bandLabel);
    final initTxPower = radio.txPowerDbm?.toString() ?? 'auto';
    if (_isDisabled != radio.isDisabled) return true;
    if (_selectedChannel != initChannel) return true;
    if (_selectedHtMode != initHtMode) return true;
    if (_selectedTxPower != initTxPower) return true;
    if (_selectedCountry != initCountry) return true;
    return false;
  }

  List<Map<String, String>> _getAvailableCountryCodes() {
    final list = _dynamicCountryCodes.isNotEmpty
        ? List<Map<String, String>>.from(_dynamicCountryCodes)
        : _getCuratedCountryCodes();

    if (!list.any((item) => item['code'] == _selectedCountry)) {
      list.insert(0, {
        'code': _selectedCountry,
        'label': '$_selectedCountry — Router Active Domain',
      });
    }
    return list;
  }

  List<Map<String, String>> _getCuratedCountryCodes() {
    return <Map<String, String>>[
      {'code': '00', 'label': '00 — World / Global (Universal)'},
      {'code': 'US', 'label': 'US — United States'},
      {'code': 'DE', 'label': 'DE — Germany'},
      {'code': 'GB', 'label': 'GB — United Kingdom'},
      {'code': 'IN', 'label': 'IN — India'},
      {'code': 'JP', 'label': 'JP — Japan'},
      {'code': 'CA', 'label': 'CA — Canada'},
      {'code': 'AU', 'label': 'AU — Australia'},
      {'code': 'BR', 'label': 'BR — Brazil'},
      {'code': 'CN', 'label': 'CN — China'},
      {'code': 'FR', 'label': 'FR — France'},
      {'code': 'IT', 'label': 'IT — Italy'},
      {'code': 'ES', 'label': 'ES — Spain'},
      {'code': 'KR', 'label': 'KR — South Korea'},
      {'code': 'NL', 'label': 'NL — Netherlands'},
      {'code': 'PL', 'label': 'PL — Poland'},
      {'code': 'SE', 'label': 'SE — Sweden'},
      {'code': 'TW', 'label': 'TW — Taiwan'},
      {'code': 'NZ', 'label': 'NZ — New Zealand'},
      {'code': 'SG', 'label': 'SG — Singapore'},
      {'code': 'HK', 'label': 'HK — Hong Kong'},
      {'code': 'MX', 'label': 'MX — Mexico'},
      {'code': 'AR', 'label': 'AR — Argentina'},
      {'code': 'CL', 'label': 'CL — Chile'},
      {'code': 'ZA', 'label': 'ZA — South Africa'},
      {'code': 'TH', 'label': 'TH — Thailand'},
      {'code': 'VN', 'label': 'VN — Vietnam'},
      {'code': 'ID', 'label': 'ID — Indonesia'},
      {'code': 'MY', 'label': 'MY — Malaysia'},
      {'code': 'PH', 'label': 'PH — Philippines'},
      {'code': 'AE', 'label': 'AE — United Arab Emirates'},
      {'code': 'SA', 'label': 'SA — Saudi Arabia'},
      {'code': 'IL', 'label': 'IL — Israel'},
      {'code': 'TR', 'label': 'TR — Turkey'},
      {'code': 'CH', 'label': 'CH — Switzerland'},
      {'code': 'AT', 'label': 'AT — Austria'},
      {'code': 'BE', 'label': 'BE — Belgium'},
      {'code': 'DK', 'label': 'DK — Denmark'},
      {'code': 'FI', 'label': 'FI — Finland'},
      {'code': 'NO', 'label': 'NO — Norway'},
      {'code': 'IE', 'label': 'IE — Ireland'},
      {'code': 'PT', 'label': 'PT — Portugal'},
      {'code': 'CZ', 'label': 'CZ — Czech Republic'},
      {'code': 'HU', 'label': 'HU — Hungary'},
      {'code': 'RO', 'label': 'RO — Romania'},
      {'code': 'GR', 'label': 'GR — Greece'},
    ];
  }

  List<String> _getAvailableChannels() {
    final channels = <String>[];
    if (_dynamicChannels.isNotEmpty) {
      channels.addAll(_dynamicChannels);
    } else {
      final band = widget.radio.bandLabel;
      if (band.contains('5 GHz') || band.contains('6 GHz')) {
        channels.addAll([
          'auto',
          '36',
          '40',
          '44',
          '48',
          '52',
          '56',
          '60',
          '64',
          '100',
          '104',
          '108',
          '112',
          '116',
          '120',
          '124',
          '128',
          '132',
          '136',
          '140',
          '144',
          '149',
          '153',
          '157',
          '161',
          '165',
        ]);
      } else {
        channels.addAll([
          'auto',
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
          '10',
          '11',
          '12',
          '13',
          '14',
        ]);
      }
    }

    if (!channels.contains(_selectedChannel)) {
      channels.insert(0, _selectedChannel);
    }
    return channels;
  }

  /// Validate channel against country code
  bool _isValidChannelForCountry(int channel, String countryCode) {
    final validChannels = widget.radio.getValidChannelsForBand(
      countryCode: countryCode.toUpperCase(),
    );
    return validChannels.contains(channel);
  }

  /// Get channel validation message
  String? _getChannelValidationMessage() {
    final countryCode = _selectedCountry;
    if (countryCode.isEmpty || _selectedChannel == 'auto') return null;

    final channel = int.tryParse(_selectedChannel);
    if (channel == null) return null;

    if (!_isValidChannelForCountry(channel, countryCode)) {
      final validChannels = widget.radio.getValidChannelsForBand(
        countryCode: countryCode,
      );
      return 'Channel $_selectedChannel is not valid for country $countryCode. Valid channels: ${validChannels.join(', ')}';
    }
    return null;
  }

  List<String> _getAvailableHtModes() {
    final htModes = <String>[];
    if (_dynamicHtModes.isNotEmpty) {
      htModes.addAll(_dynamicHtModes);
    } else if (widget.radio.supportedHtModes.isNotEmpty) {
      htModes.addAll(widget.radio.supportedHtModes);
    } else {
      final band = widget.radio.bandLabel;
      if (band.contains('5 GHz') || band.contains('6 GHz')) {
        htModes.addAll([
          'HT20',
          'HT40',
          'VHT20',
          'VHT40',
          'VHT80',
          'VHT160',
          'HE20',
          'HE40',
          'HE80',
          'HE160',
          'EHT320',
        ]);
      } else {
        htModes.addAll(['HT20', 'HT40']);
      }
    }

    if (!htModes.contains(_selectedHtMode)) {
      htModes.insert(0, _selectedHtMode);
    }
    return htModes;
  }

  List<String> _getAvailableTxPowers() {
    final txPowers = <String>[];
    if (_dynamicTxPowers.isNotEmpty) {
      txPowers.addAll(_dynamicTxPowers);
    } else {
      txPowers.addAll(['auto', '30', '23', '20', '17', '14', '10']);
    }
    if (!txPowers.contains(_selectedTxPower)) {
      txPowers.insert(1, _selectedTxPower);
    }
    return txPowers;
  }

  Future<void> _submitChanges() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate channel against country
    final channelValidation = _getChannelValidationMessage();
    if (channelValidation != null) {
      if (!mounted) return;
      final proceed = await LuciGuardrail.showConfirmation(
        context,
        title: 'Invalid Channel for Country',
        subtitle: channelValidation,
        confirmLabel: 'Proceed Anyway',
        cancelLabel: 'Cancel',
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.orange,
      );
      if (!proceed) return;
    }

    final appState = ref.read(appStateProvider);
    final radio = widget.radio;

    if (_isDisabled && !radio.isDisabled) {
      final activeMac = appState.dashboardData?['activeSessionMac']
          ?.toString()
          .toUpperCase();
      bool hasActiveSessionOnRadio = false;
      for (final iface in radio.interfaces) {
        for (final st in iface.stations) {
          if (st.macAddress.toUpperCase() == activeMac) {
            hasActiveSessionOnRadio = true;
            break;
          }
        }
      }

      if (hasActiveSessionOnRadio) {
        if (!mounted) return;
        final proceed = await LuciGuardrail.showConfirmation(
          context,
          title: 'Disabling Active Radio',
          subtitle:
              'Disabling physical radio "${radio.name}" will turn off all wireless networks hosted on it and disconnect your active session.',
          confirmLabel: 'Proceed & Disable',
          cancelLabel: 'Cancel',
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.orange,
          isDestructive: true,
        );
        if (!proceed) return;
      }
    }

    if (!mounted) return;
    setState(() => _isSubmitting = true);

    final newValues = <String, String>{
      'disabled': _isDisabled ? '1' : '0',
      'channel': _selectedChannel,
      'htmode': _selectedHtMode,
      'txpower': _selectedTxPower,
      'country': _selectedCountry,
    };

    final priorSnapshot = <String, String>{
      'disabled': radio.isDisabled ? '1' : '0',
      'channel': radio.channel,
      'htmode': radio.htMode ?? 'HT20',
      'txpower': radio.txPowerDbm?.toString() ?? 'auto',
      'country': radio.country,
    };

    final success = await appState.applyWirelessRadioConfig(
      sectionName: radio.name,
      newValues: newValues,
      priorValuesSnapshot: priorSnapshot,
      targetRadio: radio,
      context: context,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        Navigator.pop(context, true);
        context.showToastSuccess('Radio settings applied directly to router.');
      } else {
        final username = appState.sessionUsername;
        if ((appState.capabilities?.hasUciWriteAccess ?? true) == false ||
            !appState.isAdministrativeUser) {
          context.showToastError(
            'Access Denied: Account \'$username\' lacks ubus UCI write authorization.',
          );
        } else {
          context.showToastError('Failed to apply radio settings to router.');
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

    final channels = _getAvailableChannels();
    final htModes = _getAvailableHtModes();
    final txPowers = _getAvailableTxPowers();
    final countryCodes = _getAvailableCountryCodes();

    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.router_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Edit Physical Radio (${widget.radio.name})',
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
                if (_isPrefetching) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                ],
                // ACL & User Authorization Warning Banner
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

                // Safety Warning Banner
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

                // Radio Hardware Enabled Switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Radio Enabled',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Physical ${widget.radio.bandLabel} wireless transceivers',
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: !_isDisabled,
                  onChanged: (enabled) =>
                      setState(() => _isDisabled = !enabled),
                ),
                const SizedBox(height: 12),

                // Operating Channel Selection
                DropdownButtonFormField<String>(
                  initialValue: _selectedChannel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Operating Channel',
                    prefixIcon: Icon(Icons.cell_tower_rounded, size: 20),
                    border: OutlineInputBorder(),
                  ),
                  items: channels.map((ch) {
                    return DropdownMenuItem(
                      value: ch,
                      child: Text(
                        ch == 'auto' ? 'Auto (ACS)' : 'Channel $ch',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedChannel = val);
                  },
                ),
                const SizedBox(height: 16),

                // Channel Width / HT Mode Selection
                DropdownButtonFormField<String>(
                  initialValue: _selectedHtMode,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Channel Width / HT Mode',
                    helperText: widget.radio.supportedHtModes.isNotEmpty
                        ? 'Modes reported by physical driver'
                        : null,
                    prefixIcon: const Icon(Icons.swap_calls_rounded, size: 20),
                    border: const OutlineInputBorder(),
                  ),
                  items: htModes.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(
                        mode,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedHtMode = val);
                  },
                ),
                const SizedBox(height: 16),

                // Transmit Power Dropdown
                DropdownButtonFormField<String>(
                  initialValue: _selectedTxPower,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Transmit Power (Tx Power)',
                    prefixIcon: Icon(Icons.bolt_rounded, size: 20),
                    border: OutlineInputBorder(),
                  ),
                  items: txPowers.map((tx) {
                    String label = tx == 'auto'
                        ? 'Auto (Maximum Allowed)'
                        : '$tx dBm';
                    if (tx == '30') label += ' (1000 mW)';
                    if (tx == '23') label += ' (200 mW)';
                    if (tx == '20') label += ' (100 mW)';
                    if (tx == '17') label += ' (50 mW)';
                    if (tx == '14') label += ' (25 mW)';
                    if (tx == '10') label += ' (10 mW)';
                    return DropdownMenuItem(
                      value: tx,
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedTxPower = val);
                  },
                ),
                const SizedBox(height: 16),

                // Country Code Dropdown
                DropdownButtonFormField<String>(
                  initialValue: _selectedCountry,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Country Code (Regulatory Domain)',
                    prefixIcon: const Icon(Icons.public_rounded, size: 20),
                    border: const OutlineInputBorder(),
                    helperText:
                        _getChannelValidationMessage() ??
                        'Regulatory domain options reported by router',
                    errorText: _getChannelValidationMessage(),
                  ),
                  items: countryCodes.map((item) {
                    return DropdownMenuItem<String>(
                      value: item['code']!,
                      child: Text(
                        item['label']!,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedCountry = val);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: (_isSubmitting || !_hasChanges())
                ? null
                : _submitChanges,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_user_rounded, size: 18),
            label: Text(
              hasUciWrite ? 'Save & Apply' : 'Attempt Save (Non-Root)',
            ),
          ),
        ],
      ),
    );
  }
}
