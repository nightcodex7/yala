// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/services/interfaces/ssh_persistent_session_interface.dart';
import 'package:yet_another_luci_app/services/service_factory.dart';
import '../models/saved_ssh_command.dart';
import '../models/ssh_command_risk.dart';
import '../services/saved_commands_service.dart';

class SshTerminalState {
  final String terminalBuffer;
  final SshSessionStatus sessionStatus;
  final bool isSendingInput;
  final String routerId;
  final List<SavedSshCommand> savedCommands;
  final bool isLoadingSavedCommands;

  const SshTerminalState({
    this.terminalBuffer = '',
    this.sessionStatus = SshSessionStatus.disconnected,
    this.isSendingInput = false,
    required this.routerId,
    this.savedCommands = const [],
    this.isLoadingSavedCommands = false,
  });

  SshTerminalState copyWith({
    String? terminalBuffer,
    SshSessionStatus? sessionStatus,
    bool? isSendingInput,
    String? routerId,
    List<SavedSshCommand> techniqueCommands = const [],
    List<SavedSshCommand>? savedCommands,
    bool? isLoadingSavedCommands,
  }) {
    return SshTerminalState(
      terminalBuffer: terminalBuffer ?? this.terminalBuffer,
      sessionStatus: sessionStatus ?? this.sessionStatus,
      isSendingInput: isSendingInput ?? this.isSendingInput,
      routerId: routerId ?? this.routerId,
      savedCommands: savedCommands ?? this.savedCommands,
      isLoadingSavedCommands:
          isLoadingSavedCommands ?? this.isLoadingSavedCommands,
    );
  }
}

class SshConsoleController extends StateNotifier<SshTerminalState> {
  final Ref _ref;
  final String _routerId;
  final SavedCommandsService _savedCmdSvc;
  final Terminal terminal = Terminal(maxLines: 2000);
  ISshPersistentSession? _session;
  StreamSubscription<String>? _outputSub;

  late final String? _host;
  late final String? _username;
  late final String? _password;

  SshConsoleController(this._ref, this._routerId, this._savedCmdSvc)
    : super(SshTerminalState(routerId: _routerId)) {
    final appState = _ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final isReviewer = appState.reviewerModeEnabled;

    if (isReviewer) {
      _host = '192.168.1.1';
      _username = 'root';
      _password = 'mock_password';
    } else if (router != null && router.id == _routerId) {
      _host = router.ipAddress;
      _username = router.username;
      _password = router.password.isNotEmpty ? router.password : null;
    } else {
      _host = null;
      _username = null;
      _password = null;
    }

    loadSavedCommands();
    connect();
  }

  Future<void> connect() async {
    if (_host == null || _password == null) {
      _appendSystem('\r\n[No SSH credentials stored for this router]\r\n');
      state = state.copyWith(sessionStatus: SshSessionStatus.authFailed);
      return;
    }

    final factory = ServiceContainer.instance.factory;
    _session = factory.createSshPersistentSession();
    state = state.copyWith(sessionStatus: SshSessionStatus.connecting);
    _appendSystem('Connecting to $_host...\r\n');

    final result = await _session!.connect(
      host: _host,
      username: _username ?? 'root',
      password: _password,
    );

    if (result.status == SshSessionStatus.connected) {
      _outputSub = _session!.outputStream.listen((chunk) {
        terminal.write(chunk);
        state = state.copyWith(terminalBuffer: getAllText());
      });
      terminal.onOutput = (data) {
        _session?.sendRaw(data);
      };
      terminal.onResize = (w, h, pw, ph) {
        _session?.resizeTerminal(w, h);
      };
      state = state.copyWith(
        sessionStatus: SshSessionStatus.connected,
        terminalBuffer: getAllText(),
      );
    } else {
      state = state.copyWith(sessionStatus: result.status);
      _appendSystem('\r\n[${result.errorMessage ?? 'Connection failed'}]\r\n');
    }
  }

