// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../models/parental_profile.dart';
import '../models/parental_controls_store.dart';

enum ParentalFailureType {
  none,
  firewallDenied,
  routerUnreachable,
  selfGuardBlocked,
  partialSuccess,
  storageError,
  permissionDenied,
  operationInProgress,
}

class ParentalActionResult {
  final bool success;
  final ParentalFailureType failureType;
  final List<String> failedMacs;
  final String message;
  final String? errorReason;

  const ParentalActionResult({
    required this.success,
    this.failureType = ParentalFailureType.none,
    this.failedMacs = const [],
    required this.message,
    this.errorReason,
  });

  static const ParentalActionResult ok = ParentalActionResult(
    success: true,
    message: 'Operation completed successfully.',
  );
}

/// Central coordinator for parental control business logic, storage sync,
/// timer-based schedule/pause enforcement, and backend router synchronization.
class ParentalControlsController {
  static ParentalControlsController? _instance;
  static ParentalControlsController get instance =>
      _instance ??= ParentalControlsController._();
  ParentalControlsController._();

  final ParentalControlsStore _store = ParentalControlsStore.instance;
  final Set<String> _pendingProfileIds = {};
  Timer? _expiryTimer;
  DateTime? _lastUsageIncrement;
  bool _isInitializing = false;

  ParentalControlsStore get store => _store;

  bool isProfileOperationPending(String profileId) =>
      _pendingProfileIds.contains(profileId);

  // ── Storage Persistence ──────────────────────────────────────────────────

  String _storageKeyFor(AppState appState) {
    final routerId = appState.selectedRouter?.id;
    return routerId != null
        ? 'parental_controls_store_v1:$routerId'
        : 'parental_controls_store_v1';
  }

