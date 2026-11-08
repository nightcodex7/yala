// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/advanced_reboot_screen.dart';

class AdvancedRebootModule extends LuciModule {
  @override
  String get id => 'advanced_reboot';

  @override
  String get name => 'Advanced Reboot';

  @override
  String get description =>
      'Dual-firmware partition switching, power management & boot diagnostics';

  @override
  IconData get icon => Icons.restart_alt_rounded;

  @override
  IconData get selectedIcon => Icons.restart_alt;

  @override
  LuciModuleCategory get category => LuciModuleCategory.system;

  @override
  int get priority => 75;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const AdvancedRebootScreen();
  }
}
