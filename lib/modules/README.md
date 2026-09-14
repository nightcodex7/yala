# LuCI App Modular Plugin Architecture

This directory houses the dynamic module loading architecture for `yala`.

## Architecture Principles

1. **Modular Scope**: Every router management feature (System Monitoring, Storage Monitoring, Network Interfaces, Firewall, Docker, Packages, LuCI Apps, etc.) is implemented as a standalone `LuciModule`.
2. **Reuse OpenWrt Backend**: Modules directly call LuCI RPC, `ubus`, `uci`, `procd`, or `rpcd` APIs rather than inventing custom abstractions.
3. **Dynamic Discovery**: Modules register with `LuciModuleRegistry`, making them available dynamically across the application (Dashboard widgets, bottom navigation bar, or category views).
4. **Zero Duplication & Backward Compatibility**: Core screens and custom modules share existing design system components (`LuciCard`, `LuciAppBar`, `LuciSectionHeader`, etc.).

---

## Coding Conventions for Module Authors

### 1. Module Structure
Create a dedicated package under `lib/modules/<module_name>/`:
```
lib/modules/<module_name>/
├── <module_name>_module.dart       # Extends LuciModule
├── screens/                       # Screen views for the module
├── models/                        # Feature specific models (if any)
└── widgets/                       # Module UI widgets / dashboard card
```

### 2. Module Implementation Example
```dart
import 'package:flutter/material.dart';
import '../core/luci_module.dart';

class MyFeatureModule extends LuciModule {
  @override
  String get id => 'my_feature';

  @override
  String get name => 'My Feature';

  @override
  String get description => 'Description of feature';

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  IconData get selectedIcon => Icons.extension;

  @override
  LuciModuleCategory get category => LuciModuleCategory.system;

  @override
  int get priority => 50;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const MyFeatureScreen();
  }

  @override
  Widget? buildDashboardWidget(BuildContext context) {
    return const MyFeatureDashboardCard();
  }
}
```

### 3. Module Registration
Register your module in `lib/modules/built_in_modules.dart` or dynamically upon LuCI application discovery:
```dart
LuciModuleRegistry.instance.registerModule(MyFeatureModule());
```
