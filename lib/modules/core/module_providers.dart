// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'luci_module.dart';
import 'luci_module_registry.dart';

/// Provider for accessing the singleton [LuciModuleRegistry].
final moduleRegistryProvider = ChangeNotifierProvider<LuciModuleRegistry>((
  ref,
) {
  return LuciModuleRegistry.instance;
});

/// Provider for retrieving all active enabled modules sorted by priority.
final enabledModulesProvider = Provider<List<LuciModule>>((ref) {
  final registry = ref.watch(moduleRegistryProvider);
  return registry.enabledModules;
});

/// Provider for retrieving bottom navigation modules.
final bottomNavModulesProvider = Provider<List<LuciModule>>((ref) {
  final registry = ref.watch(moduleRegistryProvider);
  return registry.bottomNavModules;
});
