// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/services/service_factory.dart';
import '../models/account_access_models.dart';
import '../services/account_access_inspector.dart';

/// State representation for the Account & Access inspector screen.
@immutable
class AccountAccessState {
  final bool isLoading;
  final AccountAccessSnapshot? snapshot;
  final String? errorMessage;
  final String? activeRouterId;

  const AccountAccessState({
    this.isLoading = false,
    this.snapshot,
    this.errorMessage,
    this.activeRouterId,
  });

  bool get hasSnapshot => snapshot != null;

  AccountAccessState copyWith({
    bool? isLoading,
    AccountAccessSnapshot? snapshot,
    String? errorMessage,
    String? activeRouterId,
  }) {
    return AccountAccessState(
      isLoading: isLoading ?? this.isLoading,
      snapshot: snapshot ?? this.snapshot,
      errorMessage: errorMessage,
      activeRouterId: activeRouterId ?? this.activeRouterId,
    );
  }
}

/// Controller managing the lifecycle and inspection state of the Account & Access inspector.
class AccountAccessController extends StateNotifier<AccountAccessState> {
  final Ref ref;
  final AccountAccessInspector inspector;

  int _currentEpoch = 0;
  String? _lastInspectedRouterId;

  AccountAccessController({required this.ref, required this.inspector})
    : super(const AccountAccessState()) {
    inspect();
  }

  /// Triggers a non-destructive read-only audit of current router account and access methods.
  Future<void> inspect({bool force = false}) async {
    final appState = ref.read(appStateProvider);
    final currentRouter = appState.selectedRouter;
    final routerId = currentRouter?.id ?? 'none';
    final isReviewerMode = appState.reviewerModeEnabled;

    // Check if snapshot is already fresh for this router and force is not requested
    if (!force &&
        state.hasSnapshot &&
        _lastInspectedRouterId == routerId &&
        !state.isLoading) {
      return;
    }

    _lastInspectedRouterId = routerId;
    final epoch = ++_currentEpoch;

    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      activeRouterId: routerId,
    );

    try {
      final snapshot = await inspector.inspect(
        router: currentRouter,
        sysauth: appState.sysauth,
        capabilities: appState.capabilities,
        isReviewerMode: isReviewerMode,
      );

      // Protect against late async responses from an old router session
      if (_currentEpoch != epoch) {
        return;
      }

      state = state.copyWith(
        isLoading: false,
        snapshot: snapshot,
        errorMessage: snapshot.errorMessage,
        activeRouterId: routerId,
      );
    } catch (e) {
      if (_currentEpoch != epoch) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Account & Access inspection failed: $e',
        activeRouterId: routerId,
      );
    }
  }

  /// Manually forces a fresh re-inspection.
  Future<void> refresh() async {
    await inspect(force: true);
  }
}

/// Auto-disposed provider for [AccountAccessController].
final accountAccessControllerProvider =
    StateNotifierProvider.autoDispose<
      AccountAccessController,
      AccountAccessState
    >((ref) {
      final apiService = ServiceContainer.instance.factory.createApiService();
      final sshService = ServiceContainer.instance.factory.createSshService();
      final inspector = AccountAccessInspector(
        apiService: apiService,
        sshService: sshService,
      );
      return AccountAccessController(ref: ref, inspector: inspector);
    });
