// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/utils/logger.dart';

class RealAuthService implements IAuthService {
  final SecureStorageService _secureStorageService = SecureStorageService();
  final IApiService _apiService;

  String? _sysauth;
  String? _ipAddress;
  bool _useHttps = false;

  RealAuthService(this._apiService);

  @override
  String? get sysauth => _sysauth;
  @override
  String? get ipAddress => _ipAddress;
  @override
  bool get useHttps => _useHttps;
  @override
  bool get isAuthenticated => _sysauth != null;

  @override
  Future<void> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    final result = await _apiService.authenticate(
      ipAddress,
      username,
      password,
      useHttps,
      context: context,
    );

    if (result.isSuccess && result.token != null) {
      _sysauth = result.token;
      _ipAddress = ipAddress;
      _useHttps = result.actualUseHttps;

      await _secureStorageService.saveCredentials(
        ipAddress: ipAddress,
        username: username,
        password: password,
        useHttps: result.actualUseHttps,
      );

      if (result.actualUseHttps != useHttps) {
        Logger.info(
          'Protocol changed from ${useHttps ? "HTTPS" : "HTTP"} to ${result.actualUseHttps ? "HTTPS" : "HTTP"} due to redirect',
        );
      }
    } else {
      _sysauth = null;
    }
  }

  @override
  Future<bool> tryAutoLogin(
    String? ipAddress,
    String? username,
    String? password,
    bool? useHttps, {
    bool force = false,
    BuildContext? context,
  }) async {
    if (!force && isAuthenticated) {
      return true;
    }

    if (force) {
      _sysauth = null;
    }

    if (ipAddress != null &&
        username != null &&
        password != null &&
        useHttps != null) {
      await login(ipAddress, username, password, useHttps, context: context);
      return isAuthenticated;
    }

    final credentials = await _secureStorageService.getCredentials();
    final ip = credentials['ipAddress'];
    final user = credentials['username'];
    final pass = credentials['password'];
    final storedHttps = credentials['useHttps'] == 'true';

    if (ip != null && user != null && pass != null) {
      await login(
        ip,
        user,
        pass,
        storedHttps,
        context: context?.mounted == true ? context : null,
      );
      return isAuthenticated;
    }

    return false;
  }

  @override
  Future<void> logout() async {
    _sysauth = null;
    _ipAddress = null;
    _useHttps = false;
    // Session token cleared. Saved router profile credentials in SecureStorageService are preserved
    // so auto-login on app restart or router profile selection functions reliably.
  }

  @override
  Future<bool> checkRouterAvailability(
    String ipAddress,
    bool useHttps, {
    BuildContext? context,
  }) async {
    if (ipAddress.isEmpty) return false;

    try {
      final result = await _apiService.call(
        ipAddress,
        '',
        useHttps,
        object: 'system',
        method: 'board',
        params: {},
        context: context,
      );
      return result != null;
    } catch (e) {
      return false;
    }
  }
}
