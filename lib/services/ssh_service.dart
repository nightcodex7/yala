// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import '../utils/logger.dart';
import 'interfaces/ssh_service_interface.dart';

// Security note:
// 1. Host-key verification: Currently accepts all host keys (LAN-only tool,
//    established project posture — same as account_access_inspector). Do not change.
// 2. Password safety: Logger.exception logs '$username@$host:$port' — never logs the password.
// 3. Error handling: SSHAuthFailError / SSHAuthAbortError are caught in general catch(e);
//    in ISshPersistentSession they are typed and classified.
// 4. Per-command sessions: RealSshService remains dedicated to single-command execution
//    for non-console SSH operations. Persistent PTY sessions use ISshPersistentSession.
class RealSshService implements ISshService {
  @override
  Future<SshCommandResult> executeCommand({
    required String host,
    required String username,
    required String password,
    required String command,
    int port = 22,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(host, port, timeout: timeout);

      client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );

      await client.authenticated.timeout(timeout);

      final session = await client.execute(command);

      final stdoutFuture = utf8.decodeStream(session.stdout);
      final stderrFuture = utf8.decodeStream(session.stderr);

      await session.done.timeout(timeout);
      final stdout = await stdoutFuture.timeout(timeout);
      final stderr = await stderrFuture.timeout(timeout);
      final exitCode = session.exitCode ?? 0;

      return SshCommandResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        success: exitCode == 0,
      );
    } catch (e, stack) {
      Logger.exception(
        'SSH command execution failed for $username@$host:$port',
        e,
        stack,
      );
      return SshCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: '',
        success: false,
        errorMessage: e.toString(),
      );
    } finally {
      try {
        await client?.close();
      } catch (_) {}
    }
  }
}
