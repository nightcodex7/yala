// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class DashboardPreferences {
  static const List<String> defaultCardOrder = [
    'quick_actions',
    'device_info',
    'realtime_traffic',
    'system_vitals',
    'connected_clients',
    'wireless_networks',
    'network_interfaces',
    'system_modules',
  ];

  static const Set<String> defaultQuickActions = {
    'reboot',
    'flush_dns',
    'guest_wifi',
    'vpn',
    'refresh',
  };

  final Set<String> enabledWirelessInterfaces;
  final Set<String> enabledWiredInterfaces;
  final String? primaryThroughputInterface;
  final bool showAllThroughput;
  final bool maskPublicIp;

  // Section visibility toggles
  final bool showDeviceInfo;
  final bool showRealtimeTraffic;
  final bool showSystemVitals;
  final bool showConnectedClients;
  final bool showWirelessNetworks;
  final bool showNetworkInterfaces;
  final bool showSystemModules;
  final bool showQuickActions;

  // Card reorder list
  final List<String> cardOrder;

  // System Vitals metric toggles
  final bool showCpuLoad;
  final bool showRamUsage;
  final bool showLoadAverage;
  final bool showUptime;

  // Formatting & display options
  final String speedUnit; // 'bits' or 'bytes'
  final bool showInactiveInterfaces;

  // Quick Action Shortcuts selection
  final Set<String> enabledQuickActions;

  DashboardPreferences({
    Set<String>? enabledWirelessInterfaces,
    Set<String>? enabledWiredInterfaces,
    this.primaryThroughputInterface,
    this.showAllThroughput = true,
    this.maskPublicIp = false,
    this.showDeviceInfo = true,
    this.showRealtimeTraffic = true,
    this.showSystemVitals = true,
    this.showConnectedClients = true,
    this.showWirelessNetworks = true,
    this.showNetworkInterfaces = true,
    this.showSystemModules = true,
    this.showQuickActions = false,
    List<String>? cardOrder,
    this.showCpuLoad = true,
    this.showRamUsage = true,
    this.showLoadAverage = true,
    this.showUptime = true,
    this.speedUnit = 'bits',
    this.showInactiveInterfaces = true,
    Set<String>? enabledQuickActions,
  }) : enabledWirelessInterfaces = enabledWirelessInterfaces ?? {},
       enabledWiredInterfaces = enabledWiredInterfaces ?? {},
       cardOrder = _sanitizeCardOrder(cardOrder),
       enabledQuickActions =
           enabledQuickActions ?? Set.from(defaultQuickActions);

  static List<String> _sanitizeCardOrder(List<String>? inputOrder) {
    if (inputOrder == null || inputOrder.isEmpty) {
      return List.from(defaultCardOrder);
    }
    final sanitized = inputOrder
        .where((id) => defaultCardOrder.contains(id))
        .toList();
    for (final id in defaultCardOrder) {
      if (!sanitized.contains(id)) {
        sanitized.add(id);
      }
    }
    return sanitized;
  }

  bool isSectionVisible(String cardId) {
    switch (cardId) {
      case 'quick_actions':
        return showQuickActions;
      case 'device_info':
        return showDeviceInfo;
      case 'realtime_traffic':
        return showRealtimeTraffic;
      case 'system_vitals':
        return showSystemVitals;
      case 'connected_clients':
        return showConnectedClients;
      case 'wireless_networks':
        return showWirelessNetworks;
      case 'network_interfaces':
        return showNetworkInterfaces;
      case 'system_modules':
        return showSystemModules;
      default:
        return true;
    }
  }

  DashboardPreferences copyWith({
    Set<String>? enabledWirelessInterfaces,
    Set<String>? enabledWiredInterfaces,
    String? primaryThroughputInterface,
    bool? showAllThroughput,
    bool? maskPublicIp,
    bool? showDeviceInfo,
    bool? showRealtimeTraffic,
    bool? showSystemVitals,
    bool? showConnectedClients,
    bool? showWirelessNetworks,
    bool? showNetworkInterfaces,
    bool? showSystemModules,
    bool? showQuickActions,
    List<String>? cardOrder,
    bool? showCpuLoad,
    bool? showRamUsage,
    bool? showLoadAverage,
    bool? showUptime,
    String? speedUnit,
    bool? showInactiveInterfaces,
    Set<String>? enabledQuickActions,
  }) {
    return DashboardPreferences(
      enabledWirelessInterfaces:
          enabledWirelessInterfaces ?? this.enabledWirelessInterfaces,
      enabledWiredInterfaces:
          enabledWiredInterfaces ?? this.enabledWiredInterfaces,
      primaryThroughputInterface:
          primaryThroughputInterface ?? this.primaryThroughputInterface,
      showAllThroughput: showAllThroughput ?? this.showAllThroughput,
      maskPublicIp: maskPublicIp ?? this.maskPublicIp,
      showDeviceInfo: showDeviceInfo ?? this.showDeviceInfo,
      showRealtimeTraffic: showRealtimeTraffic ?? this.showRealtimeTraffic,
      showSystemVitals: showSystemVitals ?? this.showSystemVitals,
      showConnectedClients: showConnectedClients ?? this.showConnectedClients,
      showWirelessNetworks: showWirelessNetworks ?? this.showWirelessNetworks,
      showNetworkInterfaces:
          showNetworkInterfaces ?? this.showNetworkInterfaces,
      showSystemModules: showSystemModules ?? this.showSystemModules,
      showQuickActions: showQuickActions ?? this.showQuickActions,
      cardOrder: cardOrder ?? this.cardOrder,
      showCpuLoad: showCpuLoad ?? this.showCpuLoad,
      showRamUsage: showRamUsage ?? this.showRamUsage,
      showLoadAverage: showLoadAverage ?? this.showLoadAverage,
      showUptime: showUptime ?? this.showUptime,
      speedUnit: speedUnit ?? this.speedUnit,
      showInactiveInterfaces:
          showInactiveInterfaces ?? this.showInactiveInterfaces,
      enabledQuickActions: enabledQuickActions ?? this.enabledQuickActions,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabledWirelessInterfaces': enabledWirelessInterfaces.toList(),
    'enabledWiredInterfaces': enabledWiredInterfaces.toList(),
    'primaryThroughputInterface': primaryThroughputInterface,
    'showAllThroughput': showAllThroughput,
    'maskPublicIp': maskPublicIp,
    'showDeviceInfo': showDeviceInfo,
    'showRealtimeTraffic': showRealtimeTraffic,
    'showSystemVitals': showSystemVitals,
    'showConnectedClients': showConnectedClients,
    'showWirelessNetworks': showWirelessNetworks,
    'showNetworkInterfaces': showNetworkInterfaces,
    'showSystemModules': showSystemModules,
    'showQuickActions': showQuickActions,
    'cardOrder': cardOrder,
    'showCpuLoad': showCpuLoad,
    'showRamUsage': showRamUsage,
    'showLoadAverage': showLoadAverage,
    'showUptime': showUptime,
    'speedUnit': speedUnit,
    'showInactiveInterfaces': showInactiveInterfaces,
    'enabledQuickActions': enabledQuickActions.toList(),
  };

  factory DashboardPreferences.fromJson(Map<String, dynamic> json) {
    return DashboardPreferences(
      enabledWirelessInterfaces: Set<String>.from(
        json['enabledWirelessInterfaces'] ?? [],
      ),
      enabledWiredInterfaces: Set<String>.from(
        json['enabledWiredInterfaces'] ?? [],
      ),
      primaryThroughputInterface: json['primaryThroughputInterface'],
      showAllThroughput: json['showAllThroughput'] ?? true,
      maskPublicIp: json['maskPublicIp'] ?? false,
      showDeviceInfo: json['showDeviceInfo'] ?? true,
      showRealtimeTraffic: json['showRealtimeTraffic'] ?? true,
      showSystemVitals: json['showSystemVitals'] ?? true,
      showConnectedClients: json['showConnectedClients'] ?? true,
      showWirelessNetworks: json['showWirelessNetworks'] ?? true,
      showNetworkInterfaces: json['showNetworkInterfaces'] ?? true,
      showSystemModules: json['showSystemModules'] ?? true,
      showQuickActions: json['showQuickActions'] ?? false,
      cardOrder: json['cardOrder'] != null
          ? List<String>.from(json['cardOrder'])
          : null,
      showCpuLoad: json['showCpuLoad'] ?? true,
      showRamUsage: json['showRamUsage'] ?? true,
      showLoadAverage: json['showLoadAverage'] ?? true,
      showUptime: json['showUptime'] ?? true,
      speedUnit: json['speedUnit']?.toString() ?? 'bits',
      showInactiveInterfaces: json['showInactiveInterfaces'] ?? true,
      enabledQuickActions: json['enabledQuickActions'] != null
          ? Set<String>.from(json['enabledQuickActions'])
          : null,
    );
  }

  static DashboardPreferences get defaultPreferences => DashboardPreferences();
}
