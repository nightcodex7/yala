// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/services/interfaces/ssh_persistent_session_interface.dart';
import 'package:yet_another_luci_app/utils/logger.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../controllers/ssh_console_controller.dart';
import '../models/saved_ssh_command.dart';
import '../models/ssh_command_risk.dart';
import '../services/saved_commands_service.dart';
import '../widgets/save_command_dialog.dart';
import '../widgets/saved_commands_sheet.dart';

class SshConsoleScreen extends ConsumerStatefulWidget {
  const SshConsoleScreen({super.key});

  @override
  ConsumerState<SshConsoleScreen> createState() => _SshConsoleScreenState();
}

class _SshConsoleScreenState extends ConsumerState<SshConsoleScreen> {
  final FocusNode _terminalFocusNode = FocusNode();
  final TerminalController _terminalController = TerminalController();
  bool _noteDismissed = false;

  @override
  void initState() {
    super.initState();
    _terminalFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _terminalFocusNode.removeListener(_onFocusChange);
    _terminalFocusNode.dispose();
    _terminalController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _copyAll(String text) {
    Clipboard.setData(ClipboardData(text: text));
    final l10n = AppLocalizations.of(context);
    LuciToastManager.showSuccess(
      context,
      l10n?.sshTerminalAllCopied ?? 'Terminal output copied to clipboard',
    );
  }

  Future<void> _clearBuffer(SshConsoleController controller) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n?.sshTerminalClearConfirm ?? 'Clear terminal output?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n?.actionDelete ?? 'Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      controller.clearBuffer();
    }
  }

  Widget _buildKeycapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required ThemeData theme,
  }) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled
              ? () {
                  unawaited(HapticFeedback.selectionClick());
                  onPressed();
                }
              : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: enabled ? 0.9 : 0.4,
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(
                  alpha: enabled ? 0.6 : 0.25,
                ),
                width: 0.8,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: enabled
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextKeycapButton({
    required String label,
    required String tooltip,
    required VoidCallback? onPressed,
    required ThemeData theme,
  }) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled
              ? () {
                  unawaited(HapticFeedback.selectionClick());
                  onPressed();
                }
              : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: enabled ? 0.9 : 0.4,
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(
                  alpha: enabled ? 0.6 : 0.25,
                ),
                width: 0.8,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: enabled
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSaveDialog(
    String initialCommand,
    SshConsoleController controller,
    AppLocalizations? l10n,
  ) async {
    final res = await SaveCommandDialog.show(
      context,
      initialCommand: initialCommand,
    );
    if (res != null && mounted) {
      final saveResult = await controller.saveCommand(
        res['name']!,
        res['command']!,
      );
      if (!mounted) return;
      if (saveResult == SaveResult.ok) {
        LuciToastManager.showSuccess(
          context,
          l10n?.sshCommandSaved ?? 'Command saved',
        );
      } else if (saveResult == SaveResult.limitReached) {
        LuciToastManager.showError(
          context,
          l10n?.sshTerminalMaxCommandsReached ??
              'Maximum of 50 saved commands reached. Delete one to save another.',
        );
      } else {
        LuciToastManager.showError(context, 'Failed to save command');
      }
    }
  }

  void _showSavedCommandsSheet(
    List<SavedSshCommand> commands,
    SshConsoleController controller,
    AppLocalizations? l10n,
  ) {
    SavedCommandsSheet.show(
      context,
      commands: commands,
      onRun: (cmd) async {
        final risk = controller.classifyCommand(cmd.command);
        if (risk == SshCommandRisk.destructive) {
          final confirmed = await LuciGuardrail.confirmCriticalOperation(
            context,
            title:
                l10n?.sshTerminalRiskDestructiveTitle ??
                'Potentially Destructive Command',
            description:
                l10n?.sshTerminalRiskDestructiveBody ??
                'This command may cause service interruption or data loss. Proceed only if you understand the consequences.',
            requireAcknowledgement: true,
            isDestructive: true,
          );
          if (!confirmed || !mounted) return;
        } else if (risk == SshCommandRisk.elevated) {
          LuciToastManager.showWarning(
            context,
            l10n?.sshTerminalRiskElevatedBody ??
                'This command modifies router configuration. Review carefully before sending.',
          );
        }

        controller.sendCommand(cmd.command);
      },
      onDelete: (cmd) async {
        await controller.deleteSavedCommand(cmd.id);
        if (mounted) {
          LuciToastManager.showSuccess(
            context,
            l10n?.sshCommandDeleted ?? 'Command deleted',
          );
        }
      },
      onAdd: () => _showSaveDialog('', controller, l10n),
      onImport: () => _importSavedCommands(controller, l10n),
    );
  }

  Future<void> _importSavedCommands(
    SshConsoleController controller,
    AppLocalizations? l10n,
  ) async {
    try {
      PlatformFile? pickedFile;
      bool pickerAttempted = false;
      try {
        pickedFile = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        pickerAttempted = true;
      } catch (e, stack) {
        Logger.exception('FilePicker custom extension failed', e, stack);
      }

      if (!pickerAttempted) {
        try {
          pickedFile = await FilePicker.pickFile(type: FileType.any);
        } catch (e, stack) {
          Logger.exception('FilePicker any fallback failed', e, stack);
          return;
        }
      }

      if (pickedFile == null) return;

      String? content;
      try {
        final bytes = await pickedFile.readAsBytes();
        if (bytes.isNotEmpty) {
          content = utf8.decode(bytes);
        }
      } catch (_) {
        if (pickedFile.path != null) {
          try {
            content = await File(pickedFile.path!).readAsString();
          } catch (e, stack) {
            Logger.exception('Reading file from path failed', e, stack);
          }
        }
      }

      if (content == null || content.trim().isEmpty) {
        if (mounted) {
          LuciToastManager.showError(
            context,
            l10n?.sshImportCommandsEmpty ?? 'The selected file is empty.',
          );
        }
        return;
      }

      final count = await controller.importCommands(content);
      if (!mounted) return;

      if (count > 0) {
        LuciToastManager.showSuccess(
          context,
          l10n?.sshImportCommandsSuccess(count) ??
              'Successfully imported $count command(s)',
        );
      } else {
        LuciToastManager.showWarning(
          context,
          l10n?.sshImportCommandsNoValid ??
              'No valid SSH commands found in JSON.',
        );
      }
    } catch (e) {
      if (mounted) {
        LuciToastManager.showError(context, 'Import failed: $e');
      }
    }
  }

  String _statusLabel(SshSessionStatus status, AppLocalizations? l10n) {
    switch (status) {
      case SshSessionStatus.connected:
        return l10n?.sshTerminalConnected ?? 'Connected';
      case SshSessionStatus.connecting:
        return 'Connecting...';
      case SshSessionStatus.authFailed:
        return l10n?.sshTerminalAuthFailed ?? 'Auth Failed';
      case SshSessionStatus.connectionFailed:
        return l10n?.sshTerminalConnectionFailed ?? 'Connection Failed';
      case SshSessionStatus.disconnected:
        return l10n?.sshTerminalDisconnected ?? 'Disconnected';
    }
  }

  Color _statusColor(SshSessionStatus status) {
    switch (status) {
      case SshSessionStatus.connected:
        return Colors.green;
      case SshSessionStatus.connecting:
        return Colors.amber;
      case SshSessionStatus.authFailed:
      case SshSessionStatus.connectionFailed:
        return Colors.red;
      case SshSessionStatus.disconnected:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appStateProvider.select((s) => s.selectedRouter));
    final routerId = router?.id ?? '';
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final state = ref.watch(sshConsoleControllerProvider(routerId));
    final controller = ref.read(
      sshConsoleControllerProvider(routerId).notifier,
    );

    final statusColor = _statusColor(state.sessionStatus);
    final statusLabel = _statusLabel(state.sessionStatus, l10n);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n?.sshTerminalTitle ?? 'SSH Terminal'),
            Text(
              '${router?.displayName ?? 'Router'} • $statusLabel',
              style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
            ),
          ],
        ),
        actions: [
          Badge(
            isLabelVisible: state.savedCommands.isNotEmpty,
            label: Text('${state.savedCommands.length}'),
            child: IconButton(
              icon: const Icon(Icons.bookmarks_outlined),
              tooltip: l10n?.sshTerminalSavedCommands ?? 'Saved Commands',
              onPressed: () => _showSavedCommandsSheet(
                state.savedCommands,
                controller,
                l10n,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: l10n?.sshTerminalCopyAll ?? 'Copy All',
            onPressed: () => _copyAll(controller.getAllText()),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n?.sshTerminalClear ?? 'Clear Terminal',
            onPressed: () => _clearBuffer(controller),
          ),
        ],
      ),
      body: Column(
        children: [
          // Dismissible session note banner
          if (!_noteDismissed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n?.sshTerminalSessionNote ??
                          'Shell state persists within this session (cd, exports work). Closing the screen ends the session.',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _noteDismissed = true),
                  ),
                ],
              ),
            ),

          // Interactive VT100 / xterm Terminal View
          Expanded(
            child: Container(
              color: theme.colorScheme.surface,
              width: double.infinity,
              height: double.infinity,
              child: TerminalView(
                controller.terminal,
                controller: _terminalController,
                focusNode: _terminalFocusNode,
                autofocus: true,
                autoResize: true,
                deleteDetection: true,
                cursorType: TerminalCursorType.block,
                keyboardType: TextInputType.emailAddress,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                theme: TerminalTheme(
                  cursor: theme.colorScheme.primary,
                  selection: theme.colorScheme.primary.withValues(alpha: 0.35),
                  foreground: theme.colorScheme.onSurface,
                  background: theme.colorScheme.surface,
                  black: const Color(0XFF1E1E1E),
                  red: const Color(0XFFCD3131),
                  green: const Color(0XFF0DBC79),
                  yellow: const Color(0XFFE5E510),
                  blue: const Color(0XFF2472C8),
                  magenta: const Color(0XFFBC3FBC),
                  cyan: const Color(0XFF11A8CD),
                  white: const Color(0XFFE5E5E5),
                  brightBlack: const Color(0XFF666666),
                  brightRed: const Color(0XFFF14C4C),
                  brightGreen: const Color(0XFF23D18B),
                  brightYellow: const Color(0XFFF5F543),
                  brightBlue: const Color(0XFF3B8EEA),
                  brightMagenta: const Color(0XFFD670D6),
                  brightCyan: const Color(0XFF29B8DB),
                  brightWhite: const Color(0XFFFFFFFF),
                  searchHitBackground: const Color(0XFFFFFF2B),
                  searchHitBackgroundCurrent: const Color(0XFF31FF26),
                  searchHitForeground: const Color(0XFF000000),
                ),
              ),
            ),
          ),

          // Bottom Accessory Bar (ESC, TAB, Ctrl+C, arrow keys, keyboard toggle)
          // Located at the bottom of the screen; rises above the software keyboard when opened
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: theme.colorScheme.surfaceContainerLow,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // ESC key
                    _buildTextKeycapButton(
                      label: 'ESC',
                      tooltip: 'Escape (ESC)',
                      onPressed: state.sessionStatus.isConnected
                          ? () => controller.sendEscape()
                          : null,
                      theme: theme,
                    ),
                    const SizedBox(width: 4),
                    // TAB key
                    _buildTextKeycapButton(
                      label: 'TAB',
                      tooltip: 'Tab (Auto-complete)',
                      onPressed: state.sessionStatus.isConnected
                          ? () => controller.sendTab()
                          : null,
                      theme: theme,
                    ),
                    const SizedBox(width: 6),
                    // Prominent Ctrl+C button
                    Tooltip(
                      message:
                          l10n?.sshTerminalCtrlCTooltip ??
                          'Send interrupt signal (Ctrl+C) to current process',
                      child: OutlinedButton.icon(
                        icon: Icon(
                          Icons.stop_circle_outlined,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                        label: Text(
                          l10n?.sshTerminalCtrlC ?? 'Ctrl+C',
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: state.sessionStatus.isConnected
                            ? () {
                                unawaited(HapticFeedback.lightImpact());
                                controller.sendCtrlC();
                              }
                            : null,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: theme.colorScheme.error.withValues(
                              alpha: state.sessionStatus.isConnected
                                  ? 1.0
                                  : 0.3,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Keyboard Arrow Controls
                    _buildKeycapButton(
                      icon: Icons.keyboard_arrow_left_rounded,
                      tooltip: l10n?.sshTerminalArrowLeft ?? 'Left (←)',
                      onPressed: state.sessionStatus.isConnected
                          ? () => controller.sendArrowLeft()
                          : null,
                      theme: theme,
                    ),
                    const SizedBox(width: 4),
                    _buildKeycapButton(
                      icon: Icons.keyboard_arrow_up_rounded,
                      tooltip: l10n?.sshTerminalArrowUp ?? 'Up (↑)',
                      onPressed: state.sessionStatus.isConnected
                          ? () => controller.sendArrowUp()
                          : null,
                      theme: theme,
                    ),
                    const SizedBox(width: 4),
                    _buildKeycapButton(
                      icon: Icons.keyboard_arrow_down_rounded,
                      tooltip: l10n?.sshTerminalArrowDown ?? 'Down (↓)',
                      onPressed: state.sessionStatus.isConnected
                          ? () => controller.sendArrowDown()
                          : null,
                      theme: theme,
                    ),
                    const SizedBox(width: 4),
                    _buildKeycapButton(
                      icon: Icons.keyboard_arrow_right_rounded,
                      tooltip: l10n?.sshTerminalArrowRight ?? 'Right (→)',
                      onPressed: state.sessionStatus.isConnected
                          ? () => controller.sendArrowRight()
                          : null,
                      theme: theme,
                    ),
                    const SizedBox(width: 6),
                    // Keyboard toggle button
                    Tooltip(
                      message: _terminalFocusNode.hasFocus
                          ? 'Hide Keyboard'
                          : 'Show Keyboard',
                      child: IconButton(
                        icon: Icon(
                          _terminalFocusNode.hasFocus
                              ? Icons.keyboard_hide_outlined
                              : Icons.keyboard_outlined,
                          size: 20,
                        ),
                        onPressed: () {
                          if (_terminalFocusNode.hasFocus) {
                            _terminalFocusNode.unfocus();
                          } else {
                            _terminalFocusNode.requestFocus();
                          }
                        },
                      ),
                    ),
                    if (!state.sessionStatus.isConnected) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(l10n?.sshTerminalReconnect ?? 'Reconnect'),
                        onPressed: () => controller.reconnect(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
