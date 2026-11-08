// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/design/luci_theme.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/screens/dashboard_settings_list_screen.dart';
import 'package:yet_another_luci_app/screens/manage_routers_screen.dart';
import 'package:yet_another_luci_app/services/update_checker_service.dart';
import 'package:yet_another_luci_app/widgets/theme_router_logo.dart';
import 'package:yet_another_luci_app/widgets/language_picker_dialog.dart';
import 'package:yet_another_luci_app/widgets/rpc_permissions_dialog.dart';
import 'package:yet_another_luci_app/widgets/edit_hostname_dialog.dart';
import 'package:yet_another_luci_app/widgets/change_router_password_dialog.dart';
import 'package:yet_another_luci_app/modules/json_export/json_export_screen.dart';
import 'package:yet_another_luci_app/modules/account_access/screens/account_access_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isRedetecting = false;

  void _showReviewerModeResetDialog(BuildContext context, WidgetRef ref) {
    final appState = ref.read(appStateProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        icon: Icon(
          Icons.exit_to_app_rounded,
          color: theme.colorScheme.primary,
          size: 28,
        ),
        title: Text(l10n?.settingsExitReviewerTitle ?? 'Exit Reviewer Mode?'),
        content: SingleChildScrollView(
          child: Text(
            l10n?.settingsExitReviewerContent ??
                'This will disable reviewer mode and return to normal authentication. '
                    'You will need to log in with real router credentials.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final rootNav = Navigator.of(context, rootNavigator: true);
              rootNav.pop();
              await appState.setReviewerMode(false);
              rootNav.pushNamedAndRemoveUntil('/login', (route) => false);
            },
            child: Text(l10n?.settingsExitReviewerBtn ?? 'Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final activeRouter = appState.selectedRouter;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: LuciAppBar(
        title: l10n?.settingsTitle ?? 'Settings',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: l10n?.accountAndAccessTitle ?? 'Account & Access',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AccountAccessScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          // Active Router Quick Banner
          if (activeRouter != null) ...[
            _buildActiveRouterBanner(context, appState),
            const SizedBox(height: 20),
          ],

          // Theme / Appearance Section
          _buildSectionHeader(
            context,
            l10n?.appearanceSection ?? 'APPEARANCE',
            Icons.palette_outlined,
          ),
          const SizedBox(height: 8),
          _buildThemeSegmentedSelector(context, appState),
          const SizedBox(height: 12),
          _buildPaletteSelector(context, appState),
          const SizedBox(height: 12),
          _buildLanguageSelector(context, appState),
          const SizedBox(height: 24),

          // Dashboard Section
          _buildSectionHeader(
            context,
            l10n?.dashboardSection ?? 'DASHBOARD',
            Icons.dashboard_customize_outlined,
          ),
          const SizedBox(height: 8),
          _buildCustomizeDashboardTile(context),
          const SizedBox(height: 24),

          // Data Management Section
          _buildSectionHeader(
            context,
            l10n?.settingsDataManagement ?? 'DATA MANAGEMENT',
            Icons.storage_rounded,
          ),
          const SizedBox(height: 8),
          _buildExportConfigTile(context),
          const SizedBox(height: 24),

          // Router Diagnostics & Features Section
          _buildSectionHeader(
            context,
            l10n?.diagnosticsSection ?? 'ROUTER DIAGNOSTICS & FEATURES',
            Icons.radar_outlined,
          ),
          const SizedBox(height: 8),
          _buildCapabilitiesTile(context, appState),
          const SizedBox(height: 24),

          // Router Security & Access Section
          if (activeRouter != null) ...[
            _buildSectionHeader(
              context,
              l10n?.routerSecuritySection ?? 'ROUTER SECURITY & ACCESS',
              Icons.security_outlined,
            ),
            const SizedBox(height: 8),
            _buildChangePasswordTile(context, appState),
            const SizedBox(height: 24),
          ],

          // App Updates (if community flavor and not F-Droid build)
          if (AppConfig.isCommunityFlavor && !AppConfig.isFdroidBuild) ...[
            _buildSectionHeader(
              context,
              l10n?.appUpdatesSection ?? 'APP UPDATES',
              Icons.system_update_outlined,
            ),
            const SizedBox(height: 8),
            _buildUpdatesTile(context),
            const SizedBox(height: 24),
          ],

          // Build Verification & Privacy
          _buildSectionHeader(
            context,
            l10n?.buildVerificationSection ?? 'BUILD VERIFICATION & PRIVACY',
            Icons.verified_user_outlined,
          ),
          const SizedBox(height: 8),
          _buildBuildVerificationTile(context),
          const SizedBox(height: 24),

          // Legal & Policy
          _buildSectionHeader(
            context,
            l10n?.legalSection ?? 'LEGAL & POLICY',
            Icons.gavel_outlined,
          ),
          const SizedBox(height: 8),
          _buildLegalGroupCard(context),
          const SizedBox(height: 24),

          // Reviewer Mode Active Banner
          if (appState.reviewerModeEnabled) ...[
            _buildReviewerModeCard(context, ref),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon, {
    int maxLines = 2,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: LuciTextStyles.sectionHeader(context),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRouterBanner(BuildContext context, AppState appState) {
    final l10n = AppLocalizations.of(context);
    final router = appState.selectedRouter!;
    final colorScheme = Theme.of(context).colorScheme;
    final hostname = router.lastKnownHostname?.isNotEmpty == true
        ? router.lastKnownHostname!
        : router.ipAddress;
    final boardName =
        appState.dashboardData?['system']?['board_name'] as String? ??
        appState.dashboardData?['system']?['model'] as String? ??
        'OpenWrt Router';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.7),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: const ThemeRouterLogo(width: 32, height: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        hostname,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (appState.hasActiveSession) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        visualDensity: VisualDensity.compact,
                        tooltip: l10n?.tooltipEditHostname ?? 'Edit hostname',
                        onPressed: () => EditHostnameDialog.show(
                          context,
                          currentHostname: hostname,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${router.ipAddress} • $boardName',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip:
                l10n?.settingsSwitchManageRouters ?? 'Switch or Manage Routers',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ManageRoutersScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSegmentedSelector(BuildContext context, AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMode = appState.themeMode;
    final l10n = AppLocalizations.of(context);

    final options = [
      (
        mode: ThemeMode.system,
        label: l10n?.themeModeSystem ?? 'System',
        icon: Icons.brightness_auto_rounded,
      ),
      (
        mode: ThemeMode.light,
        label: l10n?.themeModeLight ?? 'Light',
        icon: Icons.light_mode_rounded,
      ),
      (
        mode: ThemeMode.dark,
        label: l10n?.themeModeDark ?? 'Dark',
        icon: Icons.dark_mode_rounded,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: options.map((opt) {
          final isSelected = currentMode == opt.mode;
          return Expanded(
            child: GestureDetector(
              onTap: () => appState.setThemeMode(opt.mode),
              child: AnimatedContainer(
                duration: LuciAnimations.fast,
                curve: LuciAnimations.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      opt.icon,
                      size: 18,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      opt.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isSelected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPaletteSelector(BuildContext context, AppState appState) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final currentPalette = appState.themePalette;
    final l10n = AppLocalizations.of(context);

    String getPaletteSubtitle(AppThemePalette p) {
      switch (p) {
        case AppThemePalette.amber:
          return l10n?.paletteAmberDesc ?? p.subtitle;
        case AppThemePalette.dynamicTheme:
          return l10n?.paletteMaterialYouDesc ?? p.subtitle;
      }
    }

    return Container(
      decoration: LuciCardStyles.standardCard(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.colorPalette ??
                        'Color Palette',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  currentPalette.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          ...AppThemePalette.values.map((palette) {
            final isSelected = currentPalette == palette;
            final dynamicPrimary = isDark
                ? appState.preloadedDarkDynamic?.primary
                : appState.preloadedLightDynamic?.primary;
            final swatch =
                (palette == AppThemePalette.dynamicTheme &&
                    dynamicPrimary != null)
                ? dynamicPrimary
                : palette.swatchColor(isDark);

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => appState.setThemePalette(palette),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: swatch.withValues(alpha: isDark ? 0.22 : 0.15),
                          border: Border.all(color: swatch, width: 2),
                        ),
                        child: Icon(palette.icon, size: 16, color: swatch),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              palette.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              getPaletteSubtitle(palette),
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedContainer(
                        duration: LuciAnimations.fast,
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? colorScheme.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                            width: 1.5,
                          ),
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check,
                                size: 14,
                                color: colorScheme.onPrimary,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector(BuildContext context, AppState appState) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentLocale = appState.locale;
    final l10n = AppLocalizations.of(context);

    final currentOption = kAppLanguages.firstWhere((opt) {
      if (opt.locale == null && currentLocale == null) return true;
      if (opt.locale != null && currentLocale != null) {
        if (opt.locale!.languageCode == currentLocale.languageCode) {
          if (opt.locale!.countryCode == null ||
              opt.locale!.countryCode == currentLocale.countryCode) {
            return true;
          }
        }
      }
      return false;
    }, orElse: () => kAppLanguages.first);

    return Container(
      decoration: LuciCardStyles.standardCard(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: LuciCardStyles.standardRadius,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Icon(Icons.language_rounded, color: colorScheme.primary),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n?.languageTitle ?? 'Language',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              const LocalizationBetaBadge(),
            ],
          ),
          subtitle: Text(
            currentOption.locale == null
                ? (l10n?.languageSystemDefault ?? 'System Default')
                : '${currentOption.nativeLabel} (${currentOption.label})',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentOption.locale == null
                    ? (l10n?.languageSystemDefault ?? 'System Default')
                    : currentOption.nativeLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          onTap: () => showLanguagePickerDialog(context, appState: appState),
        ),
      ),
    );
  }

  Widget _buildCustomizeDashboardTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: LuciCardStyles.standardCard(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: LuciCardStyles.standardRadius,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.dashboard_customize_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 24,
            ),
          ),
          title: Text(
            AppLocalizations.of(context)?.customizeDashboardTitle ??
                'Customize Dashboard',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              AppLocalizations.of(context)?.customizeDashboardSubtitle ??
                  'Rearrange layout, toggle card visibility, quick action shortcuts & interface throughput monitoring',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const DashboardSettingsListScreen(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildExportConfigTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: LuciCardStyles.standardCard(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: LuciCardStyles.standardRadius,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.download_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 24,
            ),
          ),
          title: Text(
            l10n?.settingsExportConfigTitle ?? 'Export Configuration (JSON)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              l10n?.settingsExportConfigSubtitle ??
                  'Export DDNS, DHCP leases, firewall rules, packages, cron jobs & more as JSON',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const JsonExportScreen()),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCapabilitiesTile(BuildContext context, AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    final caps = appState.capabilities;
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: LuciCardStyles.standardCard(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: LuciCardStyles.standardRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.radar_rounded,
                      color: colorScheme.onSecondaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n?.redetectCapabilitiesTitle ??
                              'Re-detect Router Capabilities',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n?.redetectCapabilitiesSubtitle ??
                              'Probe active router ubus objects & package manager capabilities',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _isRedetecting
                        ? null
                        : () async {
                            setState(() => _isRedetecting = true);
                            await appState.redetectCapabilities();
                            if (mounted && context.mounted) {
                              setState(() => _isRedetecting = false);
                              context.showToastSuccess(
                                l10n?.capDetectedSuccess ??
                                    'Capabilities Detected',
                                subtitle:
                                    l10n?.capDetectedSuccessSubtitle ??
                                    'Router capabilities re-detected & cached successfully!',
                              );
                            }
                          },
                    icon: _isRedetecting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
              if (caps != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildCapabilityChip(
                      context,
                      l10n?.capPackageEngine ?? 'Package Engine',
                      caps.packageEngine.name.toUpperCase(),
                      Icons.inventory_2_outlined,
                    ),
                    _buildCapabilityChip(
                      context,
                      l10n?.capFirewall ?? 'Firewall',
                      caps.firewallBackend.name.toUpperCase(),
                      Icons.shield_outlined,
                    ),
                    _buildCapabilityChip(
                      context,
                      l10n?.capNetworkModel ?? 'Network Model',
                      caps.networkModel.name.toUpperCase(),
                      Icons.lan_outlined,
                    ),
                    _buildCapabilityChip(
                      context,
                      'RPC Status',
                      caps.isRpcComplete ? 'READY' : 'SETUP REQUIRED',
                      caps.isRpcComplete
                          ? Icons.verified_user_outlined
                          : Icons.warning_amber_rounded,
                      valueColor: caps.isRpcComplete
                          ? Colors.teal
                          : Colors.amber.shade800,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => RpcPermissionsDialog.show(
                    context,
                    actionName: l10n?.tileRpcPermissions ?? 'RPC & Permissions',
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (caps.isRpcComplete
                                  ? colorScheme.surfaceContainerHighest
                                  : Colors.amber.shade700)
                              .withValues(
                                alpha: caps.isRpcComplete ? 0.35 : 0.12,
                              ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            (caps.isRpcComplete
                                    ? colorScheme.outlineVariant
                                    : Colors.amber.shade700)
                                .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          caps.isRpcComplete
                              ? Icons.admin_panel_settings_outlined
                              : Icons.build_circle_outlined,
                          size: 16,
                          color: caps.isRpcComplete
                              ? colorScheme.primary
                              : Colors.amber.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            caps.isRpcComplete
                                ? (l10n?.rpcPermissionsVerified ??
                                      'RPC permissions & execution modules verified')
                                : (l10n?.rpcPermissionsMissingWarning ??
                                      'Missing RPC permissions may restrict advanced router management features'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: caps.isRpcComplete
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                              color: caps.isRpcComplete
                                  ? colorScheme.onSurfaceVariant
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          caps.isRpcComplete
                              ? (l10n?.actionManage ?? 'Manage')
                              : (l10n?.actionAutoFix ?? 'Auto-Fix'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: caps.isRpcComplete
                                ? colorScheme.primary
                                : Colors.amber.shade900,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: caps.isRpcComplete
                              ? colorScheme.primary
                              : Colors.amber.shade900,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChangePasswordTile(BuildContext context, AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final caps = appState.capabilities;
    final isSupported = caps?.hasSetPasswordRpc ?? false;

    return Container(
      decoration: LuciCardStyles.standardCard(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: LuciCardStyles.standardRadius,
        child: InkWell(
          borderRadius: LuciCardStyles.standardRadius,
          onTap: isSupported
              ? () => ChangeRouterPasswordDialog.show(context)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSupported
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.password_rounded,
                    color: isSupported
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.changePasswordTitle ?? 'Change Router Password',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isSupported
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isSupported
                            ? (l10n?.changePasswordSubtitle ??
                                  'Update root/admin password on active router')
                            : (l10n?.changePasswordUnsupported ??
                                  'Router does not expose luci.setPassword via rpcd-mod-luci.'),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSupported)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCapabilityChip(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: valueColor ?? colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: valueColor ?? colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatesTile(BuildContext context) {
    if (AppConfig.isFdroidBuild) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: LuciCardStyles.standardCard(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: LuciCardStyles.standardRadius,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.system_update_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 24,
            ),
          ),
          title: Text(
            l10n?.checkForUpdatesTitle ?? 'Check for Updates',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text(
            l10n?.checkForUpdatesSubtitle ??
                'Check for new release builds on GitHub',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
          onTap: () {
            UpdateCheckerService.checkForUpdates(context);
          },
        ),
      ),
    );
  }

  Widget _buildBuildVerificationTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOfficial = AppConfig.isOfficialBuild;
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: LuciCardStyles.standardCard(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: LuciCardStyles.standardRadius,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isOfficial
                  ? LuciStatusColors.successBg(context)
                  : colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isOfficial
                  ? Icons.verified_user_rounded
                  : Icons.gpp_maybe_rounded,
              color: isOfficial
                  ? LuciStatusColors.connected
                  : colorScheme.onErrorContainer,
              size: 24,
            ),
          ),
          title: Text(
            isOfficial
                ? (l10n?.buildOfficialTitle ??
                      'Official Build & Privacy Guarantee')
                : (l10n?.buildUnofficialTitle ??
                      'Unofficial / Self-Built Build'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Text(
              isOfficial
                  ? (l10n?.buildOfficialSubtitle ??
                        'Flavor: ${AppConfig.flavorName} • Zero Analytics & Telemetry')
                  : (l10n?.buildUnofficialSubtitle ??
                        'Flavor: ${AppConfig.flavorName} (Unverified) • Zero Analytics'),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          trailing: Icon(
            isOfficial
                ? Icons.check_circle_rounded
                : Icons.warning_amber_rounded,
            size: 22,
            color: isOfficial
                ? LuciStatusColors.connectedColor(context)
                : LuciStatusColors.warningColor(context),
          ),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                actionsOverflowButtonSpacing: 8,
                actionsOverflowDirection: VerticalDirection.down,
                title: Row(
                  children: [
                    Icon(
                      isOfficial
                          ? Icons.verified_rounded
                          : Icons.warning_amber_rounded,
                      color: isOfficial
                          ? LuciStatusColors.connectedColor(context)
                          : LuciStatusColors.warningColor(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isOfficial
                            ? (l10n?.buildVerificationTitle ??
                                  'Build Verification')
                            : (l10n?.buildUnofficialNotice ??
                                  'Unofficial Build Notice'),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n != null
                            ? 'Build Channel: ${AppConfig.flavorName} Edition ${isOfficial ? (l10n.settingsBuildOfficial) : (l10n.settingsBuildUnofficial)}'
                            : 'Build Channel: ${AppConfig.flavorName} Edition ${isOfficial ? "(Official)" : "(Unofficial / Local)"}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isOfficial
                            ? '• ${l10n?.settingsBuildVerified ?? "Verified Official Release Build"}'
                            : '• ${l10n?.settingsBuildSelfCompiled ?? "Unofficial / Self-Compiled Build"}',
                        style: TextStyle(
                          color: isOfficial
                              ? LuciStatusColors.connected
                              : Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '• ${l10n?.settingsPrivacyBulletRpc ?? "100% On-Device RPC Communication"}',
                      ),
                      Text(
                        '• ${l10n?.settingsPrivacyBulletAnalytics ?? "Zero Analytics, Tracking, or Telemetry"}',
                      ),
                      const SizedBox(height: 12),
                      const SelectableText(
                        'Repository: ${AppConfig.githubRepositoryUrl}',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n?.actionConfirm ?? 'OK'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLegalGroupCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: LuciCardStyles.standardCard(context),
      child: ClipRRect(
        borderRadius: LuciCardStyles.standardRadius,
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.privacy_tip_outlined,
                  color: colorScheme.primary,
                ),
                title: Text(
                  l10n?.privacyPolicyTitle ?? 'Privacy Policy',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  l10n?.privacyPolicySubtitle ??
                      'Read our local-first zero-telemetry policy',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => launchUrlString(
                  AppConfig.privacyPolicyUrl,
                  mode: LaunchMode.externalApplication,
                ),
              ),
              Divider(
                height: 1,
                indent: 56,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              ListTile(
                leading: Icon(
                  Icons.description_outlined,
                  color: colorScheme.primary,
                ),
                title: Text(
                  l10n?.termsAndConditionsTitle ?? 'Terms & Conditions',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  l10n?.termsAndConditionsSubtitle ??
                      'Terms of service and usage guidelines',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => launchUrlString(
                  AppConfig.termsAndConditionsUrl,
                  mode: LaunchMode.externalApplication,
                ),
              ),
              Divider(
                height: 1,
                indent: 56,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              ListTile(
                leading: Icon(
                  Icons.contact_support_outlined,
                  color: colorScheme.primary,
                ),
                title: Text(
                  l10n?.contactSupportTitle ?? 'Contact & Support',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  l10n?.contactSupportSubtitle ??
                      'Get in touch or request support',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => launchUrlString(
                  AppConfig.contactUrl,
                  mode: LaunchMode.externalApplication,
                ),
              ),
              Divider(
                height: 1,
                indent: 56,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              ListTile(
                leading: Icon(
                  Icons.policy_outlined,
                  color: colorScheme.primary,
                ),
                title: Text(
                  l10n?.licenseAttributionTitle ??
                      'License & Attribution (GPLv3)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  l10n?.licenseAttributionSubtitle ??
                      'GNU General Public License v3.0 • Copyleft & Credits',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => _showGplLicenseDialog(context),
              ),
              Divider(
                height: 1,
                indent: 56,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              ListTile(
                leading: Icon(
                  Icons.article_outlined,
                  color: colorScheme.primary,
                ),
                title: Text(
                  l10n?.openSourceLicensesTitle ?? 'Open Source Licenses',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  l10n?.openSourceLicensesSubtitle ??
                      'Third-party software notices and licenses',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Yet Another LuCI App (YALA)',
                  applicationLegalese:
                      'Original work Copyright (C) 2025–2026 cogwheel0 (luci-mobile)\n'
                      'Modifications and enhancements Copyright (C) 2026 @nightcodex7\n'
                      'Licensed under the GNU General Public License v3.0 or later.\n\n'
                      'DISCLAIMER: YALA is an independent open-source project and is not '
                      'affiliated with, endorsed by, or sponsored by the OpenWrt Project, '
                      'AdGuard Ltd., WireGuard LLC, Tailscale Inc., Cloudflare Inc., '
                      'or any other third-party service or trademark referenced herein. '
                      'All product names, trademarks, and registered trademarks are the '
                      'property of their respective owners.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGplLicenseDialog(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.policy_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'License & Copyleft (GPLv3)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConfig.licenseName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SPDX-License-Identifier: ${AppConfig.licenseSpdx}',
                      style: LuciTypography.monoStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Credits & Copyright:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '• Original Work: Copyright (C) 2025–2026 cogwheel0 (luci-mobile)\n'
                '• Modifications: Copyright (C) 2026 @nightcodex7',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Copyleft & Freedom Notice:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppConfig.gplWarrantyDisclaimer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await launchUrlString(
                AppConfig.upstreamRepositoryUrl,
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.fork_right_rounded, size: 16),
            label: Text(l10n?.btnOriginalProject ?? 'Original Project'),
          ),
          TextButton.icon(
            onPressed: () async {
              await launchUrlString(
                '${AppConfig.githubRepositoryUrl}/blob/main/LICENSE',
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text(l10n?.btnFullGplText ?? 'Full GPL Text'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n?.actionClose ?? 'Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewerModeCard(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n?.settingsReviewerModeActive ?? 'Reviewer Mode Active',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Tooltip(
                message:
                    'Bypasses live router connection and populates mock metrics for testing and review.',
                child: Icon(
                  Icons.help_outline_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n?.settingsReviewerModeDesc ??
                'Mock data is being used for demonstration. No live router is currently connected.',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showReviewerModeResetDialog(context, ref),
              icon: const Icon(Icons.exit_to_app_rounded, size: 18),
              label: Text(
                l10n?.settingsExitReviewerMode ?? 'Exit Reviewer Mode',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
