// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

enum RpcCallStatus {
  success,
  methodNotFound,
  permissionDenied, // ACL error
  failed,
  networkError,
}

/// Generic wrapper for RPC responses with detailed status information.
class RpcResult<T> {
  final RpcCallStatus status;
  final T? data;
  final String? errorMessage;
  final int? errorCode;

  const RpcResult({
    required this.status,
    this.data,
    this.errorMessage,
    this.errorCode,
  });

  bool get isSuccess => status == RpcCallStatus.success && data != null;
  bool get isMethodNotFound => status == RpcCallStatus.methodNotFound;
  bool get isPermissionDenied => status == RpcCallStatus.permissionDenied;

  /// Returns true if the RPC error indicates insufficient filesystem / disk storage space.
  bool get isInsufficientStorage {
    if (errorMessage == null) return false;
    final lower = errorMessage!.toLowerCase();
    return lower.contains('no space left on device') ||
        lower.contains('disk full') ||
        lower.contains('insufficient space') ||
        lower.contains('not enough disk space') ||
        lower.contains('not enough space') ||
        lower.contains('needs more disk space') ||
        (lower.contains('available on filesystem') && lower.contains('needs'));
  }

  /// Returns true if the RPC error indicates out-of-memory or process termination by the OOM killer.
  bool get isMemoryExhausted {
    if (errorCode == 137) return true;
    if (errorMessage == null) return false;
    final lower = errorMessage!.toLowerCase().trim();
    return lower == 'killed' ||
        lower.contains('out of memory') ||
        lower.contains('cannot allocate memory') ||
        lower.contains('memory exhausted') ||
        lower.contains('oom killer') ||
        lower.contains('oom-killer');
  }

  /// Extracts a clean, concise, human-readable error reason for any failed action (service toggle,
  /// SSID change, client ban, backup restore, etc.).
  ///
  /// Returns a safe, user-facing subtitle string suitable for passing directly to
  /// `showToastError(..., subtitle: result.userFriendlyActionError)`.
  String get userFriendlyActionError {
    switch (status) {
      case RpcCallStatus.permissionDenied:
        return 'Permission denied. Check router ACL/rpcd configuration.';
      case RpcCallStatus.methodNotFound:
        // Distinguish binary-not-found (exit 127) from RPC method not found
        if (errorCode == 127) {
          return 'Required binary not found on router (command not found).';
        }
        return 'RPC method or service not available on this router.';
      case RpcCallStatus.networkError:
        return 'Router unreachable. Check your network connection.';
      case RpcCallStatus.failed:
        if (isInsufficientStorage)
          return 'Router storage is full (no space left on device).';
        if (isMemoryExhausted)
          return 'Router ran out of memory during operation.';
        // Check errorCode for known ubus codes
        if (errorCode == 7) return 'Request timed out. Router may be busy.';
        if (errorCode == 6)
          return 'Permission denied. Check router ACL/rpcd configuration.';
        if (errorCode == 126)
          return 'Permission denied executing command on router.';
        // Extract the most useful line from raw errorMessage
        if (errorMessage != null && errorMessage!.trim().isNotEmpty) {
          final lines = errorMessage!
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
          for (final line in lines.reversed) {
            final lower = line.toLowerCase();
            if (lower.startsWith('error:') ||
                lower.startsWith('fatal:') ||
                lower.contains('failed') ||
                lower.contains('permission denied') ||
                lower.contains('access denied')) {
              return line.replaceFirst(
                RegExp(r'^(ERROR|FATAL|error|fatal):\s*'),
                '',
              );
            }
          }
          // Return last non-empty line as a best-effort summary
          if (lines.isNotEmpty && lines.last.length <= 150) return lines.last;
        }
        return 'Operation failed. Please try again.';
      case RpcCallStatus.success:
        return '';
    }
  }

  /// Extracts a clean, concise, human-readable error summary from package manager output.
  String get userFriendlyPackageError {
    if (errorMessage == null || errorMessage!.trim().isEmpty) {
      return 'Operation failed';
    }
    final raw = errorMessage!.trim();
    if (isInsufficientStorage) {
      return 'Insufficient storage space on router (No space left on device).';
    }
    if (isMemoryExhausted) {
      return 'Router ran out of memory (OOM) during package dependency resolution.';
    }
    // Clean up multiline stderr or raw error codes to get the most relevant line
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    for (final line in lines.reversed) {
      final lower = line.toLowerCase();
      if (lower.startsWith('error:') ||
          lower.startsWith('fatal:') ||
          lower.contains('failed')) {
        return line.replaceFirst(RegExp(r'^(ERROR|error):\s*'), '');
      }
    }
    return lines.last;
  }

  factory RpcResult.success(T data) {
    return RpcResult(status: RpcCallStatus.success, data: data);
  }

  factory RpcResult.methodNotFound(String message) {
    return RpcResult(
      status: RpcCallStatus.methodNotFound,
      errorMessage: message,
      errorCode: -32601, // Standard JSON-RPC Method Not Found
    );
  }

  factory RpcResult.permissionDenied(String message) {
    return RpcResult(
      status: RpcCallStatus.permissionDenied,
      errorMessage: message,
      errorCode: 403, // Access Denied / ACL restriction
    );
  }

  factory RpcResult.networkError(String message) {
    return RpcResult(
      status: RpcCallStatus.networkError,
      errorMessage: message,
      errorCode: 503,
    );
  }

