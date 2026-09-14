// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import '../models/parental_profile.dart';
import '../models/parental_controls_store.dart';

enum ParentalFailureType {
  none,
  firewallDenied,
  routerUnreachable,
  selfGuardBlocked,
  partialSuccess,
  storageError,
}

class ParentalActionResult {
  final bool success;
  final ParentalFailureType failureType;
  final List<String> failedMacs;
  final String message;

  const ParentalActionResult({
    required this.success,
    this.failureType = ParentalFailureType.none,
    this.failedMacs = const [],
    required this.message,
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
  Timer? _expiryTimer;
  bool _isInitializing = false;

  ParentalControlsStore get store => _store;

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

    try {
      final key = _storageKeyFor(appState);
      var raw = await appState.secureRead(key);
      if ((raw == null || raw.isEmpty) && appState.selectedRouter?.id != null) {
        final legacy = await appState.secureRead('parental_controls_store_v1');
        if (legacy != null && legacy.isNotEmpty) {
          raw = legacy;
        }
      }
      _store.loadFromString(raw);

      final routerProfiles = await appState.fetchParentalProfiles();
      if (routerProfiles != null && routerProfiles.isNotEmpty) {
        _store.setProfiles(routerProfiles);
        await persistStore(appState);
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

  /// Auto-resume expired manual pauses and sync active scheduled time blocks.
  Future<void> checkPausesAndSchedules(AppState appState) async {
    if (!_store.isLoaded) return;
    final now = DateTime.now().toUtc();

    for (final profile in _store.profiles) {
      // 1. Auto-resume any timed manual pauses that have expired
      if (profile.isPaused &&
          profile.pauseExpiresAt != null &&
          profile.pauseExpiresAt!.isBefore(now)) {
        await resumeProfile(profile, appState: appState, auto: true);
      }

      // 2. Sync scheduled access windows for active (non-bypassed) profiles
      if (profile.isEnabled && profile.hasSchedule) {
        final inScheduleWindow = profile.schedule!.isTimeInBlockWindow();
        for (final mac in profile.macAddresses) {
          final currentlyPaused = appState.isInternetPaused(mac);
          if (inScheduleWindow && !currentlyPaused) {
            // Schedule block window active: enforce firewall block
            await appState.pauseClientInternet(mac, pause: true, context: null);
          } else if (!inScheduleWindow &&
              !profile.isPaused &&
              currentlyPaused) {
            // Schedule block window ended: restore internet access
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
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.firewallDenied,
        message: 'Firewall write access unavailable. Cannot pause internet.',
      );
    }

    // Run self-device guard against ALL MAC addresses assigned to profile
    if (context != null) {
      for (final mac in profile.macAddresses) {
        final safe = await SelfDeviceGuard.checkSelfActionGuardrail(
          context,
          actionName: 'Pause Internet for ${profile.name}',
          targetMac: mac,
        );
        if (!safe) {
          return ParentalActionResult(
            success: false,
            failureType: ParentalFailureType.selfGuardBlocked,
            message: 'Action cancelled to protect self device.',
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

    final List<String> failedMacs = [];
    for (final mac in profile.macAddresses) {
      final ok = await appState.pauseClientInternet(
        mac,
        pause: true,
        context: null,
      );
      if (!ok) failedMacs.add(mac);
    }

    if (failedMacs.isEmpty || profile.macAddresses.isEmpty) {
      _store.markProfilePaused(profile.id, expiresAt: expiresAt);
      await persistStore(appState);
      final msg = expiresAt != null
          ? 'Internet paused for ${profile.name} (${duration.label}).'
          : 'Internet paused for ${profile.name}.';
      return ParentalActionResult(success: true, message: msg);
    } else if (failedMacs.length < profile.macAddresses.length) {
      // Partial success
      _store.markProfilePaused(profile.id, expiresAt: expiresAt);
      await persistStore(appState);
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.partialSuccess,
        failedMacs: failedMacs,
        message:
            'Paused internet for some devices, but failed for: ${failedMacs.join(", ")}.',
      );
    } else {
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.routerUnreachable,
        failedMacs: failedMacs,
        message: 'Failed to pause internet. Check router connection.',
      );
    }
  }

  Future<ParentalActionResult> resumeProfile(
    ParentalProfile profile, {
    required AppState appState,
    bool auto = false,
  }) async {
    final List<String> failedMacs = [];
    for (final mac in profile.macAddresses) {
      final ok = await appState.pauseClientInternet(
        mac,
        pause: false,
        context: null,
      );
      if (!ok) failedMacs.add(mac);
    }

    if (failedMacs.isEmpty || profile.macAddresses.isEmpty) {
      _store.markProfileResumed(profile.id);
      await persistStore(appState);
      return ParentalActionResult(
        success: true,
        message: 'Internet resumed for ${profile.name}.',
      );
    } else if (failedMacs.length < profile.macAddresses.length) {
      _store.markProfileResumed(profile.id);
      await persistStore(appState);
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.partialSuccess,
        failedMacs: failedMacs,
        message:
            'Resumed internet for some devices, but failed for: ${failedMacs.join(", ")}.',
      );
    } else {
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.routerUnreachable,
        failedMacs: failedMacs,
        message: 'Failed to resume internet for devices.',
      );
    }
  }

  Future<ParentalActionResult> addProfile(
    ParentalProfile profile,
    AppState appState,
  ) async {
    _store.addProfile(profile);
    await appState.saveParentalProfile(profile: profile);

    if (profile.isCurrentlyBlocked) {
      for (final mac in profile.macAddresses) {
        await appState.pauseClientInternet(mac, pause: true, context: null);
      }
    }
    if (profile.hasContentFilter) {
      await appState.applyParentalProfileDns(
        profileId: profile.id,
        macAddresses: profile.macAddresses,
        dnsServers: profile.contentFilter == ContentFilterDns.custom
            ? profile.customDnsServers
            : profile.contentFilter.primaryServers,
        context: null,
      );
    }
    await persistStore(appState);
    return ParentalActionResult(
      success: true,
      message: 'Profile "${profile.name}" created.',
    );
  }

  Future<ParentalActionResult> updateProfile(
    ParentalProfile updated,
    ParentalProfile oldProfile,
    AppState appState,
  ) async {
    final oldMacs = Set<String>.from(oldProfile.macAddresses);
    final newMacs = Set<String>.from(updated.macAddresses);
    _store.updateProfile(updated);

    await appState.saveParentalProfile(profile: updated);

    // 1. Unblock MACs removed from profile (if no other profile blocks them)
    final removedMacs = oldMacs.difference(newMacs);
    for (final mac in removedMacs) {
      if (!_store.isMacPaused(mac)) {
        await appState.pauseClientInternet(mac, pause: false, context: null);
      }
    }
    // 2. Block MACs newly added to profile (if profile is currently blocked)
    final addedMacs = newMacs.difference(oldMacs);
    if (updated.isCurrentlyBlocked) {
      for (final mac in addedMacs) {
        await appState.pauseClientInternet(mac, pause: true, context: null);
      }
    }

    // 3. Apply DNS changes
    await appState.applyParentalProfileDns(
      profileId: updated.id,
      macAddresses: updated.macAddresses,
      dnsServers: updated.contentFilter == ContentFilterDns.custom
          ? updated.customDnsServers
          : updated.contentFilter.primaryServers,
      context: null,
    );

    await persistStore(appState);
    return ParentalActionResult(
      success: true,
      message: 'Profile "${updated.name}" updated.',
    );
  }

  Future<ParentalActionResult> deleteProfile(
    String profileId,
    AppState appState,
  ) async {
    final profile = _store.getProfile(profileId);
    final profileName = profile?.name ?? 'Profile';

    _store.deleteProfile(profileId);
    await appState.deleteParentalProfile(profileId: profileId);
    await appState.applyParentalProfileDns(
      profileId: profileId,
      macAddresses: [],
      dnsServers: null,
      context: null,
    );

    await persistStore(appState);
    return ParentalActionResult(
      success: true,
      message: 'Profile "$profileName" deleted.',
    );
  }

  Future<ParentalActionResult> toggleProfileEnabled(
    String profileId,
    AppState appState,
  ) async {
    _store.toggleProfileEnabled(profileId);
    final updated = _store.getProfile(profileId);
    if (updated == null) {
      return const ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.storageError,
        message: 'Profile not found.',
      );
    }

    final isNowEnabled = updated.isEnabled;
    await appState.saveParentalProfile(profile: updated);

    if (!isNowEnabled) {
      for (final mac in updated.macAddresses) {
        await appState.pauseClientInternet(mac, pause: false, context: null);
      }
    } else if (updated.isCurrentlyBlocked) {
      for (final mac in updated.macAddresses) {
        await appState.pauseClientInternet(mac, pause: true, context: null);
      }
    }

    await appState.applyParentalProfileDns(
      profileId: updated.id,
      macAddresses: isNowEnabled ? updated.macAddresses : [],
      dnsServers: isNowEnabled
          ? (updated.contentFilter == ContentFilterDns.custom
                ? updated.customDnsServers
                : updated.contentFilter.primaryServers)
          : null,
      context: null,
    );

    await persistStore(appState);
    final msg = isNowEnabled
        ? 'Rules re-enabled for ${updated.name}'
        : 'Restrictions bypassed for ${updated.name}';
    return ParentalActionResult(success: true, message: msg);
  }
}
