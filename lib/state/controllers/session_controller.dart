// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/design/luci_theme.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/services/local_network_permission_service.dart';
import 'package:yet_another_luci_app/services/service_factory.dart';
import 'package:yet_another_luci_app/state/controllers/dashboard_controller.dart';
import 'package:yet_another_luci_app/services/operation_queue.dart';
import 'package:yet_another_luci_app/utils/http_client_manager.dart';
import 'package:yet_another_luci_app/utils/logger.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';

/// Progress states during router password modification.
enum ChangePasswordStatus {
  idle,
  validating,
  requesting,
  reauthenticating,
  verifying,
  savingStorage,
  success,
  storageWarning,
  ambiguous,
  failed,
}

/// Result returned from [SessionController.changeRouterPassword].
class ChangePasswordResult {
  final ChangePasswordStatus status;
  final String? errorMessage;
  final bool isSuccess;

  const ChangePasswordResult.success()
    : status = ChangePasswordStatus.success,
      errorMessage = null,
      isSuccess = true;

  const ChangePasswordResult.storageWarning(this.errorMessage)
    : status = ChangePasswordStatus.storageWarning,
      isSuccess = true;

  const ChangePasswordResult.ambiguous(this.errorMessage)
    : status = ChangePasswordStatus.ambiguous,
      isSuccess = false;

  const ChangePasswordResult.failed(this.errorMessage)
    : status = ChangePasswordStatus.failed,
      isSuccess = false;
}

/// Encapsulates authentication session lifecycle, router profile selection,
/// preference storage, theme persistence, and reviewer mode configuration.
///
/// Extracted from [AppState] to enforce single-responsibility.
class SessionController {
  SessionController({
    bool initialReviewerMode = false,
    ThemeMode initialThemeMode = ThemeMode.system,
    AppThemePalette initialThemePalette = AppThemePalette.amber,
    Locale? initialLocale,
    bool initialClientsAggregateAllRouters = true,
    DashboardPreferences? initialDashboardPreferences,
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
    VoidCallback? onSessionReset,
  }) : _reviewerModeEnabled = initialReviewerMode,
       _themeMode = initialThemeMode,
       _themePalette = initialThemePalette,
       _locale = initialLocale,
       _clientsAggregateAllRouters = initialClientsAggregateAllRouters,
       _dashboardPreferences =
           initialDashboardPreferences ?? DashboardPreferences(),
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
       _notifyListeners = notifyListeners,
       _onSessionReset = onSessionReset;

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
  final VoidCallback? _onSessionReset;

  IApiService? get _apiService => _apiServiceRef();
  IAuthService? get _authService => _authServiceRef();
  RouterService? get _routerService => _routerServiceRef();
  SecureStorageService get _secureStorageService => _secureStorageServiceRef();
  HttpClientManager get _httpClientManager => _httpClientManagerRef();
  DashboardController? get _dashboardController => _dashboardControllerRef();

  // Reviewer mode state
  bool _reviewerModeEnabled = false;
  bool get reviewerModeEnabled => _reviewerModeEnabled;

  SharedPreferences? _prefs;

  // Pre-hydrated Monet dynamic color schemes (Android 12+)
  ColorScheme? _preloadedLightDynamic;
  ColorScheme? _preloadedDarkDynamic;
  ColorScheme? get preloadedLightDynamic => _preloadedLightDynamic;
  ColorScheme? get preloadedDarkDynamic => _preloadedDarkDynamic;

  void setPreloadedDynamicColorSchemes({
    ColorScheme? light,
    ColorScheme? dark,
  }) {
    _preloadedLightDynamic = light;
    _preloadedDarkDynamic = dark;
  }

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

  // Locale state (null = System default)
  Locale? _locale;
  Locale? get locale => _locale;
  static const String _localeKey = 'app_locale';

