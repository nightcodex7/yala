// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/utils/url_parser.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/utils/logger.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class ManageRoutersScreen extends ConsumerStatefulWidget {
  final bool isFromLogin;

  const ManageRoutersScreen({super.key, this.isFromLogin = false});

  @override
  ConsumerState<ManageRoutersScreen> createState() =>
      _ManageRoutersScreenState();
}

class _ManageRoutersScreenState extends ConsumerState<ManageRoutersScreen> {
  String? _switchingRouterId;

  Future<void> _showRenameDialog(
    BuildContext context,
    model.Router router,
  ) async {
    final appState = ref.read(appStateProvider);
    final controller = TextEditingController(text: router.name ?? '');
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Rename Router Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assign a custom nickname to identify ${router.ipAddress}',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Profile Name',
                  hintText: 'e.g. Home Lab, Living Room, Travel Router',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline_rounded),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            if (router.name != null && router.name!.trim().isNotEmpty)
              TextButton(
                onPressed: () {
                  controller.clear();
                  Navigator.pop(ctx, true);
                },
                child: const Text('Clear Name'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (saved == true && context.mounted) {
        final newName = controller.text.trim().isEmpty
            ? null
            : controller.text.trim();
        await appState.updateRouterName(router.id, newName);
        if (context.mounted) {
          context.showToastSuccess(
            'Profile Updated',
            subtitle: newName != null
                ? 'Renamed to "$newName"'
                : 'Reset to default name',
          );
        }
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _exportProfiles(BuildContext context, AppState appState) async {
    if (appState.routers.isEmpty) {
      context.showToastInfo('No router profiles to export.');
      return;
    }

    try {
      context.showToastLoading(
        'Exporting Profiles...',
        actionKey: 'export_profiles',
      );
      final result = await appState.exportRouterProfiles();
      LuciToastManager.dismissAllLoading();

      if (!context.mounted) return;

      if (result != null) {
        context.showToastSuccess(
          'Profiles Exported',
          subtitle: 'Saved to Downloads: ${result.filePath.split('/').last}',
        );
        await OsPlatformIntegration.showFileDownloadedPrompt(
          context,
          result,
          title: 'Profiles Exported Successfully',
          fileLabel: 'Profiles JSON Path',
          icon: Icons.file_download_done_rounded,
          accentColor: Theme.of(context).colorScheme.primary,
        );
      } else {
        context.showToastError(
          'Export Failed',
          subtitle: 'Could not save file to downloads directory.',
        );
      }
    } catch (e) {
      LuciToastManager.dismissAllLoading();
      if (context.mounted) {
        context.showToastError('Export Error', subtitle: e.toString());
      }
    }
  }

  Future<void> _importProfiles(BuildContext context, AppState appState) async {
    try {
      final result = await appState.importRouterProfilesFromFile();

      if (!context.mounted) return;

      if (result.errorMessage == 'No file selected.') {
        // User cancelled file picker; quietly return
        return;
      }

      if (result.success) {
        final buffer = StringBuffer();
        if (result.importedCount > 0) {
          buffer.write('Imported ${result.importedCount} new profile(s)');
        }
        if (result.updatedCount > 0) {
          if (buffer.isNotEmpty) buffer.write(', ');
          buffer.write('updated ${result.updatedCount} existing profile(s)');
        }
        if (buffer.isEmpty) {
          buffer.write('Profiles processed successfully');
        }

        context.showToastSuccess(
          'Import Successful',
          subtitle: buffer.toString(),
        );

        await appState.loadRouters();
      } else {
        context.showToastError(
          'Import Failed',
          subtitle: result.errorMessage ?? 'Could not import profiles.',
        );
      }
    } catch (e, stack) {
      Logger.exception('Unexpected error during profile import', e, stack);
      if (context.mounted) {
        context.showToastError(
          'Import Failed',
          subtitle: 'Unable to import router profiles. Please check the file and try again.',
        );
      }
    }
  }

  Future<void> _showAddRouterDialog(
    BuildContext context,
    AppState appState,
  ) async {
    final nameController = TextEditingController();
    final ipController = TextEditingController();
    final userController = TextEditingController(text: 'root');
    final passController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscureText = true;
    bool isConnecting = false;
    String? errorMessage;
    try {
      await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.95),
                shadowColor: Theme.of(
                  context,
                ).shadowColor.withValues(alpha: 0.08),
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 60,
                ),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 400,
                  ),
                  child: AutofillGroup(
                    child: Form(
                      key: formKey,
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                controller: nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Profile Name (Optional)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.label_outline_rounded),
                                  helperText:
                                      'e.g. Home Lab, Living Room, Travel Router',
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: ipController,
                                decoration: const InputDecoration(
                                  labelText: 'Router Address',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.router_outlined),
                                  helperText:
                                      'e.g. 192.168.1.1, router.local:8080, https://192.168.1.1',
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter the router address';
                                  }
                                  final parsed = UrlParser.parse(value);
                                  if (!parsed.isValid) {
                                    return parsed.error ??
                                        'Invalid address format';
                                  }
                                  return null;
                                },
                                autofillHints: const [AutofillHints.url],
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: userController,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person_outline),
                                  helperText: 'Default is usually root',
                                ),
                                validator: (v) =>
                                    v == null || v.isEmpty ? 'Required' : null,
                                autofillHints: const [AutofillHints.username],
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: passController,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  helperText: 'Your router password',
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscureText
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () => setState(
                                      () => obscureText = !obscureText,
                                    ),
                                    tooltip: obscureText
                                        ? 'Hide password'
                                        : 'Show password',
                                  ),
                                ),
                                obscureText: obscureText,
                                autofillHints: const [AutofillHints.password],
                              ),
                              if (errorMessage != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .errorContainer
                                        .withValues(alpha: 1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          errorMessage!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onErrorContainer,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 28),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: isConnecting
                                      ? null
                                      : () async {
                                          if (formKey.currentState!
                                              .validate()) {
                                            final input = ipController.text
                                                .trim();
                                            final user = userController.text
                                                .trim();
                                            final pass = passController.text;

                                            // Parse the input to extract host, port, and protocol
                                            final parsedUrl = UrlParser.parse(
                                              input,
                                            );

                                            if (!parsedUrl.isValid) {
                                              setState(() {
                                                errorMessage =
                                                    parsedUrl.error ??
                                                    'Invalid address format';
                                              });
                                              return;
                                            }

                                            final hostWithPort =
                                                parsedUrl.hostWithPort;
                                            final useHttps = parsedUrl.useHttps;
                                            final id = RouterService.generateId(
                                              hostWithPort,
                                              user,
                                              useHttps,
                                            );

                                            if (appState.routers.any(
                                              (r) => r.id == id,
                                            )) {
                                              setState(() {
                                                errorMessage =
                                                    'Router already exists.';
                                              });
                                              return;
                                            }

                                            // Show connecting state
                                            setState(() {
                                              errorMessage = null;
                                              isConnecting = true;
                                            });

                                            // Always fetch hostname from router after login
                                            try {
                                              final customName =
                                                  nameController.text
                                                      .trim()
                                                      .isEmpty
                                                  ? null
                                                  : nameController.text.trim();
                                              final loginSuccess =
                                                  await appState.login(
                                                    hostWithPort,
                                                    user,
                                                    pass,
                                                    useHttps,
                                                    fromRouter: false,
                                                    routerName: customName,
                                                    context: context,
                                                  );
                                              if (!loginSuccess) {
                                                setState(() {
                                                  errorMessage =
                                                      appState.errorMessage ??
                                                      'Failed to connect: Invalid credentials or host unreachable.';
                                                  isConnecting = false;
                                                });
                                                return;
                                              }
                                              // Do NOT addRouter here; login already adds it if needed
                                              if (!context.mounted) {
                                                return;
                                              }
                                              Navigator.pop(context);
                                              if (widget.isFromLogin &&
                                                  appState.hasActiveSession &&
                                                  context.mounted) {
                                                Navigator.of(
                                                  context,
                                                ).pushAndRemoveUntil(
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        const MainScreen(),
                                                  ),
                                                  (route) => false,
                                                );
                                              }
                                            } catch (e) {
                                              setState(() {
                                                errorMessage =
                                                    'Failed to connect: ${e.toString()}';
                                                isConnecting = false;
                                              });
                                            } finally {
                                              if (mounted) {
                                                setState(() {
                                                  _switchingRouterId = null;
                                                });
                                              }
                                            }
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 18,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 4,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                  ),
                                  child: isConnecting
                                      ? Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 3,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(
                                                      Theme.of(
                                                        context,
                                                      ).colorScheme.onPrimary,
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Text('Connecting...'),
                                          ],
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(Icons.add),
                                            SizedBox(width: 12),
                                            Text('Add'),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
      ipController.dispose();
      userController.dispose();
      passController.dispose();
    }
    if (!context.mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final List<model.Router> routers = appState.routers;
    final String? selectedId = appState.selectedRouter?.id;
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Routers',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Import Profiles from JSON',
            onPressed: () => _importProfiles(context, appState),
          ),
          if (routers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: 'Export Profiles as JSON',
              onPressed: () => _exportProfiles(context, appState),
            ),
          const SizedBox(width: 8),
        ],
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => appState.loadRouters(),
              child: routers.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.15,
                        ),
                        Center(
                          child: Icon(
                            Icons.router_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            'No routers added yet.',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: Text(
                            'Add your router credentials manually or restore profiles from a JSON backup.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.add, size: 20),
                                  label: const Text('Add Router'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 20,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                    elevation: 2,
                                  ),
                                  onPressed: () =>
                                      _showAddRouterDialog(context, appState),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.file_download_outlined,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    'Import Profiles from JSON',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 20,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () =>
                                      _importProfiles(context, appState),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      children: [
                        ...List.generate(routers.length, (index) {
                          final model.Router router = routers[index];
                          final bool isSelected = router.id == selectedId;
                          final bool isSwitching =
                              router.id == _switchingRouterId;
                          String routerTitle;
                          if (router.name != null &&
                              router.name!.trim().isNotEmpty) {
                            routerTitle = router.name!.trim();
                          } else if (isSelected &&
                              appState.dashboardData != null) {
                            final boardInfo =
                                appState.dashboardData?['boardInfo']
                                    as Map<String, dynamic>?;
                            final hostname = boardInfo?['hostname']?.toString();
                            routerTitle =
                                (hostname != null && hostname.isNotEmpty)
                                ? hostname
                                : router.displayName;
                          } else {
                            routerTitle = router.displayName;
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: _UnifiedRouterCard(
                              routerIndex: index,
                              routerTitle: routerTitle,
                              subtitle:
                                  '${router.ipAddress} (${router.username})',
                              isSelected: isSelected,
                              isSwitching: isSwitching,
                              onRename: () =>
                                  _showRenameDialog(context, router),
                              onTap: () async {
                                if (isSwitching) return;
                                if (isSelected && !widget.isFromLogin) {
                                  Navigator.of(
                                    context,
                                  ).popUntil((route) => route.isFirst);
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    ref.read(appStateProvider).requestTab(0);
                                  });
                                  return;
                                }
                                if (!isSelected || widget.isFromLogin) {
                                  setState(() {
                                    _switchingRouterId = router.id;
                                  });

                                  try {
                                    await appState.selectRouter(
                                      router.id,
                                      context: context,
                                    );
                                    if (appState.hasActiveSession) {
                                      await appState.fetchDashboardData();
                                      if (!context.mounted) return;
                                      if (widget.isFromLogin) {
                                        Navigator.of(
                                          context,
                                        ).pushAndRemoveUntil(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const MainScreen(),
                                          ),
                                          (route) => false,
                                        );
                                      } else {
                                        Navigator.of(
                                          context,
                                        ).popUntil((route) => route.isFirst);
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              ref
                                                  .read(appStateProvider)
                                                  .requestTab(0);
                                            });
                                      }
                                    } else if (context.mounted) {
                                      final err =
                                          appState.errorMessage ??
                                          'Failed to connect to ${router.displayName}. Please verify host reachability and credentials.';
                                      context.showToastError(
                                        'Connection Failed',
                                        subtitle: err,
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        _switchingRouterId = null;
                                      });
                                    }
                                  }
                                }
                              },
                              onDelete: () async {
                                final routerLabel = router.displayName;
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Remove Router'),
                                    content: Text(
                                      'Are you sure you want to remove $routerLabel?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                );
                                if (!context.mounted) return;
                                if (confirm == true) {
                                  await appState.removeRouter(router.id);
                                }
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add, size: 20),
                              label: const Text('Add Router'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 24,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onPrimary,
                                elevation: 2,
                              ),
                              onPressed: () =>
                                  _showAddRouterDialog(context, appState),
                            ),
                          ),
                        ),
                        if (routers.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.file_download_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Import JSON'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                        horizontal: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () =>
                                        _importProfiles(context, appState),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.file_upload_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Export JSON'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                        horizontal: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () =>
                                        _exportProfiles(context, appState),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 100),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnifiedRouterCard extends StatelessWidget {
  final int routerIndex;
  final String routerTitle;
  final String subtitle;
  final bool isSelected;
  final bool isSwitching;
  final VoidCallback? onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const _UnifiedRouterCard({
    required this.routerIndex,
    required this.routerTitle,
    required this.subtitle,
    required this.isSelected,
    required this.isSwitching,
    this.onTap,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: isSelected ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: isSelected
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                child: Text(
                  '${routerIndex + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routerTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSelected && !isSwitching)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Chip(
                    label: const Text('Active'),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimary,
                    ),
                    backgroundColor: colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
              if (isSwitching)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              if (onRename != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Rename',
                  onPressed: onRename,
                ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
