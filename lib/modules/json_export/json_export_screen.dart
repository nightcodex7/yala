// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/json_export/json_export_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

/// Describes one exportable configuration category.
class _ExportCategory {
  final String key;
  final String Function(AppLocalizations?) getTitle;
  final String Function(AppLocalizations?) getSubtitle;
  final IconData icon;
  final Future<ExportCategoryResult> Function(AppState) fetch;

  const _ExportCategory({
    required this.key,
    required this.getTitle,
    required this.getSubtitle,
    required this.icon,
    required this.fetch,
  });
}

/// Screen that allows the user to export router configuration as JSON,
/// either one category at a time or all at once.
class JsonExportScreen extends ConsumerStatefulWidget {
  const JsonExportScreen({super.key});

  @override
  ConsumerState<JsonExportScreen> createState() => _JsonExportScreenState();
}

class _JsonExportScreenState extends ConsumerState<JsonExportScreen> {
  /// Set of category keys currently being exported.
  final Set<String> _busyCategories = {};

  /// Whether the all-in-one export is in progress.
  bool _allExportBusy = false;

  static final _categories = <_ExportCategory>[
    _ExportCategory(
      key: 'ddns',
      getTitle: (l10n) => l10n?.jsonExportCatDdns ?? 'DDNS Entries',
      getSubtitle: (l10n) =>
          l10n?.jsonExportCatDdnsSubtitle ??
          'Dynamic DNS service configurations (passwords redacted)',
      icon: Icons.public_rounded,
      fetch: _fetchDdns,
    ),
    _ExportCategory(
      key: 'staticDhcpLeases',
      getTitle: (l10n) => l10n?.jsonExportCatDhcp ?? 'Static DHCP Leases',
      getSubtitle: (l10n) =>
          l10n?.jsonExportCatDhcpSubtitle ??
          'Hostname → IP → MAC static lease mappings',
      icon: Icons.lan_rounded,
      fetch: _fetchDhcp,
    ),
    _ExportCategory(
      key: 'firewallRules',
      getTitle: (l10n) => l10n?.jsonExportCatFirewall ?? 'Firewall Rules',
      getSubtitle: (l10n) =>
          l10n?.jsonExportCatFirewallSubtitle ??
          'Custom traffic rules (non-system)',
      icon: Icons.shield_rounded,
      fetch: _fetchFirewallRules,
    ),
    _ExportCategory(
      key: 'zoneForwarding',
      getTitle: (l10n) =>
          l10n?.jsonExportCatZoneForwarding ?? 'Zone Forwarding',
      getSubtitle: (l10n) =>
          l10n?.jsonExportCatZoneForwardingSubtitle ??
          'Firewall zone-to-zone forwarding definitions',
      icon: Icons.swap_horiz_rounded,
      fetch: _fetchZoneForwarding,
    ),
    _ExportCategory(
      key: 'portForwarding',
      getTitle: (l10n) =>
          l10n?.jsonExportCatPortForwarding ?? 'Port Forwarding',
      getSubtitle: (l10n) =>
          l10n?.jsonExportCatPortForwardingSubtitle ??
          'DNAT / port redirect rules',
      icon: Icons.router_rounded,
      fetch: _fetchPortForwarding,
    ),
    _ExportCategory(
      key: 'parentalControls',
      getTitle: (l10n) =>
          l10n?.jsonExportCatParentalControls ?? 'Parental Control Profiles',
      getSubtitle: (l10n) =>
          l10n?.jsonExportCatParentalControlsSubtitle ??
          'Local per-router parental control profiles',
      icon: Icons.family_restroom_rounded,
      fetch: _fetchParentalControls,
    ),
    _ExportCategory(
      key: 'installedPackages',
      getTitle: (l10n) =>
          l10n?.jsonExportCatInstalledPackages ?? 'Installed Packages',
      getSubtitle: (l10n) =>
          l10n?.jsonExportCatInstalledPackagesSubtitle ??
          'List of installed opkg / apk packages (live fetch)',
      icon: Icons.inventory_2_rounded,
      fetch: _fetchPackages,
    ),
    _ExportCategory(
      key: 'cronJobs',
      getTitle: (l10n) => l10n?.jsonExportCatCronJobs ?? 'Cron Jobs',
      getSubtitle: (l10n) =>
          l10n?.jsonExportCatCronJobsSubtitle ??
          'Scheduled cron entries from the router',
      icon: Icons.schedule_rounded,
      fetch: _fetchCronJobs,
    ),
    _ExportCategory(
      key: 'initScripts',
      getTitle: (l10n) => l10n?.jsonExportCatInitScripts ?? 'Init Scripts',
      getSubtitle: (l10n) =>
          l10n?.jsonExportCatInitScriptsSubtitle ??
          'rc.list init script enabled/disabled state',
      icon: Icons.terminal_rounded,
      fetch: _fetchInitScripts,
    ),
    _ExportCategory(
      key: 'dashboardSettings',
      getTitle: (l10n) =>
          l10n?.jsonExportCatDashboardSettings ?? 'Dashboard Settings',
      getSubtitle: (l10n) =>
          l10n?.jsonExportCatDashboardSettingsSubtitle ??
          'UI preferences: card order, visibility, shortcuts',
      icon: Icons.dashboard_customize_rounded,
      fetch: _fetchDashboardSettings,
    ),
    _ExportCategory(
      key: 'sshSavedCommands',
      getTitle: (l10n) =>
          l10n?.jsonExportCatSshSavedCommands ?? 'SSH Saved Commands',
      getSubtitle: (l10n) =>
          l10n?.jsonExportCatSshSavedCommandsSubtitle ??
          'Saved SSH console commands and shortcuts',
      icon: Icons.terminal_rounded,
      fetch: _fetchSshSavedCommands,
    ),
  ];

