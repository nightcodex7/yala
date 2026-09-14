// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/system_backup_upgrade_screen.dart';

class SystemBackupUpgradeModule extends LuciModule {
  @override
  String get id => 'system_backup_upgrade';

  @override
  String get name => 'Backup & Flash Firmware';

  @override
  String get description =>
      'Router configuration backup & restore, factory reset, and sysupgrade firmware flashing';

  @override
  IconData get icon => Icons.system_update_alt_outlined;

  @override
  IconData get selectedIcon => Icons.system_update_alt;

  @override
  LuciModuleCategory get category => LuciModuleCategory.system;

  @override
  int get priority => 75;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const SystemBackupUpgradeScreen();
  }
}
