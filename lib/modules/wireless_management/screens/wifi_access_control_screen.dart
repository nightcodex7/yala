// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import '../models/wireless_info.dart';
import '../widgets/wireless_rollback_banner.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

class WifiAccessControlScreen extends ConsumerStatefulWidget {
  const WifiAccessControlScreen({super.key});

  @override
  ConsumerState<WifiAccessControlScreen> createState() =>
      _WifiAccessControlScreenState();
}

class _WifiAccessControlScreenState
    extends ConsumerState<WifiAccessControlScreen> {
  final TextEditingController _macController = TextEditingController();
  List<Client> _availableClients = [];
  Client? _selectedClient;
  bool _isLoadingClients = true;

  String _selectedMac = '';
  final Map<String, bool> _initialIfaceAllows = {};
  final Map<String, bool> _selectedIfaceAllows = {};
  String? _phoneMac;
  Client? _phoneClient;

  @override
  void initState() {
    super.initState();
    // Consume already-available cached client state immediately to eliminate loading lag
    final appState = ref.read(appStateProvider);
    final cachedClients = appState.clients;
    if (cachedClients.isNotEmpty) {
      _availableClients = cachedClients;
      _isLoadingClients = false;
    }
    _loadClients();
  }

  @override
  void dispose() {
    _macController.dispose();
    super.dispose();
  }

  // ... (keeping internal state methods)

  void _detectPhoneMac(List<Client> clients, [Set<String>? localAddresses]) {
    if (localAddresses == null || localAddresses.isEmpty) return;

    for (final c in clients) {
      final normMac = _normalizeMac(c.macAddress);
      final normIp = c.ipAddress.toLowerCase().trim();
      final hasMatchingIp =
          normIp.isNotEmpty &&
          normIp != 'n/a' &&
          localAddresses.contains(normIp);
      final hasMatchingIpv6 =
          c.ipv6Addresses?.any(
            (ip6) => localAddresses.contains(ip6.toLowerCase().trim()),
          ) ??
          false;
      final hasMatchingMac = localAddresses.any(
        (a) => SelfDeviceGuard.normalizeMac(a) == normMac,
      );

      if (hasMatchingIp || hasMatchingIpv6 || hasMatchingMac) {
        _phoneClient = c;
        _phoneMac = normMac;
        return;
      }
    }
  }

  bool _isPhoneConnectedToIface(WirelessInterface iface, String secName) {
    if (_phoneClient == null) return false;
    if (_phoneClient!.connectionType != ConnectionType.wireless) return false;
    if (!_phoneClient!.isConnected) return false;

    // 1. If phone's SSID is known, match against this interface's SSID
    if (_phoneClient!.ssid != null && _phoneClient!.ssid!.trim().isNotEmpty) {
      return _phoneClient!.ssid!.trim().toLowerCase() ==
          iface.ssid.trim().toLowerCase();
    }

    // 2. If phone's wireless interface name / section is known, match it
    if (_phoneClient!.wirelessIface != null &&
        _phoneClient!.wirelessIface!.trim().isNotEmpty) {
      final ifaceName = _phoneClient!.wirelessIface!.trim().toLowerCase();
      return ifaceName == iface.ifName.trim().toLowerCase() ||
          ifaceName == secName.trim().toLowerCase();
    }

    return false;
  }

  Future<void> _loadClients() async {
    final appState = ref.read(appStateProvider);
    try {
      final localAddressesFuture = SelfDeviceGuard.getLocalDeviceAddresses();
      final clientsFuture = appState.fetchAggregatedClients(
        onIncrementalUpdate: (incremental) {
          if (!mounted) return;
          if (incremental.isNotEmpty) {
            setState(() {
              _availableClients = incremental;
              if (_selectedClient != null) {
                final norm = _normalizeMac(_selectedClient!.macAddress);
                for (final c in incremental) {
                  if (_normalizeMac(c.macAddress) == norm) {
                    _selectedClient = c;
                    break;
                  }
                }
              }
              _isLoadingClients = false;
            });
          }
        },
      );
      final results = await Future.wait([localAddressesFuture, clientsFuture]);
      if (!mounted) return;
      final localAddresses = results[0] as Set<String>;
      final clients = results[1] as List<Client>;
      final effectiveClients = clients.isNotEmpty ? clients : _availableClients;
      setState(() {
        if (effectiveClients.isNotEmpty) {
          _availableClients = effectiveClients;
          if (_selectedClient != null) {
            final norm = _normalizeMac(_selectedClient!.macAddress);
            for (final c in effectiveClients) {
              if (_normalizeMac(c.macAddress) == norm) {
                _selectedClient = c;
                break;
              }
            }
          }
        }
        _isLoadingClients = false;
        _detectPhoneMac(_availableClients, localAddresses);
      });
    } catch (_) {
      if (!mounted) return;
      if (_availableClients.isEmpty) {
        setState(() {
          _isLoadingClients = false;
        });
      }
    }
  }

  String? _parseFlexibleMac(String input) {
    final trimmed = input.trim();
    final pairReg = RegExp(r'(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}');
    final matchPair = pairReg.firstMatch(trimmed);
    if (matchPair != null) {
      return matchPair.group(0)!.toUpperCase().replaceAll('-', ':');
    }

    final ciscoReg = RegExp(r'[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}');
    final matchCisco = ciscoReg.firstMatch(trimmed);
    if (matchCisco != null) {
      final cleaned = matchCisco.group(0)!.replaceAll('.', '');
      final sb = StringBuffer();
      for (int i = 0; i < 12; i += 2) {
        if (i > 0) sb.write(':');
        sb.write(cleaned.substring(i, i + 2).toUpperCase());
      }
      return sb.toString();
    }

    final raw12Reg = RegExp(r'\b[0-9a-fA-F]{12}\b');
    final match12 = raw12Reg.firstMatch(trimmed);
    if (match12 != null) {
      final cleaned = match12.group(0)!;
      final sb = StringBuffer();
      for (int i = 0; i < 12; i += 2) {
        if (i > 0) sb.write(':');
        sb.write(cleaned.substring(i, i + 2).toUpperCase());
      }
      return sb.toString();
    }

    return null;
  }

  String _normalizeMac(String mac) {
    final parsed = _parseFlexibleMac(mac);
    if (parsed != null) return parsed;
    return mac.trim().toUpperCase().replaceAll('-', ':');
  }

  bool _isValidMac(String mac) {
    final norm = _normalizeMac(mac);
    return RegExp(r'^([0-9A-FA-F]{2}:){5}[0-9A-FA-F]{2}$').hasMatch(norm);
  }

  void _onClientSelected(Client? client) {
    if (client == null) return;
    final norm = _normalizeMac(client.macAddress);
    setState(() {
      _selectedClient = client;
      _selectedMac = norm;
      _macController.text = norm;
    });
    _populateCurrentIfaceStates(norm);
  }

  void _onManualMacChanged(String val) {
    final norm = _normalizeMac(val);
    Client? match;
    for (final c in _availableClients) {
      if (_normalizeMac(c.macAddress) == norm) {
        match = c;
        break;
      }
    }
    setState(() {
      _selectedClient = match;
      _selectedMac = norm;
    });
    if (_isValidMac(norm)) {
      _populateCurrentIfaceStates(norm);
    } else {
      setState(() {
        _initialIfaceAllows.clear();
        _selectedIfaceAllows.clear();
      });
    }
  }

  Map<String, dynamic>? _findSecMap(dynamic rawUci, String secName) {
    if (rawUci == null) return null;

    if (rawUci is Map<String, dynamic>) {
      if (rawUci.containsKey(secName) &&
          rawUci[secName] is Map<String, dynamic>) {
        return rawUci[secName] as Map<String, dynamic>;
      }

      if (rawUci.containsKey('values') &&
          rawUci['values'] is Map<String, dynamic>) {
        final valuesMap = rawUci['values'] as Map<String, dynamic>;
        if (valuesMap.containsKey(secName) &&
            valuesMap[secName] is Map<String, dynamic>) {
          return valuesMap[secName] as Map<String, dynamic>;
        }
      }

      for (final entry in rawUci.entries) {
        final val = entry.value;
        if (val is Map<String, dynamic>) {
          if (entry.key == secName) return val;
          if (val['.name'] == secName || val['section'] == secName) return val;
          if (val['interfaces'] is List) {
            for (final ifc in val['interfaces']) {
              if (ifc is Map<String, dynamic>) {
                final cfg = ifc['config'] as Map<String, dynamic>?;
                if (ifc['section'] == secName ||
                    ifc['.name'] == secName ||
                    cfg?['.name'] == secName) {
                  return cfg ?? ifc;
                }
              }
            }
          }
        }
      }
    }
    return null;
  }

  void _populateCurrentIfaceStates(String targetMac) {
    final normTarget = _normalizeMac(targetMac);
    if (!_isValidMac(normTarget)) return;

    final appState = ref.read(appStateProvider);
    final overview = WirelessOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final rawUci =
        appState.dashboardData?['uciWirelessConfig'] ??
        appState.dashboardData?['wireless'];
    final newAllows = <String, bool>{};

    for (final radio in overview.radios) {
      for (final iface in radio.interfaces) {
        final secName = iface.sectionName;
        List<String> maclist = [];
        String filterMode = 'disable';

        final secMap = _findSecMap(rawUci, secName);
        if (secMap != null) {
          filterMode =
              secMap['macfilter']?.toString().toLowerCase() ?? 'disable';
          final rawList = secMap['maclist'];
          if (rawList is List) {
            maclist = rawList.map((e) => _normalizeMac(e.toString())).toList();
          } else if (rawList is String) {
            maclist = rawList
                .split(RegExp(r'\s+'))
                .map((e) => _normalizeMac(e))
                .toList();
          }
        }

        final inAllowList =
            (filterMode == 'allow') && maclist.contains(normTarget);
        newAllows[secName] = inAllowList;
      }
    }

    setState(() {
      _initialIfaceAllows.clear();
      _initialIfaceAllows.addAll(newAllows);
      _selectedIfaceAllows.clear();
      _selectedIfaceAllows.addAll(newAllows);
    });
  }

  bool get _hasChanges {
    if (!_isValidMac(_selectedMac)) return false;
    for (final entry in _selectedIfaceAllows.entries) {
      final initial = _initialIfaceAllows[entry.key] ?? false;
      if (entry.value != initial) return true;
    }
    return false;
  }

  int get _stagedChangesCount {
    int count = 0;
    for (final entry in _selectedIfaceAllows.entries) {
      final initial = _initialIfaceAllows[entry.key] ?? false;
      if (entry.value != initial) count++;
    }
    return count;
  }

  bool get _isNewClientRule {
    return !_initialIfaceAllows.values.any((v) => v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final overview = WirelessOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: !appState.isAccessControlPendingConfirmation,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canExit = await LuciGuardrail.confirmStagedChangesOrExit(
          context,
          appState,
        );
        if (canExit && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: LuciAppBar(
          title: l10n?.wifiAccessControlTitle ?? 'Wi-Fi Access Control',
          showBack: true,
        ),
        body: Column(
          children: [
            const WirelessRollbackBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 840),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeaderCard(context),
                        const SizedBox(height: 16),
                        _buildDeviceSelectionCard(context),
                        const SizedBox(height: 16),
                        if (_isValidMac(_selectedMac)) ...[
                          _buildStaticLeaseOptionCard(context, appState),
                          _buildAccessControlMatrix(
                            context,
                            overview,
                            appState,
                          ),
                          const SizedBox(height: 24),
                          _buildApplyButton(context, overview, appState),
                        ] else ...[
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.touch_app_rounded,
                                      size: 48,
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.4),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      l10n?.selectDevicePrompt ??
                                          'Select a device from the dropdown above or enter a valid MAC address to configure Wi-Fi access rules.',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.security_rounded,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n?.macAccessControlTitle ?? 'MAC Access Control',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n?.macAccessControlDesc ??
                        'Grant or deny wireless access for specific devices across SSIDs using MAC address filtering.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSelectionCard(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1. Select Target Device',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoadingClients)
              const Center(child: CircularProgressIndicator())
            else
              DropdownButtonFormField<Client>(
                initialValue: _selectedClient,
                hint: Text(
                  l10n?.wifiAclSelectClient ??
                      'Select a connected client device...',
                ),
                decoration: InputDecoration(
                  labelText: l10n?.clientsTitle ?? 'Connected Clients',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.devices_rounded),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                isExpanded: true,
                menuMaxHeight: 380,
                borderRadius: BorderRadius.circular(16),
                dropdownColor: theme.colorScheme.surfaceContainerHigh,
                elevation: 4,
                icon: const Icon(Icons.arrow_drop_down_rounded),
                selectedItemBuilder: (context) {
                  return _availableClients.map((c) {
                    final isWifi = c.connectionType == ConnectionType.wireless;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isWifi ? Icons.wifi_rounded : Icons.lan_outlined,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${c.displayName} (${c.macAddress})',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                },
                items: _availableClients.map((c) {
                  final isWifi = c.connectionType == ConnectionType.wireless;
                  return DropdownMenuItem<Client>(
                    value: c,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isWifi
                                  ? theme.colorScheme.primaryContainer
                                        .withValues(alpha: 0.6)
                                  : theme.colorScheme.secondaryContainer
                                        .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isWifi ? Icons.wifi_rounded : Icons.lan_outlined,
                              size: 18,
                              color: isWifi
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${c.displayName} (${c.macAddress})',
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (c.ipAddress.isNotEmpty &&
                                    c.ipAddress != 'N/A') ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    c.ipAddress,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (c.isDumbApClient) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                c.apName ?? 'AP',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: _onClientSelected,
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    'OR Manual Entry',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _macController,
              onChanged: _onManualMacChanged,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                TextInputFormatter.withFunction(
                  (oldValue, newValue) => TextEditingValue(
                    text: newValue.text.toUpperCase(),
                    selection: newValue.selection,
                  ),
                ),
              ],
              decoration: InputDecoration(
                labelText: 'MAC Address (XX:XX:XX:XX:XX:XX)',
                hintText: 'AA:BB:CC:11:22:33',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.fingerprint_rounded),
                errorText:
                    (_selectedMac.isNotEmpty && !_isValidMac(_selectedMac))
                    ? 'Enter valid MAC address format (e.g. AA:BB:CC:11:22:33)'
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaticLeaseOptionCard(BuildContext context, AppState appState) {
    final theme = Theme.of(context);
    final normMac = _normalizeMac(_selectedMac);

    final dhcpOverview = DhcpDnsOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    DhcpStaticMapping? existingMapping;
    for (final s in dhcpOverview.staticMappings) {
      if (_normalizeMac(s.macAddress) == normMac) {
        existingMapping = s;
        break;
      }
    }

    if (existingMapping != null) {
      final connectedColor = LuciStatusColors.connectedColor(context);
      return Card(
        color: connectedColor.withValues(alpha: 0.1),
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: connectedColor.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.push_pin, color: connectedColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Static Lease Active',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: connectedColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: connectedColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            existingMapping.ipAddress,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Custom DHCP Lease Name: ${existingMapping.hostname}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _showAddStaticLeaseDialog(
                  context,
                  normMac,
                  appState,
                  existingMapping: existingMapping,
                ),
                icon: const Icon(Icons.edit_rounded, size: 14),
                label: const Text(
                  'Edit Lease',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: connectedColor,
                  side: BorderSide(color: connectedColor),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.25),
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.push_pin_outlined,
              color: theme.colorScheme.tertiary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Static DHCP Reservation',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  Text(
                    'Optionally assign a custom DHCP lease name & fixed IP for $normMac.',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onTertiaryContainer.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  _showAddStaticLeaseDialog(context, normMac, appState),
              icon: const Icon(Icons.add, size: 14),
              label: const Text(
                'Add Static Lease',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.tertiary,
                side: BorderSide(color: theme.colorScheme.tertiary),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddStaticLeaseDialog(
    BuildContext context,
    String mac,
    AppState appState, {
    DhcpStaticMapping? existingMapping,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AddStaticLeaseDialog(
        macAddress: mac,
        existingMapping: existingMapping,
        client: _selectedClient,
        allClients: _availableClients,
        onSaved: () {
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  Widget _buildAccessControlMatrix(
    BuildContext context,
    WirelessOverview overview,
    AppState appState,
  ) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '2. Wi-Fi Allow Mode Rules for $_selectedMac',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Check SSIDs where this device should be explicitly allowed to connect.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ...overview.radios.map((radio) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${radio.name.toUpperCase()} (${radio.bandLabel})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...radio.interfaces.map((iface) {
                    final secName = iface.sectionName;
                    final isStagedAllowed =
                        _selectedIfaceAllows[secName] ?? false;
                    final isInitialAllowed =
                        _initialIfaceAllows[secName] ?? false;
                    final isStagedChanged = isStagedAllowed != isInitialAllowed;

                    final rawUci =
                        appState.dashboardData?['uciWirelessConfig'] ??
                        appState.dashboardData?['wireless'];
                    final secMap = _findSecMap(rawUci, secName);
                    final currentFilterMode =
                        secMap?['macfilter']?.toString().toLowerCase() ??
                        'disable';
                    List<String> currentMacList = [];
                    final rawList = secMap?['maclist'];
                    if (rawList is List) {
                      currentMacList = rawList
                          .map((e) => _normalizeMac(e.toString()))
                          .toList();
                    } else if (rawList is String) {
                      currentMacList = rawList
                          .split(RegExp(r'\s+'))
                          .map((e) => _normalizeMac(e))
                          .toList();
                    }

                    final normMac = _normalizeMac(_selectedMac);
                    final isCurrentlyInAllowList =
                        (currentFilterMode == 'allow') &&
                        currentMacList.contains(normMac);
                    final isCurrentlyInDenyList =
                        (currentFilterMode == 'deny') &&
                        currentMacList.contains(normMac);

                    // Real Current Status Badge (Accurate router policy)
                    Widget currentStatusChip;
                    if (isCurrentlyInAllowList) {
                      currentStatusChip = Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: LuciStatusColors.connectedColor(
                            context,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Current: Allowed',
                          style: TextStyle(
                            color: LuciStatusColors.connectedColor(context),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      );
                    } else if (isCurrentlyInDenyList) {
                      currentStatusChip = Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Current: Blocked',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      );
                    } else if (currentFilterMode == 'allow') {
                      currentStatusChip = Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Current: Restricted (Not in allow list)',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      );
                    } else if (currentFilterMode == 'deny') {
                      currentStatusChip = Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Current: Permitted (Not in deny list)',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      );
                    } else {
                      currentStatusChip = Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Current: Open (Filter disabled)',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      );
                    }

                    // Staged Change Indicator Chip (if user toggled checkbox)
                    Widget? stagedChip;
                    if (isStagedChanged) {
                      stagedChip = Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (isStagedAllowed
                                      ? Colors.teal
                                      : Colors.deepOrange)
                                  .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isStagedAllowed
                                ? Colors.teal
                                : Colors.deepOrange,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          isStagedAllowed
                              ? 'STAGED: Will Allow'
                              : 'STAGED: Will Remove',
                          style: TextStyle(
                            color: isStagedAllowed
                                ? Colors.teal.shade300
                                : Colors.deepOrange.shade300,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      );
                    }

                    return CheckboxListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      title: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            iface.ssid,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          currentStatusChip,
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(
                            'Interface: ${iface.ifName} ($secName)',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (stagedChip != null) ...[
                            const SizedBox(height: 4),
                            stagedChip,
                          ],
                        ],
                      ),
                      value: isStagedAllowed,
                      onChanged: (val) {
                        setState(() {
                          _selectedIfaceAllows[secName] = val ?? false;
                        });
                      },
                    );
                  }),
                  const SizedBox(height: 12),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildApplyButton(
    BuildContext context,
    WirelessOverview overview,
    AppState appState,
  ) {
    final hasChanges = _hasChanges;
    final isNewRule = _isNewClientRule;

    String buttonLabel;
    IconData buttonIcon;

    if (isNewRule) {
      if (!hasChanges) {
        buttonLabel = 'Select SSIDs to Add Access Rules';
        buttonIcon = Icons.add_moderator_outlined;
      } else {
        buttonLabel = 'Add Client Access Rules ($_stagedChangesCount SSIDs)';
        buttonIcon = Icons.add_moderator_rounded;
      }
    } else {
      if (!hasChanges) {
        buttonLabel = 'Apply Access Control Rules';
        buttonIcon = Icons.shield_outlined;
      } else {
        buttonLabel =
            'Apply Access Control Rules ($_stagedChangesCount changes)';
        buttonIcon = Icons.shield_rounded;
      }
    }

    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: hasChanges
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          foregroundColor: hasChanges
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        onPressed: hasChanges
            ? () => _handleApplyChanges(context, overview, appState)
            : null,
        icon: Icon(buttonIcon),
        label: Text(
          buttonLabel,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _handleApplyChanges(
    BuildContext context,
    WirelessOverview overview,
    AppState appState,
  ) async {
    final l10n = AppLocalizations.of(context);
    final targetMac = _normalizeMac(_selectedMac);
    if (!_isValidMac(targetMac)) return;

    final rawUci =
        appState.dashboardData?['uciWirelessConfig'] ??
        appState.dashboardData?['wireless'];

    // Construct prior snapshots & new payload map
    final priorMaclistSnapshot = <String, List<String>>{};
    final priorMacfilterSnapshot = <String, String>{};

    final newMaclistByIface = <String, List<String>>{};
    final newMacfilterByIface = <String, String>{};

    final affectedSsids = <String>[];
    bool phoneLockoutRisk = false;

    for (final radio in overview.radios) {
      for (final iface in radio.interfaces) {
        final secName = iface.sectionName;
        List<String> currentMaclist = [];
        String currentFilterMode = 'disable';

        final secMap = _findSecMap(rawUci, secName);
        if (secMap != null) {
          currentFilterMode =
              secMap['macfilter']?.toString().toLowerCase() ?? 'disable';
          final rawList = secMap['maclist'];
          if (rawList is List) {
            currentMaclist = rawList
                .map((e) => _normalizeMac(e.toString()))
                .toList();
          } else if (rawList is String) {
            currentMaclist = rawList
                .split(RegExp(r'\s+'))
                .map((e) => _normalizeMac(e))
                .toList();
          }
        }

        priorMaclistSnapshot[secName] = List.from(currentMaclist);
        priorMacfilterSnapshot[secName] = currentFilterMode;

        final shouldAllow = _selectedIfaceAllows[secName] ?? false;
        final updatedMaclist = List<String>.from(currentMaclist);
        final isPhoneOnThisIface = _isPhoneConnectedToIface(iface, secName);

        if (shouldAllow) {
          if (!updatedMaclist.contains(targetMac)) {
            updatedMaclist.add(targetMac);
          }
          newMacfilterByIface[secName] = 'allow';
          newMaclistByIface[secName] = updatedMaclist;
          affectedSsids.add('${iface.ssid} (${radio.name})');

          // Check phone lockout risk: ONLY if the managing device is actively connected
          // to this wireless interface, and the new allowlist will exclude the managing device!
          if (isPhoneOnThisIface &&
              _phoneMac != null &&
              _phoneMac!.isNotEmpty &&
              !updatedMaclist.contains(_phoneMac)) {
            phoneLockoutRisk = true;
          }
        } else {
          updatedMaclist.remove(targetMac);
          newMaclistByIface[secName] = updatedMaclist;
          if (updatedMaclist.isEmpty) {
            newMacfilterByIface[secName] = 'disable';
          } else {
            newMacfilterByIface[secName] = 'allow';
            // If managing device is on this interface, and user explicitly removed the managing device
            // from the allowlist while the interface remains in allow mode:
            if (isPhoneOnThisIface &&
                _phoneMac != null &&
                targetMac == _phoneMac &&
                !updatedMaclist.contains(_phoneMac)) {
              phoneLockoutRisk = true;
            }
          }
        }
      }
    }

    // Phone Lockout Warning Dialog
    if (phoneLockoutRisk && context.mounted) {
      final addPhone = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(ctx).colorScheme.error,
            size: 40,
          ),
          title: Text(l10n?.wifiAclLockoutWarning ?? 'Device Lockout Warning'),
          content: Text(
            'You have not added this device (${_phoneMac ?? "current phone"}) to the allow-list for affected SSIDs. Enabling this filter may disconnect you from this network.',
          ),
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                l10n?.wifiAclProceedWithoutPhone ?? 'Proceed Without Phone',
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add_link_rounded),
              label: Text(l10n?.wifiAclAddMyDevice ?? 'Add My Current Device'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );

      if (addPhone == true && _phoneMac != null) {
        for (final secName in newMaclistByIface.keys) {
          if (newMacfilterByIface[secName] == 'allow') {
            if (!newMaclistByIface[secName]!.contains(_phoneMac!)) {
              newMaclistByIface[secName]!.add(_phoneMac!);
            }
          }
        }
      }
    }

    // Final Confirmation Dialog
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.verified_user_rounded,
          color: Theme.of(ctx).colorScheme.primary,
          size: 36,
        ),
        title: Text(
          l10n?.wifiAclConfirmRulesTitle ?? 'Confirm Wi-Fi Access Rules',
        ),
        content: SingleChildScrollView(
          child: Text(
            'Updating Wi-Fi Access Control for $targetMac on SSIDs:\n\n'
            '${affectedSsids.isNotEmpty ? affectedSsids.join('\n') : "All (Disabled)"}\n\n'
            'Note: This affects $targetMac specifically.',
          ),
        ),
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n?.wifiAclApplyChanges ?? 'Apply Changes'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final actionKey = 'wifi_access_control_$targetMac';
      context.showToastLoading(
        'Applying Wi-Fi Access Control changes...',
        actionKey: actionKey,
      );

      final success = await appState.applyWifiAccessControl(
        newMaclistByIface: newMaclistByIface,
        newMacfilterByIface: newMacfilterByIface,
        priorMaclistSnapshot: priorMaclistSnapshot,
        priorMacfilterSnapshot: priorMacfilterSnapshot,
        context: context,
      );

      if (success) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
        if (context.mounted) {
          LuciToastManager.safeShowSuccess(
            context,
            'Access Control applied.',
            subtitle:
                l10n?.wifiAccessRulesUpdatedToast ??
                'Wi-Fi access rules updated successfully.',
            actionKey: actionKey,
          );
        }
      } else {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
        if (context.mounted) {
          LuciToastManager.safeShowError(
            context,
            'Failed to apply Wi-Fi Access Control rules.',
            actionKey: actionKey,
          );
        }
      }
    }
  }
}
