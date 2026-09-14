// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/dhcp_dns_screen.dart';
import 'widgets/dhcp_dns_card.dart';

class DhcpDnsModule extends LuciModule {
  @override
  String get id => 'dhcp_dns';

  @override
  String get name => 'DHCP & DNS';

  @override
  String get description =>
      'Active DHCP v4/v6 leases, static IP reservations, Dnsmasq DNS server, upstream forwarders & domain rules';

  @override
  IconData get icon => Icons.dns_outlined;

  @override
  IconData get selectedIcon => Icons.dns;

  @override
  LuciModuleCategory get category => LuciModuleCategory.network;

  @override
  int get priority => 35;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const DhcpDnsScreen();
  }

  @override
  Widget? buildDashboardWidget(BuildContext context) {
    return const DhcpDnsCard();
  }
}
