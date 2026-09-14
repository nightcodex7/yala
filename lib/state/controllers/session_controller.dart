// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/design/luci_theme.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/services/service_factory.dart';
import 'package:yet_another_luci_app/state/controllers/dashboard_controller.dart';
import 'package:yet_another_luci_app/utils/http_client_manager.dart';
import 'package:yet_another_luci_app/utils/logger.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';

/// Encapsulates authentication session lifecycle, router profile selection,
/// preference storage, theme persistence, and reviewer mode configuration.
///
/// Extracted from [AppState] to enforce single-responsibility.
class SessionController {
  SessionController({
    bool initialReviewerMode = false,
    required IApiService? Function() apiServiceRef,
    required IAuthService? Function() authServiceRef,
    required RouterService? Function() routerServiceRef,
    required SecureStorageService Function() secureStorageServiceRef,
    required HttpClientManager Function() httpClientManagerRef,
    required DashboardController? Function() dashboardControllerRef,
    required void Function() cancelThroughputTimer,
    required void Function() startThroughputTimer,
    required Future<void> Function({bool force}) fetchDashboardData,
    required void Function() initializeServices,
    required void Function(bool isLoading) setLoadingState,
    required void Function(String? error) setErrorState,
    required VoidCallback notifyListeners,
  }) : _reviewerModeEnabled = initialReviewerMode,
       _apiServiceRef = apiServiceRef,
       _authServiceRef = authServiceRef,
       _routerServiceRef = routerServiceRef,
       _secureStorageServiceRef = secureStorageServiceRef,
       _httpClientManagerRef = httpClientManagerRef,
       _dashboardControllerRef = dashboardControllerRef,
       _cancelThroughputTimer = cancelThroughputTimer,
       _startThroughputTimer = startThroughputTimer,
       _fetchDashboardData = fetchDashboardData,
       _initializeServices = initializeServices,
       _setLoadingState = setLoadingState,
       _setErrorState = setErrorState,
       _notifyListeners = notifyListeners;

  final IApiService? Function() _apiServiceRef;
  final IAuthService? Function() _authServiceRef;
  final RouterService? Function() _routerServiceRef;
  final SecureStorageService Function() _secureStorageServiceRef;
  final HttpClientManager Function() _httpClientManagerRef;
  final DashboardController? Function() _dashboardControllerRef;
  final void Function() _cancelThroughputTimer;
  final void Function() _startThroughputTimer;
  final Future<void> Function({bool force}) _fetchDashboardData;
  final void Function() _initializeServices;
  final void Function(bool isLoading) _setLoadingState;
  final void Function(String? error) _setErrorState;
  final VoidCallback _notifyListeners;

  IApiService? get _apiService => _apiServiceRef();
  IAuthService? get _authService => _authServiceRef();
  RouterService? get _routerService => _routerServiceRef();
  SecureStorageService get _secureStorageService => _secureStorageServiceRef();
  HttpClientManager get _httpClientManager => _httpClientManagerRef();
  DashboardController? get _dashboardController => _dashboardControllerRef();

  // Reviewer mode state
  bool _reviewerModeEnabled = false;
  bool get reviewerModeEnabled => _reviewerModeEnabled;

  // Theme mode state
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;
  static const String _themeModeKey = 'themeMode';

  // Theme palette state
  AppThemePalette _themePalette = AppThemePalette.amber;
  AppThemePalette get themePalette => _themePalette;
  static const String _themePaletteKey = 'appThemePalette';

  // Dynamic theme state (Material You)
  bool get useDynamicTheme => _themePalette == AppThemePalette.dynamicTheme;
  static const String _dynamicThemeKey = 'useDynamicTheme';

  // Clients view mode (aggregate across routers)
  bool _clientsAggregateAllRouters = true;
  static const String _clientsAggregateKey = 'clients_aggregate_all';
  bool get clientsAggregateAllRouters => _clientsAggregateAllRouters;

  // Dashboard preferences state
  DashboardPreferences _dashboardPreferences = DashboardPreferences();
  DashboardPreferences get dashboardPreferences => _dashboardPreferences;

  // Public IP state
  String? _publicIpv4;
  String? _publicIpv6;
  bool _isFetchingPublicIps = false;

  String? get publicIpv4 => _publicIpv4;
  String? get publicIpv6 => _publicIpv6;
  bool get isFetchingPublicIps => _isFetchingPublicIps;

