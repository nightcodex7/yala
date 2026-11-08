// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/rpc_permissions_dialog.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/package_info.dart';

import '../../../state/controllers/package_controller.dart';

class PackageManagerScreen extends ConsumerStatefulWidget {
  const PackageManagerScreen({super.key});

  @override
  ConsumerState<PackageManagerScreen> createState() =>
      _PackageManagerScreenState();
}

class _PackageManagerScreenState extends ConsumerState<PackageManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  String _searchQuery = '';
  List<OpenWrtPackage> _filteredInstalled = const [];
  List<OpenWrtPackage> _filteredAvailable = const [];
  List<OpenWrtPackage> _filteredUpgradable = const [];
  PackageManagerOverview? _overview;
  bool _isLoading = true;
  bool _isUpdatingLists = false;
  String? _errorMessage;
  bool _isPermissionDenied = false;

  void _recomputeFilteredPackages() {
    final installedList = _overview?.installedPackages ?? const [];
    final availableList = _overview?.availablePackages ?? const [];
    final upgradableList = _overview?.upgradablePackages ?? const [];

    if (_searchQuery.isEmpty) {
      _filteredInstalled = installedList;
      _filteredAvailable = availableList;
      _filteredUpgradable = upgradableList;
      return;
    }

    _filteredInstalled = installedList.where((p) {
      return p.name.toLowerCase().contains(_searchQuery) ||
          p.description.toLowerCase().contains(_searchQuery);
    }).toList();

    _filteredAvailable = availableList.where((p) {
      return p.name.toLowerCase().contains(_searchQuery) ||
          p.description.toLowerCase().contains(_searchQuery);
    }).toList();

    _filteredUpgradable = upgradableList.where((p) {
      return p.name.toLowerCase().contains(_searchQuery) ||
          p.description.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _searchController.addListener(() {
      _searchDebounceTimer?.cancel();
      _searchDebounceTimer = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        final newQuery = _searchController.text.trim().toLowerCase();
        if (_searchQuery != newQuery) {
          setState(() {
            _searchQuery = newQuery;
            _recomputeFilteredPackages();
          });
        }
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPackages();
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPackages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isPermissionDenied = false;
      });
    }

    try {
      final appState = ref.read(appStateProvider);
      final res = await appState.fetchPackageManagerOverview();
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (res.isSuccess && res.data != null) {
            _overview = res.data;
            _recomputeFilteredPackages();
            if (_overview != null &&
                _overview!.activeManager !=
                    appState.capabilities?.packageEngine) {
              appState.updatePackageEngine(_overview!.activeManager);
            }
          } else {
            _errorMessage =
                res.errorMessage ??
                'Could not read package overview from router.';
            _isPermissionDenied =
                res.isPermissionDenied ||
                (res.errorMessage != null &&
                    (res.errorMessage!.contains('code 6') ||
                        res.errorMessage!.toLowerCase().contains(
                          'permission denied',
                        )));
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
          _isPermissionDenied =
              e.toString().toLowerCase().contains('permission denied') ||
              e.toString().contains('code 6');
        });
      }
    }
  }

  void _showCommandOutputDialog({
    required String title,
    required String output,
    int? exitCode,
    bool isError = true,
  }) {
    final isReadOnlyError = output.toLowerCase().contains(
      'read-only file system',
    );
    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final theme = Theme.of(context);
        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                color: isError
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isReadOnlyError) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: LuciStatusColors.warningBg(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: LuciStatusColors.warningBorder(context),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: LuciStatusColors.warningColor(context),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'The router\'s root filesystem is mounted read-only because there is no space left in the flash overlay partition (/overlay).\n\nTo resolve this:\n• Free up flash space or remove unused packages\n• Run "firstboot" via SSH to reset the overlay\n• Use Extroot (USB drive) for expanded storage',
                            style: TextStyle(
                              fontSize: 12,
                              color: LuciStatusColors.warningText(context),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (exitCode != null) ...[
                  Text(
                    'Exit code: $exitCode',
                    style: TextStyle(
                      color: isError
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    output.isNotEmpty ? output : 'No output returned.',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (output.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('Copy Log'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: output));
                  context.showToastSuccess('Log copied to clipboard');
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n?.actionConfirm ?? 'OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleUpdateLists() async {
    final appState = ref.read(appStateProvider);
    final l10n = AppLocalizations.of(context);

    if (appState.isMissingRpcPackages) {
      await RpcPermissionsDialog.show(
        context,
        actionName: l10n?.pkgBtnUpdateLists ?? 'Update lists',
      );
      return;
    }

    setState(() => _isUpdatingLists = true);
    context.showToastLoading(
      l10n?.pkgBtnUpdateLists ?? 'Updating package lists...',
      subtitle: l10n?.pkgUpdatingListsToast ?? 'Fetching repository feeds...',
      actionKey: 'pkg_update_lists',
    );

    final res = await appState.updatePackageLists();

    if (mounted) {
      setState(() => _isUpdatingLists = false);
      if (res.isSuccess) {
        context.showToastSuccess(
          l10n?.pkgBtnUpdateLists ?? 'Lists Updated',
          subtitle:
              l10n?.pkgListsUpdatedSuccess ??
              'Package lists updated successfully.',
          actionKey: 'pkg_update_lists',
        );
        await _loadPackages(silent: true);
      } else {
        context.showToastError(
          l10n?.pkgListsUpdateFailed ?? 'Update Failed',
          subtitle: res.userFriendlyPackageError,
          actionKey: 'pkg_update_lists',
        );
        _showCommandOutputDialog(
          title: l10n?.pkgExecutionOutputTitle ?? 'Package Manager Output',
          output: res.errorMessage ?? 'Command failed',
          exitCode: res.errorCode,
          isError: true,
        );
      }
    }
  }

  Future<void> _showInstallCustomDialog() async {
    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);

    if (appState.isMissingRpcPackages) {
      await RpcPermissionsDialog.show(
        context,
        actionName: l10n?.pkgBtnInstallCustom ?? 'Install Custom Package',
      );
      return;
    }

    final isApk =
        (_overview?.activeManager ?? appState.capabilities?.packageEngine) ==
            PackageManagerType.apk ||
        (appState.capabilities?.isApk ?? false);
    final ext = isApk ? '.apk' : '.ipk';

    final controller = TextEditingController();
    final target = await showDialog<String>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Text(l10n?.pkgInstallCustomTitle ?? 'Install Custom Package'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n?.pkgInstallCustomDesc(ext) ??
                      'Enter package name, or URL to an $ext package:',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText:
                        l10n?.pkgInstallCustomHint ??
                        'e.g. luci-app-wireguard or https://...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n?.actionCancel ?? 'Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final val = controller.text.trim();
                if (val.isNotEmpty) Navigator.pop(context, val);
              },
              child: Text(l10n?.pkgActionInstall ?? 'Install'),
            ),
          ],
        );
      },
    );

    if (target == null || target.isEmpty) return;

    if (mounted) {
      context.showToastLoading(
        l10n?.pkgInstallingToast(target) ?? 'Installing $target...',
        actionKey: 'pkg_install_$target',
      );
    }

    final res = await appState.installCustomPackage(target);

    if (mounted) {
      if (res.isSuccess) {
        context.showToastSuccess(
          l10n?.pkgInstalledSuccess(target) ??
              '$target installed successfully.',
          actionKey: 'pkg_install_$target',
        );
        await _loadPackages(silent: true);
      } else {
        context.showToastError(
          'Installation Failed',
          subtitle: res.userFriendlyPackageError,
          actionKey: 'pkg_install_$target',
        );
        _showCommandOutputDialog(
          title: l10n?.pkgExecutionOutputTitle ?? 'Installation Output',
          output: res.errorMessage ?? 'Failed to install $target',
          exitCode: res.errorCode,
          isError: true,
        );
      }
    }
  }

  Future<void> _confirmAndUninstall(OpenWrtPackage pkg) async {
    final appState = ref.read(appStateProvider);
    final l10n = AppLocalizations.of(context);

    if (appState.isMissingRpcPackages) {
      await RpcPermissionsDialog.show(
        context,
        actionName: '${l10n?.pkgActionUninstall ?? "Uninstall"} ${pkg.name}',
      );
      return;
    }

    final isCritical = PackageController.isCriticalPackage(pkg.name);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        if (isCritical) {
          return AlertDialog(
            actionsOverflowButtonSpacing: 8,
            actionsOverflowDirection: VerticalDirection.down,
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.pkgCriticalWarningTitle ?? 'Critical System Package',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(
                l10n?.pkgCriticalWarningDesc(pkg.name) ??
                    '${pkg.name} is an essential system component. Removing it may permanently break router connectivity or the LuCI interface. Do you still wish to proceed?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n?.actionCancel ?? 'Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n?.pkgActionUninstall ?? 'Uninstall Anyway'),
              ),
            ],
          );
        }

        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Text(
            l10n?.pkgMgrRemoveTitle(pkg.name) ?? 'Uninstall ${pkg.name}?',
          ),
          content: SingleChildScrollView(
            child: Text(
              l10n?.pkgMgrRemoveConfirm(pkg.name) ??
                  'Are you sure you want to uninstall ${pkg.name} from the router?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n?.actionCancel ?? 'Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n?.pkgActionUninstall ?? 'Uninstall'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final actionKey = 'pkg_remove_${pkg.name}';
    if (mounted) {
      context.showToastLoading(
        l10n?.pkgMgrToastRemoving ?? 'Removing Package',
        subtitle:
            l10n?.pkgMgrToastRemovingSubtitle(pkg.name) ??
            'Removing ${pkg.name}...',
        actionKey: actionKey,
      );
    }

    final res = await appState.removePackage(pkg.name);

    if (mounted) {
      if (res.isSuccess) {
        context.showToastSuccess(
          l10n?.pkgMgrToastRemoved ?? 'Package Removed',
          subtitle:
              l10n?.pkgMgrToastRemovedSubtitle(pkg.name) ??
              '${pkg.name} uninstalled successfully.',
          actionKey: actionKey,
        );
        await _loadPackages(silent: true);
      } else {
        context.showToastError(
          'Uninstall Failed',
          subtitle: res.userFriendlyPackageError,
          actionKey: actionKey,
        );
        _showCommandOutputDialog(
          title: l10n?.pkgExecutionOutputTitle ?? 'Package Removal Output',
          output: res.errorMessage ?? 'Failed to remove ${pkg.name}',
          exitCode: res.errorCode,
          isError: true,
        );
      }
    }
  }

  Future<void> _confirmAndInstall(OpenWrtPackage pkg) async {
    final appState = ref.read(appStateProvider);
    final l10n = AppLocalizations.of(context);

    if (appState.isMissingRpcPackages) {
      await RpcPermissionsDialog.show(
        context,
        actionName: '${l10n?.pkgActionInstall ?? "Install"} ${pkg.name}',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Text(
          l10n?.pkgConfirmInstallTitle(pkg.name) ?? 'Install ${pkg.name}?',
        ),
        content: SingleChildScrollView(
          child: Text(
            l10n?.pkgConfirmInstallPrompt(pkg.name) ??
                'Are you sure you want to install ${pkg.name} on the router?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n?.pkgActionInstall ?? 'Install'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final actionKey = 'pkg_install_${pkg.name}';
    if (mounted) {
      context.showToastLoading(
        l10n?.pkgInstallingToast(pkg.name) ?? 'Installing ${pkg.name}...',
        actionKey: actionKey,
      );
    }

    final res = await appState.installPackage(pkg.name);

    if (mounted) {
      if (res.isSuccess) {
        context.showToastSuccess(
          l10n?.pkgInstalledSuccess(pkg.name) ??
              '${pkg.name} installed successfully.',
          actionKey: actionKey,
        );
        await _loadPackages(silent: true);
      } else {
        context.showToastError(
          'Installation Failed',
          subtitle: res.userFriendlyPackageError,
          actionKey: actionKey,
        );
        _showCommandOutputDialog(
          title: l10n?.pkgExecutionOutputTitle ?? 'Installation Output',
          output: res.errorMessage ?? 'Failed to install ${pkg.name}',
          exitCode: res.errorCode,
          isError: true,
        );
      }
    }
  }

  Future<void> _confirmAndUpgrade(OpenWrtPackage pkg) async {
    final appState = ref.read(appStateProvider);
    final l10n = AppLocalizations.of(context);

    if (appState.isMissingRpcPackages) {
      await RpcPermissionsDialog.show(
        context,
        actionName: '${l10n?.pkgActionUpgrade ?? "Upgrade"} ${pkg.name}',
      );
      return;
    }

    final newVer = pkg.newVersion ?? 'latest';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Text(
          l10n?.pkgConfirmUpgradeTitle(pkg.name) ?? 'Upgrade ${pkg.name}?',
        ),
        content: SingleChildScrollView(
          child: Text(
            l10n?.pkgConfirmUpgradePrompt(pkg.name, pkg.version, newVer) ??
                'Upgrade ${pkg.name} from ${pkg.version} to $newVer?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n?.pkgActionUpgrade ?? 'Upgrade'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final actionKey = 'pkg_upgrade_${pkg.name}';
    if (mounted) {
      context.showToastLoading(
        l10n?.pkgUpgradingToast(pkg.name) ?? 'Upgrading ${pkg.name}...',
        actionKey: actionKey,
      );
    }

    final res = await appState.upgradePackage(pkg.name);

    if (mounted) {
      if (res.isSuccess) {
        context.showToastSuccess(
          l10n?.pkgUpgradedSuccess(pkg.name) ??
              '${pkg.name} upgraded successfully.',
          actionKey: actionKey,
        );
        await _loadPackages(silent: true);
      } else {
        context.showToastError(
          'Upgrade Failed',
          subtitle: res.userFriendlyPackageError,
          actionKey: actionKey,
        );
        _showCommandOutputDialog(
          title: l10n?.pkgExecutionOutputTitle ?? 'Upgrade Output',
          output: res.errorMessage ?? 'Failed to upgrade ${pkg.name}',
          exitCode: res.errorCode,
          isError: true,
        );
      }
    }
  }

  void _showPackageDetails(BuildContext context, OpenWrtPackage pkg) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isRpcMissing = ref.read(appStateProvider).isMissingRpcPackages;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: ListView(
                controller: scrollController,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: pkg.isInstalled
                            ? LuciStatusColors.connectedColor(
                                context,
                              ).withValues(alpha: 0.15)
                            : theme.colorScheme.primary.withValues(alpha: 0.15),
                        child: Icon(
                          pkg.isInstalled
                              ? Icons.inventory_2_outlined
                              : Icons.cloud_download_outlined,
                          color: pkg.isInstalled
                              ? LuciStatusColors.connectedColor(context)
                              : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pkg.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    pkg.fileExtension,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (PackageController.isCriticalPackage(
                                  pkg.name,
                                ))
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'CORE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildDetailRow(
                    l10n?.pkgDetailsVersion ?? 'Version',
                    pkg.hasUpdate && pkg.newVersion != null
                        ? '${pkg.version} ➔ ${pkg.newVersion}'
                        : pkg.version,
                  ),
                  if (pkg.formattedSize != null)
                    _buildDetailRow(
                      l10n?.pkgDetailsSize ?? 'Size',
                      pkg.formattedSize!,
                    ),
                  if (pkg.architecture != null)
                    _buildDetailRow(
                      l10n?.pkgDetailsArchitecture ?? 'Architecture',
                      pkg.architecture!,
                    ),
                  if (pkg.section != null)
                    _buildDetailRow(
                      l10n?.pkgDetailsSection ?? 'Section',
                      pkg.section!,
                    ),
                  if (pkg.license != null)
                    _buildDetailRow(
                      l10n?.pkgDetailsLicense ?? 'License',
                      pkg.license!,
                    ),
                  _buildDetailRow(
                    l10n?.pkgDetailsDependencies ?? 'Dependencies',
                    pkg.dependencies?.isNotEmpty == true
                        ? pkg.dependencies!
                        : (l10n?.pkgDetailsNoDeps ?? 'None'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pkg.description,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  if (pkg.isInstalled)
                    Row(
                      children: [
                        if (pkg.hasUpdate) ...[
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isRpcMissing
                                    ? theme.colorScheme.surfaceContainerHighest
                                    : theme.colorScheme.primary,
                                foregroundColor: isRpcMissing
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.onPrimary,
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                if (isRpcMissing) {
                                  RpcPermissionsDialog.show(
                                    context,
                                    actionName:
                                        '${l10n?.pkgActionUpgrade ?? "Upgrade"} ${pkg.name}',
                                  );
                                } else {
                                  _confirmAndUpgrade(pkg);
                                }
                              },
                              icon: Icon(
                                isRpcMissing
                                    ? Icons.lock_outline_rounded
                                    : Icons.upgrade_rounded,
                                size: 18,
                                color: isRpcMissing
                                    ? LuciStatusColors.warningColor(context)
                                    : null,
                              ),
                              label: Text(l10n?.pkgActionUpgrade ?? 'Upgrade'),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isRpcMissing
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.error,
                              side: BorderSide(
                                color: isRpcMissing
                                    ? theme.colorScheme.outlineVariant
                                    : theme.colorScheme.error.withValues(
                                        alpha: 0.5,
                                      ),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              if (isRpcMissing) {
                                RpcPermissionsDialog.show(
                                  context,
                                  actionName:
                                      '${l10n?.pkgActionUninstall ?? "Uninstall"} ${pkg.name}',
                                );
                              } else {
                                _confirmAndUninstall(pkg);
                              }
                            },
                            icon: Icon(
                              isRpcMissing
                                  ? Icons.lock_outline_rounded
                                  : Icons.delete_outline,
                              size: 18,
                              color: isRpcMissing
                                  ? LuciStatusColors.warningColor(context)
                                  : null,
                            ),
                            label: Text(
                              l10n?.pkgActionUninstall ?? 'Uninstall',
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRpcMissing
                            ? theme.colorScheme.surfaceContainerHighest
                            : theme.colorScheme.primary,
                        foregroundColor: isRpcMissing
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        if (isRpcMissing) {
                          RpcPermissionsDialog.show(
                            context,
                            actionName:
                                '${l10n?.pkgActionInstall ?? "Install"} ${pkg.name}',
                          );
                        } else {
                          _confirmAndInstall(pkg);
                        }
                      },
                      icon: Icon(
                        isRpcMissing
                            ? Icons.lock_outline_rounded
                            : Icons.download_rounded,
                        size: 18,
                        color: isRpcMissing
                            ? LuciStatusColors.warningColor(context)
                            : null,
                      ),
                      label: Text(l10n?.pkgActionInstall ?? 'Install Package'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildRpcPermissionsBanner(
    BuildContext context,
    AppState appState,
    AppLocalizations? l10n,
  ) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: LuciStatusColors.warningBg(context),
        border: Border(
          bottom: BorderSide(color: LuciStatusColors.warningBorder(context)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 20,
            color: LuciStatusColors.warningColor(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n?.rpcdPermissionDenied ?? 'Permissions Required',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: LuciStatusColors.warningText(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n != null
                      ? l10n.rpcdPermissionDeniedMessage(
                          l10n.pkgCardPackageManager,
                        )
                      : 'Package updates, installations, and removals are restricted until RPC permissions are granted.',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => RpcPermissionsDialog.show(
              context,
              actionName: l10n?.pkgCardPackageManager ?? 'Package Manager',
            ),
            child: Text(
              l10n?.btnFixAutomatically ?? 'Fix Permissions',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final caps = ref.watch(appStateProvider.select((s) => s.capabilities));
    final isRpcMissing = ref.watch(
      appStateProvider.select((s) => s.isMissingRpcPackages),
    );
    final isApk =
        (_overview?.activeManager ?? caps?.packageEngine) ==
            PackageManagerType.apk ||
        (caps?.isApk ?? false);
    final title = isApk
        ? (l10n?.pkgMgrTitleApk ?? 'APK Package Manager')
        : (l10n?.pkgMgrTitleOpkg ?? 'OPKG Package Manager');

    if (caps != null && caps.packageEngine == PackageManagerEngine.none) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.extension_off_rounded,
                  size: 64,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n?.pkgMgrNotDetectedTitle ??
                      'Package Manager Not Detected',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n?.pkgMgrNotDetectedDesc ??
                      'This router image does not have an active OPKG or APK package manager installed, or capability probing failed to detect one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () async {
                    context.showToastInfo(
                      'Capabilities Probe',
                      subtitle:
                          l10n?.pkgReProbingCapabilities ??
                          'Re-probing router capabilities...',
                    );
                    await ref.read(appStateProvider).redetectCapabilities();
                    await _loadPackages();
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    l10n?.pkgMgrBtnRedetect ?? 'Re-detect Router Capabilities',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final installedList = _overview?.installedPackages ?? [];
    final availableList = _overview?.availablePackages ?? [];
    final upgradableList = _overview?.upgradablePackages ?? [];

    final filteredInstalled = _filteredInstalled;
    final filteredAvailable = _filteredAvailable;
    final filteredUpgradable = _filteredUpgradable;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: l10n?.pkgMgrTooltipRefresh ?? 'Refresh Packages',
            onPressed: _isLoading ? null : () => _loadPackages(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n?.pkgTabInstalled ?? 'Installed'),
                  if (installedList.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildBadgeCount(installedList.length),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n?.pkgTabAvailable ?? 'Available'),
                  if (availableList.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildBadgeCount(availableList.length),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n?.pkgTabUpdates ?? 'Updates'),
                  if (upgradableList.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildBadgeCount(upgradableList.length, isAmber: true),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    l10n?.pkgMgrLoadingPackages ??
                        'Fetching software packages...',
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (isRpcMissing)
                  _buildRpcPermissionsBanner(
                    context,
                    ref.read(appStateProvider),
                    l10n,
                  ),
                // Top Action Toolbar
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Search bar
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText:
                              l10n?.pkgMgrSearchHint ??
                              'Search packages (e.g. luci-app, wireguard)...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchDebounceTimer?.cancel();
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                      _recomputeFilteredPackages();
                                    });
                                  },
                                )
                              : null,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Top Buttons & Free space indicator
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                side: isRpcMissing
                                    ? BorderSide(
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.3),
                                      )
                                    : null,
                              ),
                              onPressed: _isUpdatingLists
                                  ? null
                                  : (isRpcMissing
                                        ? () => RpcPermissionsDialog.show(
                                            context,
                                            actionName:
                                                l10n?.pkgBtnUpdateLists ??
                                                'Update lists',
                                          )
                                        : _handleUpdateLists),
                              icon: _isUpdatingLists
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      isRpcMissing
                                          ? Icons.lock_outline_rounded
                                          : Icons.sync_rounded,
                                      size: 16,
                                      color: isRpcMissing
                                          ? LuciStatusColors.warningColor(
                                              context,
                                            )
                                          : null,
                                    ),
                              label: Text(
                                l10n?.pkgBtnUpdateLists ?? 'Update lists...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isRpcMissing
                                      ? theme.colorScheme.onSurface.withValues(
                                          alpha: 0.6,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: isRpcMissing
                                ? (l10n?.rpcdPermissionDenied ??
                                      'Permissions Required')
                                : (l10n?.pkgBtnInstallCustom ??
                                      'Install custom package'),
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              side: isRpcMissing
                                  ? BorderSide(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.3),
                                    )
                                  : null,
                            ),
                            icon: Icon(
                              isRpcMissing
                                  ? Icons.lock_outline_rounded
                                  : Icons.add_box_outlined,
                              size: 18,
                              color: isRpcMissing
                                  ? LuciStatusColors.warningColor(context)
                                  : null,
                            ),
                            onPressed: isRpcMissing
                                ? () => RpcPermissionsDialog.show(
                                    context,
                                    actionName:
                                        l10n?.pkgBtnInstallCustom ??
                                        'Install custom package',
                                  )
                                : _showInstallCustomDialog,
                          ),
                          if (_overview?.formattedFreeSpace != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.storage_outlined,
                                    size: 14,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    l10n?.pkgFreeSpace(
                                          _overview!.formattedFreeSpace!,
                                        ) ??
                                        'Free: ${_overview!.formattedFreeSpace}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Error or Permission Denied banner
                if (_errorMessage != null &&
                    (_overview == null || installedList.isEmpty)) ...[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: _isPermissionDenied
                          ? theme.colorScheme.errorContainer.withValues(
                              alpha: 0.3,
                            )
                          : theme.colorScheme.surfaceContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            Icon(
                              _isPermissionDenied
                                  ? Icons.lock_outline_rounded
                                  : Icons.cloud_off_rounded,
                              size: 48,
                              color: _isPermissionDenied
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isPermissionDenied
                                  ? (l10n?.pkgMgrPermDeniedTitle ??
                                        'Router Permission Denied (ubus code 6)')
                                  : (l10n?.pkgMgrListUnavailable ??
                                        'Package List Unavailable'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: _isPermissionDenied
                                        ? theme.colorScheme.onErrorContainer
                                        : null,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isPermissionDenied
                                  ? (l10n?.pkgMgrPermDeniedDesc ??
                                        'Stock LuCI images require /usr/libexec/package-manager-call.')
                                  : _errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _isPermissionDenied
                                    ? theme.colorScheme.onErrorContainer
                                    : theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _loadPackages(),
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: Text(l10n?.pkgMgrBtnRetry ?? 'Retry'),
                                ),
                                if (_isPermissionDenied || isRpcMissing) ...[
                                  const SizedBox(width: 12),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          theme.colorScheme.primary,
                                      foregroundColor:
                                          theme.colorScheme.onPrimary,
                                    ),
                                    onPressed: () => RpcPermissionsDialog.show(
                                      context,
                                      actionName:
                                          l10n?.pkgCardPackageManager ??
                                          'Package Manager',
                                    ),
                                    icon: const Icon(
                                      Icons.build_circle_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      l10n?.btnFixAutomatically ??
                                          'Fix Permissions',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 0: Installed
                      _buildPackageList(
                        packages: filteredInstalled,
                        emptyMessage: _searchQuery.isNotEmpty
                            ? (l10n?.pkgMgrNoMatching(_searchQuery) ??
                                  'No installed packages matching "$_searchQuery".')
                            : (l10n?.pkgMgrNoPackages ??
                                  'No installed packages found.'),
                        actionType: _PackageActionType.uninstall,
                      ),

                      // Tab 1: Available
                      _buildPackageList(
                        packages: filteredAvailable,
                        emptyMessage: _searchQuery.isNotEmpty
                            ? 'No available packages matching "$_searchQuery".'
                            : 'No repository packages available. Tap "Update lists..." to refresh feeds.',
                        actionType: _PackageActionType.install,
                      ),

                      // Tab 2: Updates
                      _buildPackageList(
                        packages: filteredUpgradable,
                        emptyMessage: _searchQuery.isNotEmpty
                            ? 'No updates matching "$_searchQuery".'
                            : 'All packages are up to date.',
                        actionType: _PackageActionType.upgrade,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBadgeCount(int count, {bool isAmber = false}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: isAmber
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isAmber
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildPackageList({
    required List<OpenWrtPackage> packages,
    required String emptyMessage,
    required _PackageActionType actionType,
  }) {
    if (packages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: packages.length,
      itemBuilder: (context, index) {
        final pkg = packages[index];
        return _buildPackageItem(pkg, actionType);
      },
    );
  }

  Widget _buildPackageItem(OpenWrtPackage pkg, _PackageActionType actionType) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isCore = PackageController.isCriticalPackage(pkg.name);
    final isRpcMissing = ref.watch(appStateProvider).isMissingRpcPackages;

    final Widget actionButton;
    switch (actionType) {
      case _PackageActionType.uninstall:
        actionButton = OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: isRpcMissing
                  ? theme.colorScheme.outlineVariant
                  : Colors.red,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: isRpcMissing
              ? () => RpcPermissionsDialog.show(
                  context,
                  actionName:
                      '${l10n?.pkgActionUninstall ?? "Uninstall"} ${pkg.name}',
                )
              : () => _confirmAndUninstall(pkg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRpcMissing) ...[
                Icon(
                  Icons.lock_outline_rounded,
                  size: 12,
                  color: LuciStatusColors.warningColor(context),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                l10n?.pkgActionUninstall ?? 'Uninstall',
                style: TextStyle(
                  color: isRpcMissing
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.error,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
        break;

      case _PackageActionType.install:
        actionButton = ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isRpcMissing
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primary,
            foregroundColor: isRpcMissing
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: isRpcMissing
              ? () => RpcPermissionsDialog.show(
                  context,
                  actionName:
                      '${l10n?.pkgActionInstall ?? "Install"} ${pkg.name}',
                )
              : () => _confirmAndInstall(pkg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRpcMissing) ...[
                Icon(
                  Icons.lock_outline_rounded,
                  size: 12,
                  color: LuciStatusColors.warningColor(context),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                l10n?.pkgActionInstall ?? 'Install',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
        break;

      case _PackageActionType.upgrade:
        actionButton = ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isRpcMissing
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primary,
            foregroundColor: isRpcMissing
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: isRpcMissing
              ? () => RpcPermissionsDialog.show(
                  context,
                  actionName:
                      '${l10n?.pkgActionUpgrade ?? "Upgrade"} ${pkg.name}',
                )
              : () => _confirmAndUpgrade(pkg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRpcMissing) ...[
                Icon(
                  Icons.lock_outline_rounded,
                  size: 12,
                  color: LuciStatusColors.warningColor(context),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                l10n?.pkgActionUpgrade ?? 'Upgrade',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showPackageDetails(context, pkg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: pkg.isInstalled
                    ? LuciStatusColors.successBg(context)
                    : theme.colorScheme.primary.withValues(alpha: 0.15),
                child: Icon(
                  actionType == _PackageActionType.upgrade
                      ? Icons.upgrade_rounded
                      : (pkg.isInstalled
                            ? Icons.inventory_2_outlined
                            : Icons.cloud_download_outlined),
                  color: actionType == _PackageActionType.upgrade
                      ? theme.colorScheme.primary
                      : (pkg.isInstalled
                            ? LuciStatusColors.connectedColor(context)
                            : theme.colorScheme.primary),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            pkg.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            pkg.fileExtension,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        if (isCore) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'CORE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      actionType == _PackageActionType.upgrade &&
                              pkg.newVersion != null
                          ? 'v${pkg.version} ➔ v${pkg.newVersion} • ${pkg.description}'
                          : 'v${pkg.version}${pkg.formattedSize != null ? " • ${pkg.formattedSize}" : ""} • ${pkg.description}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              actionButton,
            ],
          ),
        ),
      ),
    );
  }
}

enum _PackageActionType { install, uninstall, upgrade }