  factory RpcResult.failed(String message, {int? code}) {
    return RpcResult(
      status: RpcCallStatus.failed,
      errorMessage: message,
      errorCode: code,
    );
  }

  /// Evaluates standard ubus response arrays `[0, data]` or `[errCode, msg]`.
  static RpcResult<T> fromUbusResponse<T>(
    dynamic rawResponse,
    T Function(dynamic data) parseData,
  ) {
    if (rawResponse == null) {
      return RpcResult.methodNotFound('RPC response was null');
    }
    if (rawResponse is List && rawResponse.isNotEmpty) {
      final code = rawResponse[0];
      if (code is int && code != 0) {
        final msg = rawResponse.length > 1
            ? rawResponse[1].toString()
            : 'ubus status code $code';
        if (code == 6 || msg.toLowerCase().contains('permission denied')) {
          return RpcResult.permissionDenied('Permission denied ($msg)');
        }
        if (code == 2 || code == 3 || msg.toLowerCase().contains('not found')) {
          return RpcResult.methodNotFound('Method not found ($msg)');
        }
        if (code == 7 ||
            msg.toLowerCase().contains('timed out') ||
            msg.toLowerCase().contains('timeout')) {
          return RpcResult.failed(
            'Operation timed out on router (ubus error 7)',
            code: code,
          );
        }
        return RpcResult.failed('ubus error: $msg', code: code);
      }
      if (rawResponse.length > 1) {
        final parsed = parseData(rawResponse[1]);
        return RpcResult.success(parsed);
      }
    } else if (rawResponse is Map) {
      final parsed = parseData(rawResponse);
      return RpcResult.success(parsed);
    }
    return RpcResult.failed('Invalid RPC payload format');
  }

  /// Classifies a 2-level result from a `file.exec` RPC call.
  /// Evaluates both the ubus RPC transport status and the underlying shell command's exit code + stderr.
  static RpcResult<T> classifyExecResult<T>(
    dynamic rawRpcResponse,
    T Function(dynamic data) parseData,
  ) {
    if (rawRpcResponse == null) {
      return RpcResult.methodNotFound(
        'RPC method or command execution unavailable',
      );
    }

    // 1. Transport Level: Check standard ubus response code array [err_code, data_or_msg]
    if (rawRpcResponse is List && rawRpcResponse.isNotEmpty) {
      final code = rawRpcResponse[0];
      if (code is int && code != 0) {
        final msg = rawRpcResponse.length > 1
            ? rawRpcResponse[1].toString()
            : 'ubus status code $code';
        if (code == 6 || msg.toLowerCase().contains('permission denied')) {
          return RpcResult.permissionDenied(
            'RPC transport permission denied ($msg)',
          );
        }
        if (code == 2 || code == 3 || msg.toLowerCase().contains('not found')) {
          return RpcResult.methodNotFound(
            'RPC object or method not found ($msg)',
          );
        }
        if (code == 7 ||
            msg.toLowerCase().contains('timed out') ||
            msg.toLowerCase().contains('timeout')) {
          return RpcResult.failed(
            'Command timed out on router (ubus error 7)',
            code: code,
          );
        }
        return RpcResult.failed('RPC transport error: $msg', code: code);
      }
    }

    // 2. Command Level: Evaluate shell execution output (exit code + stderr)
    dynamic execData;
    if (rawRpcResponse is List &&
        rawRpcResponse.length > 1 &&
        rawRpcResponse[0] == 0) {
      execData = rawRpcResponse[1];
    } else if (rawRpcResponse is Map) {
      execData = rawRpcResponse;
    } else {
      return RpcResult.failed('Invalid RPC payload format');
    }

    if (execData is Map) {
      final code = execData['code'] is int ? execData['code'] as int : 0;
      final stdout = execData['stdout']?.toString() ?? '';
      final stderr = execData['stderr']?.toString() ?? '';
      final combined = '$stdout $stderr'.trim().toLowerCase();

      // Command level exit-code / stderr classification
      if (code == 127 || combined.contains('command not found')) {
        return RpcResult.methodNotFound(
          'Package manager binary not found on router (exit code 127)',
        );
      }
      if (code == 126 ||
          combined.contains('permission denied') ||
          combined.contains('access denied')) {
        return RpcResult.permissionDenied(
          'Permission denied executing command on router (exit code 126)',
        );
      }

      // Check if parseData can extract valid non-empty output from stdout (e.g. apk info returning exit code 1 due to repo cache warnings)
      final parsed = parseData(execData);
      final isValidParsed =
          parsed != null &&
          (parsed is! String || parsed.trim().isNotEmpty) &&
          (parsed is! List || parsed.isNotEmpty) &&
          (parsed is! Map || parsed.isNotEmpty);

      if (isValidParsed) {
        return RpcResult.success(parsed);
      }

      if (code != 0) {
        final errorDetail = stderr.trim().isNotEmpty
            ? stderr.trim()
            : (stdout.trim().isNotEmpty
                  ? stdout.trim()
                  : 'Command exited with code $code');
        return RpcResult.failed(errorDetail, code: code);
      }

      return RpcResult.failed(
        'Command succeeded but returned no usable package output',
      );
    }

    return RpcResult.failed('Unexpected payload format from exec RPC');
  }
}
