// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/wireless_management_screen.dart';

class WirelessManagementModule extends LuciModule {
  @override
  String get id => 'wireless_management';

  @override
  String get name => 'Wireless Management';

  @override
  String get description =>
      'Wi-Fi radios (2.4GHz/5GHz/6GHz), SSIDs, guest network isolation, channels, security encryption & connected stations';

  @override
  IconData get icon => Icons.wifi_outlined;

  @override
  IconData get selectedIcon => Icons.wifi;

  @override
  LuciModuleCategory get category => LuciModuleCategory.wireless;

  @override
  int get priority => 25;

  @override
  bool get showInBottomNav => true;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const WirelessManagementScreen();
  }

  @override
  Widget buildDashboardWidget(BuildContext context) {
    return const SizedBox.shrink();
  }
}
