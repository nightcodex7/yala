// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/log_viewer_screen.dart';

class LogViewerModule extends LuciModule {
  @override
  String get id => 'log_viewer';

  @override
  String get name => 'System & Kernel Logs';

  @override
  String get description =>
      'System log (logread) and kernel ring buffer (dmesg) viewer';

  @override
  IconData get icon => Icons.article_outlined;

  @override
  IconData get selectedIcon => Icons.article;

  @override
  LuciModuleCategory get category => LuciModuleCategory.system;

  @override
  int get priority => 55;

  @override
  bool get showInBottomNav => false;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const LogViewerScreen();
  }
}
