// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/ssh_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/ssh_persistent_session_interface.dart';
import 'package:yet_another_luci_app/services/auth_service.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/services/ssh_service.dart';
import 'package:yet_another_luci_app/services/ssh_persistent_session.dart';
import 'package:yet_another_luci_app/services/mock_auth_service.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/mock_ssh_service.dart';
import 'package:yet_another_luci_app/services/mock_ssh_persistent_session.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/throughput_service.dart';

abstract class ServiceFactory {
  IAuthService createAuthService();
  IApiService createApiService();
  ISshService createSshService();
  ISshPersistentSession createSshPersistentSession();
  SecureStorageService createSecureStorageService();
  RouterService createRouterService();
  ThroughputService createThroughputService();
}

class ProductionServiceFactory implements ServiceFactory {
  RealApiService? _apiService;
  RealAuthService? _authService;
  RealSshService? _sshService;
  SecureStorageService? _secureStorageService;
  RouterService? _routerService;
  ThroughputService? _throughputService;

  @override
  IApiService createApiService() => _apiService ??= RealApiService();

  @override
  IAuthService createAuthService() =>
      _authService ??= RealAuthService(createApiService());

  @override
  ISshService createSshService() => _sshService ??= RealSshService();

  @override
  ISshPersistentSession createSshPersistentSession() =>
      RealSshPersistentSession();

  @override
  SecureStorageService createSecureStorageService() =>
      _secureStorageService ??= SecureStorageService();

  @override
  RouterService createRouterService() => _routerService ??= RouterService();

  @override
  ThroughputService createThroughputService() =>
      _throughputService ??= ThroughputService();
}

class ReviewerModeServiceFactory implements ServiceFactory {
  MockApiService? _apiService;
  MockAuthService? _authService;
  MockSshService? _sshService;
  SecureStorageService? _secureStorageService;
  RouterService? _routerService;
  ThroughputService? _throughputService;

  @override
  IAuthService createAuthService() => _authService ??= MockAuthService();

  @override
  IApiService createApiService() => _apiService ??= MockApiService();

  @override
  ISshService createSshService() => _sshService ??= MockSshService();

  @override
  ISshPersistentSession createSshPersistentSession() =>
      MockSshPersistentSession();

  @override
  SecureStorageService createSecureStorageService() =>
      _secureStorageService ??= SecureStorageService();

  @override
  RouterService createRouterService() =>
      _routerService ??= RouterService(isReviewerMode: true);

  @override
  ThroughputService createThroughputService() =>
      _throughputService ??= ThroughputService();

  /// Resets mock service instances so no reviewer state lingers across mode switches.
  void reset() {
    _apiService = null;
    _authService = null;
    _sshService = null;
    _secureStorageService = null;
    _routerService = null;
    _throughputService = null;
    MockApiService.resetMockState();
  }
}

class ServiceContainer {
  static ServiceContainer? _instance;
  static ServiceContainer get instance => _instance ??= ServiceContainer._();

  ServiceContainer._();

  final ProductionServiceFactory _productionFactory =
      ProductionServiceFactory();
  final ReviewerModeServiceFactory _reviewerFactory =
      ReviewerModeServiceFactory();

  ServiceFactory? _factory;

  void setFactory(ServiceFactory factory) {
    _factory = factory;
  }

  ServiceFactory get factory {
    _factory ??= _productionFactory;
    return _factory!;
  }

  static void configure({required bool reviewerMode}) {
    if (!reviewerMode) {
      instance._reviewerFactory.reset();
    }
    instance.setFactory(
      reviewerMode ? instance._reviewerFactory : instance._productionFactory,
    );
  }
}
