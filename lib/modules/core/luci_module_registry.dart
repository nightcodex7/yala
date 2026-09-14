// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'luci_module.dart';
import '../built_in_modules.dart';

/// Central registry for managing dynamic LuCI app modules.
class LuciModuleRegistry extends ChangeNotifier {
  static final LuciModuleRegistry _instance = LuciModuleRegistry._internal();
  factory LuciModuleRegistry() => _instance;
  LuciModuleRegistry._internal();

  static LuciModuleRegistry get instance => _instance;

  final Map<String, LuciModule> _modules = {};
  bool _isAutoInitializing = false;

  void _ensureInitialized() {
    if (_modules.isEmpty && !_isAutoInitializing) {
      _isAutoInitializing = true;
      registerBuiltInModules();
      _isAutoInitializing = false;
    }
  }

  /// Registers multiple modules in a single batch, notifying listeners only once.
  void registerModules(List<LuciModule> modules) {
    bool addedAny = false;
    for (final module in modules) {
      if (!_modules.containsKey(module.id)) {
        _modules[module.id] = module;
        module.initialize();
        addedAny = true;
      }
    }
    if (addedAny) {
      notifyListeners();
    }
  }

  /// Registers a module with the framework.
  void registerModule(LuciModule module) {
    if (_modules.containsKey(module.id)) {
      return;
    }
    _modules[module.id] = module;
    module.initialize();
    notifyListeners();
  }

  /// Unregisters a module by its ID.
  void unregisterModule(String id) {
    final module = _modules.remove(id);
    if (module != null) {
      module.dispose();
      notifyListeners();
    }
  }

  /// Retrieves a registered module by ID.
  LuciModule? getModule(String id) {
    _ensureInitialized();
    return _modules[id];
  }

  /// Returns all registered modules sorted by priority.
  List<LuciModule> get allModules {
    _ensureInitialized();
    final list = _modules.values.toList();
    list.sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  /// Returns only enabled modules sorted by priority.
  List<LuciModule> get enabledModules {
    return allModules.where((m) => m.isEnabled).toList();
  }

  /// Returns enabled modules that belong to a specific category.
  List<LuciModule> getModulesByCategory(LuciModuleCategory category) {
    return enabledModules.where((m) => m.category == category).toList();
  }

  /// Returns enabled modules marked for bottom navigation bar.
  List<LuciModule> get bottomNavModules {
    return enabledModules.where((m) => m.showInBottomNav).toList();
  }

  /// Clears all modules.
  void clear() {
    for (final module in _modules.values) {
      module.dispose();
    }
    _modules.clear();
    notifyListeners();
  }
}
