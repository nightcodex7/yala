// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/secure_storage_service.dart';

class RouterService {
  RouterService({this.isReviewerMode = false});

  final bool isReviewerMode;
  final SecureStorageService _secureStorageService = SecureStorageService();

  List<model.Router> _routers = [];
  model.Router? _selectedRouter;

  static final model.Router mockRouter = model.Router(
    id: 'http://192.168.1.1-root',
    ipAddress: '192.168.1.1',
    username: 'root',
    password: '',
    useHttps: false,
    lastKnownHostname: 'OpenWrt-Reviewer',
  );

  List<model.Router> get routers =>
      _routers.isEmpty && isReviewerMode ? [mockRouter] : _routers;
  model.Router? get selectedRouter =>
      _selectedRouter ?? (isReviewerMode ? mockRouter : null);

  static String generateId(String ip, String user, bool useHttps) {
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$ip-$user';
  }

  Future<void> loadRouters() async {
    _routers = await _secureStorageService.getRouters();

    // Try to restore the previously selected router
    final selectedId = await _secureStorageService.getSelectedRouterId();
    if (selectedId != null && _routers.isNotEmpty) {
      try {
        _selectedRouter = _routers.firstWhere((r) => r.id == selectedId);
      } catch (_) {
        _selectedRouter = _routers.first;
      }
    } else if (_routers.isNotEmpty) {
      _selectedRouter = _routers.first;
    } else {
      _selectedRouter = null;
    }

    if (_selectedRouter != null) {
      await _secureStorageService.saveSelectedRouterId(_selectedRouter!.id);
      await _secureStorageService.saveCredentials(
        ipAddress: _selectedRouter!.ipAddress,
        username: _selectedRouter!.username,
        password: _selectedRouter!.password,
        useHttps: _selectedRouter!.useHttps,
      );
    }
  }

  Future<void> addRouter(model.Router router) async {
    final idx = _routers.indexWhere((r) => r.id == router.id);
    if (idx != -1) {
      _routers[idx] = router;
    } else {
      _routers.add(router);
    }
    _selectedRouter = router;
    await _secureStorageService.saveRouters(_routers);
    await _secureStorageService.saveSelectedRouterId(router.id);
    await _secureStorageService.saveCredentials(
      ipAddress: router.ipAddress,
      username: router.username,
      password: router.password,
      useHttps: router.useHttps,
    );
  }

  Future<void> clearAllRouters() async {
    _routers = [];
    _selectedRouter = null;
    await _secureStorageService.saveRouters([]);
    await _secureStorageService.saveSelectedRouterId(null);
    await _secureStorageService.clearCredentials();
  }

  Future<bool> removeRouter(String id) async {
    final wasActive = _selectedRouter?.id == id;
    _routers.removeWhere((r) => r.id == id);
    await _secureStorageService.saveRouters(_routers);

    if (wasActive) {
      if (_routers.isNotEmpty) {
        _selectedRouter = _routers.first;
        await _secureStorageService.saveSelectedRouterId(_selectedRouter!.id);
        await _secureStorageService.saveCredentials(
          ipAddress: _selectedRouter!.ipAddress,
          username: _selectedRouter!.username,
          password: _selectedRouter!.password,
          useHttps: _selectedRouter!.useHttps,
        );
        return true; // Indicates need to switch to new router
      } else {
        _selectedRouter = null;
        await _secureStorageService.saveSelectedRouterId(null);
        await _secureStorageService.clearCredentials();
        return false;
      }
    }
    return false;
  }

  Future<model.Router?> selectRouter(String id) async {
    if (_routers.isEmpty) return null;
    final found = _routers.firstWhere(
      (r) => r.id == id,
      orElse: () => _routers.first,
    );
    _selectedRouter = found;
    await _secureStorageService.saveSelectedRouterId(found.id);
    await _secureStorageService.saveCredentials(
      ipAddress: found.ipAddress,
      username: found.username,
      password: found.password,
      useHttps: found.useHttps,
    );
    return found;
  }

  Future<void> updateRouter(model.Router router) async {
    final idx = _routers.indexWhere((r) => r.id == router.id);
    if (idx != -1) {
      _routers[idx] = router;
      if (_selectedRouter?.id == router.id) {
        _selectedRouter = router;
        await _secureStorageService.saveCredentials(
          ipAddress: router.ipAddress,
          username: router.username,
          password: router.password,
          useHttps: router.useHttps,
        );
      }
      await _secureStorageService.saveRouters(_routers);
    } else {
      await addRouter(router);
    }
  }

  Future<void> updateSelectedRouterHostname(String hostname) async {
    if (_selectedRouter != null && hostname.isNotEmpty) {
      _selectedRouter = _selectedRouter!.copyWith(lastKnownHostname: hostname);
      final idx = _routers.indexWhere((r) => r.id == _selectedRouter!.id);
      if (idx != -1) {
        _routers[idx] = _selectedRouter!;
      } else {
        _routers.add(_selectedRouter!);
      }
      await _secureStorageService.saveRouters(_routers);
    }
  }

  Future<void> updateRouterName(String id, String? name) async {
    final cleanName = name?.trim().isEmpty == true ? null : name?.trim();
    final idx = _routers.indexWhere((r) => r.id == id);
    if (idx != -1) {
      _routers[idx] = _routers[idx].copyWith(
        name: cleanName,
        clearName: cleanName == null,
      );
      if (_selectedRouter?.id == id) {
        _selectedRouter = _routers[idx];
      }
      await _secureStorageService.saveRouters(_routers);
    }
  }