  static Locale? _parseLocale(String? stored) {
    if (stored == null || stored.isEmpty || stored == 'system') {
      return null;
    } else if (stored.contains('_') || stored.contains('-')) {
      final parts = stored.replaceAll('-', '_').split('_');
      return Locale(parts[0], parts.length > 1 ? parts[1] : null);
    } else {
      return Locale(stored);
    }
  }

  /// Synchronously or fast-asynchronously pre-hydrates user UI preferences
  /// (Theme Palette, Theme Mode, Locale, Dynamic Color) prior to building Frame 1.
  /// Eliminates the split-second theme flicker (FOUC) from default Amber to Material You.
  Future<void> preHydratePreferences({SharedPreferences? prefs}) async {
    try {
      _prefs = prefs ?? await SharedPreferences.getInstance();

      final corePalette = await DynamicColorPlugin.getCorePalette();
      if (corePalette != null) {
        _preloadedLightDynamic = corePalette.toColorScheme(
          brightness: Brightness.light,
        );
        _preloadedDarkDynamic = corePalette.toColorScheme(
          brightness: Brightness.dark,
        );
      }

      // 1. Theme Palette Pre-Hydration
      final cachedPalette = _prefs?.getString(_themePaletteKey);
      if (cachedPalette != null) {
        _themePalette = AppThemePalette.values.firstWhere(
          (p) => p.name == cachedPalette,
          orElse: () => AppThemePalette.amber,
        );
      } else {
        final storedPalette = await _secureStorageService.readValue(
          _themePaletteKey,
        );
        if (storedPalette != null) {
          _themePalette = AppThemePalette.values.firstWhere(
            (p) => p.name == storedPalette,
            orElse: () => AppThemePalette.amber,
          );
        } else {
          final storedDynamic = await _secureStorageService.readValue(
            _dynamicThemeKey,
          );
          if (storedDynamic == 'true') {
            _themePalette = AppThemePalette.dynamicTheme;
          } else {
            _themePalette = AppThemePalette.amber;
          }
        }
        await _prefs?.setString(_themePaletteKey, _themePalette.name);
        await _prefs?.setBool(
          _dynamicThemeKey,
          _themePalette == AppThemePalette.dynamicTheme,
        );
      }

      // 2. Theme Mode Pre-Hydration
      final cachedMode = _prefs?.getString(_themeModeKey);
      if (cachedMode != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == cachedMode,
          orElse: () => ThemeMode.system,
        );
      } else {
        final stored = await _secureStorageService.readValue(_themeModeKey);
        if (stored == 'dark') {
          _themeMode = ThemeMode.dark;
        } else if (stored == 'light') {
          _themeMode = ThemeMode.light;
        } else {
          _themeMode = ThemeMode.system;
        }
        await _prefs?.setString(_themeModeKey, _themeMode.name);
      }

      // 3. Locale Pre-Hydration
      final cachedLocale = _prefs?.getString(_localeKey);
      if (cachedLocale != null) {
        _locale = _parseLocale(cachedLocale);
      } else {
        final stored = await _secureStorageService.readValue(_localeKey);
        _locale = _parseLocale(stored);
        if (stored != null) {
          await _prefs?.setString(_localeKey, stored);
        }
      }
    } catch (e, stack) {
      Logger.exception(
        'SessionController.preHydratePreferences failed',
        e,
        stack,
      );
    }
  }

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
    _onSessionReset?.call();

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
      await _routerService?.loadRouters();
    }
    _setLoadingState(false);
    _notifyListeners();
  }

  Future<void> loadThemeMode({bool notify = true}) async {
    final cached = _prefs?.getString(_themeModeKey);
    final stored =
        cached ?? await _secureStorageService.readValue(_themeModeKey);
    if (stored == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (stored == 'light') {
      _themeMode = ThemeMode.light;
    } else if (stored == 'system') {
      _themeMode = ThemeMode.system;
    }
    if (notify) {
      _notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.setString(_themeModeKey, mode.name);
    } catch (_) {}
    await _secureStorageService.writeValue(_themeModeKey, mode.name);
    _notifyListeners();
  }

  Future<void> loadDynamicTheme({bool notify = true}) async {
    final cached = _prefs?.getString(_themePaletteKey);
    final storedPalette =
        cached ?? await _secureStorageService.readValue(_themePaletteKey);
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
      final cachedDynamic = _prefs?.getBool(_dynamicThemeKey);
      final stored = cachedDynamic != null
          ? cachedDynamic.toString()
          : await _secureStorageService.readValue(_dynamicThemeKey);
      if (stored == 'true') {
        _themePalette = AppThemePalette.dynamicTheme;
      } else {
        _themePalette = AppThemePalette.amber;
      }
    }
    if (notify) {
      _notifyListeners();
    }
  }

  Future<void> setThemePalette(AppThemePalette palette) async {
    _themePalette = palette;
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.setString(_themePaletteKey, palette.name);
      await prefs.setBool(
        _dynamicThemeKey,
        palette == AppThemePalette.dynamicTheme,
      );
    } catch (_) {}
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

  Future<void> loadLocale({bool notify = true}) async {
    final cached = _prefs?.getString(_localeKey);
    final stored = cached ?? await _secureStorageService.readValue(_localeKey);
    _locale = _parseLocale(stored);
    if (notify) {
      _notifyListeners();
    }
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    final code = locale == null
        ? 'system'
        : (locale.countryCode != null && locale.countryCode!.isNotEmpty
              ? '${locale.languageCode}_${locale.countryCode}'
              : locale.languageCode);
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.setString(_localeKey, code);
    } catch (_) {}
    await _secureStorageService.writeValue(_localeKey, code);
    _notifyListeners();
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
      if (_reviewerModeEnabled ||
          RouterService.isMockRouter(_routerService?.selectedRouter)) {
        _notifyListeners();
        return;
      }
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

  void setDashboardPreferencesForTesting(DashboardPreferences prefs) {
    _dashboardPreferences = prefs;
    _notifyListeners();
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

  Future<void> loadRouters({bool notify = true}) async {
    await _routerService?.loadRouters();
    if (notify) {
      _notifyListeners();
    }
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

  int _switchEpoch = 0;

  Future<void> selectRouter(String id, {BuildContext? context}) async {
    if (_routerService == null || _routerService!.routers.isEmpty) return;

    // Fast-path: if already connected to this router and session is valid, no need to re-login from scratch
    if (_routerService?.selectedRouter?.id == id &&
        _authService?.isAuthenticated == true &&
        _dashboardController?.dashboardData != null) {
      _setLoadingState(false);
      return;
    }

    final currentEpoch = ++_switchEpoch;

    final found = await _routerService!.selectRouter(id);
    if (found == null || currentEpoch != _switchEpoch) return;

    _setLoadingState(true);
    _setErrorState(null);
    _cancelThroughputTimer();

    try {
      // Context-aware guardrail: Ensure previous socket connections and auth token
      // are completely cleared before initializing a session for the newly selected router profile
      _httpClientManager.disposeAll(forceCloseAdapter: true);
      await _authService?.logout();
      if (currentEpoch != _switchEpoch) return;

      _dashboardController?.resetState();
      _onSessionReset?.call();

      await loadDashboardPreferences();
      if (currentEpoch != _switchEpoch) return;

      _notifyListeners();
      final loginSuccess = await login(
        found.ipAddress,
        found.username,
        found.password,
        found.useHttps,
        fromRouter: true,
        context: (context != null && context.mounted) ? context : null,
      );
      if (currentEpoch != _switchEpoch) return;

      if (loginSuccess) {
        await _fetchDashboardData(force: true);
        if (currentEpoch != _switchEpoch) return;
        _startThroughputTimer();
      } else {
        // Guardrail: Reset dashboard state if connection fails to avoid displaying stale data under new profile label
        _dashboardController?.resetState();
        final routerLabel = found.lastKnownHostname ?? found.ipAddress;
        final target =
            found.lastKnownHostname != null &&
                found.lastKnownHostname != found.ipAddress
            ? '$routerLabel (${found.ipAddress})'
            : found.ipAddress;
        final l10n = (context != null && context.mounted)
            ? AppLocalizations.of(context)
            : null;
        _setErrorState(
          l10n?.loginFailedSession(target) ??
              'Failed to establish session with $target.',
        );
      }
    } finally {
      if (currentEpoch == _switchEpoch) {
        _setLoadingState(false);
        _notifyListeners();
      }
    }
  }

  Future<void> updateRouter(model.Router router, {String? oldId}) async {
    await _routerService?.updateRouter(router, oldId: oldId);
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
        final l10n = (context != null && context.mounted)
            ? AppLocalizations.of(context)
            : null;
        _setErrorState(
          l10n?.loginInvalidCredentials ??
              'Login Failed: Invalid credentials or host unreachable.',
        );
        _setLoadingState(false);
        _notifyListeners();
        return false;
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      final l10n = (context != null && context.mounted)
          ? AppLocalizations.of(context)
          : null;
      if (!kIsWeb &&
          Platform.isIOS &&
          (errStr.contains('operation not permitted') ||
              errStr.contains('errno = 1'))) {
        _setErrorState(
          l10n?.localNetworkPermissionRequiredIos ??
              'Local network permission required. Please allow access in iOS Settings > Yet Another LuCI App.',
        );
      } else if (!kIsWeb &&
          Platform.isAndroid &&
          (errStr.contains('socketexception') ||
              errStr.contains('operation not permitted') ||
              errStr.contains('connection timed out') ||
              errStr.contains('connection refused') ||
              errStr.contains('errno = 110') ||
              errStr.contains('errno = 111'))) {
        final hasPerm = await LocalNetworkPermissionService.isGranted();
        if (!hasPerm) {
          _setErrorState(
            l10n?.localNetworkPermissionRequiredAndroid ??
                'Local network permission required. Please allow access in Android Settings > Apps > Yet Another LuCI App > Permissions.',
          );
        } else {
          _setErrorState('An error occurred: $e');
        }
      } else {
        _setErrorState('An error occurred: $e');
      }
      _setLoadingState(false);
      _notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _cancelThroughputTimer();
    await _authService?.logout();
    final wasReviewer = _reviewerModeEnabled;
    _reviewerModeEnabled = false;
    await _secureStorageService.writeValue(AppConfig.reviewerModeKey, 'false');

    // Guarantee that service container is restored to production factory!
    ServiceContainer.configure(reviewerMode: false);
    _initializeServices();

    // Reset all controller states to prevent ANY data leakage
    _dashboardController?.resetState();
    _onSessionReset?.call();
    _publicIpv4 = null;
    _publicIpv6 = null;
    _setErrorState(null);

    // If was in reviewer mode, reload real production routers cleanly
    if (wasReviewer) {
      await _routerService?.loadRouters();
    }
    _notifyListeners();
  }

  Future<bool> tryAutoLogin({
    bool force = false,
    bool fetchDashboard = true,
    BuildContext? context,
  }) async {
    if (_routerService?.selectedRouter == null) {
      await loadRouters();
    }
    final selected = _routerService?.selectedRouter;
    final success =
        await _authService?.tryAutoLogin(
          selected?.ipAddress,
          selected?.username,
          selected?.password,
          selected?.useHttps,
          force: force,
          context: (context != null && context.mounted) ? context : null,
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

  /// Refreshes extracted Material You dynamic color schemes from Android Monet / OS.
  Future<void> refreshDynamicColors() async {
    try {
      final corePalette = await DynamicColorPlugin.getCorePalette();
      if (corePalette != null) {
        final newLight = corePalette.toColorScheme(
          brightness: Brightness.light,
        );
        final newDark = corePalette.toColorScheme(brightness: Brightness.dark);
        if (_preloadedLightDynamic != newLight ||
            _preloadedDarkDynamic != newDark) {
          _preloadedLightDynamic = newLight;
          _preloadedDarkDynamic = newDark;
          _notifyListeners();
        }
        return;
      }
      final accentColor = await DynamicColorPlugin.getAccentColor();
      if (accentColor != null) {
        final newLight = ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.light,
        );
        final newDark = ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.dark,
        );
        if (_preloadedLightDynamic != newLight ||
            _preloadedDarkDynamic != newDark) {
          _preloadedLightDynamic = newLight;
          _preloadedDarkDynamic = newDark;
          _notifyListeners();
        }
      }
    } catch (_) {}
  }

  /// Handles app resumption when screen turns on or app returns from background.
  Future<void> handleAppResume() async {
    if (!_reviewerModeEnabled) {
      _startThroughputTimer();
    }

    // Refresh dynamic colors from OS Monet on app resume in case the wallpaper was changed
    unawaited(refreshDynamicColors());

    if (_reviewerModeEnabled) {
      return;
    }

    // Flush stale HTTP client sockets from memory on app resume to ensure immediate fresh TCP connections
    _httpClientManager.disposeAll(forceCloseAdapter: false);

    // Refresh dashboard data upon resuming from background if authenticated
    if (selectedRouter != null && _authService?.isAuthenticated == true) {
      unawaited(_fetchDashboardData());
    }
  }

  /// Changes the active router root/admin password following the 10-state transactional flow.
  Future<ChangePasswordResult> changeRouterPassword({
    required String currentPassword,
    required String newPassword,
    void Function(ChangePasswordStatus status)? onProgress,
  }) async {
    final router = selectedRouter;
    if (router == null) {
      return const ChangePasswordResult.failed('No router selected');
    }

    if (currentPassword != router.password) {
      return const ChangePasswordResult.failed(
        'Current password does not match saved password',
      );
    }

    if (newPassword.isEmpty) {
      return const ChangePasswordResult.failed('New password cannot be empty');
    }

    if (newPassword == currentPassword) {
      return const ChangePasswordResult.failed(
        'New password must be different from current password',
      );
    }

    final apiService = _apiService;
    final authService = _authService;
    if (apiService == null || authService == null) {
      return const ChangePasswordResult.failed(
        'Authentication service is unavailable',
      );
    }

    final routerId = router.id;

    // Acquire router-exclusive '*' queue lock
    return await RouterScopedOperationQueue.instance.runLocked(
      routerId: routerId,
      domain: '*',
      timeout: const Duration(seconds: 60),
      action: () async {
        // State 4: Advance auth epoch & engage renewal barrier
        authService.startPasswordTransition();

        try {
          // State 5: Execute password change RPC
          onProgress?.call(ChangePasswordStatus.requesting);
          final oldSysauth = authService.sysauth ?? '';
          final rpcRes = await apiService.setRouterPassword(
            router.ipAddress,
            oldSysauth,
            router.useHttps,
            username: router.username,
            newPassword: newPassword,
          );

          if (rpcRes.isRejected) {
            authService.cancelPasswordTransition();
            return ChangePasswordResult.failed(
              rpcRes.message ?? 'Password change was rejected by router',
            );
          }

          // State 6: Destroy old session (best effort)
          onProgress?.call(ChangePasswordStatus.reauthenticating);
          try {
            await apiService.call(
              router.ipAddress,
              oldSysauth,
              router.useHttps,
              object: 'session',
              method: 'destroy',
            );
          } catch (_) {}
          authService.updateSessionToken(null);

          // State 7: Reauthenticate with new password
          final newAuthResult = await apiService.authenticate(
            router.ipAddress,
            router.username,
            newPassword,
            router.useHttps,
          );

          if (!newAuthResult.isSuccess || newAuthResult.token == null) {
            // New password authentication failed. Disambiguate by testing old password.
            final oldAuthResult = await apiService.authenticate(
              router.ipAddress,
              router.username,
              currentPassword,
              router.useHttps,
            );

            if (oldAuthResult.isSuccess && oldAuthResult.token != null) {
              // Old password still works: change was rejected router-side
              authService.completePasswordTransition(
                newToken: oldAuthResult.token!,
                newPassword: currentPassword,
                ipAddress: router.ipAddress,
                useHttps: oldAuthResult.actualUseHttps,
              );
              return const ChangePasswordResult.failed(
                'Password change was not applied by router',
              );
            } else {
              // Both failed or network dropped: ambiguous recovery
              authService.cancelPasswordTransition();
              return const ChangePasswordResult.ambiguous(
                'Unable to verify password change. Credentials unchanged.',
              );
            }
          }

          // State 8: Harmless RPC verification (system.board)
          onProgress?.call(ChangePasswordStatus.verifying);
          final newToken = newAuthResult.token!;
          bool boardVerified = false;
          try {
            final boardRes = await apiService.call(
              router.ipAddress,
              newToken,
              newAuthResult.actualUseHttps,
              object: 'system',
              method: 'board',
            );
            boardVerified =
                (boardRes is List && boardRes.isNotEmpty && boardRes[0] == 0) ||
                (boardRes is Map && boardRes['result'] != null);
          } catch (_) {
            boardVerified = false;
          }

          if (!boardVerified) {
            // Verification with new token failed. Disambiguate with old password.
            final oldAuthResult = await apiService.authenticate(
              router.ipAddress,
              router.username,
              currentPassword,
              router.useHttps,
            );

            if (oldAuthResult.isSuccess && oldAuthResult.token != null) {
              authService.completePasswordTransition(
                newToken: oldAuthResult.token!,
                newPassword: currentPassword,
                ipAddress: router.ipAddress,
                useHttps: oldAuthResult.actualUseHttps,
              );
              return const ChangePasswordResult.failed(
                'Password change verification failed',
              );
            } else {
              authService.cancelPasswordTransition();
              return const ChangePasswordResult.ambiguous(
                'Password change verification inconclusive',
              );
            }
          }

          // State 9: Update secure storage (dual-write)
          onProgress?.call(ChangePasswordStatus.savingStorage);
          final updatedRouter = router.copyWith(
            password: newPassword,
            useHttps: newAuthResult.actualUseHttps,
          );

          // Update in-memory state first so any follow-up actions use new credentials
          _routerService?.updateRouterInMemory(updatedRouter);
          authService.completePasswordTransition(
            newToken: newToken,
            newPassword: newPassword,
            ipAddress: router.ipAddress,
            useHttps: newAuthResult.actualUseHttps,
          );

          bool storageSaved = false;
          try {
            await _routerService?.persistRouterCredentials(updatedRouter);
            storageSaved = true;
          } catch (storageErr) {
            Logger.error('Failed to persist router credentials: $storageErr');
          }

          // State 10: Complete transition
          _notifyListeners();

          if (!storageSaved) {
            return const ChangePasswordResult.storageWarning(
              'Password changed on router, but saving to device secure storage failed.',
            );
          }

          return const ChangePasswordResult.success();
        } catch (e, stack) {
          Logger.exception('Unexpected error during password change', e, stack);
          authService.cancelPasswordTransition();
          return ChangePasswordResult.failed(
            'Unexpected error occurred: ${e.toString()}',
          );
        }
      },
    );
  }

  /// Retries persisting newly set router credentials to secure storage
  /// without re-invoking router password change RPC.
  Future<bool> retrySaveRouterPassword(model.Router router) async {
    try {
      await _routerService?.persistRouterCredentials(router);
      _notifyListeners();
      return true;
    } catch (e) {
      Logger.error('retrySaveRouterPassword failed: $e');
      return false;
    }
  }
}
