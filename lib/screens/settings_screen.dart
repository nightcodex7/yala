// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yet_another_luci_app/main.dart';

import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/design/luci_theme.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/screens/dashboard_settings_list_screen.dart';
import 'package:yet_another_luci_app/screens/manage_routers_screen.dart';
import 'package:yet_another_luci_app/services/update_checker_service.dart';
import 'package:yet_another_luci_app/widgets/theme_router_logo.dart';
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Reviewer Mode?'),
        content: const Text(
          'This will disable reviewer mode and return to normal authentication. '
          'You will need to log in with real router credentials.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await appState.setReviewerMode(false);
              if (context.mounted) {
                await Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final activeRouter = appState.selectedRouter;

    return Scaffold(
      appBar: const LuciAppBar(title: 'Settings', showBack: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          // Active Router Quick Banner
          if (activeRouter != null) ...[
            _buildActiveRouterBanner(context, appState),
            const SizedBox(height: 20),
          ],

          // Theme / Appearance Section
          _buildSectionHeader(context, 'APPEARANCE', Icons.palette_outlined),
          const SizedBox(height: 8),
          _buildThemeSegmentedSelector(context, appState),
          const SizedBox(height: 12),
          _buildPaletteSelector(context, appState),
          const SizedBox(height: 24),

          // Dashboard Section
          _buildSectionHeader(
            context,
            'DASHBOARD',
            Icons.dashboard_customize_outlined,
          ),
          const SizedBox(height: 8),
          _buildCustomizeDashboardTile(context),
          const SizedBox(height: 24),

          // Router Diagnostics & Surface Section
          _buildSectionHeader(
            context,
            'ROUTER DIAGNOSTICS & SURFACE',
            Icons.radar_outlined,
          ),
          const SizedBox(height: 8),
          _buildCapabilitiesTile(context, appState),
          const SizedBox(height: 24),

          // App Updates (if community flavor)
          if (AppConfig.isCommunityFlavor) ...[
            _buildSectionHeader(
              context,
              'APP UPDATES',
              Icons.system_update_outlined,
            ),
            const SizedBox(height: 8),
            _buildUpdatesTile(context),
            const SizedBox(height: 24),
          ],

          // Build Verification & Privacy
          _buildSectionHeader(
            context,
            'BUILD VERIFICATION & PRIVACY',
            Icons.verified_user_outlined,
          ),
          const SizedBox(height: 8),
          _buildBuildVerificationTile(context),
          const SizedBox(height: 24),

          // Legal & Policy
          _buildSectionHeader(context, 'LEGAL & POLICY', Icons.gavel_outlined),
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
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: LuciTextStyles.sectionHeader(context)),
        ],
      ),
    );
  }

  Widget _buildActiveRouterBanner(BuildContext context, AppState appState) {
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
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: LuciStatusColors.successBg(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: LuciStatusColors.successBorder(context),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LuciStatusIndicators.statusDot(
                            context,
                            appState.hasActiveSession,
                            size: 8,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            appState.hasActiveSession ? 'Active' : 'Offline',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: LuciStatusColors.successText(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${router.ipAddress} • $boardName',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: 'Switch or Manage Routers',
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

    final options = [
      (
        mode: ThemeMode.system,
        label: 'System',
        icon: Icons.brightness_auto_rounded,
      ),
      (mode: ThemeMode.light, label: 'Light', icon: Icons.light_mode_rounded),
      (mode: ThemeMode.dark, label: 'Dark', icon: Icons.dark_mode_rounded),
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

  Widget _buildPaletteSelector(
    BuildContext context,
    AppState appState,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final currentPalette = appState.themePalette;

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
                Text(
                  'Color Palette',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
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
            final swatch = palette.swatchColor(isDark);

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
                          border: Border.all(
                            color: swatch,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          palette.icon,
                          size: 16,
                          color: swatch,
                        ),
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
                              palette.subtitle,
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
                                : colorScheme.outlineVariant.withValues(alpha: 0.5),
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
          title: const Text(
            'Customize Dashboard',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
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

  Widget _buildCapabilitiesTile(BuildContext context, AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    final caps = appState.capabilities;

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
                        const Text(
                          'Re-detect Router Capabilities',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
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
                                'Capabilities Detected',
                                subtitle:
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
                      'Package Engine',
                      caps.packageEngine.name.toUpperCase(),
                      Icons.inventory_2_outlined,
                    ),
                    _buildCapabilityChip(
                      context,
                      'Firewall',
                      caps.firewallBackend.name.toUpperCase(),
                      Icons.shield_outlined,
                    ),
                    _buildCapabilityChip(
                      context,
                      'Network Model',
                      caps.networkModel.name.toUpperCase(),
                      Icons.lan_outlined,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapabilityChip(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
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
          Icon(icon, size: 14, color: colorScheme.primary),
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
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatesTile(BuildContext context) {
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
              Icons.system_update_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 24,
            ),
          ),
          title: const Text(
            'Check for Updates',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text(
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
                ? 'Official Build & Privacy Guarantee'
                : 'Unofficial / Self-Built Build',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Text(
              isOfficial
                  ? 'Flavor: ${AppConfig.flavorName} • Zero Analytics & Telemetry'
                  : 'Flavor: ${AppConfig.flavorName} (Unverified) • Zero Analytics',
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
                ? LuciStatusColors.connected
                : Colors.orange.shade700,
          ),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(
                      isOfficial
                          ? Icons.verified_rounded
                          : Icons.warning_amber_rounded,
                      color: isOfficial
                          ? LuciStatusColors.connected
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isOfficial
                            ? 'Build Verification'
                            : 'Unofficial Build Notice',
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
                        'Build Channel: ${AppConfig.flavorName} Edition ${isOfficial ? "(Official)" : "(Unofficial / Local)"}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isOfficial
                            ? '• Verified Official Release Build'
                            : '• Unofficial / Self-Compiled Build',
                        style: TextStyle(
                          color: isOfficial
                              ? LuciStatusColors.connected
                              : Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text('• 100% On-Device RPC Communication'),
                      const Text('• Zero Analytics, Tracking, or Telemetry'),
                      const SizedBox(height: 12),
                      SelectableText(
                        'Repository: ${AppConfig.githubRepositoryUrl}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
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
                title: const Text(
                  'Privacy Policy',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Read our local-first zero-telemetry policy',
                  style: TextStyle(fontSize: 12),
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
                title: const Text(
                  'Terms & Conditions',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Terms of service and usage guidelines',
                  style: TextStyle(fontSize: 12),
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
                title: const Text(
                  'Contact & Support',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Get in touch or request support',
                  style: TextStyle(fontSize: 12),
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
                title: const Text(
                  'License & Attribution (GPLv3)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'GNU General Public License v3.0 • Copyleft & Credits',
                  style: TextStyle(fontSize: 12),
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
                title: const Text(
                  'Open Source Licenses',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Third-party software notices and licenses',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Yet Another LuCI App',
                  applicationVersion: '1.0.3',
                  applicationLegalese:
                      'Original work Copyright (C) 2025–2026 cogwheel0\n'
                      'Modifications Copyright (C) 2026 @nightcodex7\n'
                      'Licensed under GNU General Public License v3.0 or later.',
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
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
            label: const Text('Original Project'),
          ),
          TextButton.icon(
            onPressed: () async {
              await launchUrlString(
                '${AppConfig.githubRepositoryUrl}/blob/main/LICENSE',
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Full GPL Text'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewerModeCard(BuildContext context, WidgetRef ref) {
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
              const Expanded(
                child: Text(
                  'Reviewer Mode Active',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
            'Mock data is being used for demonstration. No live router is currently connected.',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showReviewerModeResetDialog(context, ref),
              icon: const Icon(Icons.exit_to_app_rounded, size: 18),
              label: const Text('Exit Reviewer Mode'),
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
