// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' hide Router;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/operation_queue.dart';
import '../models/sqm_queue.dart';
import '../models/sqm_telemetry.dart';
import '../services/sqm_telemetry_service.dart';

/// Riverpod StateNotifier coordinating SQM configuration discovery, flow offloading
/// verification, and real-time Linux Traffic Control (`tc`) queue discipline telemetry.
///
/// Features:
/// - Scoped by [routerId] with autoDispose to prevent memory leaks.
/// - Single-flight refresh mutex (`_isRefreshing`) and epoch guards preventing race conditions.
/// - Dedicated telemetry single-flight mutex (`_isTelemetryFetching`) and epoch guards.
/// - 3-second live telemetry polling strictly activated by `SqmScreen` via [startLiveTelemetry].
/// - Dashboard observers and provider listeners consume cached state only and never initiate telemetry polling.
/// - Immediate timer cancellation when `SqmScreen` disposes via [stopLiveTelemetry].
/// - Full Reviewer Mode support with realistic simulated CAKE qdisc telemetry.
/// - Complete isolation from protected files (`client_controller.dart`, `sha256.dart`, `self_device_guard.dart`).
class SqmController extends StateNotifier<SqmState> {
  final Ref? ref;
  final String routerId;
  final IApiService? _apiServiceOverride;
  final SqmTelemetryService? _telemetryServiceOverride;
  final Future<RpcResult<String>> Function(String packageName)?
  _packageInstallerOverride;

  Timer? _telemetryTimer;
  int _fetchEpoch = 0;
  int _telemetryEpoch = 0;
  bool _isRefreshing = false;
  bool _isTelemetryFetching = false;
  int _activeScreenSessions = 0;
  bool _disposed = false;

  static final Map<String, SqmState> _sessionCache = {};

  /// Clears the session cache for a specific router or all routers.
  static void clearSessionCache([String? routerId]) {
    if (routerId != null) {
      _sessionCache.remove(routerId);
    } else {
      _sessionCache.clear();
    }
  }

  @visibleForTesting
  static Map<String, SqmState> get sessionCache => _sessionCache;

  SqmController(
    this.routerId, {
    this.ref,
    IApiService? apiServiceOverride,
    SqmTelemetryService? telemetryServiceOverride,
    Future<RpcResult<String>> Function(String packageName)?
    packageInstallerOverride,
  }) : _apiServiceOverride = apiServiceOverride,
       _telemetryServiceOverride = telemetryServiceOverride,
       _packageInstallerOverride = packageInstallerOverride,
       super(_sessionCache[routerId] ?? SqmState.initial());

  // ── Dependency Accessors ──────────────────────────────────────────────────

