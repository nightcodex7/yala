// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/services_system_screen.dart';
import 'widgets/services_system_card.dart';

class ServicesSystemModule extends LuciModule {
  @override
  String get id => 'services_system';

  @override
  String get name => 'Services & System';

  @override
  String get description =>
      'Procd system services, startup init scripts, cron scheduled tasks, Dynamic DNS (DDNS) providers, and system logs';

  @override
  IconData get icon => Icons.settings_applications_outlined;

  @override
  IconData get selectedIcon => Icons.settings_applications;

  @override
  LuciModuleCategory get category => LuciModuleCategory.system;

  @override
  int get priority => 50;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const ServicesSystemScreen();
  }

  @override
  Widget? buildDashboardWidget(BuildContext context) {
    return const ServicesSystemCard();
  }
}
