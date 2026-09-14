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