  bool get _isReviewerMode {
    if (routerId == 'reviewer-mock-router' ||
        routerId.startsWith('reviewer://')) {
      return true;
    }
    try {
      return ref?.read(appStateProvider).reviewerModeEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  Router? get _currentRouter {
    try {
      final appState = ref?.read(appStateProvider);
      if (appState?.selectedRouter?.id == routerId) {
        return appState?.selectedRouter;
      }
      return appState?.routers.firstWhere(
        (r) => r.id == routerId,
        orElse: () => Router(
          id: routerId,
          ipAddress: '192.168.1.1',
          username: 'root',
          password: '',
          useHttps: false,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  IApiService get _apiService {
    if (_apiServiceOverride != null) return _apiServiceOverride;
    if (_isReviewerMode) return MockApiService();
    try {
      final api = ref?.read(appStateProvider).apiService;
      if (api != null) return api;
    } catch (_) {}
    throw StateError('No active ApiService available for SQM controller');
  }

  String? get _sysauth {
    try {
      return ref?.read(appStateProvider).sysauth;
    } catch (_) {
      return null;
    }
  }

  SqmTelemetryService get _telemetryService =>
      _telemetryServiceOverride ?? SqmTelemetryService();

  @visibleForTesting
  int get activeScreenSessions => _activeScreenSessions;

  @visibleForTesting
  bool get isTelemetryTimerActive => _telemetryTimer != null;

  // ── Discovery & Lifecycle ─────────────────────────────────────────────────

  /// Discovers SQM configuration, firewall flow-offloading state, and service status.
  ///
  /// Protected by single-flight mutex and fetch epoch guards.
  Future<void> refresh({bool forceTelemetry = false}) async {
    if (_isRefreshing || _disposed) return;
    _isRefreshing = true;
    final currentEpoch = ++_fetchEpoch;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      if (_isReviewerMode) {
        _populateReviewerModeState(
          currentEpoch,
          forceTelemetry: forceTelemetry,
        );
        return;
      }

      final router = _currentRouter;
      final ip = router?.ipAddress ?? '192.168.1.1';
      final sysauth = _sysauth ?? '';
      final useHttps = router?.useHttps ?? false;

      // Run independent discovery probes concurrently
      bool rcSuccess = false;
      bool uciSuccess = false;

      final results = await Future.wait([
        _apiService
            .call(ip, sysauth, useHttps, object: 'rc', method: 'list')
            .then(
              (val) {
                rcSuccess = true;
                return val;
              },
              onError: (e) {
                if (kDebugMode) debugPrint('rc.list probe failed for SQM: $e');
                return null;
              },
            ),
        _apiService
            .call(
              ip,
              sysauth,
              useHttps,
              object: 'uci',
              method: 'get',
              params: {'config': 'sqm'},
            )
            .then(
              (val) {
                uciSuccess = true;
                return val;
              },
              onError: (e) {
                if (kDebugMode) debugPrint('uci.get sqm probe failed: $e');
                return null;
              },
            ),
        _apiService
            .call(
              ip,
              sysauth,
              useHttps,
              object: 'uci',
              method: 'get',
              params: {'config': 'firewall'},
            )
            .catchError((e) {
              if (kDebugMode) {
                debugPrint('firewall flow offload probe failed: $e');
              }
              return null;
            }),
        _apiService
            .call(
              ip,
              sysauth,
              useHttps,
              object: 'network.interface',
              method: 'dump',
            )
            .catchError((_) => null),
      ]);

      if (_disposed || currentEpoch != _fetchEpoch) return;

      final rcRes = results[0];
      final uciRes = results[1];
      final fwRes = results[2];
      final netRes = results[3];

      // Guard: If both critical probes failed with RPC/network exceptions,
      // we cannot accurately determine installation status.
      if (!rcSuccess && !uciSuccess) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Unable to check SQM status: connection or RPC failed',
        );
        return;
      }

      // 1. Process rc.list
      bool servicePresent = false;
      bool serviceRunning = false;
      bool serviceEnabled = false;

      Map<String, dynamic>? servicesMap;
      if (rcRes is List && rcRes.length > 1 && rcRes[0] == 0) {
        servicesMap = rcRes[1] as Map<String, dynamic>?;
      } else if (rcRes is Map<String, dynamic>) {
        servicesMap = rcRes;
      }

      if (servicesMap != null && servicesMap['sqm'] is Map) {
        servicePresent = true;
        final sqmMeta = servicesMap['sqm'] as Map;
        serviceRunning =
            sqmMeta['running'] == true ||
            sqmMeta['running'] == 1 ||
            sqmMeta['running'] == '1';
        serviceEnabled =
            sqmMeta['enabled'] == true ||
            sqmMeta['enabled'] == 1 ||
            sqmMeta['enabled'] == '1';
      }

      // 2. Process UCI /etc/config/sqm
      final List<SqmQueue> parsedQueues = [];
      bool uciConfigFound = false;

      Map<String, dynamic>? uciValues;
      if (uciRes is List && uciRes.length > 1 && uciRes[0] == 0) {
        final body = uciRes[1];
        if (body is Map && body['values'] is Map) {
          uciValues = Map<String, dynamic>.from(body['values'] as Map);
        } else if (body is Map) {
          uciValues = Map<String, dynamic>.from(body);
        }
      } else if (uciRes is Map && uciRes['values'] is Map) {
        uciValues = Map<String, dynamic>.from(uciRes['values'] as Map);
      }

      if (uciValues != null && uciValues.isNotEmpty) {
        uciConfigFound = true;
        uciValues.forEach((key, val) {
          if (val is Map) {
            final isQueue =
                val['.type'] == 'queue' ||
                val['interface'] != null ||
                val['download'] != null ||
                val['qdisc'] != null;
            if (isQueue) {
              parsedQueues.add(
                SqmQueue.fromUci(key, Map<String, dynamic>.from(val)),
              );
            }
          }
        });
      }

      // 3. Process UCI firewall flow-offloading in @defaults[0]
      bool softwareOffload = false;
      bool hardwareOffload = false;

      Map<String, dynamic>? fwValues;
      if (fwRes is List && fwRes.length > 1 && fwRes[0] == 0) {
        final body = fwRes[1];
        if (body is Map && body['values'] is Map) {
          fwValues = Map<String, dynamic>.from(body['values'] as Map);
        } else if (body is Map) {
          fwValues = Map<String, dynamic>.from(body);
        }
      } else if (fwRes is Map && fwRes['values'] is Map) {
        fwValues = Map<String, dynamic>.from(fwRes['values'] as Map);
      }

      if (fwValues != null) {
        for (final sec in fwValues.values) {
          if (sec is Map && sec['.type'] == 'defaults') {
            softwareOffload =
                sec['flow_offloading'] == '1' ||
                sec['flow_offloading'] == 1 ||
                sec['flow_offloading'] == true;
            hardwareOffload =
                sec['flow_offloading_hw'] == '1' ||
                sec['flow_offloading_hw'] == 1 ||
                sec['flow_offloading_hw'] == true;
            break;
          }
        }
      }

      // 4. Process network interfaces
      final Set<String> discoveredInterfaces = {'eth0'};
      String? primaryWan;

      if (netRes is List && netRes.length > 1 && netRes[0] == 0) {
        final ifacesList = netRes[1]?['interface'];
        if (ifacesList is List) {
          for (final item in ifacesList) {
            if (item is Map) {
              final ifname =
                  item['device']?.toString() ??
                  item['l3_device']?.toString() ??
                  item['interface']?.toString();
              if (ifname != null && ifname.isNotEmpty) {
                discoveredInterfaces.add(ifname);
              }
              final protoName = item['interface']?.toString() ?? '';
              if (protoName == 'wan' || protoName == 'wan6') {
                primaryWan = ifname;
              }
            }
          }
        }
      }

      // Add interfaces present in parsed queues
      for (final q in parsedQueues) {
        if (q.interface.isNotEmpty) {
          discoveredInterfaces.add(q.interface);
        }
      }

      final isInstalled =
          servicePresent || uciConfigFound || parsedQueues.isNotEmpty;

      // 5. Operating state classification
      SqmOperatingState opState;
      if (!isInstalled) {
        opState = SqmOperatingState.notInstalled;
      } else if (softwareOffload || hardwareOffload) {
        opState = SqmOperatingState.flowOffloadingConflict;
      } else if (!serviceRunning || parsedQueues.every((q) => !q.enabled)) {
        opState = SqmOperatingState.inactive;
      } else {
        opState = SqmOperatingState.active;
      }

      // 6. Kernel-level running detection override.
      //
      // sqm-scripts is not a procd daemon — its init script configures tc
      // qdiscs and exits without ever calling procd_open_instance.  As a
      // result, `ubus call service list '{"name":"sqm"}'` always returns
      // {"sqm": {}} with no "running" key, making serviceRunning perpetually
      // false regardless of whether the shaper is actively delaying packets.
      //
      // Fix: when UCI shows at least one enabled queue but procd says
      // not-running, probe the kernel directly via
      // `tc -s qdisc show dev <iface>`.  A root qdisc other than the kernel
      // defaults (noqueue / pfifo_fast) can only exist if sqm-scripts has
      // already applied its tc configuration, proving the shaper is live.
      //
      // This probe reuses _telemetryService.fetchQueueTelemetry so we also
      // populate telemetryByInterface for free — no extra RPC categories.
      if (!serviceRunning &&
          opState == SqmOperatingState.inactive &&
          isInstalled &&
          parsedQueues.any((q) => q.enabled)) {
        final enabledQueues = parsedQueues.where((q) => q.enabled).toList();
        for (final q in enabledQueues) {
          if (_disposed || currentEpoch != _fetchEpoch) break;
          try {
            final telem = await _telemetryService.fetchQueueTelemetry(
              apiService: _apiService,
              ipAddress: ip,
              sysauth: sysauth,
              useHttps: useHttps,
              interfaceName: q.interface,
              isReviewerMode: _isReviewerMode,
            );
            // A root qdisc that is not the kernel placeholder proves sqm has
            // applied its configuration.  pfifo_fast and noqueue are the
            // kernel defaults; anything else (cake, fq_codel, htb …) means
            // sqm-scripts is running.
            final tcIndicatesRunning =
                telem != null &&
                telem.root &&
                telem.qdisc != 'unknown' &&
                telem.qdisc != 'none' &&
                telem.qdisc != 'noqueue' &&
                telem.qdisc != 'pfifo_fast';
            if (tcIndicatesRunning) {
              serviceRunning = true;
              opState = SqmOperatingState.active;
              break;
            }
          } catch (_) {
            // Probe failure is non-fatal; keep opState as inactive.
          }
        }
      }

      if (_disposed || currentEpoch != _fetchEpoch) return;

      // Stage 1: Publish configuration immediately
      state = SqmState(
        operatingState: opState,
        isInstalled: isInstalled,
        isServiceRunning: serviceRunning,
        isServiceEnabled: serviceEnabled,
        queues: List.unmodifiable(parsedQueues),
        primaryWanInterface:
            primaryWan ??
            (parsedQueues.isNotEmpty ? parsedQueues.first.interface : 'eth0'),
        networkInterfaces: List.unmodifiable(
          discoveredInterfaces.toList()..sort(),
        ),
        hasSoftwareFlowOffload: softwareOffload,
        hasHardwareFlowOffload: hardwareOffload,
        telemetryByInterface: state.telemetryByInterface,
        previousTelemetryByInterface: state.previousTelemetryByInterface,
        isLoading: false,
        isTelemetryPolling: _activeScreenSessions > 0,
        errorMessage: null,
        lastUpdated: DateTime.now(),
      );

      _sessionCache[routerId] = state;

      // Stage 2: Progressive Telemetry
      if (isInstalled && parsedQueues.isNotEmpty) {
        if (forceTelemetry) {
          await _pollTelemetry();
        } else if (_activeScreenSessions > 0) {
          unawaited(_pollTelemetry());
        }
      }
    } catch (e) {
      if (_disposed || currentEpoch != _fetchEpoch) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to refresh SQM status: $e',
      );
    } finally {
      _isRefreshing = false;
    }
  }

  void _populateReviewerModeState(int epoch, {bool forceTelemetry = false}) {
    final mockQueues = [
      const SqmQueue(
        name: 'eth0',
        enabled: true,
        interface: 'eth0',
        download: 100000,
        upload: 20000,
        qdisc: 'cake',
        script: 'piece_of_cake.qos',
        linklayer: 'none',
        overhead: 0,
      ),
      const SqmQueue(
        name: 'eth1',
        enabled: false,
        interface: 'eth1',
        download: 50000,
        upload: 10000,
        qdisc: 'fq_codel',
        script: 'simplest.qos',
      ),
    ];

    final mockTelemetry = {
      'eth0': SqmTelemetryService.generateMockTelemetry('eth0'),
    };

    if (_disposed || epoch != _fetchEpoch) return;

    state = SqmState(
      operatingState: SqmOperatingState.active,
      isInstalled: true,
      isServiceRunning: true,
      isServiceEnabled: true,
      queues: List.unmodifiable(mockQueues),
      primaryWanInterface: 'eth0',
      networkInterfaces: const ['br-lan', 'eth0', 'eth1', 'wlan0', 'wlan1'],
      hasSoftwareFlowOffload: false,
      hasHardwareFlowOffload: false,
      telemetryByInterface: Map.unmodifiable(mockTelemetry),
      previousTelemetryByInterface: state.telemetryByInterface,
      isLoading: false,
      isTelemetryPolling: _activeScreenSessions > 0,
      errorMessage: null,
      lastUpdated: DateTime.now(),
    );
    _sessionCache[routerId] = state;
    _isRefreshing = false;
  }

  // ── Live Telemetry Polling ────────────────────────────────────────────────

  /// Explicitly activates 3-second live telemetry polling when `SqmScreen` mounts.
  ///
  /// Increments the active screen session count. On first mount, initiates a
  /// fixed 3-second periodic polling timer and dispatches an immediate poll.
  ///
  /// Note: Dashboard widgets and standard provider listeners do NOT call this method;
  /// they consume cached state only and never trigger telemetry polling.
  void startLiveTelemetry() {
    _activeScreenSessions++;
    if (_telemetryTimer == null) {
      if (!_disposed) {
        state = state.copyWith(isTelemetryPolling: true);
      }
      _telemetryTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _pollTelemetry(),
      );
      _pollTelemetry();
    }
  }

  /// Explicitly deactivates live telemetry polling when `SqmScreen` disposes.
  ///
  /// Decrements active screen session count. When all active `SqmScreen` instances
  /// leave the tree, immediately cancels the periodic timer to preserve router CPU
  /// and network bandwidth.
  void stopLiveTelemetry() {
    if (_activeScreenSessions > 0) {
      _activeScreenSessions--;
    }
    if (_activeScreenSessions == 0) {
      _telemetryTimer?.cancel();
      _telemetryTimer = null;
      if (!_disposed) {
        state = state.copyWith(isTelemetryPolling: false);
      }
    }
  }

  /// Internal telemetry poll executed on periodic timer or subscriber start.
  /// Protected by dedicated telemetry mutex and epoch guards.
  Future<void> _pollTelemetry() async {
    if (_disposed || _isTelemetryFetching) return;
    if (state.operatingState == SqmOperatingState.notInstalled ||
        state.queues.isEmpty) {
      return;
    }

    _isTelemetryFetching = true;
    final pollEpoch = ++_telemetryEpoch;

    try {
      final activeInterfaces = state.queues
          .where((q) => q.enabled)
          .map((q) => q.interface)
          .where((i) => i.isNotEmpty)
          .toSet();

      if (activeInterfaces.isEmpty && state.queues.isNotEmpty) {
        activeInterfaces.add(state.queues.first.interface);
      }

      final router = _currentRouter;
      final ip = router?.ipAddress ?? '192.168.1.1';
      final sysauth = _sysauth ?? '';
      final useHttps = router?.useHttps ?? false;

      final updatedTelemetry = Map<String, SqmQueueTelemetry>.from(
        state.telemetryByInterface,
      );

      SqmOperatingState currentOpState = state.operatingState;
      for (final iface in activeInterfaces) {
        if (_disposed || pollEpoch != _telemetryEpoch) return;

        final telem = await _telemetryService.fetchQueueTelemetry(
          apiService: _apiService,
          ipAddress: ip,
          sysauth: sysauth,
          useHttps: useHttps,
          interfaceName: iface,
          isReviewerMode: _isReviewerMode,
        );

        if (telem != null) {
          updatedTelemetry[iface] = telem;
        } else if (currentOpState == SqmOperatingState.active) {
          currentOpState = SqmOperatingState.telemetryUnavailable;
        }
      }

      if (_disposed || pollEpoch != _telemetryEpoch) return;

      state = state.copyWith(
        operatingState: currentOpState,
        telemetryByInterface: Map.unmodifiable(updatedTelemetry),
        previousTelemetryByInterface: Map.unmodifiable(
          state.telemetryByInterface,
        ),
        lastUpdated: DateTime.now(),
      );
      _sessionCache[routerId] = state;
    } catch (e) {
      if (kDebugMode) debugPrint('Telemetry polling tick error: $e');
    } finally {
      _isTelemetryFetching = false;
    }
  }

  // ── Configuration Mutations ───────────────────────────────────────────────

  /// Saves and applies configuration for an SQM queue section.
  Future<bool> saveQueue(SqmQueue queue, {BuildContext? context}) async {
    final router = _currentRouter;
    final ip = router?.ipAddress ?? '192.168.1.1';
    final sysauth = _sysauth ?? '';
    final useHttps = router?.useHttps ?? false;

    if (_isReviewerMode) {
      final updatedQueues = List<SqmQueue>.from(state.queues);
      final idx = updatedQueues.indexWhere((q) => q.name == queue.name);
      if (idx >= 0) {
        updatedQueues[idx] = queue;
      } else {
        updatedQueues.add(queue);
      }
      state = state.copyWith(queues: List.unmodifiable(updatedQueues));
      return true;
    }

    final success = await _apiService.saveSqmQueue(
      ip,
      sysauth,
      useHttps,
      queue: queue,
      context: context,
    );
    if (success) {
      await refresh();
    }
    return success;
  }

  /// Deletes an SQM queue section.
  Future<bool> deleteQueue(String queueName, {BuildContext? context}) async {
    final router = _currentRouter;
    final ip = router?.ipAddress ?? '192.168.1.1';
    final sysauth = _sysauth ?? '';
    final useHttps = router?.useHttps ?? false;

    if (_isReviewerMode) {
      final updatedQueues = state.queues
          .where((q) => q.name != queueName)
          .toList();
      state = state.copyWith(queues: List.unmodifiable(updatedQueues));
      return true;
    }

    final success = await _apiService.deleteSqmQueue(
      ip,
      sysauth,
      useHttps,
      sectionName: queueName,
      context: context,
    );
    if (success) {
      await refresh();
    }
    return success;
  }

  /// Starts/enables or stops/disables the SQM daemon service.
  Future<bool> toggleService(bool enable, {BuildContext? context}) async {
    final router = _currentRouter;
    final ip = router?.ipAddress ?? '192.168.1.1';
    final sysauth = _sysauth ?? '';
    final useHttps = router?.useHttps ?? false;

    if (_isReviewerMode) {
      state = state.copyWith(
        isServiceRunning: enable,
        isServiceEnabled: enable,
        operatingState: enable
            ? SqmOperatingState.active
            : SqmOperatingState.inactive,
      );
      return true;
    }

    final success = await _apiService.toggleSqmService(
      ip,
      sysauth,
      useHttps,
      enable: enable,
      context: context,
    );
    if (success) {
      await refresh();
    }
    return success;
  }

  /// Restarts the SQM daemon service via `manageServiceAction`.
  Future<bool> restartService({BuildContext? context}) async {
    final router = _currentRouter;
    final ip = router?.ipAddress ?? '192.168.1.1';
    final sysauth = _sysauth ?? '';
    final useHttps = router?.useHttps ?? false;

    if (_isReviewerMode) {
      return true;
    }

    final success = await _apiService.manageServiceAction(
      ip,
      sysauth,
      useHttps,
      serviceName: 'sqm',
      action: 'restart',
      context: context,
    );
    if (success) {
      await refresh();
    }
    return success;
  }

  /// Safely installs the core SQM package (`sqm-scripts`) on the router.
  ///
  /// Protected by a router-exclusive lock (`domain: '*'`) via [RouterScopedOperationQueue]
  /// with a 15-second lock acquisition timeout.
  /// Suspends active live telemetry polling during execution to prevent `tc` polling collisions.
  /// Post-installation, re-probes capabilities, executes a refresh, and conditionally restores
  /// telemetry polling if the screen remains mounted.
  Future<RpcResult<String>> installSqmPackage() async {
    const packageName = 'sqm-scripts';
    final wasTimerActive = _telemetryTimer != null;
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    if (!_disposed && wasTimerActive) {
      state = state.copyWith(isTelemetryPolling: false);
    }

    try {
      return await RouterScopedOperationQueue.instance
          .runLocked<RpcResult<String>>(
            routerId: routerId,
            domain: '*',
            timeout: const Duration(seconds: 15),
            action: () async {
              RpcResult<String> res;
              if (_packageInstallerOverride != null) {
                res = await _packageInstallerOverride(packageName);
              } else if (_isReviewerMode) {
                res = RpcResult.success(
                  'Installed $packageName successfully (Reviewer Mode)',
                );
                _populateReviewerModeState(_fetchEpoch);
                return res;
              } else {
                final appState = ref?.read(appStateProvider);
                if (appState == null) {
                  return RpcResult.failed('AppState is unavailable');
                }
                res = await appState.installPackage(packageName);
              }

              if (res.isSuccess) {
                final appState = ref?.read(appStateProvider);
                if (appState != null) {
                  try {
                    await appState.redetectCapabilities();
                  } catch (_) {}
                }
                await refresh(forceTelemetry: false);
              }
              return res;
            },
          );
    } finally {
      if (!_disposed &&
          _activeScreenSessions > 0 &&
          state.isInstalled &&
          _telemetryTimer == null) {
        state = state.copyWith(isTelemetryPolling: true);
        _telemetryTimer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => _pollTelemetry(),
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    super.dispose();
  }
}

/// Scoped provider for SQM controller per router instance.
final sqmControllerProvider = StateNotifierProvider.autoDispose
    .family<SqmController, SqmState, String>((ref, routerId) {
      return SqmController(routerId, ref: ref);
    });
