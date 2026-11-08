// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';

abstract class ISshService {
  Future<SshCommandResult> executeCommand({
    required String host,
    required String username,
    required String password,
    required String command,
    int port = 22,
    Duration timeout = const Duration(seconds: 15),
  });
}

class SshCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool success;
  final String? errorMessage;

  const SshCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.success,
    this.errorMessage,
  });

  @override
  String toString() =>
      'SshCommandResult(exitCode: $exitCode, success: $success, stdout: $stdout, stderr: $stderr, error: $errorMessage)';
}

/// Structured SSH transport error classification using dartssh2 exception hierarchy.
/// Avoids string matching on human-readable error messages.
enum SshTransportErrorType {
  authenticationFailed, // SSHAuthFailError: credentials rejected by server
  authenticationAborted, // SSHAuthAbortError: connection dropped during auth
  connectionRefused, // SocketException (connection refused)
  hostUnreachable, // SocketException (no route, network unreachable)
  connectionTimeout, // TimeoutException on socket connect
  commandTimeout, // TimeoutException on command execution
  unknown, // SSHError or any other exception type
}

extension SshTransportErrorTypeX on SshTransportErrorType {
  /// Classify a caught exception from dartssh2 into a transport error type.
  static SshTransportErrorType fromException(Object e) {
    if (e is SSHAuthFailError)
      return SshTransportErrorType.authenticationFailed;
    if (e is SSHAuthAbortError)
      return SshTransportErrorType.authenticationAborted;
    if (e is SocketException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('refused'))
        return SshTransportErrorType.connectionRefused;
      if (msg.contains('no route') ||
          msg.contains('unreachable') ||
          msg.contains('network is down')) {
        return SshTransportErrorType.hostUnreachable;
      }
      return SshTransportErrorType.connectionRefused;
    }
    if (e is TimeoutException) return SshTransportErrorType.connectionTimeout;
    return SshTransportErrorType.unknown;
  }
}
