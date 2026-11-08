// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'interfaces/ssh_persistent_session_interface.dart';
import 'interfaces/ssh_service_interface.dart';
import '../utils/logger.dart';

class RealSshPersistentSession implements ISshPersistentSession {
  SSHClient? _client;
  SSHSession? _shell;
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;

  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  SshSessionStatus _status = SshSessionStatus.disconnected;

  @override
  Stream<String> get outputStream => _outputController.stream;

  @override
  SshSessionStatus get status => _status;

  @override
  bool get isConnected => _status == SshSessionStatus.connected;

  @override
  Future<SshConnectResult> connect({
    required String host,
    required String username,
    required String password,
    int port = 22,
    Duration connectTimeout = const Duration(seconds: 15),
  }) async {
    await disconnect();

    _status = SshSessionStatus.connecting;
    try {
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: connectTimeout,
      );

      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
        // Security note: host keys not verified (LAN-only tool — established project posture).
        // Passwords are never logged.
      );

      await _client!.authenticated.timeout(connectTimeout);

      _shell = await _client!.shell(
        pty: const SSHPtyConfig(type: 'xterm-256color', width: 80, height: 24),
      );

      // Subscribe to stdout
      _stdoutSub = _shell!.stdout.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          if (text.isNotEmpty) _outputController.add(text);
        },
        onDone: _onShellDone,
        onError: (e) => Logger.warning('SSH shell stdout error: $e'),
      );

      // Subscribe to stderr
      _stderrSub = _shell!.stderr.listen((data) {
        final text = utf8.decode(data, allowMalformed: true);
        if (text.isNotEmpty) _outputController.add(text);
      }, onError: (e) => Logger.warning('SSH shell stderr error: $e'));

      _status = SshSessionStatus.connected;
      return const SshConnectResult(status: SshSessionStatus.connected);
    } on SSHAuthFailError catch (e) {
      _status = SshSessionStatus.authFailed;
      Logger.warning('SSH auth failed for $username@$host: $e');
      return const SshConnectResult(
        status: SshSessionStatus.authFailed,
        errorType: SshTransportErrorType.authenticationFailed,
        errorMessage: 'Authentication failed — check router password',
      );
    } on SSHAuthAbortError catch (e) {
      _status = SshSessionStatus.connectionFailed;
      Logger.warning('SSH auth aborted for $username@$host: $e');
      return const SshConnectResult(
        status: SshSessionStatus.connectionFailed,
        errorType: SshTransportErrorType.authenticationAborted,
        errorMessage:
            'Authentication aborted — connection dropped during handshake',
      );
    } on SocketException catch (e) {
      _status = SshSessionStatus.connectionFailed;
      final errorType = SshTransportErrorTypeX.fromException(e);
      Logger.warning('SSH socket error for $host:$port: $e');
      return SshConnectResult(
        status: SshSessionStatus.connectionFailed,
        errorType: errorType,
        errorMessage: 'Connection failed — router unreachable',
      );
    } on TimeoutException catch (_) {
      _status = SshSessionStatus.connectionFailed;
      Logger.warning('SSH connect timeout for $host:$port');
      return const SshConnectResult(
        status: SshSessionStatus.connectionFailed,
        errorType: SshTransportErrorType.connectionTimeout,
        errorMessage: 'Connection timed out',
      );
    } catch (e, stack) {
      _status = SshSessionStatus.connectionFailed;
      Logger.exception('SSH persistent session connect failed', e, stack);
      return SshConnectResult(
        status: SshSessionStatus.connectionFailed,
        errorType: SshTransportErrorType.unknown,
        errorMessage: 'SSH error: ${e.runtimeType}',
      );
    }
  }

  void _onShellDone() {
    _status = SshSessionStatus.disconnected;
    _outputController.add('\r\n[Session ended]\r\n');
    Logger.info('SSH persistent shell session ended');
  }

  @override
  void sendInput(String input) {
    if (!isConnected || _shell == null) return;
    final bytes = utf8.encode('$input\r');
    _shell!.write(Uint8List.fromList(bytes));
  }

  @override
  void sendBytes(List<int> bytes) {
    if (!isConnected || _shell == null) return;
    _shell!.write(Uint8List.fromList(bytes));
  }

  @override
  void sendCtrlC() => sendBytes([3]);

  @override
  void sendCtrlZ() => sendBytes([0x1A]);

  @override
  void sendArrowUp() => sendBytes([0x1B, 0x5B, 0x41]);

  @override
  void sendArrowDown() => sendBytes([0x1B, 0x5B, 0x42]);

  @override
  void sendArrowRight() => sendBytes([0x1B, 0x5B, 0x43]);

  @override
  void sendArrowLeft() => sendBytes([0x1B, 0x5B, 0x44]);

  @override
  void sendNewline() => sendBytes([0x0D]);

  @override
  void sendRaw(String text) {
    if (!isConnected || _shell == null) return;
    _shell!.write(Uint8List.fromList(utf8.encode(text)));
  }

  @override
  void sendBackspace() => sendBytes([0x7F]);

  @override
  void sendTab() => sendBytes([0x09]);

  @override
  void sendEscape() => sendBytes([0x1B]);

  @override
  void resizeTerminal(int width, int height) {
    if (!isConnected || _shell == null) return;
    _shell!.resizeTerminal(width, height);
  }

  @override
  Future<void> disconnect() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    try {
      _shell?.close();
    } catch (_) {}
    try {
      await _client?.close();
    } catch (_) {}
    _shell = null;
    _client = null;
    _status = SshSessionStatus.disconnected;
  }

  /// Comprehensive ANSI/control character sanitizer.
  static String sanitizeOutput(String raw) {
    var s = raw;
    // Remove OSC sequences: ESC ] ... (ST=ESC\\ or BEL=0x07)
    s = s.replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)'), '');
    // Remove CSI sequences: ESC [ params final-byte.
    // Built via adjacent string literals to safely include a single-quote.
    s = s.replaceAll(
      RegExp(
        r'\x1B\[[0-9;:<=>?]*'
        r'[ !"#'
        "'"
        r'$%&()*+,\-./]*[@-~]',
      ),
      '',
    );
    // Remove remaining ESC + one char (other escape sequences)
    s = s.replaceAll(RegExp(r'\x1B[@-_]'), '');
    // Remove C0 control characters EXCEPT: 0x09=TAB, 0x0A=LF, 0x0D=CR
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    // Remove C1 control characters (0x80–9F)
    s = s.replaceAll(RegExp(r'[\x80-\x9F]'), '');
    // Normalize CRLF to LF
    s = s.replaceAll('\r\n', '\n');
    // Remove standalone CR (not followed by LF)
    s = s.replaceAll(RegExp(r'\r(?!\n)'), '');
    return s;
  }
}
