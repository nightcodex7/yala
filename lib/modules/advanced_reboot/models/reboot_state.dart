// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'reboot_capability.dart';

/// Finite state machine for Advanced Reboot operations.
enum RebootExecutionState {
  /// No active operation. Ready for interaction.
  idle,

  /// Performing pre-flight checks (router ID verification, lock acquisition, evidence validation).
  preflight,

  /// Preflight passed; awaiting explicit user confirmation with full risk disclosures.
  awaitingConfirmation,

  /// Command dispatched to router via authorized RPC / SSH channel.
  executing,

  /// Command sent; waiting for connection to drop as the router shuts down or restarts.
  waitingForDisconnect,

  /// Router rebooting; actively polling for router availability with bounded backoff.
  reconnecting,

  /// Reconnected; re-reading board and partition state to verify the intended outcome.
  verifying,

  /// Operation verified successfully (e.g. booted into target partition, or standard reboot complete).
  succeeded,

  /// Operation failed definitively with a known error reason.
  failed,

  /// Operation outcome cannot be confirmed (e.g. timeout after dispatch, network unreachable, unknown firmware).
  /// NEVER reported as succeeded.
  outcomeUnknown,

  /// User or system cancelled the operation prior to command execution.
  cancelled,
}

/// Progress model capturing the current execution state and context.
class RebootExecutionProgress {
  final RebootExecutionState state;
  final RebootOperationType? operation;
  final String message;
  final String? detail;
  final DateTime? startedAt;
  final int pollAttempt;
  final int maxPollAttempts;
  final String? targetSlot;
  final String? failureReason;
  final bool canCancel;

  const RebootExecutionProgress({
    this.state = RebootExecutionState.idle,
    this.operation,
    this.message = '',
    this.detail,
    this.startedAt,
    this.pollAttempt = 0,
    this.maxPollAttempts = 30,
    this.targetSlot,
    this.failureReason,
    this.canCancel = false,
  });

  bool get isIdle => state == RebootExecutionState.idle;
  bool get isPreflight => state == RebootExecutionState.preflight;
  bool get isAwaitingConfirmation =>
      state == RebootExecutionState.awaitingConfirmation;
  bool get isExecuting => state == RebootExecutionState.executing;
  bool get isWaitingForDisconnect =>
      state == RebootExecutionState.waitingForDisconnect;
  bool get isReconnecting => state == RebootExecutionState.reconnecting;
  bool get isVerifying => state == RebootExecutionState.verifying;
  bool get isSucceeded => state == RebootExecutionState.succeeded;
  bool get isFailed => state == RebootExecutionState.failed;
  bool get isOutcomeUnknown => state == RebootExecutionState.outcomeUnknown;
  bool get isCancelled => state == RebootExecutionState.cancelled;

  bool get isTerminal =>
      state == RebootExecutionState.succeeded ||
      state == RebootExecutionState.failed ||
      state == RebootExecutionState.outcomeUnknown ||
      state == RebootExecutionState.cancelled ||
      state == RebootExecutionState.idle;

  bool get isBusy => !isTerminal;

  RebootExecutionProgress copyWith({
    RebootExecutionState? state,
    RebootOperationType? operation,
    String? message,
    String? detail,
    DateTime? startedAt,
    int? pollAttempt,
    int? maxPollAttempts,
    String? targetSlot,
    String? failureReason,
    bool? canCancel,
  }) {
    return RebootExecutionProgress(
      state: state ?? this.state,
      operation: operation ?? this.operation,
      message: message ?? this.message,
      detail: detail ?? this.detail,
      startedAt: startedAt ?? this.startedAt,
      pollAttempt: pollAttempt ?? this.pollAttempt,
      maxPollAttempts: maxPollAttempts ?? this.maxPollAttempts,
      targetSlot: targetSlot ?? this.targetSlot,
      failureReason: failureReason ?? this.failureReason,
      canCancel: canCancel ?? this.canCancel,
    );
  }

  @override
  String toString() =>
      'RebootExecutionProgress(state: ${state.name}, op: ${operation?.name}, msg: "$message", poll: $pollAttempt/$maxPollAttempts)';
}