  // ── Static fetch wrappers (top-level so they are const-compatible) ──────────

  static Future<ExportCategoryResult> _fetchDdns(AppState a) async =>
      ConfigExportService.exportDdns(a);

  static Future<ExportCategoryResult> _fetchDhcp(AppState a) async =>
      ConfigExportService.exportStaticDhcpLeases(a);

  static Future<ExportCategoryResult> _fetchFirewallRules(AppState a) async =>
      ConfigExportService.exportFirewallRules(a);

  static Future<ExportCategoryResult> _fetchZoneForwarding(AppState a) async =>
      ConfigExportService.exportZoneForwarding(a);

  static Future<ExportCategoryResult> _fetchPortForwarding(AppState a) async =>
      ConfigExportService.exportPortForwarding(a);

  static Future<ExportCategoryResult> _fetchParentalControls(
    AppState a,
  ) async => ConfigExportService.exportParentalControls(a);

  static Future<ExportCategoryResult> _fetchPackages(AppState a) =>
      ConfigExportService.exportInstalledPackages(a);

  static Future<ExportCategoryResult> _fetchCronJobs(AppState a) async =>
      ConfigExportService.exportCronJobs(a);

  static Future<ExportCategoryResult> _fetchInitScripts(AppState a) async =>
      ConfigExportService.exportInitScripts(a);

  static Future<ExportCategoryResult> _fetchDashboardSettings(
    AppState a,
  ) async => ConfigExportService.exportDashboardSettings(a);

  static Future<ExportCategoryResult> _fetchSshSavedCommands(
    AppState a,
  ) async => ConfigExportService.exportSshSavedCommands(a);

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<String> _buildFileName({String? categoryKey}) async {
    final routerLabel =
        ref
            .read(appStateProvider)
            .selectedRouter
            ?.displayName
            .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_') ??
        'router';
    final dateStr = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(':', '-');
    final suffix = categoryKey ?? 'all';
    return 'yala-config-$routerLabel-$suffix-$dateStr.json';
  }

