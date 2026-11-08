// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../../state/app_state.dart';
import '../models/speed_test_models.dart';
import '../services/speed_test_service.dart';

@immutable
class SpeedTestState {
  final bool isRunning;
  final SpeedTestProgress? progress;
  final SpeedTestResult? result;
  final String? errorMessage;

  const SpeedTestState({
    this.isRunning = false,
    this.progress,
    this.result,
    this.errorMessage,
  });

  SpeedTestState copyWith({
    bool? isRunning,
    SpeedTestProgress? progress,
    SpeedTestResult? result,
    String? errorMessage,
  }) {
    return SpeedTestState(
      isRunning: isRunning ?? this.isRunning,
      progress: progress ?? this.progress,
      result: result ?? this.result,
      errorMessage: errorMessage,
    );
  }
}

final speedTestServiceProvider = Provider<ISpeedTestService>((ref) {
  return SpeedTestService();
});

final speedTestControllerProvider =
    StateNotifierProvider<SpeedTestController, SpeedTestState>((ref) {
      final service = ref.watch(speedTestServiceProvider);
      final routerKey = ref.watch(
        appStateProvider.select(
          (s) => s.reviewerModeEnabled
              ? 'reviewer-mock-router'
              : (s.selectedRouter?.id.isNotEmpty == true
                    ? s.selectedRouter!.id
                    : s.selectedRouter?.ipAddress),
        ),
      );
      return SpeedTestController(service, ref, routerKey);
    });

class SpeedTestController extends StateNotifier<SpeedTestState> {
  static final Map<String, SpeedTestResult> _routerResultsCache = {};

  final ISpeedTestService _service;
  final Ref? _ref;
  final String? _routerKey;
  StreamSubscription<SpeedTestProgress>? _progressSub;

  SpeedTestController(this._service, [this._ref, this._routerKey])
    : super(
        SpeedTestState(
          result: _routerKey != null ? _routerResultsCache[_routerKey] : null,
        ),
      ) {
    _progressSub = _service.progressStream.listen((prog) {
      state = state.copyWith(progress: prog);
    });
  }

  /// Clears cached speed test results across all router profiles (e.g. on logout or app reset).
  static void clearCache() {
    _routerResultsCache.clear();
  }

  /// Returns cached result for a given router key, if any.
  static SpeedTestResult? getCachedResult(String routerKey) {
    return _routerResultsCache[routerKey];
  }

  static String? _resolveRouterKey(AppState? appState) {
    if (appState == null) return null;
    if (appState.reviewerModeEnabled) return 'reviewer-mock-router';
    final router = appState.selectedRouter;
    if (router != null) {
      if (router.id.isNotEmpty) return router.id;
      if (router.ipAddress.isNotEmpty) return router.ipAddress;
    }
    return null;
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _service.cancel();
    super.dispose();
  }

  Future<void> startTest({
    int downloadByteTarget = 10000000,
    int uploadByteTarget = 2097152,
  }) async {
    // Single-flight lock
    if (state.isRunning) return;

    state = state.copyWith(
      isRunning: true,
      errorMessage: null,
      progress: const SpeedTestProgress(
        stage: SpeedTestStage.discoveringEndpoint,
        statusMessage: 'Connecting to OpenWrt router for WAN speed test...',
      ),
    );

    final appState = _ref?.read(appStateProvider);
    final api = appState?.apiService;
    final isReviewer =
        (appState?.reviewerModeEnabled ?? false) ||
        api.runtimeType.toString().contains('Mock');
    final routerIp =
        appState?.selectedRouter?.ipAddress ??
        (isReviewer ? '192.168.1.1' : null);
    final sysauth =
        appState?.sysauth ?? (isReviewer ? 'mock_auth_token' : null);
    final useHttps = appState?.selectedRouter?.useHttps ?? false;
    final wanInterface = appState?.selectedRouter?.displayName ?? 'WAN';

    try {
      SpeedTestResult res;
      if (api != null && routerIp != null && sysauth != null) {
        res = await _service.runRouterSpeedTest(
          api: api,
          routerIp: routerIp,
          sysauth: sysauth,
          useHttps: useHttps,
          wanInterface: wanInterface,
          capabilities: appState?.capabilities,
        );
      } else if (isReviewer || _ref == null) {
        // In reviewer mode or mock unit tests without active router, simulate router test
        res = await _service.runTest(
          downloadByteTarget: downloadByteTarget,
          uploadByteTarget: uploadByteTarget,
        );
      } else {
        // Router is required: WAN Speed Test runs exclusively from the router
        const err =
            'Router connection required: Internet Speed Test runs directly on your OpenWrt router (WAN). Please connect and log in to your router.';
        state = state.copyWith(
          isRunning: false,
          errorMessage: err,
          progress: const SpeedTestProgress(
            stage: SpeedTestStage.failed,
            statusMessage: err,
          ),
        );
        return;
      }

      state = state.copyWith(
        isRunning: false,
        result: res,
        errorMessage: res.stage == SpeedTestStage.failed
            ? res.errorMessage
            : null,
      );

      final currentKey =
          _routerKey ?? _resolveRouterKey(_ref?.read(appStateProvider));
      if (currentKey != null && res.stage != SpeedTestStage.cancelled) {
        _routerResultsCache[currentKey] = res;
      }
    } catch (e) {
      state = state.copyWith(isRunning: false, errorMessage: e.toString());
    }
  }

  void cancelTest() {
    if (!state.isRunning) return;
    _service.cancel();
    state = state.copyWith(isRunning: false);
  }

  void reset() {
    _service.cancel();
    final currentKey =
        _routerKey ?? _resolveRouterKey(_ref?.read(appStateProvider));
    if (currentKey != null) {
      _routerResultsCache.remove(currentKey);
    }
    state = const SpeedTestState();
  }
}