  String exportRoutersAsJson() {
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'app': 'Yet Another LuCI App',
      'profiles': _routers.map((r) => r.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  model.Router createRouter(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    String? name,
    String? lastKnownHostname,
  }) {
    final id = generateId(ip, user, useHttps);
    return model.Router(
      id: id,
      ipAddress: ip,
      username: user,
      password: pass,
      useHttps: useHttps,
      name: name,
      lastKnownHostname: lastKnownHostname,
    );
  }

  Future<RouterImportResult> importRoutersFromJson(String jsonContent) async {
    var trimmed = jsonContent.trim();
    if (trimmed.startsWith('\uFEFF')) {
      trimmed = trimmed.substring(1).trim();
    }
    if (trimmed.isEmpty) {
      return const RouterImportResult(
        success: false,
        errorMessage: 'The selected JSON file is empty.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (e) {
      return RouterImportResult(
        success: false,
        errorMessage: 'Invalid JSON syntax: ${e.message}',
      );
    } catch (e) {
      return RouterImportResult(
        success: false,
        errorMessage: 'Could not parse JSON: $e',
      );
    }

    List<dynamic> rawProfiles;
    if (decoded is Map<String, dynamic> || decoded is Map) {
      final map = decoded as Map;
      if (map['profiles'] is List) {
        rawProfiles = map['profiles'] as List;
      } else if (map.containsKey('ipAddress') && map.containsKey('username')) {
        rawProfiles = [map];
      } else {
        return const RouterImportResult(
          success: false,
          errorMessage:
              'Invalid format: Expected a JSON object with a "profiles" array or a single profile object.',
        );
      }
    } else if (decoded is List) {
      rawProfiles = decoded;
    } else {
      return const RouterImportResult(
        success: false,
        errorMessage:
            'Invalid format: Root element must be a JSON object or array.',
      );
    }

    if (rawProfiles.isEmpty) {
      return const RouterImportResult(
        success: false,
        errorMessage: 'No router profiles found in the JSON file.',
      );
    }

    final List<String> warnings = [];
    final List<model.Router> validRouters = [];

    for (int i = 0; i < rawProfiles.length; i++) {
      final item = rawProfiles[i];
      if (item is! Map) {
        warnings.add('Item #${i + 1} is not a valid profile object.');
        continue;
      }

      final rawIp = item['ipAddress'];
      if (rawIp is! String || rawIp.trim().isEmpty) {
        warnings.add('Profile #${i + 1} is missing a valid ipAddress.');
        continue;
      }
      final ip = rawIp.trim();

      final cleanHost = ip
          .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
          .split('/')[0]
          .split(':')[0]
          .trim();
      if (cleanHost.isEmpty ||
          cleanHost.contains(' ') ||
          cleanHost.contains('\t') ||
          cleanHost.contains('\n')) {
        warnings.add('Profile #${i + 1} has an invalid IP or hostname: "$ip".');
        continue;
      }

      final rawUser = item['username'];
      if (rawUser is! String || rawUser.trim().isEmpty) {
        warnings.add('Profile #${i + 1} ($ip) is missing a valid username.');
        continue;
      }
      final username = rawUser.trim();

      final rawPass = item['password'];
      final password = rawPass is String ? rawPass : '';

      final rawHttps = item['useHttps'];
      final useHttps = rawHttps == true || rawHttps == 'true';

      final rawName = item['name'];
      final name = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : null;

      final rawHostname = item['lastKnownHostname'];
      final lastKnownHostname =
          rawHostname is String && rawHostname.trim().isNotEmpty
          ? rawHostname.trim()
          : null;

      final id =
          item['id'] is String && (item['id'] as String).trim().isNotEmpty
          ? (item['id'] as String).trim()
          : generateId(ip, username, useHttps);

      validRouters.add(
        model.Router(
          id: id,
          ipAddress: ip,
          username: username,
          password: password,
          useHttps: useHttps,
          name: name,
          lastKnownHostname: lastKnownHostname,
        ),
      );
    }

    if (validRouters.isEmpty) {
      return RouterImportResult(
        success: false,
        errorMessage: 'No valid profiles found: ${warnings.join('; ')}',
        warnings: warnings,
      );
    }

    // Ensure _routers is populated from storage before merging
    if (_routers.isEmpty) {
      await loadRouters();
    }

    int importedCount = 0;
    int updatedCount = 0;
    final List<model.Router> affectedRouters = [];

    for (final imported in validRouters) {
      final existingIdx = _routers.indexWhere((r) => r.id == imported.id);
      if (existingIdx != -1) {
        final existing = _routers[existingIdx];
        final merged = existing.copyWith(
          password: imported.password,
          name: imported.name ?? existing.name,
          lastKnownHostname:
              imported.lastKnownHostname ?? existing.lastKnownHostname,
          useHttps: imported.useHttps,
        );
        _routers[existingIdx] = merged;
        if (_selectedRouter?.id == merged.id) {
          _selectedRouter = merged;
        }
        updatedCount++;
        affectedRouters.add(merged);
      } else {
        _routers.add(imported);
        importedCount++;
        affectedRouters.add(imported);
      }
    }

    await _secureStorageService.saveRouters(_routers);

    if (_selectedRouter == null && _routers.isNotEmpty) {
      await selectRouter(_routers.first.id);
    }

    return RouterImportResult(
      success: true,
      importedCount: importedCount,
      updatedCount: updatedCount,
      totalFound: validRouters.length,
      warnings: warnings,
      importedRouters: affectedRouters,
    );
  }
}

class RouterImportResult {
  final bool success;
  final int importedCount;
  final int updatedCount;
  final int totalFound;
  final String? errorMessage;
  final List<String> warnings;
  final List<model.Router> importedRouters;

  const RouterImportResult({
    required this.success,
    this.importedCount = 0,
    this.updatedCount = 0,
    this.totalFound = 0,
    this.errorMessage,
    this.warnings = const [],
    this.importedRouters = const [],
  });
}