  String getAllText() {
    try {
      final buffer = StringBuffer();
      final lines = terminal.buffer.lines;
      for (var i = 0; i < lines.length; i++) {
        buffer.writeln(lines[i].toString());
      }
      return buffer.toString().trimRight();
    } catch (_) {
      return '';
    }
  }

  void _appendSystem(String message) {
    terminal.write(message);
    state = state.copyWith(terminalBuffer: getAllText());
  }

  SshCommandRisk classifyCommand(String command) =>
      SshCommandClassifier.classify(command);

  void sendCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;
    if (!state.sessionStatus.isConnected || _session == null) return;
    _session!.sendInput(trimmed);
  }

  void sendCtrlC() {
    _session?.sendCtrlC();
  }

  void sendCtrlZ() {
    _session?.sendCtrlZ();
  }

  void sendArrowUp() => terminal.keyInput(TerminalKey.arrowUp);

  void sendArrowDown() => terminal.keyInput(TerminalKey.arrowDown);

  void sendArrowLeft() => terminal.keyInput(TerminalKey.arrowLeft);

  void sendArrowRight() => terminal.keyInput(TerminalKey.arrowRight);

  void sendNewline() => terminal.keyInput(TerminalKey.enter);

  void sendRaw(String text) {
    if (!state.sessionStatus.isConnected || _session == null) return;
    _session!.sendRaw(text);
  }

  void sendBackspace() => terminal.keyInput(TerminalKey.backspace);

  void sendTab() => terminal.keyInput(TerminalKey.tab);

  void sendEscape() => terminal.keyInput(TerminalKey.escape);

  void resizeTerminal(int width, int height) {
    _session?.resizeTerminal(width, height);
  }

  void clearBuffer() {
    terminal.eraseDisplay();
    terminal.setCursor(0, 0);
    state = state.copyWith(terminalBuffer: '');
  }

  Future<void> reconnect() async {
    await _outputSub?.cancel();
    await _session?.disconnect();
    clearBuffer();
    state = state.copyWith(
      terminalBuffer: '',
      sessionStatus: SshSessionStatus.disconnected,
    );
    await connect();
  }

  Future<void> loadSavedCommands() async {
    state = state.copyWith(isLoadingSavedCommands: true);
    final cmds = await _savedCmdSvc.getAll(_routerId);
    state = state.copyWith(savedCommands: cmds, isLoadingSavedCommands: false);
  }

  Future<SaveResult> saveCommand(String name, String command) async {
    final cmd = SavedSshCommand(
      id: SavedSshCommand.generateId(_routerId),
      routerId: _routerId,
      name: name.trim(),
      command: command.trim(),
      createdAt: DateTime.now(),
    );
    final result = await _savedCmdSvc.save(_routerId, cmd);
    if (result == SaveResult.ok) {
      await loadSavedCommands();
    }
    return result;
  }

  Future<void> deleteSavedCommand(String id) async {
    await _savedCmdSvc.delete(_routerId, id);
    await loadSavedCommands();
  }

  Future<void> runSavedCommand(SavedSshCommand cmd) async {
    sendCommand(cmd.command);
    await _savedCmdSvc.updateLastRun(_routerId, cmd.id);
    await loadSavedCommands();
  }

  Future<int> importCommands(String jsonContent) async {
    final count = await _savedCmdSvc.importFromJson(_routerId, jsonContent);
    if (count > 0) {
      await loadSavedCommands();
    }
    return count;
  }

  @override
  void dispose() {
    _outputSub?.cancel();
    _session?.disconnect();
    super.dispose();
  }
}

extension SshSessionStatusX on SshSessionStatus {
  bool get isConnected => this == SshSessionStatus.connected;
}

final sshConsoleControllerProvider = StateNotifierProvider.autoDispose
    .family<SshConsoleController, SshTerminalState, String>((ref, routerId) {
      final savedCmdSvc = ref.read(savedCommandsServiceProvider);
      return SshConsoleController(ref, routerId, savedCmdSvc);
    });
