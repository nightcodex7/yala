// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/screens/router_dashboard_settings_screen.dart';

import 'package:yet_another_luci_app/widgets/theme_router_logo.dart';

class DashboardSettingsListScreen extends ConsumerWidget {
  const DashboardSettingsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final routers = appState.routers;

    return Scaffold(
      appBar: const LuciAppBar(title: 'Dashboard Settings', showBack: true),
      body: routers.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(LuciSpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.router_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    SizedBox(height: LuciSpacing.md),
                    Text(
                      'No Routers Added',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: LuciSpacing.xs),
                    Text(
                      'Add a router to customize its dashboard settings.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.symmetric(
                vertical: LuciSpacing.sm,
                horizontal: LuciSpacing.md,
              ),
              itemBuilder: (context, index) {
                final r = routers[index];
                final title = r.lastKnownHostname?.isNotEmpty == true
                    ? r.lastKnownHostname!
                    : r.ipAddress;
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const ThemeRouterLogo(width: 32, height: 32),
                    title: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(r.ipAddress),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              RouterDashboardSettingsScreen(routerId: r.id),
                        ),
                      );
                    },
                  ),
                );
              },
              separatorBuilder: (context, index) =>
                  SizedBox(height: LuciSpacing.sm),
              itemCount: routers.length,
            ),
    );
  }
}