  String? get sysauth => _authService?.sysauth;

  List<model.Router> get routers => _routerService?.routers ?? [];
  model.Router? get selectedRouter => _routerService?.selectedRouter;
  String? get currentRouterIp => selectedRouter?.ipAddress;

  /// Explicit setter for public IPs (e.g. from DashboardController reviewer mode)
  void setPublicIps(String v4, String v6) {
    _publicIpv4 = v4;
    _publicIpv6 = v6;
  }

  Future<void> loadReviewerMode(SecureStorageService defaultStorage) async {
    final stored = await defaultStorage.readValue(AppConfig.reviewerModeKey);
    _reviewerModeEnabled = stored == 'true';
  }

  Future<void> setReviewerMode(bool enabled, {BuildContext? context}) async {
    _cancelThroughputTimer();
    _setLoadingState(true);
    _setErrorState(null);

    // Invalidate active auth session token to prevent real router context bleed into reviewer mode or vice versa
    await _authService?.logout();
    _dashboardController?.resetState();

    _reviewerModeEnabled = enabled;
    await _secureStorageService.writeValue(
      AppConfig.reviewerModeKey,
      enabled.toString(),
    );

    ServiceContainer.configure(reviewerMode: enabled);
    _initializeServices();

    if (enabled) {
      setPublicIps('203.0.113.195', '2001:db8:85a3::8a2e:0370:7334');
      await tryAutoLogin(
        context: (context != null && context.mounted) ? context : null,
      );
    } else {
      _publicIpv4 = null;
      _publicIpv6 = null;
    }
    _setLoadingState(false);
    _notifyListeners();
  }

