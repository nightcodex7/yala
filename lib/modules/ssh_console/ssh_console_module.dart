// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/ssh_console_screen.dart';

class SshConsoleModule extends LuciModule {
  @override
  String get id => 'ssh_console';

  @override
  String get name => 'SSH Terminal';

  @override
  String get description =>
      'Interactive persistent SSH shell with saved command library';

  @override
  IconData get icon => Icons.terminal_outlined;

  @override
  IconData get selectedIcon => Icons.terminal;

  @override
  LuciModuleCategory get category => LuciModuleCategory.system;

  @override
  int get priority => 56;

  @override
  bool get showInBottomNav => false;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const SshConsoleScreen();
  }
}
