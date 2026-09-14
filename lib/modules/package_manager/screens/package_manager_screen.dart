// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';
import 'package:yet_another_luci_app/widgets/rpc_result_dialog.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../models/package_info.dart';

class PackageManagerScreen extends ConsumerStatefulWidget {
  const PackageManagerScreen({super.key});

  @override
  ConsumerState<PackageManagerScreen> createState() =>
      _PackageManagerScreenState();
}

class _PackageManagerScreenState extends ConsumerState<PackageManagerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<OpenWrtPackage>? _installedPackages;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isPermissionDenied = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPackages();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPackages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isPermissionDenied = false;
    });

    try {
      final appState = ref.read(appStateProvider);
      final res = await appState.fetchInstalledPackages();
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (res.isSuccess && res.data != null) {
            _installedPackages = res.data;
          } else {
            _errorMessage =
                res.errorMessage ??
                'Could not read installed packages from router.';
            _isPermissionDenied =
                res.isPermissionDenied ||
                (res.errorMessage != null &&
                    (res.errorMessage!.contains('code 6') ||
                        res.errorMessage!.toLowerCase().contains(
                          'permission denied',
                        )));
            _installedPackages = null;
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
          _installedPackages = null;
        });
      }
    }
  }

  void _handleRpcResult<T>(RpcResult<T> result, String actionLabel) {
    RpcResultUiHelper.handleRpcResult(context, result, actionLabel);
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final caps = appState.capabilities;
    final isApk = caps?.packageEngine == PackageManagerEngine.apk;
    final title = isApk ? 'APK Package Manager' : 'OPKG Package Manager';

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
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'Package Manager Not Detected',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'This router image does not have an active OPKG or APK package manager installed, or capability probing failed to detect one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () async {
                    context.showToastInfo(
                      'Capabilities Probe',
                      subtitle: 'Re-probing router capabilities...',
                    );
                    await ref.read(appStateProvider).redetectCapabilities();
                    await _loadPackages();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-detect Router Capabilities'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final filteredPackages = (_installedPackages ?? []).where((p) {
      if (_searchQuery.isEmpty) return true;
      return p.name.toLowerCase().contains(_searchQuery) ||
          p.description.toLowerCase().contains(_searchQuery);
    }).toList();

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
            tooltip: 'Refresh Installed Packages',
            onPressed: _isLoading ? null : _loadPackages,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Fetching installed packages...'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadPackages,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
                children: [
                  // Search input
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText:
                          'Search installed packages (e.g. luci-app, wireguard)...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_errorMessage != null &&
                      (_installedPackages == null ||
                          _installedPackages!.isEmpty)) ...[
                    const SizedBox(height: 24),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: _isPermissionDenied
                          ? Colors.orange.shade50
                          : Theme.of(context).cardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            Icon(
                              _isPermissionDenied
                                  ? Icons.lock_outline_rounded
                                  : Icons.cloud_off_rounded,
                              size: 56,
                              color: _isPermissionDenied
                                  ? Colors.orange.shade800
                                  : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isPermissionDenied
                                  ? 'Router Permission Denied (ubus code 6)'
                                  : 'Package List Unavailable',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: _isPermissionDenied
                                        ? Colors.orange.shade900
                                        : null,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isPermissionDenied
                                  ? 'OpenWrt\'s RPC daemon (rpcd) blocked package queries with ubus code 6 (Permission Denied).\n\n'
                                        'Stock LuCI images only allow package listing via the whitelisted helper:\n'
                                        '/usr/libexec/package-manager-call list-installed\n\n'
                                        'To fix on the router:\n'
                                        '1. Install luci-app-package-manager (grants the whitelisted exec ACL).\n'
                                        '2. Or install luci-mod-rpc for broader RPC file access.\n'
                                        '3. Ensure you log in as root.'
                                  : _errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _isPermissionDenied
                                    ? Colors.orange.shade900
                                    : Colors.grey.shade600,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _loadPackages,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    context.showToastInfo(
                                      'Capabilities Probe',
                                      subtitle:
                                          'Re-probing router capabilities...',
                                    );
                                    await ref
                                        .read(appStateProvider)
                                        .redetectCapabilities();
                                    await _loadPackages();
                                  },
                                  icon: const Icon(Icons.search),
                                  label: const Text('Re-detect Capabilities'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // Installed Packages Header
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Installed Packages (${filteredPackages.length})',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (filteredPackages.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Center(
                          child: Text(
                            _searchQuery.isNotEmpty
                                ? 'No installed packages matching "$_searchQuery".'
                                : 'No installed packages found.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      )
                    else
                      ...filteredPackages.map(
                        (p) => _buildPackageCard(context, p),
                      ),
                    const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildPackageCard(BuildContext context, OpenWrtPackage pkg) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: LuciStatusColors.connected.withValues(alpha: 0.15),
          child: Icon(
            Icons.inventory_2_outlined,
            color: LuciStatusColors.connected,
            size: 18,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                pkg.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                pkg.fileExtension,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'v${pkg.version} • ${pkg.description}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: OutlinedButton(
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Remove ${pkg.name}?'),
                content: Text(
                  'Are you sure you want to uninstall ${pkg.name} from the router?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            );

            if (confirm != true) return;

            final actionKey = 'pkg_remove_${pkg.name}';
            if (context.mounted) {
              context.showToastLoading(
                'Removing Package',
                subtitle: 'Removing ${pkg.name}...',
                actionKey: actionKey,
              );
            }

            final result = await ref
                .read(appStateProvider)
                .managePackageResult(packageName: pkg.name, action: 'remove');

            if (context.mounted) {
              if (result.isSuccess) {
                context.showToastSuccess(
                  'Package Removed',
                  subtitle: '${pkg.name} uninstalled successfully.',
                  actionKey: actionKey,
                );
                await _loadPackages();
              } else {
                _handleRpcResult(result, 'Removal of ${pkg.name}');
              }
            }
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: const BorderSide(color: Colors.red),
          ),
          child: const Text(
            'Remove',
            style: TextStyle(
              color: Colors.red,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
