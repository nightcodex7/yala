// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'core/luci_module.dart';
import 'core/luci_module_registry.dart';
import 'system_monitoring/system_monitoring_module.dart';
import 'storage_monitoring/storage_monitoring_module.dart';
import 'charting/charting_module.dart';
import 'wireless_management/wireless_module.dart';
import 'firewall_security/firewall_module.dart';
import 'dhcp_dns/dhcp_dns_module.dart';
import 'services_system/services_module.dart';
import 'vpn_connectivity/vpn_module.dart';
import 'package_manager/package_module.dart';
import 'system_backup_upgrade/system_backup_upgrade_module.dart';
import 'parental_controls/parental_controls_module.dart';
import '../screens/dashboard_screen.dart';
import '../screens/clients_screen.dart';
import '../screens/interfaces_screen.dart';
import '../screens/more_screen.dart';

class DashboardModule extends LuciModule {
  @override
  String get id => 'dashboard';

  @override
  String get name => 'Dashboard';

  @override
  String get description =>
      'Router status overview, real-time traffic graph & customizable widgets';

  @override
  IconData get icon => Icons.dashboard_outlined;

  @override
  IconData get selectedIcon => Icons.dashboard;

  @override
  LuciModuleCategory get category => LuciModuleCategory.core;

  @override
  int get priority => 10;

  @override
  bool get showInBottomNav => true;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const DashboardScreen();
  }
}

class ClientsModule extends LuciModule {
  @override
  String get id => 'clients';

  @override
  String get name => 'Clients';

  @override
  String get description =>
      'Connected devices, DHCP lease table, MAC vendor details & access controls';

  @override
  IconData get icon => Icons.people_outline;

  @override
  IconData get selectedIcon => Icons.people;

  @override
  LuciModuleCategory get category => LuciModuleCategory.core;

  @override
  int get priority => 20;

  @override
  bool get showInBottomNav => true;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const ClientsScreen();
  }
}

class InterfacesModule extends LuciModule {
  @override
  String get id => 'interfaces';

  @override
  String get name => 'Interfaces';

  @override
  String get description =>
      'Wired & wireless network interfaces (WAN/LAN/WWAN), subnets & bridge devices';

  @override
  IconData get icon => Icons.lan_outlined;

  @override
  IconData get selectedIcon => Icons.lan;

  @override
  LuciModuleCategory get category => LuciModuleCategory.network;

  @override
  int get priority => 30;

  @override
  bool get showInBottomNav => true;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    final scrollToInterface = params?['scrollToInterface'] as String?;
    final onScrollComplete = params?['onScrollComplete'] as VoidCallback?;
    return InterfacesScreen(
      scrollToInterface: scrollToInterface,
      onScrollComplete: onScrollComplete,
    );
  }
}

class MoreModule extends LuciModule {
  @override
  String get id => 'more';

  @override
  String get name => 'More';

  @override
  String get description =>
      'Router management, application settings & full module directory';

  @override
  IconData get icon => Icons.more_horiz_outlined;

  @override
  IconData get selectedIcon => Icons.more_horiz;

  @override
  LuciModuleCategory get category => LuciModuleCategory.core;

  @override
  int get priority => 99;

  @override
  bool get showInBottomNav => true;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const MoreScreen();
  }
}

/// Initializes and registers all default built-in core modules.
void registerBuiltInModules() {
  final registry = LuciModuleRegistry.instance;
  registry.registerModules([
    DashboardModule(),
    SystemMonitoringModule(),
    StorageMonitoringModule(),
    ChartingModule(),
    WirelessManagementModule(),
    FirewallSecurityModule(),
    DhcpDnsModule(),
    ServicesSystemModule(),
    VpnConnectivityModule(),
    PackageManagerModule(),
    SystemBackupUpgradeModule(),
    ParentalControlsModule(),
    ClientsModule(),
    InterfacesModule(),
    MoreModule(),
  ]);
}
