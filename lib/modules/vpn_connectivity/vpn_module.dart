// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/vpn_connectivity_screen.dart';
import 'widgets/vpn_connectivity_card.dart';

class VpnConnectivityModule extends LuciModule {
  @override
  String get id => 'vpn_connectivity';

  @override
  String get name => 'VPN & Connectivity';

  @override
  String get description =>
      'WireGuard tunnels, OpenVPN clients/servers, Tailscale mesh VPN, NextDNS, and Cloudflare Tunnels (cloudflared)';

  @override
  IconData get icon => Icons.vpn_lock_outlined;

  @override
  IconData get selectedIcon => Icons.vpn_lock;

  @override
  LuciModuleCategory get category => LuciModuleCategory.network;

  @override
  int get priority => 38;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const VpnConnectivityScreen();
  }

  @override
  Widget? buildDashboardWidget(BuildContext context) {
    return const VpnConnectivityCard();
  }
}
