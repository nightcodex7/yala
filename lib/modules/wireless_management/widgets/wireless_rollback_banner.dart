// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../models/wireless_info.dart';
import 'edit_radio_dialog.dart';
import 'edit_ssid_dialog.dart';

/// Top-level banner displayed when high-risk wireless or ACL changes are staged
/// pending manual confirmation. Provides confirm/revert actions,
/// status verification, and automatic re-opening of edit dialogs upon reversion.
class WirelessRollbackBanner extends ConsumerWidget {
  const WirelessRollbackBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);

    if (!appState.isAccessControlPendingConfirmation) {
      return const SizedBox.shrink();
    }

    final hasUciWrite =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;
    final pendingSection = appState.pendingSectionName ?? 'Wireless';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.amber.shade900,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.pending_actions_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Staged Changes Pending ($pendingSection)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Confirm to save permanently, or revert to undo changes.',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _handleRevert(context, ref, appState),
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: const Text(
                  'Revert Changes Now',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: hasUciWrite
                    ? () async {
                        final success = await appState
                            .confirmWifiAccessControlChanges();
                        if (context.mounted) {
                          if (success) {
                            context.showToastSuccess(
                              'Wireless changes confirmed & saved permanently.',
                            );
                          } else {
                            context.showToastError(
                              'Failed to send confirmation to router.',
                            );
                          }
                        }
                      }
                    : null,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                label: const Text(
                  'Confirm & Keep',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleRevert(
    BuildContext context,
    WidgetRef ref,
    AppState appState,
  ) async {
    final pendingSection = appState.pendingSectionName;
    final pendingType = appState.pendingTargetType;
    final targetRadio = appState.pendingTargetRadio;
    final targetInterface = appState.pendingTargetInterface;

    context.showToastLoading(
      'Reverting staged wireless changes...',
      actionKey: 'revert_wireless',
    );

    final reverted = await appState.revertWifiAccessControlChanges(
      context: context,
    );

    if (!context.mounted) return;

    if (reverted) {
      context.showToastSuccess(
        'Wireless changes reverted & verified on router.',
        actionKey: 'revert_wireless',
      );
    } else {
      context.showToastInfo(
        'Revert signal sent. Verifying router UCI status...',
        actionKey: 'revert_wireless',
      );
    }

    // Re-open relevant settings dialog if target radio or interface reference exists
    final overview = WirelessOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    if (pendingType == 'radio' &&
        (targetRadio != null || pendingSection != null)) {
      final radioToEdit =
          targetRadio ??
          overview.radios.firstWhere(
            (r) => r.name == pendingSection,
            orElse: () => overview.radios.first,
          );
      await showDialog(
        context: context,
        builder: (ctx) => EditRadioDialog(radio: radioToEdit),
      );
    } else if (pendingType == 'ssid' && targetInterface != null) {
      final parentRadio =
          targetRadio ??
          overview.radios.firstWhere(
            (r) => r.interfaces.any(
              (i) => i.sectionName == targetInterface.sectionName,
            ),
            orElse: () => overview.radios.first,
          );
      await showDialog(
        context: context,
        builder: (ctx) =>
            EditSsidDialog(radio: parentRadio, interface: targetInterface),
      );
    }
  }
}
