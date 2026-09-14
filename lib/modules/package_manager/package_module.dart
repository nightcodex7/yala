// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/package_manager_screen.dart';

class PackageManagerModule extends LuciModule {
  @override
  String get id => 'package_manager';

  @override
  String get name => 'OPKG/APK Package Manager';

  @override
  String get description =>
      'OPKG & APK package managers, software updates, repository configuration & LuCI app management';

  @override
  IconData get icon => Icons.inventory_2_outlined;

  @override
  IconData get selectedIcon => Icons.inventory_2;

  @override
  LuciModuleCategory get category => LuciModuleCategory.system;

  @override
  int get priority => 60;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const PackageManagerScreen();
  }

  @override
  Widget? buildDashboardWidget(BuildContext context) {
    return null;
  }
}