  Future<void> _exportCategory(_ExportCategory category) async {
    if (_busyCategories.contains(category.key) || _allExportBusy) return;

    final l10n = AppLocalizations.of(context);
    final catTitle = category.getTitle(l10n);

    setState(() => _busyCategories.add(category.key));
    if (!mounted) return;
    context.showToastLoading(
      l10n?.jsonExportToastExporting(catTitle) ?? 'Exporting $catTitle…',
    );

    try {
      final appState = ref.read(appStateProvider);
      final result = await category.fetch(appState);

      if (!mounted) return;

      if (result.isFailed) {
        context.showToastError(
          l10n?.jsonExportToastFailed ?? 'Export Failed',
          subtitle: result.errorMessage ?? 'Unknown error',
        );
        return;
      }

      if (result.isEmpty || result.isUnsupported) {
        context.showToastError(
          l10n?.jsonExportToastNoData ?? 'No Data',
          subtitle:
              l10n?.jsonExportToastNoDataSubtitle(catTitle) ??
              '$catTitle: no data available to export.',
        );
        return;
      }

      final bytes = ConfigExportService.encodeCategoryToJson(
        category.key,
        result,
        appState,
      );
      final fileName = await _buildFileName(categoryKey: category.key);

      final saveResult =
          await OsPlatformIntegration.saveDownloadedFileWithResult(
            bytes: bytes,
            fileName: fileName,
          );

      if (!mounted) return;

      if (saveResult != null) {
        context.showToastSuccess(
          l10n?.jsonExportToastExported(catTitle) ?? '$catTitle exported',
          subtitle:
              l10n?.jsonExportToastItemCount(result.itemCount) ??
              '${result.itemCount} item(s)',
        );
        await OsPlatformIntegration.showFileDownloadedPrompt(
          context,
          saveResult,
          title: l10n?.jsonExportDialogTitle ?? 'Configuration Exported',
          fileLabel:
              l10n?.jsonExportDialogCategoryFileLabel(catTitle) ??
              '$catTitle JSON',
          icon: Icons.download_done_rounded,
          accentColor: Colors.teal,
        );
      } else {
        context.showToastError(
          l10n?.jsonExportToastSaveCancelled ?? 'Save Cancelled',
          subtitle:
              l10n?.jsonExportToastSaveCancelledSubtitle ??
              'File was not saved.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      context.showToastError(
        l10n?.jsonExportToastError ?? 'Export Error',
        subtitle: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _busyCategories.remove(category.key));
    }
  }

  Future<void> _exportAll() async {
    if (_allExportBusy || _busyCategories.isNotEmpty) return;

    final l10n = AppLocalizations.of(context);

    setState(() => _allExportBusy = true);
    if (!mounted) return;
    context.showToastLoading(
      l10n?.jsonExportToastBuilding ?? 'Building full configuration export…',
    );

    try {
      final appState = ref.read(appStateProvider);
      final doc = await ConfigExportService.buildAllCategoriesExport(appState);
      final bytes = ConfigExportService.encodeToJson(doc);
      final fileName = await _buildFileName();

      if (!mounted) return;

      final saveResult =
          await OsPlatformIntegration.saveDownloadedFileWithResult(
            bytes: bytes,
            fileName: fileName,
          );

      if (!mounted) return;

      if (saveResult != null) {
        context.showToastSuccess(
          l10n?.jsonExportToastFullExported ?? 'Full configuration exported',
        );
        await OsPlatformIntegration.showFileDownloadedPrompt(
          context,
          saveResult,
          title: l10n?.jsonExportDialogTitle ?? 'Configuration Exported',
          fileLabel: l10n?.jsonExportDialogFullFileLabel ?? 'Full Config JSON',
          icon: Icons.download_done_rounded,
          accentColor: Colors.teal,
        );
      } else {
        context.showToastError(
          l10n?.jsonExportToastSaveCancelled ?? 'Save Cancelled',
          subtitle:
              l10n?.jsonExportToastSaveCancelledSubtitle ??
              'File was not saved.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      context.showToastError(
        l10n?.jsonExportToastError ?? 'Export Error',
        subtitle: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _allExportBusy = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final anyBusy = _allExportBusy || _busyCategories.isNotEmpty;

    return Scaffold(
      appBar: LuciAppBar(
        title: l10n?.jsonExportTitle ?? 'Export Configuration',
        showBack: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Explanation banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: LuciCardStyles.standardRadius,
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n?.jsonExportBanner ??
                        'Export router configuration categories as JSON files. '
                            'Sensitive fields such as passwords are automatically '
                            'redacted before export. Data is sourced from the last '
                            'dashboard refresh; installed packages require a live '
                            'network call.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Individual exports section
          _buildSectionHeader(
            context,
            l10n?.jsonExportSectionIndividual ?? 'INDIVIDUAL EXPORTS',
            Icons.list_alt_rounded,
          ),
          const SizedBox(height: 8),
          Container(
            decoration: LuciCardStyles.standardCard(context),
            child: ClipRRect(
              borderRadius: LuciCardStyles.standardRadius,
              child: Column(
                children: [
                  for (int i = 0; i < _categories.length; i++) ...[
                    _buildCategoryTile(context, _categories[i], anyBusy),
                    if (i < _categories.length - 1)
                      Divider(
                        height: 1,
                        indent: 56,
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // All-in-one export section
          _buildSectionHeader(
            context,
            l10n?.jsonExportSectionAllInOne ?? 'ALL-IN-ONE',
            Icons.download_for_offline_rounded,
          ),
          const SizedBox(height: 8),
          Container(
            decoration: LuciCardStyles.standardCard(context),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n?.jsonExportAllTitle ?? 'Export All (JSON)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n?.jsonExportAllSubtitle ??
                        'Collects all 10 categories into a single structured JSON '
                            'file. Installed packages require an active router session.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: anyBusy ? null : _exportAll,
                      icon: _allExportBusy
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(
                        _allExportBusy
                            ? (l10n?.jsonExportBtnExporting ?? 'Exporting…')
                            : (l10n?.jsonExportBtnAll ?? 'Export All (JSON)'),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: LuciTextStyles.sectionHeader(context)),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(
    BuildContext context,
    _ExportCategory category,
    bool anyBusy,
  ) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isBusy = _busyCategories.contains(category.key);
    final catTitle = category.getTitle(l10n);
    final catSubtitle = category.getSubtitle(l10n);

    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            category.icon,
            color: colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: Text(
          catTitle,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          catSubtitle,
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        trailing: isBusy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              )
            : IconButton(
                icon: Icon(
                  Icons.download_rounded,
                  color: anyBusy
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                      : colorScheme.primary,
                ),
                tooltip:
                    l10n?.jsonExportTooltipExport(catTitle) ??
                    'Export $catTitle',
                onPressed: anyBusy ? null : () => _exportCategory(category),
              ),
        onTap: anyBusy ? null : () => _exportCategory(category),
      ),
    );
  }
}
