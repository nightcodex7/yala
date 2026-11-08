// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'log_entry.dart';

sealed class LogFetchResult {
  const LogFetchResult();
}

class LogFetchSuccess extends LogFetchResult {
  final List<LogEntry> entries;
  const LogFetchSuccess(this.entries);
}

class LogFetchPermissionError extends LogFetchResult {
  const LogFetchPermissionError();
}

class LogFetchBinaryMissing extends LogFetchResult {
  const LogFetchBinaryMissing();
}

class LogFetchRpcError extends LogFetchResult {
  final String? message;
  const LogFetchRpcError({this.message});
}

class LogFetchTimeout extends LogFetchResult {
  const LogFetchTimeout();
}
