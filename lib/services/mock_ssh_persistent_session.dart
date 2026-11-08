// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'interfaces/ssh_persistent_session_interface.dart';

class MockSshPersistentSession implements ISshPersistentSession {
  final StreamController<String> _ctrl = StreamController<String>.broadcast();
  SshSessionStatus _status = SshSessionStatus.disconnected;

  @override
  Stream<String> get outputStream => _ctrl.stream;

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
    _status = SshSessionStatus.connected;
    _ctrl.add('[Mock SSH session — Reviewer Mode]\r\n');
    _ctrl.add(
      'BusyBox v1.36.1 (2023-11-01 12:00:00 UTC) built-in shell (ash)\r\n',
    );
    _ctrl.add('root@OpenWrt:~# ');
    return const SshConnectResult(status: SshSessionStatus.connected);
  }

  @override
  void sendInput(String input) {
    if (!isConnected) return;
    _ctrl.add('$input\r\n');
    final trimmed = input.trim();
    if (trimmed == 'uptime') {
      _ctrl.add(
        ' 12:34:56 up 3 days,  2:15,  load average: 0.01, 0.05, 0.02\r\n',
      );
    } else if (trimmed == 'uname -a') {
      _ctrl.add(
        'Linux OpenWrt 6.1.64 #0 SMP Wed Nov 1 12:00:00 2023 aarch64 GNU/Linux\r\n',
      );
    } else {
      _ctrl.add('(mock output for: $input)\r\n');
    }
    _ctrl.add('root@OpenWrt:~# ');
  }

  @override
  void sendBytes(List<int> bytes) {
    if (!isConnected) return;
    if (bytes.length == 1 && bytes[0] == 3) {
      _ctrl.add('^C\r\nroot@OpenWrt:~# ');
    }
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
    if (!isConnected) return;
    _ctrl.add(text);
  }

  @override
  void sendBackspace() {
    if (!isConnected) return;
    _ctrl.add('\b \b');
  }

  @override
  void sendTab() => sendBytes([0x09]);

  @override
  void sendEscape() => sendBytes([0x1B]);

  @override
  void resizeTerminal(int width, int height) {}

  @override
  Future<void> disconnect() async {
    _status = SshSessionStatus.disconnected;
  }
}
