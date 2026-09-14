// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// Categories for organizing LuCI management modules.
enum LuciModuleCategory {
  core,
  monitoring,
  network,
  wireless,
  security,
  system,
  services,
  applications,
  tools,
}

/// Represents a quick action provided by a module.
class LuciModuleQuickAction {
  final String id;
  final String label;
  final IconData icon;
  final void Function(BuildContext context) onTap;

  const LuciModuleQuickAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

/// Abstract contract for all LuCI feature modules.
/// Every new router management feature must extend [LuciModule].
abstract class LuciModule {
  /// Unique string identifier for the module (e.g., 'dashboard', 'storage_monitoring').
  String get id;

  /// Human-readable title of the module.
  String get name;

  /// Short description of the module's capabilities.
  String get description;

  /// Default icon used for navigation or menus.
  IconData get icon;

  /// Selected icon variant (optional, defaults to [icon]).
  IconData get selectedIcon => icon;

  /// Category under which this module is classified.
  LuciModuleCategory get category;

  /// Priority score used for ordering modules (lower numbers appear first).
  int get priority => 100;

  /// Whether this module is currently active/enabled (e.g. based on router backend capability).
  bool get isEnabled => true;

  /// Whether this module should appear in the primary bottom navigation bar.
  bool get showInBottomNav => false;

  /// Builds the main full-screen view widget for this module.
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params});

  /// Optional widget snippet to be embedded in the central monitoring dashboard.
  Widget? buildDashboardWidget(BuildContext context) => null;

  /// List of quick shortcuts supplied by this module.
  List<LuciModuleQuickAction> get quickActions => const [];

  /// Lifecycle callback triggered when module is registered/initialized.
  Future<void> initialize() async {}

  /// Lifecycle callback triggered when module is removed/disposed.
  Future<void> dispose() async {}
}