  /// Reset in-memory store so another router's profiles don't linger.
  void reset() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _store.loadFromString(null);
  }

  /// Deterministically load store state from secure storage and sync with backend if available.
  Future<ParentalActionResult> loadStore(AppState appState) async {
    if (_isInitializing) return ParentalActionResult.ok;
    _isInitializing = true;

    final isMock =
        appState.reviewerModeEnabled ||
        RouterService.isMockRouter(appState.selectedRouter);

    try {
      if (!isMock) {
        final key = _storageKeyFor(appState);
        var raw = await appState.secureRead(key);
        if ((raw == null || raw.isEmpty) &&
            appState.selectedRouter?.id != null) {
          final legacy = await appState.secureRead(
            'parental_controls_store_v1',
          );
          if (legacy != null && legacy.isNotEmpty) {
            raw = legacy;
          }
        }
        _store.loadFromString(raw);
      } else {
        _store.loadFromString(null);
      }

      final routerProfiles = await appState.fetchParentalProfiles();
      if (routerProfiles != null) {
        if (routerProfiles.isNotEmpty) {
          _store.setProfiles(routerProfiles);
          if (!isMock) {
            await persistStore(appState);
          }
        } else if (_store.profiles.isNotEmpty && !isMock) {
          // Provision existing local profiles to router UCI
          for (final profile in _store.profiles) {
            await appState.saveParentalProfile(profile: profile);
          }
        }
      }
      return const ParentalActionResult(
        success: true,
        message: 'Parental store loaded successfully.',
      );
    } catch (e) {
      debugPrint('ParentalControlsController: load error — $e');
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.storageError,
        message: 'Failed to load parental controls store: $e',
      );
    } finally {
      _isInitializing = false;
    }
  }

  /// Single write path to persist store to secure storage.
  Future<ParentalActionResult> persistStore(AppState appState) async {
    if (appState.reviewerModeEnabled ||
        RouterService.isMockRouter(appState.selectedRouter)) {
      return ParentalActionResult.ok;
    }
    if (!_store.isLoaded) {
      return const ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.storageError,
        message: 'Cannot persist store before initial load completes.',
      );
    }
    try {
      final key = _storageKeyFor(appState);
      await appState.secureWrite(key, _store.toJsonString());
      return ParentalActionResult.ok;
    } catch (e) {
      debugPrint('ParentalControlsController: persist error — $e');
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.storageError,
        message: 'Failed to persist parental controls store: $e',
      );
    }
  }

  Future<ParentalActionResult> clearActivityLog(AppState appState) async {
    _store.clearActivityLog();
    final res = await persistStore(appState);
    if (res.success) {
      return const ParentalActionResult(
        success: true,
        message: 'Activity log cleared.',
      );
    } else {
      return res;
    }
  }

  // ── Timer & Lifecycle Orchestration ──────────────────────────────────────

  void startExpiryTimer(AppState appState) {
    if (_expiryTimer != null && _expiryTimer!.isActive) return;
    _expiryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      checkPausesAndSchedules(appState);
    });
  }

  void stopExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  void handleLifecycleState(AppLifecycleState state, AppState appState) {
    if (state == AppLifecycleState.resumed) {
      startExpiryTimer(appState);
      checkPausesAndSchedules(appState);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      stopExpiryTimer();
    }
  }

  /// Auto-resume expired manual pauses, track daily usage quota, and sync active scheduled time blocks.
  Future<void> checkPausesAndSchedules(AppState appState) async {
    if (!_store.isLoaded) return;
    final now = DateTime.now().toUtc();

    // 1. Accumulate daily usage minutes for connected devices under profiles with time limits
    final shouldIncrementUsage =
        _lastUsageIncrement == null ||
        now.difference(_lastUsageIncrement!).inSeconds >= 60;
    if (shouldIncrementUsage) {
      _lastUsageIncrement = now;
      final connectedMacs = appState.clients
          .where((c) => c.isConnected)
          .map((c) => c.macAddress.toUpperCase())
          .toSet();

      for (final profile in _store.profiles) {
        if (!profile.isEnabled || !profile.hasTimeLimit) continue;
        if (profile.isPaused || profile.isScheduleBlocked) continue;

        for (final rawMac in profile.macAddresses) {
          final normMac = rawMac.toUpperCase();
          if (connectedMacs.contains(normMac)) {
            _store.incrementDailyMinutesUsed(normMac, 1);
          }
        }
      }
    }

    for (final profile in _store.profiles) {
      // 2. Auto-resume any timed manual pauses that have expired
      if (profile.isPaused &&
          profile.pauseExpiresAt != null &&
          profile.pauseExpiresAt!.isBefore(now)) {
        await resumeProfile(profile, appState: appState, auto: true);
      }

      // 3. Sync scheduled access windows and daily quota blocks for active (non-bypassed) profiles
      if (profile.isEnabled) {
        final inScheduleWindow =
            profile.hasSchedule && profile.schedule!.isTimeInBlockWindow();
        final isQuotaFinished = _store.isProfileQuotaFinished(profile);
        final shouldBlock =
            profile.isPaused || inScheduleWindow || isQuotaFinished;

        for (final mac in profile.macAddresses) {
          final currentlyPaused = appState.isInternetPaused(mac);
          if (shouldBlock && !currentlyPaused) {
            await appState.pauseClientInternet(mac, pause: true, context: null);
          } else if (!shouldBlock && currentlyPaused) {
            await appState.pauseClientInternet(
              mac,
              pause: false,
              context: null,
            );
          }
        }
      }
    }
  }

  // ── Profile Actions & Router Sync ─────────────────────────────────────────

  Future<ParentalActionResult> pauseProfile(
    ParentalProfile profile,
    PauseDuration duration,
    AppState appState, {
    BuildContext? context,
  }) async {
    final caps = appState.capabilities;
    final hasFirewall = caps == null || caps.hasUciWriteAccess;

    if (!hasFirewall) {
      return const ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.firewallDenied,
        message: 'Firewall write access unavailable.',
        errorReason:
            'Router permissions do not allow modifying firewall rules.',
      );
    }

    if (_pendingProfileIds.contains(profile.id)) {
      return const ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.operationInProgress,
        message: 'Changes are currently being applied. Please wait.',
        errorReason: 'A previous request is still executing on the router.',
      );
    }
    _pendingProfileIds.add(profile.id);
    _store.notifyChanges();

    try {
      // Run self-device guard against ALL MAC addresses assigned to profile
      if (context != null) {
        for (final mac in profile.macAddresses) {
          final safe = await SelfDeviceGuard.checkSelfActionGuardrail(
            context,
            actionName: 'Pause Internet for ${profile.name}',
            targetMac: mac,
          );
          if (!safe) {
            return const ParentalActionResult(
              success: false,
              failureType: ParentalFailureType.selfGuardBlocked,
              message: 'Action cancelled to protect self device.',
              errorReason:
                  'Target device MAC matches the controlling management phone.',
            );
          }
        }
      }

      DateTime? expiresAt;
      if (duration == PauseDuration.untilTomorrow) {
        final now = DateTime.now().toLocal();
        final tomorrow = DateTime(now.year, now.month, now.day + 1, 7, 0);
        expiresAt = tomorrow.toUtc();
      } else if (duration.duration != null) {
        expiresAt = DateTime.now().toUtc().add(duration.duration!);
      }

      final updatedProfile = profile.copyWith(
        isPaused: true,
        pauseExpiresAt: expiresAt,
      );

      if (context != null && !context.mounted) {
        return const ParentalActionResult(
          success: false,
          failureType: ParentalFailureType.selfGuardBlocked,
          message: 'Action cancelled.',
        );
      }

      final ok = await appState.saveParentalProfile(
        profile: updatedProfile,
        context: context,
      );
      if (ok) {
        _store.markProfilePaused(profile.id, expiresAt: expiresAt);
        await persistStore(appState);
        final msg = expiresAt != null
            ? 'Internet paused for ${profile.name} (${duration.label}).'
            : 'Internet paused for ${profile.name}.';
        return ParentalActionResult(success: true, message: msg);
      } else {
        return const ParentalActionResult(
          success: false,
          failureType: ParentalFailureType.routerUnreachable,
          message: 'Failed to pause internet on router.',
          errorReason: 'Router rejected firewall pause rule or command failed.',
        );
      }
    } catch (e) {
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.routerUnreachable,
        message: 'Failed to pause internet for ${profile.name}.',
        errorReason: LuciToastManager.parseErrorReason(e),
      );
    } finally {
      _pendingProfileIds.remove(profile.id);
      _store.notifyChanges();
    }
  }

  Future<ParentalActionResult> resumeProfile(
    ParentalProfile profile, {
    required AppState appState,
    bool auto = false,
  }) async {
    if (_pendingProfileIds.contains(profile.id)) {
      return const ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.operationInProgress,
        message: 'Changes are currently being applied. Please wait.',
        errorReason: 'A previous request is still executing on the router.',
      );
    }
    _pendingProfileIds.add(profile.id);
    _store.notifyChanges();

    try {
      final updatedProfile = profile.copyWith(
        isPaused: false,
        pauseExpiresAt: null,
      );

      final ok = await appState.saveParentalProfile(
        profile: updatedProfile,
        context: null,
      );
      if (ok) {
        _store.markProfileResumed(profile.id);
        await persistStore(appState);
        return ParentalActionResult(
          success: true,
          message: 'Internet resumed for ${profile.name}.',
        );
      } else {
        return const ParentalActionResult(
          success: false,
          failureType: ParentalFailureType.routerUnreachable,
          message: 'Failed to resume internet on router.',
          errorReason:
              'Router rejected firewall unpause rule or command failed.',
        );
      }
    } catch (e) {
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.routerUnreachable,
        message: 'Failed to resume internet for ${profile.name}.',
        errorReason: LuciToastManager.parseErrorReason(e, null),
      );
    } finally {
      _pendingProfileIds.remove(profile.id);
      _store.notifyChanges();
    }
  }

  Future<ParentalActionResult> addProfile(
    ParentalProfile profile,
    AppState appState, {
    BuildContext? context,
  }) async {
    if (_pendingProfileIds.contains(profile.id)) {
      return const ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.operationInProgress,
        message: 'Changes are currently being applied. Please wait.',
        errorReason: 'A previous request is still executing on the router.',
      );
    }
    _pendingProfileIds.add(profile.id);
    _store.notifyChanges();

    try {
      _store.addProfile(profile);
      final ok = await appState.saveParentalProfile(
        profile: profile,
        context: context,
      );
      await persistStore(appState);
      if (ok) {
        return ParentalActionResult(
          success: true,
          message: 'Profile "${profile.name}" created.',
        );
      } else {
        return const ParentalActionResult(
          success: false,
          failureType: ParentalFailureType.routerUnreachable,
          message: 'Profile created locally, but router sync failed.',
          errorReason: 'Check router RPC permissions or firewall write access.',
        );
      }
    } catch (e) {
      await persistStore(appState);
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.routerUnreachable,
        message: 'Failed to sync profile to router.',
        errorReason: LuciToastManager.parseErrorReason(e),
      );
    } finally {
      _pendingProfileIds.remove(profile.id);
      _store.notifyChanges();
    }
  }

  Future<ParentalActionResult> updateProfile(
    ParentalProfile updated,
    ParentalProfile oldProfile,
    AppState appState, {
    BuildContext? context,
  }) async {
    if (_pendingProfileIds.contains(updated.id)) {
      return const ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.operationInProgress,
        message: 'Changes are currently being applied. Please wait.',
        errorReason: 'A previous request is still executing on the router.',
      );
    }
    _pendingProfileIds.add(updated.id);
    _store.notifyChanges();

    try {
      _store.updateProfile(updated);
      final ok = await appState.saveParentalProfile(
        profile: updated,
        context: context,
      );
      await persistStore(appState);
      if (ok) {
        return ParentalActionResult(
          success: true,
          message: 'Profile "${updated.name}" updated.',
        );
      } else {
        return const ParentalActionResult(
          success: false,
          failureType: ParentalFailureType.routerUnreachable,
          message: 'Profile updated locally, but router sync failed.',
          errorReason: 'Check router RPC permissions or firewall write access.',
        );
      }
    } catch (e) {
      await persistStore(appState);
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.routerUnreachable,
        message: 'Failed to update profile on router.',
        errorReason: LuciToastManager.parseErrorReason(e),
      );
    } finally {
      _pendingProfileIds.remove(updated.id);
      _store.notifyChanges();
    }
  }

  Future<ParentalActionResult> deleteProfile(
    String profileId,
    AppState appState, {
    BuildContext? context,
  }) async {
    if (_pendingProfileIds.contains(profileId)) {
      return const ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.operationInProgress,
        message: 'Changes are currently being applied. Please wait.',
        errorReason: 'A previous request is still executing on the router.',
      );
    }
    _pendingProfileIds.add(profileId);
    _store.notifyChanges();

    try {
      final profile = _store.getProfile(profileId);
      final profileName = profile?.name ?? 'Profile';

      _store.deleteProfile(profileId);
      final ok = await appState.deleteParentalProfile(
        profileId: profileId,
        context: context,
      );
      await persistStore(appState);
      if (ok) {
        return ParentalActionResult(
          success: true,
          message: 'Profile "$profileName" deleted.',
        );
      } else {
        return const ParentalActionResult(
          success: false,
          failureType: ParentalFailureType.routerUnreachable,
          message: 'Profile deleted locally, but router cleanup failed.',
          errorReason: 'Check router RPC permissions or firewall write access.',
        );
      }
    } catch (e) {
      await persistStore(appState);
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.routerUnreachable,
        message: 'Failed to delete profile from router.',
        errorReason: LuciToastManager.parseErrorReason(e),
      );
    } finally {
      _pendingProfileIds.remove(profileId);
      _store.notifyChanges();
    }
  }

  Future<ParentalActionResult> toggleProfileEnabled(
    String profileId,
    AppState appState, {
    BuildContext? context,
  }) async {
    if (_pendingProfileIds.contains(profileId)) {
      return const ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.operationInProgress,
        message: 'Changes are currently being applied. Please wait.',
        errorReason: 'A previous request is still executing on the router.',
      );
    }
    _pendingProfileIds.add(profileId);
    _store.notifyChanges();

    try {
      _store.toggleProfileEnabled(profileId);
      final updated = _store.getProfile(profileId);
      if (updated == null) {
        return const ParentalActionResult(
          success: false,
          failureType: ParentalFailureType.storageError,
          message: 'Profile not found.',
        );
      }

      final ok = await appState.saveParentalProfile(
        profile: updated,
        context: context,
      );
      await persistStore(appState);
      final msg = updated.isEnabled
          ? 'Rules re-enabled for ${updated.name}'
          : 'Restrictions bypassed for ${updated.name}';
      if (ok) {
        return ParentalActionResult(success: true, message: msg);
      } else {
        return const ParentalActionResult(
          success: false,
          failureType: ParentalFailureType.routerUnreachable,
          message: 'Toggled profile locally, but router sync failed.',
          errorReason: 'Check router RPC permissions or firewall write access.',
        );
      }
    } catch (e) {
      await persistStore(appState);
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.routerUnreachable,
        message: 'Failed to toggle profile on router.',
        errorReason: LuciToastManager.parseErrorReason(e),
      );
    } finally {
      _pendingProfileIds.remove(profileId);
      _store.notifyChanges();
    }
  }
}
