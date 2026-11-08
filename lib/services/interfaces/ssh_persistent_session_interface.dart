// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'ssh_service_interface.dart';

enum SshSessionStatus {
  disconnected,
  connecting,
  connected,
  authFailed,
  connectionFailed,
}

/// Represents the result of a connect() attempt.
class SshConnectResult {
  final SshSessionStatus status;
  final SshTransportErrorType? errorType; // null if connected successfully
  final String? errorMessage; // human-readable, no passwords

  const SshConnectResult({
    required this.status,
    this.errorType,
    this.errorMessage,
  });
}

/// Persistent SSH shell session with PTY support.
/// Uses dartssh2 client.shell() — shell state persists across input sends.
/// Each instance manages one SSHClient + one shell SSHSession.
abstract class ISshPersistentSession {
  /// Broadcast stream of raw terminal output chunks (ANSI-stripped, UTF-8).
  Stream<String> get outputStream;

  /// Current session status.
  SshSessionStatus get status;

  /// Connects to the router and starts an interactive shell.
  /// PTY config: xterm-256color, 80x24 (resizable via resizeTerminal).
  Future<SshConnectResult> connect({
    required String host,
    required String username,
    required String password,
    int port = 22,
    Duration connectTimeout = const Duration(seconds: 15),
  });

  /// Sends input text to the shell stdin (appends '\n').
  /// No-op if not connected.
  void sendInput(String input);

  /// Sends raw bytes to stdin. Used for control sequences.
  void sendBytes(List<int> bytes);

  /// Sends Ctrl+C (SIGINT = 0x03) to interrupt the current foreground process.
  void sendCtrlC() => sendBytes([3]);

  /// Sends Ctrl+Z (SIGTSTP = 0x1A) to suspend the current foreground process.
  void sendCtrlZ() => sendBytes([0x1A]);

  /// Sends arrow keys (ANSI escape sequences):
  /// Up: \x1b[A, Down: \x1b[B, Right: \x1b[C, Left: \x1b[D
  void sendArrowUp() => sendBytes([0x1B, 0x5B, 0x41]);
  void sendArrowDown() => sendBytes([0x1B, 0x5B, 0x42]);
  void sendArrowRight() => sendBytes([0x1B, 0x5B, 0x43]);
  void sendArrowLeft() => sendBytes([0x1B, 0x5B, 0x44]);

  /// Sends a newline (\r) to stdin (equivalent to pressing Enter in a terminal).
  void sendNewline() => sendBytes([0x0D]);

  /// Sends raw string to stdin (UTF-8 encoded, without appending newline).
  void sendRaw(String text);

  /// Sends Backspace (ASCII 0x7F / DEL).
  void sendBackspace() => sendBytes([0x7F]);

  /// Sends Tab (ASCII 0x09).
  void sendTab() => sendBytes([0x09]);

  /// Sends Escape (ASCII 0x1B).
  void sendEscape() => sendBytes([0x1B]);

  /// Informs the remote PTY of a terminal resize.
  void resizeTerminal(int width, int height);

  /// Disconnects and cleans up all resources.
  Future<void> disconnect();

  bool get isConnected;
}
