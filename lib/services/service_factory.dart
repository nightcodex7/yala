// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/auth_service.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/services/mock_auth_service.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/throughput_service.dart';

abstract class ServiceFactory {
  IAuthService createAuthService();
  IApiService createApiService();
  SecureStorageService createSecureStorageService();
  RouterService createRouterService();
  ThroughputService createThroughputService();
}

class ProductionServiceFactory implements ServiceFactory {
  RealApiService? _apiService;
  RealAuthService? _authService;
  SecureStorageService? _secureStorageService;
  RouterService? _routerService;
  ThroughputService? _throughputService;

  @override
  IApiService createApiService() => _apiService ??= RealApiService();

  @override
  IAuthService createAuthService() =>
      _authService ??= RealAuthService(createApiService());

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
  SecureStorageService? _secureStorageService;
  RouterService? _routerService;
  ThroughputService? _throughputService;

  @override
  IAuthService createAuthService() => _authService ??= MockAuthService();

  @override
  IApiService createApiService() => _apiService ??= MockApiService();

  @override
  SecureStorageService createSecureStorageService() =>
      _secureStorageService ??= SecureStorageService();

  @override
  RouterService createRouterService() =>
      _routerService ??= RouterService(isReviewerMode: true);

  @override
  ThroughputService createThroughputService() =>
      _throughputService ??= ThroughputService();
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
    instance.setFactory(
      reviewerMode ? instance._reviewerFactory : instance._productionFactory,
    );
  }
}
