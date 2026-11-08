// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/widgets/luci_animation_system.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

class RouterDashboardSettingsScreen extends ConsumerStatefulWidget {
  final String routerId;
  const RouterDashboardSettingsScreen({super.key, required this.routerId});

  @override
  ConsumerState<RouterDashboardSettingsScreen> createState() =>
      _RouterDashboardSettingsScreenState();
}

class _RouterDashboardSettingsScreenState
    extends ConsumerState<RouterDashboardSettingsScreen> {
  late DashboardPreferences _preferences;
  bool _isLoading = true;
  String? _errorMessage;
  final Set<String> _availableWirelessInterfaces = {};
  final Set<String> _availableWiredInterfaces = {};
  final List<String> _allInterfaces = [];
  Timer? _autoSaveTimer;

  static const Map<String, ({String name, IconData icon, String desc})>
  _cardMeta = {
    'quick_actions': (
      name: 'Quick Actions Bar',
      icon: Icons.flash_on,
      desc:
          'Shortcuts for reboot, flush DNS cache, guest Wi-Fi, VPNs & refresh',
    ),
    'device_info': (
      name: 'Device Info & Firmware',
      icon: Icons.router,
      desc: 'Hardware model, system uptime, and OpenWrt release information',
    ),
    'realtime_traffic': (
      name: 'Real-time Network Traffic',
      icon: Icons.swap_vert,
      desc:
          'Live upload/download speed graph and context-aware interface throughput',
    ),
    'system_vitals': (
      name: 'System Vitals',
      icon: Icons.monitor_heart,
      desc: 'CPU load, RAM memory usage, load average, and system uptime stats',
    ),
    'connected_clients': (
      name: 'Connected Clients Overview',
      icon: Icons.devices,
      desc: 'Wired and wireless connected client device counts & MAC info',
    ),
    'wireless_networks': (
      name: 'Wireless Radios & SSIDs',
      icon: Icons.wifi,
      desc:
          'Wi-Fi channels, signal quality, encryption, and associated stations',
    ),
    'network_interfaces': (
      name: 'Network Interfaces',
      icon: Icons.lan,
      desc:
          'WAN/LAN IP addresses, RX/TX transfer stats, subnets & bridge devices',
    ),
    'system_modules': (
      name: 'System Modules & Storage',
      icon: Icons.storage,
      desc:
          'Storage overview, filesystem usage, and dynamic service status cards',
    ),
  };

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 300), () async {
      final appState = ref.read(appStateProvider);
      try {
        await appState.saveDashboardPreferences(_preferences);
      } catch (_) {}
    });
  }

  @override
  void initState() {
    super.initState();
    final appState = ref.read(appStateProvider);
    final current = appState.selectedRouter?.id;
    Future(() async {
      if (current != widget.routerId) {
        await appState.selectRouter(widget.routerId);
      }
      await _loadPreferences();
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final appState = ref.read(appStateProvider);
      if (appState.dashboardData == null) {
        await appState.fetchDashboardData();
      }
      if (appState.dashboardData == null) {
        setState(() {
          _errorMessage =
              'Unable to load dashboard data. Please check your connection.';
          _isLoading = false;
        });
        return;
      }
      _preferences = appState.dashboardPreferences;
      _extractAvailableInterfaces(appState.dashboardData);
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load settings: $e';
        _isLoading = false;
      });
    }
  }

  void _extractAvailableInterfaces(Map<String, dynamic>? dashboardData) {
    if (dashboardData == null) return;

    final wirelessRadios = dashboardData['wireless'] as Map<String, dynamic>?;
    if (wirelessRadios != null) {
      wirelessRadios.forEach((radioName, radioData) {
        final rawIfaces = radioData['interfaces'];
        final interfaces = rawIfaces is List
            ? rawIfaces
            : (rawIfaces is Map ? rawIfaces.values.toList() : null);
        if (interfaces != null) {
          for (var interface in interfaces) {
            final config = interface['config'] ?? {};
            final iwinfo = interface['iwinfo'] ?? {};
            final ssid = iwinfo['ssid'] ?? config['ssid'];
            final deviceName = config['device'] ?? radioName;
            if (ssid != null && ssid.toString().isNotEmpty) {
              final interfaceId = '$ssid ($deviceName)';
              _availableWirelessInterfaces.add(interfaceId);
              _allInterfaces.add(interfaceId);
            }
          }
        }
      });
    }

    final rawDump = dashboardData['interfaceDump']?['interface'];
    final interfaces = rawDump is List
        ? rawDump
        : (rawDump is Map ? rawDump.values.toList() : null);
    if (interfaces != null) {
      for (var item in interfaces) {
        final interface = item as Map<String, dynamic>;
        final name = interface['interface'] as String? ?? '';
        if (name.isNotEmpty && name != 'loopback' && name != 'lo') {
          _availableWiredInterfaces.add(name);
          _allInterfaces.add(name);
        }
      }
    }
    _allInterfaces.sort();
  }

  void _onPreferenceChanged() => _scheduleAutoSave();

  Widget _buildSection({
    required String title,
    required String subtitle,
    required List<Widget> children,
    IconData? icon,
    bool initiallyExpanded = false,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: icon != null
              ? Icon(icon, color: Theme.of(context).colorScheme.primary)
              : null,
          title: Text(title, style: LuciTextStyles.cardTitle(context)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(subtitle, style: LuciTextStyles.cardSubtitle(context)),
          ),
          initiallyExpanded: initiallyExpanded,
          shape: RoundedRectangleBorder(
            borderRadius: LuciCardStyles.standardRadius,
          ),
          childrenPadding: const EdgeInsets.symmetric(
            horizontal: LuciSpacing.md,
            vertical: LuciSpacing.sm,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildCardOrderSection() {
    final l10n = AppLocalizations.of(context);
    final cardOrder = List<String>.from(_preferences.cardOrder);
    return _buildSection(
      title: l10n?.rdSettingsCardLayoutVisibility ?? 'Card Layout & Visibility',
      subtitle:
          l10n?.rdSettingsCardLayoutSubtitle ??
          'Drag handle to reorder dashboard cards or toggle switch to show/hide sections',
      icon: Icons.dashboard_customize,
      initiallyExpanded: true,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n?.rdSettingsDashboardCards ?? 'Dashboard Cards',
              style: LuciTextStyles.detailValue(
                context,
              ).copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _preferences = _preferences.copyWith(
                    cardOrder: List.from(DashboardPreferences.defaultCardOrder),
                    showQuickActions: false,
                    showDeviceInfo: true,
                    showRealtimeTraffic: true,
                    showSystemVitals: true,
                    showConnectedClients: true,
                    showWirelessNetworks: true,
                    showNetworkInterfaces: true,
                    showSystemModules: true,
                  );
                });
                _onPreferenceChanged();
              },
              icon: const Icon(Icons.restore, size: 16),
              label: Text(l10n?.rdSettingsResetLayout ?? 'Reset Layout'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cardOrder.length,
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              final item = cardOrder.removeAt(oldIndex);
              cardOrder.insert(newIndex, item);
              _preferences = _preferences.copyWith(cardOrder: cardOrder);
            });
            _onPreferenceChanged();
          },
          itemBuilder: (context, index) {
            final cardId = cardOrder[index];
            final meta =
                _cardMeta[cardId] ??
                (
                  name: cardId,
                  icon: Icons.dashboard,
                  desc: 'Dashboard section',
                );

            final isVisible = _preferences.isSectionVisible(cardId);
            final l10n = AppLocalizations.of(context);
            String localizedCardName() {
              switch (cardId) {
                case 'quick_actions':
                  return l10n?.cardQuickActions ?? meta.name;
                case 'device_info':
                  return l10n?.cardDeviceInfo ?? meta.name;
                case 'realtime_traffic':
                  return l10n?.cardRealtimeTraffic ?? meta.name;
                case 'system_vitals':
                  return l10n?.cardSystemVitals ?? meta.name;
                case 'connected_clients':
                  return l10n?.cardConnectedClients ?? meta.name;
                case 'wireless_networks':
                  return l10n?.cardWirelessRadios ?? meta.name;
                case 'network_interfaces':
                  return l10n?.cardNetworkInterfaces ?? meta.name;
                case 'system_modules':
                  return l10n?.cardSystemModules ?? meta.name;
                default:
                  return meta.name;
              }
            }

            String localizedCardDesc() {
              switch (cardId) {
                case 'quick_actions':
                  return l10n?.cardQuickActionsDesc ?? meta.desc;
                case 'device_info':
                  return l10n?.cardDeviceInfoDesc ?? meta.desc;
                case 'realtime_traffic':
                  return l10n?.cardRealtimeTrafficDesc ?? meta.desc;
                case 'system_vitals':
                  return l10n?.cardSystemVitalsDesc ?? meta.desc;
                case 'connected_clients':
                  return l10n?.cardConnectedClientsDesc ?? meta.desc;
                case 'wireless_networks':
                  return l10n?.cardWirelessRadiosDesc ?? meta.desc;
                case 'network_interfaces':
                  return l10n?.cardNetworkInterfacesDesc ?? meta.desc;
                case 'system_modules':
                  return l10n?.cardSystemModulesDesc ?? meta.desc;
                default:
                  return meta.desc;
              }
            }

            return Container(
              key: ValueKey(cardId),
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: isVisible ? 0.35 : 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isVisible
                      ? Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.5)
                      : Colors.transparent,
                ),
              ),
              child: ListTile(
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.drag_indicator,
                      color: Theme.of(context).colorScheme.outline,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      meta.icon,
                      color: isVisible
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                      size: 20,
                    ),
                  ],
                ),
                title: Text(
                  localizedCardName(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isVisible
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
                subtitle: Text(
                  localizedCardDesc(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
                trailing: Switch.adaptive(
                  value: isVisible,
                  onChanged: (val) {
                    setState(() {
                      switch (cardId) {
                        case 'quick_actions':
                          _preferences = _preferences.copyWith(
                            showQuickActions: val,
                          );
                          break;
                        case 'device_info':
                          _preferences = _preferences.copyWith(
                            showDeviceInfo: val,
                          );
                          break;
                        case 'realtime_traffic':
                          _preferences = _preferences.copyWith(
                            showRealtimeTraffic: val,
                          );
                          break;
                        case 'system_vitals':
                          _preferences = _preferences.copyWith(
                            showSystemVitals: val,
                          );
                          break;
                        case 'connected_clients':
                          _preferences = _preferences.copyWith(
                            showConnectedClients: val,
                          );
                          break;
                        case 'wireless_networks':
                          _preferences = _preferences.copyWith(
                            showWirelessNetworks: val,
                          );
                          break;
                        case 'network_interfaces':
                          _preferences = _preferences.copyWith(
                            showNetworkInterfaces: val,
                          );
                          break;
                        case 'system_modules':
                          _preferences = _preferences.copyWith(
                            showSystemModules: val,
                          );
                          break;
                      }
                    });
                    _onPreferenceChanged();
                  },
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                  activeThumbColor: Colors.white,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionsSection() {
    final l10n = AppLocalizations.of(context);
    final actions = [
      (
        id: 'reboot',
        title: l10n?.rdSettingsRebootRouterTitle ?? 'Reboot Router',
        icon: Icons.restart_alt,
        desc:
            l10n?.rdSettingsRebootRouterDesc ??
            'Quick restart trigger with confirmation',
      ),
      (
        id: 'flush_dns',
        title: l10n?.rdSettingsFlushDns ?? 'Flush DNS Cache',
        icon: Icons.cleaning_services,
        desc:
            l10n?.rdSettingsFlushDnsDesc ??
            'Restart dnsmasq to clear DNS resolver cache',
      ),
      (
        id: 'guest_wifi',
        title: l10n?.rdSettingsGuestWifiShortcut ?? 'Guest Wi-Fi Shortcut',
        icon: Icons.wifi_tethering,
        desc:
            l10n?.rdSettingsGuestWifiShortcutDesc ??
            'Jump to guest Wi-Fi management',
      ),
      (
        id: 'vpn',
        title: l10n?.rdSettingsVpnShortcut ?? 'VPN Management Shortcut',
        icon: Icons.vpn_key,
        desc:
            l10n?.rdSettingsVpnShortcutDesc ??
            'Jump to VPN configuration & status',
      ),
      (
        id: 'refresh',
        title: l10n?.rdSettingsRefreshBtn ?? 'Refresh Data Button',
        icon: Icons.refresh,
        desc:
            l10n?.rdSettingsRefreshBtnDesc ?? 'Force reload dashboard metrics',
      ),
    ];

    return _buildSection(
      title: l10n?.rdSettingsQuickActions ?? 'Quick Action Shortcuts',
      subtitle:
          l10n?.rdSettingsQuickActionsSubtitle ??
          'Select shortcut action buttons (Reboot, Flush DNS, Guest Wi-Fi, VPN, Refresh) for your dashboard',
      icon: Icons.flash_on,
      children: [
        ...actions.map((act) {
          final isEnabled = _preferences.enabledQuickActions.contains(act.id);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: CheckboxListTile(
              title: Text(
                act.title,
                style: LuciTextStyles.detailValue(context),
              ),
              subtitle: Text(
                act.desc,
                style: LuciTextStyles.cardSubtitle(context),
              ),
              secondary: Icon(
                act.icon,
                size: 20,
                color: isEnabled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              value: isEnabled,
              onChanged: (val) {
                setState(() {
                  final newSet = Set<String>.from(
                    _preferences.enabledQuickActions,
                  );
                  if (val ?? false) {
                    newSet.add(act.id);
                  } else {
                    newSet.remove(act.id);
                  }
                  _preferences = _preferences.copyWith(
                    enabledQuickActions: newSet,
                  );
                });
                _onPreferenceChanged();
              },
              activeColor: Theme.of(context).colorScheme.primary,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSystemVitalsOptionsSection() {
    final l10n = AppLocalizations.of(context);
    return _buildSection(
      title: l10n?.rdSettingsSystemVitals ?? 'System Vitals Metrics',
      subtitle:
          l10n?.rdSettingsSystemVitalsSubtitle ??
          'Choose hardware performance metrics (CPU, RAM, Load Average, Uptime, Temperature) to display',
      icon: Icons.monitor_heart,
      children: [
        SwitchListTile.adaptive(
          title: Text(l10n?.rdSettingsCpuLoad ?? 'CPU Load (%)'),
          subtitle: Text(
            l10n?.rdSettingsCpuLoadDesc ??
                'Real-time CPU processor utilization',
          ),
          value: _preferences.showCpuLoad,
          onChanged: (val) {
            setState(() {
              _preferences = _preferences.copyWith(showCpuLoad: val);
            });
            _onPreferenceChanged();
          },
          activeTrackColor: Theme.of(context).colorScheme.primary,
          activeThumbColor: Colors.white,
          dense: true,
        ),
        SwitchListTile.adaptive(
          title: Text(l10n?.rdSettingsRamUsage ?? 'RAM Usage (%)'),
          subtitle: Text(
            l10n?.rdSettingsRamUsageDesc ?? 'Memory utilization percentage',
          ),
          value: _preferences.showRamUsage,
          onChanged: (val) {
            setState(() {
              _preferences = _preferences.copyWith(showRamUsage: val);
            });
            _onPreferenceChanged();
          },
          activeTrackColor: Theme.of(context).colorScheme.primary,
          activeThumbColor: Colors.white,
          dense: true,
        ),
        SwitchListTile.adaptive(
          title: Text(l10n?.rdSettingsLoadAverage ?? 'Load Average'),
          subtitle: Text(
            l10n?.rdSettingsLoadAverageDesc ?? 'System 1-minute load average',
          ),
          value: _preferences.showLoadAverage,
          onChanged: (val) {
            setState(() {
              _preferences = _preferences.copyWith(showLoadAverage: val);
            });
            _onPreferenceChanged();
          },
          activeTrackColor: Theme.of(context).colorScheme.primary,
          activeThumbColor: Colors.white,
          dense: true,
        ),
        SwitchListTile.adaptive(
          title: Text(l10n?.rdSettingsSystemUptime ?? 'System Uptime'),
          subtitle: Text(
            l10n?.rdSettingsSystemUptimeDesc ?? 'Time since router last booted',
          ),
          value: _preferences.showUptime,
          onChanged: (val) {
            setState(() {
              _preferences = _preferences.copyWith(showUptime: val);
            });
            _onPreferenceChanged();
          },
          activeTrackColor: Theme.of(context).colorScheme.primary,
          activeThumbColor: Colors.white,
          dense: true,
        ),
        SwitchListTile.adaptive(
          title: Text(
            l10n?.rdSettingsTemperatureWithUnit(
                  _preferences.temperatureUnit == 'fahrenheit' ? '°F' : '°C',
                ) ??
                'Temperature (${_preferences.temperatureUnit == 'fahrenheit' ? '°F' : '°C'})',
          ),
          subtitle: Text(
            l10n?.rdSettingsThermalDesc ??
                'Hardware thermal sensor temperature',
          ),
          value: _preferences.showTemperature,
          onChanged: (val) {
            setState(() {
              _preferences = _preferences.copyWith(showTemperature: val);
            });
            _onPreferenceChanged();
          },
          activeTrackColor: Theme.of(context).colorScheme.primary,
          activeThumbColor: Colors.white,
          dense: true,
        ),
        const Divider(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n?.rdSettingsThermalScale ?? 'Temperature Scale',
              style: LuciTextStyles.detailValue(
                context,
              ).copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        RadioGroup<String>(
          groupValue: _preferences.temperatureUnit,
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              _preferences = _preferences.copyWith(temperatureUnit: val);
            });
            _onPreferenceChanged();
          },
          child: Column(
            children: [
              RadioListTile<String>(
                title: Text(l10n?.rdSettingsCelsius ?? 'Celsius (°C)'),
                subtitle: Text(
                  l10n?.rdSettingsCelsiusDesc ??
                      'Standard metric thermal measurement (default)',
                ),
                value: 'celsius',
                activeColor: Theme.of(context).colorScheme.primary,
                dense: true,
              ),
              RadioListTile<String>(
                title: Text(l10n?.rdSettingsFahrenheit ?? 'Fahrenheit (°F)'),
                subtitle: Text(
                  l10n?.rdSettingsFahrenheitDesc ??
                      'Imperial thermal measurement',
                ),
                value: 'fahrenheit',
                activeColor: Theme.of(context).colorScheme.primary,
                dense: true,
              ),
            ],
          ),
        ),
        if (_preferences.dismissTemperaturePrompt) ...[
          const Divider(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.restart_alt_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              l10n?.rdSettingsResetThermalPrompt ??
                  'Reset Dismissed Temperature Prompt',
            ),
            subtitle: Text(
              l10n?.rdSettingsResetThermalPromptDesc ??
                  'Show temperature script installation pill on dashboard again',
            ),
            onTap: () {
              setState(() {
                _preferences = _preferences.copyWith(
                  dismissTemperaturePrompt: false,
                );
              });
              _onPreferenceChanged();
              context.showToastSuccess(
                l10n?.rdSettingsThermalPromptRestored ??
                    'Temperature prompt restored',
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildTrafficAndUnitsSection() {
    final l10n = AppLocalizations.of(context);
    final interfaces = _availableWiredInterfaces.toList()..sort();
    return _buildSection(
      title:
          l10n?.rdSettingsTrafficSectionTitle ??
          'Traffic & Throughput Settings',
      subtitle:
          l10n?.rdSettingsTrafficSectionSubtitle ??
          'Select throughput speed units (Mbps vs MB/s) and interface monitoring scope',
      icon: Icons.speed,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n?.rdSettingsSpeedDisplayUnit ?? 'Speed Display Unit',
              style: LuciTextStyles.detailValue(
                context,
              ).copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        RadioGroup<String>(
          groupValue: _preferences.speedUnit,
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              _preferences = _preferences.copyWith(speedUnit: val);
            });
            _onPreferenceChanged();
          },
          child: Column(
            children: [
              RadioListTile<String>(
                title: Text(
                  l10n?.rdSettingsBitsPerSecond ??
                      'Bits per second (Mbps / Kbps)',
                ),
                subtitle: Text(
                  l10n?.rdSettingsBitsPerSecondDesc ??
                      'Standard network bandwidth measurement unit',
                ),
                value: 'bits',
                activeColor: Theme.of(context).colorScheme.primary,
                dense: true,
              ),
              RadioListTile<String>(
                title: Text(
                  l10n?.rdSettingsBytesPerSecond ??
                      'Bytes per second (MB/s / KB/s)',
                ),
                subtitle: Text(
                  l10n?.rdSettingsBytesPerSecondDesc ??
                      'File transfer rate measurement unit',
                ),
                value: 'bytes',
                activeColor: Theme.of(context).colorScheme.primary,
                dense: true,
              ),
            ],
          ),
        ),
        const Divider(height: 20),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SwitchListTile.adaptive(
            title: Text(
              l10n?.rdSettingsShowAllInterfacesThroughput ??
                  'Show All Interfaces Throughput',
              style: LuciTextStyles.detailValue(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              l10n?.rdSettingsAggregateOverallThroughputDesc ??
                  'Aggregate overall throughput across all interfaces',
            ),
            value: _preferences.showAllThroughput,
            onChanged: (value) {
              setState(() {
                if (value) {
                  _preferences = _preferences.copyWith(
                    showAllThroughput: true,
                    primaryThroughputInterface: null,
                  );
                } else {
                  _preferences = _preferences.copyWith(
                    showAllThroughput: false,
                    primaryThroughputInterface: interfaces.isNotEmpty
                        ? interfaces.first
                        : null,
                  );
                }
              });
              _onPreferenceChanged();
            },
            activeTrackColor: Theme.of(context).colorScheme.primary,
            activeThumbColor: Colors.white,
          ),
        ),
        if (!_preferences.showAllThroughput && interfaces.isNotEmpty) ...[
          const SizedBox(height: LuciSpacing.sm),
          RadioGroup<String>(
            groupValue: _preferences.primaryThroughputInterface,
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _preferences = _preferences.copyWith(
                  showAllThroughput: false,
                  primaryThroughputInterface: value,
                );
              });
              _onPreferenceChanged();
            },
            child: Column(
              children: interfaces.map((iface) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: LuciSpacing.xs),
                  child: RadioListTile<String>(
                    title: Text(
                      iface,
                      style: LuciTextStyles.detailValue(context),
                    ),
                    secondary: Icon(
                      Icons.lan,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    value: iface,
                    activeColor: Theme.of(context).colorScheme.primary,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNetworkPrivacySection() {
    final l10n = AppLocalizations.of(context);
    return _buildSection(
      title: l10n?.rdSettingsNetworkPrivacyTitle ?? 'Network & Privacy Options',
      subtitle:
          l10n?.rdSettingsNetworkPrivacySubtitle ??
          'IP masking and inactive interface filters',
      icon: Icons.security,
      children: [
        SwitchListTile.adaptive(
          title: Text(
            l10n?.rdSettingsMaskWanIp ?? 'Mask Public WAN IP Address',
          ),
          subtitle: Text(
            l10n?.rdSettingsMaskWanIpDesc ??
                'Hide public IP address by default for privacy & screenshots',
          ),
          value: _preferences.maskPublicIp,
          onChanged: (val) {
            setState(() {
              _preferences = _preferences.copyWith(maskPublicIp: val);
            });
            _onPreferenceChanged();
          },
          activeTrackColor: Theme.of(context).colorScheme.primary,
          activeThumbColor: Colors.white,
          dense: true,
        ),
        SwitchListTile.adaptive(
          title: Text(
            l10n?.rdSettingsShowInactive ?? 'Show Inactive / Down Interfaces',
          ),
          subtitle: Text(
            l10n?.rdSettingsShowInactiveDesc ??
                'Display interfaces even if offline or unassigned',
          ),
          value: _preferences.showInactiveInterfaces,
          onChanged: (val) {
            setState(() {
              _preferences = _preferences.copyWith(showInactiveInterfaces: val);
            });
            _onPreferenceChanged();
          },
          activeTrackColor: Theme.of(context).colorScheme.primary,
          activeThumbColor: Colors.white,
          dense: true,
        ),
      ],
    );
  }

  Widget _buildWirelessInterfacesSection() {
    final l10n = AppLocalizations.of(context);
    if (_availableWirelessInterfaces.isEmpty) return const SizedBox.shrink();
    final sortedInterfaces = _availableWirelessInterfaces.toList()..sort();
    return _buildSection(
      title: l10n?.rdSettingsWirelessNetworksTitle ?? 'Wireless Networks',
      subtitle:
          l10n?.rdSettingsWirelessNetworksSubtitle ??
          'Choose which wireless networks to display',
      icon: Icons.wifi,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SwitchListTile.adaptive(
            title: Text(
              l10n?.rdSettingsShowAllNetworks ?? 'Show All Networks',
              style: LuciTextStyles.detailValue(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            value: _preferences.enabledWirelessInterfaces.isEmpty,
            onChanged: (value) {
              setState(() {
                if (value) {
                  _preferences = _preferences.copyWith(
                    enabledWirelessInterfaces: {},
                  );
                } else {
                  _preferences = _preferences.copyWith(
                    enabledWirelessInterfaces: Set.from(
                      _availableWirelessInterfaces,
                    ),
                  );
                }
              });
              _onPreferenceChanged();
            },
            activeTrackColor: Theme.of(context).colorScheme.primary,
            activeThumbColor: Colors.white,
          ),
        ),
        if (_preferences.enabledWirelessInterfaces.isNotEmpty) ...[
          const SizedBox(height: LuciSpacing.sm),
          ...sortedInterfaces.map((interface) {
            final isEnabled = _preferences.enabledWirelessInterfaces.contains(
              interface,
            );
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: LuciSpacing.xs),
              child: CheckboxListTile(
                title: Text(
                  interface,
                  style: LuciTextStyles.detailValue(context),
                ),
                secondary: Icon(
                  Icons.wifi,
                  size: 20,
                  color: isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                value: isEnabled,
                onChanged: (value) {
                  setState(() {
                    final newSet = Set<String>.from(
                      _preferences.enabledWirelessInterfaces,
                    );
                    if (value ?? false) {
                      newSet.add(interface);
                    } else {
                      newSet.remove(interface);
                    }
                    _preferences = _preferences.copyWith(
                      enabledWirelessInterfaces: newSet,
                    );
                  });
                  _onPreferenceChanged();
                },
                activeColor: Theme.of(context).colorScheme.primary,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildWiredInterfacesSection() {
    final l10n = AppLocalizations.of(context);
    if (_availableWiredInterfaces.isEmpty) return const SizedBox.shrink();
    final sortedInterfaces = _availableWiredInterfaces.toList()..sort();
    return _buildSection(
      title:
          l10n?.rdSettingsWiredInterfacesTitle ?? 'Wired & Virtual Interfaces',
      subtitle:
          l10n?.rdSettingsWiredInterfacesSubtitle ??
          'Choose which interface status cards to display',
      icon: Icons.cable,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SwitchListTile.adaptive(
            title: Text(
              l10n?.rdSettingsShowAllInterfaces ?? 'Show All Interfaces',
              style: LuciTextStyles.detailValue(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            value: _preferences.enabledWiredInterfaces.isEmpty,
            onChanged: (value) {
              setState(() {
                if (value) {
                  _preferences = _preferences.copyWith(
                    enabledWiredInterfaces: {},
                  );
                } else {
                  _preferences = _preferences.copyWith(
                    enabledWiredInterfaces: Set.from(_availableWiredInterfaces),
                  );
                }
              });
              _onPreferenceChanged();
            },
            activeTrackColor: Theme.of(context).colorScheme.primary,
            activeThumbColor: Colors.white,
          ),
        ),
        if (_preferences.enabledWiredInterfaces.isNotEmpty) ...[
          const SizedBox(height: LuciSpacing.sm),
          ...sortedInterfaces.map((interface) {
            final isEnabled = _preferences.enabledWiredInterfaces.contains(
              interface,
            );
            final description = _getInterfaceDescription(interface);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: LuciSpacing.xs),
              child: CheckboxListTile(
                title: Text(
                  interface.toUpperCase(),
                  style: LuciTextStyles.detailValue(context),
                ),
                subtitle: description,
                secondary: Icon(
                  Icons.cable,
                  size: 20,
                  color: isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                value: isEnabled,
                onChanged: (value) {
                  setState(() {
                    final newSet = Set<String>.from(
                      _preferences.enabledWiredInterfaces,
                    );
                    if (value ?? false) {
                      newSet.add(interface);
                    } else {
                      newSet.remove(interface);
                    }
                    _preferences = _preferences.copyWith(
                      enabledWiredInterfaces: newSet,
                    );
                  });
                  _onPreferenceChanged();
                },
                activeColor: Theme.of(context).colorScheme.primary,
                controlAffinity: ListTileControlAffinity.leading,
                dense: description != null,
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget? _getInterfaceDescription(String interface) {
    final l10n = AppLocalizations.of(context);
    final lower = interface.toLowerCase();
    if (lower.startsWith('wan')) {
      return Text(
        l10n?.interfaceTypeWan ?? 'Wide Area Network',
        style: LuciTextStyles.cardSubtitle(context),
      );
    } else if (lower.startsWith('lan')) {
      return Text(
        l10n?.interfaceTypeLan ?? 'Local Area Network',
        style: LuciTextStyles.cardSubtitle(context),
      );
    } else if (lower.contains('wireguard') || lower.startsWith('wg')) {
      return Text(
        l10n?.interfaceTypeWireguard ?? 'WireGuard VPN',
        style: LuciTextStyles.cardSubtitle(context),
      );
    } else if (lower.contains('openvpn')) {
      return Text(
        l10n?.interfaceTypeOpenVpn ?? 'OpenVPN',
        style: LuciTextStyles.cardSubtitle(context),
      );
    } else if (lower.contains('pppoe')) {
      return Text(
        l10n?.interfaceTypePppoe ?? 'PPPoE Connection',
        style: LuciTextStyles.cardSubtitle(context),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = l10n?.dashboardSettingsTitle ?? 'Dashboard Settings';
    if (_isLoading) {
      return Scaffold(
        appBar: LuciAppBar(title: title, showBack: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      return Scaffold(
        appBar: LuciAppBar(title: title, showBack: true),
        body: Center(child: Text(_errorMessage!)),
      );
    }

    return Scaffold(
      appBar: LuciAppBar(title: title, showBack: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: LuciSpacing.sm),
        children: [
          LuciStaggeredAnimation(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            staggerDelay: const Duration(milliseconds: 40),
            children: [
              _buildCardOrderSection(),
              _buildQuickActionsSection(),
              _buildSystemVitalsOptionsSection(),
              _buildTrafficAndUnitsSection(),
              _buildNetworkPrivacySection(),
              _buildWirelessInterfacesSection(),
              _buildWiredInterfacesSection(),
              const SizedBox(height: LuciSpacing.lg),
            ],
          ),
        ],
      ),
    );
  }
}
