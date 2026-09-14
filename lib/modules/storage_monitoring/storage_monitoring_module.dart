// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/storage_monitoring_screen.dart';
import 'widgets/storage_monitoring_card.dart';

class StorageMonitoringModule extends LuciModule {
  @override
  String get id => 'storage_monitoring';

  @override
  String get name => 'Storage Monitoring';

  @override
  String get description =>
      'Storage filesystems, mounted USB drives & partitions, overlay FS allocation, and flash memory health';

  @override
  IconData get icon => Icons.sd_storage_outlined;

  @override
  IconData get selectedIcon => Icons.sd_storage;

  @override
  LuciModuleCategory get category => LuciModuleCategory.monitoring;

  @override
  int get priority => 16;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const StorageMonitoringScreen();
  }

  @override
  Widget? buildDashboardWidget(BuildContext context) {
    return const StorageMonitoringCard();
  }
}
