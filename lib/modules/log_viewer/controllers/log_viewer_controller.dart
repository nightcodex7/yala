// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import '../models/log_entry.dart';
import '../models/log_fetch_result.dart';

class LogViewerState {
  final bool isLoadingSyslog;
  final bool isLoadingKernel;
  final LogFetchResult? syslogResult;
  final LogFetchResult? kernelResult;
  final String filterText;
  final LogLevel? selectedLevel;
  final int linesToFetch;

  const LogViewerState({
    this.isLoadingSyslog = false,
    this.isLoadingKernel = false,
    this.syslogResult,
    this.kernelResult,
    this.filterText = '',
    this.selectedLevel,
    this.linesToFetch = 200,
  });

  bool get isLoading => isLoadingSyslog || isLoadingKernel;

  LogViewerState copyWith({
    bool? isLoadingSyslog,
    bool? isLoadingKernel,
    LogFetchResult? syslogResult,
    LogFetchResult? kernelResult,
    String? filterText,
    LogLevel? selectedLevel,
    bool clearSelectedLevel = false,
    int? linesToFetch,
  }) {
    return LogViewerState(
      isLoadingSyslog: isLoadingSyslog ?? this.isLoadingSyslog,
      isLoadingKernel: isLoadingKernel ?? this.isLoadingKernel,
      syslogResult: syslogResult ?? this.syslogResult,
      kernelResult: kernelResult ?? this.kernelResult,
      filterText: filterText ?? this.filterText,
      selectedLevel: clearSelectedLevel
          ? null
          : (selectedLevel ?? this.selectedLevel),
      linesToFetch: linesToFetch ?? this.linesToFetch,
    );
  }

  List<LogEntry> filterEntries(List<LogEntry> entries) {
    return entries.where((entry) {
      if (selectedLevel != null && entry.level != selectedLevel) {
        return false;
      }
      if (filterText.isNotEmpty) {
        return entry.raw.toLowerCase().contains(filterText.toLowerCase());
      }
      return true;
    }).toList();
  }
}

class LogViewerController extends StateNotifier<LogViewerState> {
  final Ref _ref;
  // _routerId is retained for future per-router filtering; currently used for
  // guard-checking in callers that pass the routerId family parameter.
  // ignore: unused_field
  final String _routerId;

  LogViewerController(this._ref, this._routerId)
    : super(const LogViewerState()) {
    refreshBoth();
  }

  IApiService? get _apiService => _ref.read(appStateProvider).apiService;

  String get _ipAddress =>
      _ref.read(appStateProvider).selectedRouter?.ipAddress ?? '';

  String get _sysauth => _ref.read(appStateProvider).sysauth ?? '';

  bool get _useHttps =>
      _ref.read(appStateProvider).selectedRouter?.useHttps ?? false;

  void setFilterText(String text) {
    state = state.copyWith(filterText: text.trim());
  }

  void setSelectedLevel(LogLevel? level) {
    if (level == null) {
      state = state.copyWith(clearSelectedLevel: true);
    } else {
      state = state.copyWith(selectedLevel: level);
    }
  }

  void setLinesToFetch(int lines) {
    state = state.copyWith(linesToFetch: lines);
    refreshBoth();
  }

  Future<void> loadSyslog({BuildContext? context}) async {
    final appState = _ref.read(appStateProvider);
    final router = appState.selectedRouter;
    if (router == null) {
      state = state.copyWith(
        isLoadingSyslog: false,
        syslogResult: const LogFetchRpcError(message: 'No router selected'),
      );
      return;
    }

    final api = _apiService;
    if (api == null) {
      state = state.copyWith(
        isLoadingSyslog: false,
        syslogResult: const LogFetchRpcError(
          message: 'API service unavailable',
        ),
      );
      return;
    }

    state = state.copyWith(isLoadingSyslog: true);
    final result = await api.fetchSyslog(
      _ipAddress,
      _sysauth,
      _useHttps,
      lines: state.linesToFetch,
      context: context,
    );
    state = state.copyWith(isLoadingSyslog: false, syslogResult: result);
  }

  Future<void> loadKernelLog({BuildContext? context}) async {
    final appState = _ref.read(appStateProvider);
    final router = appState.selectedRouter;
    if (router == null) {
      state = state.copyWith(
        isLoadingKernel: false,
        kernelResult: const LogFetchRpcError(message: 'No router selected'),
      );
      return;
    }

    final api = _apiService;
    if (api == null) {
      state = state.copyWith(
        isLoadingKernel: false,
        kernelResult: const LogFetchRpcError(
          message: 'API service unavailable',
        ),
      );
      return;
    }

    state = state.copyWith(isLoadingKernel: true);
    final result = await api.fetchKernelLog(
      _ipAddress,
      _sysauth,
      _useHttps,
      lines: state.linesToFetch,
      context: context,
    );
    state = state.copyWith(isLoadingKernel: false, kernelResult: result);
  }

  Future<void> refreshBoth({BuildContext? context}) async {
    await Future.wait([
      loadSyslog(context: context),
      loadKernelLog(context: context),
    ]);
  }
}

final logViewerControllerProvider = StateNotifierProvider.autoDispose
    .family<LogViewerController, LogViewerState, String>(
      (ref, routerId) => LogViewerController(ref, routerId),
    );