  Future<void> loadThemeMode() async {
    final stored = await _secureStorageService.readValue(_themeModeKey);
    if (stored == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (stored == 'light') {
      _themeMode = ThemeMode.light;
    } else if (stored == 'system') {
      _themeMode = ThemeMode.system;
    }
    _notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _secureStorageService.writeValue(_themeModeKey, mode.name);
    _notifyListeners();
  }

  Future<void> loadDynamicTheme() async {
    final storedPalette = await _secureStorageService.readValue(_themePaletteKey);
    if (storedPalette != null) {
      var found = false;
      for (final p in AppThemePalette.values) {
        if (p.name == storedPalette) {
          _themePalette = p;
          found = true;
          break;
        }
      }
      if (!found) {
        // Gracefully migrate legacy removed palettes (emerald, teal, indigo) to YALA Amber
        _themePalette = AppThemePalette.amber;
      }
    } else {
      final stored = await _secureStorageService.readValue(_dynamicThemeKey);
      if (stored == 'true') {
        _themePalette = AppThemePalette.dynamicTheme;
      } else {
        _themePalette = AppThemePalette.amber;
      }
    }
    _notifyListeners();
  }

  Future<void> setThemePalette(AppThemePalette palette) async {
    _themePalette = palette;
    await _secureStorageService.writeValue(_themePaletteKey, palette.name);
    await _secureStorageService.writeValue(
      _dynamicThemeKey,
      (palette == AppThemePalette.dynamicTheme).toString(),
    );
    _notifyListeners();
  }

  Future<void> setDynamicTheme(bool enable) async {
    if (enable) {
      await setThemePalette(AppThemePalette.dynamicTheme);
    } else {
      if (_themePalette == AppThemePalette.dynamicTheme) {
        await setThemePalette(AppThemePalette.amber);
      }
    }
  }

  Future<void> loadClientsViewMode() async {
    final stored = await _secureStorageService.readValue(_clientsAggregateKey);
    if (stored == 'true') {
      _clientsAggregateAllRouters = true;
    } else if (stored == 'false') {
      _clientsAggregateAllRouters = false;
    }
  }

  Future<void> setClientsAggregateAllRouters(bool aggregate) async {
    _clientsAggregateAllRouters = aggregate;
    await _secureStorageService.writeValue(
      _clientsAggregateKey,
      aggregate.toString(),
    );
    _notifyListeners();
  }

  Future<void> loadDashboardPreferences() async {
    try {
      final routerId = _routerService?.selectedRouter?.id;
      final key = routerId != null
          ? 'dashboard_preferences:$routerId'
          : 'dashboard_preferences';

      String? jsonStr = await _secureStorageService.readValue(key);
      if ((jsonStr == null || jsonStr.isEmpty) && routerId != null) {
        jsonStr = await _secureStorageService.readValue(
          'dashboard_preferences',
        );
      }
      if (jsonStr != null && jsonStr.isNotEmpty) {
        _dashboardPreferences = DashboardPreferences.fromJson(
          jsonDecode(jsonStr),
        );
        _notifyListeners();
      }
    } catch (e, stack) {
      Logger.exception('Failed to load dashboard preferences', e, stack);
      _dashboardPreferences = DashboardPreferences();
    }
  }

  Future<void> saveDashboardPreferences(DashboardPreferences prefs) async {
    try {
      _dashboardPreferences = prefs;
      final routerId = _routerService?.selectedRouter?.id;
      final key = routerId != null
          ? 'dashboard_preferences:$routerId'
          : 'dashboard_preferences';
      await _secureStorageService.writeValue(key, jsonEncode(prefs.toJson()));
      _notifyListeners();
    } catch (e, stack) {
      Logger.exception('Failed to save dashboard preferences', e, stack);
      rethrow;
    }
  }

  /// One-time migration: if a global 'dashboard_preferences' exists,
  /// copy it to each router-specific key that doesn't already have prefs.
  Future<void> migrateGlobalDashboardPreferencesIfNeeded() async {
    try {
      const globalKey = 'dashboard_preferences';
      final globalJson = await _secureStorageService.readValue(globalKey);
      if (globalJson == null || globalJson.isEmpty) return;

      final currentRouters = _routerService?.routers ?? const <model.Router>[];
      if (currentRouters.isEmpty) return;

      try {
        jsonDecode(globalJson);
      } catch (_) {
        return; // Not valid JSON; skip migration
      }

      for (final router in currentRouters) {
        final key = 'dashboard_preferences:${router.id}';
        final existing = await _secureStorageService.readValue(key);
        if (existing == null || existing.isEmpty) {
          await _secureStorageService.writeValue(key, globalJson);
        }
      }

      var allHavePrefs = true;
      for (final router in currentRouters) {
        final key = 'dashboard_preferences:${router.id}';
        final v = await _secureStorageService.readValue(key);
        if (v == null || v.isEmpty) {
          allHavePrefs = false;
          break;
        }
      }
      if (allHavePrefs) {
        await _secureStorageService.deleteValue(globalKey);
      }
    } catch (e, stack) {
      Logger.exception(
        'Failed migrating global dashboard preferences',
        e,
        stack,
      );
    }
  }

  Future<void> fetchPublicIps({BuildContext? context}) async {
    if (_reviewerModeEnabled) {
      _publicIpv4 = '203.0.113.195';
      _publicIpv6 = '2001:db8:85a3::8a2e:0370:7334';
      _notifyListeners();
      return;
    }

    final selected = selectedRouter;
    final sys = sysauth;
    if (selected == null || sys == null || _apiService == null) return;

    _isFetchingPublicIps = true;
    try {
      final res = await _apiService!.fetchPublicIps(
        selected.ipAddress,
        sys,
        selected.useHttps,
        context: context,
      );
      _publicIpv4 = res['ipv4'];
      _publicIpv6 = res['ipv6'];
    } catch (e) {
      Logger.warning('fetchPublicIps failed in SessionController: $e');
    } finally {
      _isFetchingPublicIps = false;
      _notifyListeners();
    }
  }

  Future<void> loadRouters() async {
    await _routerService?.loadRouters();
    _notifyListeners();
  }

  Future<void> addRouter(model.Router router) async {
    await _routerService?.addRouter(router);
    _notifyListeners();
  }

  Future<void> removeRouter(String id) async {
    if (_routerService == null) return;

    final router = _routerService!.routers.firstWhere(
      (r) => r.id == id,
      orElse: () => throw Exception('Router not found'),
    );

    await _httpClientManager.clearCertificatesForHost(router.ipAddress);

    final needsSwitch = await _routerService!.removeRouter(id);
    if (needsSwitch && _routerService!.routers.isNotEmpty) {
      if (_authService?.isAuthenticated == true || _reviewerModeEnabled) {
        await selectRouter(_routerService!.routers.first.id);
      } else {
        _notifyListeners();
      }
    } else if (_routerService!.selectedRouter == null) {
      if (_authService?.isAuthenticated == true || _reviewerModeEnabled) {
        await logout();
      } else {
        _dashboardController?.resetState();
        _notifyListeners();
      }
    } else {
      _notifyListeners();
    }
  }

  Future<void> selectRouter(String id, {BuildContext? context}) async {
    if (_routerService == null || _routerService!.routers.isEmpty) return;

    final found = await _routerService!.selectRouter(id);
    if (found == null) return;

    _setLoadingState(true);
    _setErrorState(null);
    _cancelThroughputTimer();

    // Context-aware guardrail: Ensure previous socket connections and auth token
    // are completely cleared before initializing a session for the newly selected router profile
    _httpClientManager.disposeAll();
    await _authService?.logout();
    _dashboardController?.resetState();

    await loadDashboardPreferences();

    _notifyListeners();
    final loginSuccess = await login(
      found.ipAddress,
      found.username,
      found.password,
      found.useHttps,
      fromRouter: true,
      context: (context != null && context.mounted) ? context : null,
    );
    if (loginSuccess) {
      await _fetchDashboardData(force: true);
      _startThroughputTimer();
    } else {
      // Guardrail: Reset dashboard state if connection fails to avoid displaying stale data under new profile label
      _dashboardController?.resetState();
      final routerLabel = found.lastKnownHostname ?? found.ipAddress;
      _setErrorState(
        'Failed to establish session with $routerLabel (${found.ipAddress}).',
      );
    }
    _setLoadingState(false);
    _notifyListeners();
  }

  Future<void> updateRouter(model.Router router) async {
    await _routerService?.updateRouter(router);
    _notifyListeners();
  }

  Future<void> updateRouterName(String id, String? name) async {
    await _routerService?.updateRouterName(id, name);
    _notifyListeners();
  }

  Future<FileSaveResult?> exportRouterProfiles() async {
    final jsonString = _routerService?.exportRoutersAsJson();
    if (jsonString == null || _routerService!.routers.isEmpty) {
      return null;
    }
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final fileName = 'yala_router_profiles_$timestamp.json';
    final bytes = Uint8List.fromList(utf8.encode(jsonString));
    return await OsPlatformIntegration.saveDownloadedFileWithResult(
      bytes: bytes,
      fileName: fileName,
    );
  }

  Future<RouterImportResult> importRoutersFromJson(String jsonContent) async {
    if (_routerService == null) {
      return const RouterImportResult(
        success: false,
        errorMessage: 'Router service not initialized.',
      );
    }
    final result = await _routerService!.importRoutersFromJson(jsonContent);
    if (result.success) {
      _notifyListeners();
    }
    return result;
  }

  Future<RouterImportResult> importRouterProfilesFromFile() async {
    if (_routerService == null) {
      return const RouterImportResult(
        success: false,
        errorMessage: 'Router service not initialized.',
      );
    }

    PlatformFile? pickedFile;
    bool pickerAttempted = false;
    try {
      pickedFile = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      pickerAttempted = true;
    } catch (e, stack) {
      Logger.warning('Custom JSON file picker failed: $e');
      Logger.exception('FilePicker custom extension failed', e, stack);
    }

    if (!pickerAttempted) {
      try {
        pickedFile = await FilePicker.pickFile(type: FileType.any);
      } catch (e, stack) {
        Logger.exception('FilePicker any fallback failed', e, stack);
        return RouterImportResult(
          success: false,
          errorMessage: 'Could not open file picker: $e',
        );
      }
    }

    if (pickedFile == null) {
      return const RouterImportResult(
        success: false,
        errorMessage: 'No file selected.',
      );
    }

    final fileName = pickedFile.name.toLowerCase();

    // Strict validation: Reject if not .json
    if (!fileName.endsWith('.json')) {
      return const RouterImportResult(
        success: false,
        errorMessage: 'Invalid file type. Only .json files are accepted.',
      );
    }

    String jsonContent;
    try {
      final bytes = await pickedFile.readAsBytes();
      if (bytes.isNotEmpty) {
        jsonContent = utf8.decode(bytes);
      } else {
        throw Exception('Empty byte buffer');
      }
    } catch (_) {
      try {
        jsonContent = await pickedFile.xFile.readAsString();
      } catch (e) {
        if (pickedFile.path != null && pickedFile.path!.isNotEmpty) {
          final f = File(pickedFile.path!);
          if (await f.exists()) {
            jsonContent = await f.readAsString();
          } else {
            return const RouterImportResult(
              success: false,
              errorMessage: 'The selected file could not be found.',
            );
          }
        } else {
          return RouterImportResult(
            success: false,
            errorMessage: 'Failed to read file: $e',
          );
        }
      }
    }

    if (jsonContent.trim().isEmpty) {
      return const RouterImportResult(
        success: false,
        errorMessage: 'The selected file is empty.',
      );
    }

    return await importRoutersFromJson(jsonContent);
  }

  Future<bool> login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    bool fromRouter = false,
    String? routerName,
    BuildContext? context,
  }) async {
    _setLoadingState(true);
    _setErrorState(null);

    _cancelThroughputTimer();
    _notifyListeners();

    try {
      await _authService!.login(ip, user, pass, useHttps, context: context);

      if (_authService!.isAuthenticated) {
        final actualUseHttps = _authService!.useHttps;

        if (!fromRouter) {
          if (_routerService != null) {
            final targetId = RouterService.generateId(ip, user, actualUseHttps);
            final existing = _routerService!.routers
                .where((r) => r.id == targetId)
                .firstOrNull;
            final effectiveName =
                (routerName != null && routerName.trim().isNotEmpty)
                ? routerName.trim()
                : existing?.name;

            final router = _routerService!.createRouter(
              ip,
              user,
              pass,
              actualUseHttps,
              name: effectiveName,
              lastKnownHostname: existing?.lastKnownHostname,
            );
            final idx = _routerService!.routers.indexWhere(
              (r) => r.id == router.id,
            );
            if (idx == -1) {
              await addRouter(router);
            } else {
              await updateRouter(router);
            }
          }
          _startThroughputTimer();
          _setLoadingState(false);
          _notifyListeners();
          // Trigger dashboard data fetching asynchronously so UI transitions immediately to MainScreen
          unawaited(_fetchDashboardData());
        } else if (actualUseHttps != useHttps && _routerService != null) {
          final router = _routerService!.selectedRouter;
          if (router != null) {
            final updatedRouter = router.copyWith(useHttps: actualUseHttps);
            await updateRouter(updatedRouter);
            Logger.info(
              'Updated router protocol from ${useHttps ? "HTTPS" : "HTTP"} to ${actualUseHttps ? "HTTPS" : "HTTP"}',
            );
          }
        }
        return true;
      } else {
        _setErrorState(
          'Login Failed: Invalid credentials or host unreachable.',
        );
        _setLoadingState(false);
        _notifyListeners();
        return false;
      }
    } catch (e) {
      _setErrorState('An error occurred: $e');
      _setLoadingState(false);
      _notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _cancelThroughputTimer();
    await _authService?.logout();
    _reviewerModeEnabled = false;
    await _secureStorageService.writeValue(AppConfig.reviewerModeKey, 'false');
    // Preserve saved router profiles — only clear the active session token.
    // Router profiles persist until the user explicitly removes them from the profile list.
    _dashboardController?.resetState();
    _publicIpv4 = null;
    _publicIpv6 = null;
    _setErrorState(null);
    _notifyListeners();
  }

  Future<bool> tryAutoLogin({
    bool force = false,
    bool fetchDashboard = true,
    BuildContext? context,
  }) async {
    final success =
        await _authService?.tryAutoLogin(
          null,
          null,
          null,
          null,
          force: force,
          context: context,
        ) ??
        false;
    if (success) {
      await loadRouters();
      if (fetchDashboard) {
        await _fetchDashboardData();
      }
      if (!_reviewerModeEnabled) {
        _startThroughputTimer();
      }
      _notifyListeners();
    }
    return success;
  }

  /// Handles app resumption when screen turns on or app returns from background.
  Future<void> handleAppResume() async {
    if (!_reviewerModeEnabled) {
      _startThroughputTimer();
    }

    if (_reviewerModeEnabled) {
      return;
    }

    // Flush stale HTTP client sockets from memory on app resume to ensure immediate fresh TCP connections
    _httpClientManager.disposeAll();

    // Refresh dashboard data upon resuming from background if authenticated
    if (selectedRouter != null && _authService?.isAuthenticated == true) {
      unawaited(_fetchDashboardData());
    }
  }
}
