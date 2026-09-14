// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/charting_screen.dart';

class ChartingModule extends LuciModule {
  @override
  String get id => 'charting';

  @override
  String get name => 'Real-Time Metrics';

  @override
  String get description =>
      'Interactive real-time charts for CPU, RAM memory usage, and live Network RX/TX throughput';

  @override
  IconData get icon => Icons.show_chart_outlined;

  @override
  IconData get selectedIcon => Icons.show_chart;

  @override
  LuciModuleCategory get category => LuciModuleCategory.monitoring;

  @override
  int get priority => 18;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const ChartingScreen();
  }
}
