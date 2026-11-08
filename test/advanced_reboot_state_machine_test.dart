// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/models/reboot_capability.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/models/reboot_state.dart';

void main() {
  group('RebootExecutionProgress State Machine Tests', () {
    test('Default initial state is idle and terminal/not busy', () {
      const p = RebootExecutionProgress();
      expect(p.isIdle, isTrue);
      expect(p.isTerminal, isTrue);
      expect(p.isBusy, isFalse);
      expect(p.canCancel, isFalse);
    });

    test('Preflight state is busy and cancellable', () {
      final p = const RebootExecutionProgress().copyWith(
        state: RebootExecutionState.preflight,
        operation: RebootOperationType.standardReboot,
        canCancel: true,
      );
      expect(p.isPreflight, isTrue);
      expect(p.isBusy, isTrue);
      expect(p.isTerminal, isFalse);
      expect(p.canCancel, isTrue);
    });

    test('Executing state is busy and NOT cancellable', () {
      final p = const RebootExecutionProgress().copyWith(
        state: RebootExecutionState.executing,
        operation: RebootOperationType.alternatePartitionBoot,
        canCancel: false,
      );
      expect(p.isExecuting, isTrue);
      expect(p.isBusy, isTrue);
      expect(p.isTerminal, isFalse);
      expect(p.canCancel, isFalse);
    });

    test('Waiting for disconnect state is busy and not cancellable', () {
      final p = const RebootExecutionProgress().copyWith(
        state: RebootExecutionState.waitingForDisconnect,
        operation: RebootOperationType.standardReboot,
      );
      expect(p.isWaitingForDisconnect, isTrue);
      expect(p.isBusy, isTrue);
      expect(p.isTerminal, isFalse);
    });

    test('Reconnecting state is busy and tracks poll attempts', () {
      final p = const RebootExecutionProgress().copyWith(
        state: RebootExecutionState.reconnecting,
        pollAttempt: 5,
        maxPollAttempts: 30,
      );
      expect(p.isReconnecting, isTrue);
      expect(p.isBusy, isTrue);
      expect(p.pollAttempt, equals(5));
      expect(p.maxPollAttempts, equals(30));
    });

    test('Verifying state is busy and not cancellable', () {
      final p = const RebootExecutionProgress().copyWith(
        state: RebootExecutionState.verifying,
        targetSlot: '2',
      );
      expect(p.isVerifying, isTrue);
      expect(p.isBusy, isTrue);
      expect(p.targetSlot, equals('2'));
    });

    test('Succeeded state is terminal and not busy', () {
      final p = const RebootExecutionProgress().copyWith(
        state: RebootExecutionState.succeeded,
        message: 'Reboot verified',
      );
      expect(p.isSucceeded, isTrue);
      expect(p.isTerminal, isTrue);
      expect(p.isBusy, isFalse);
    });

    test('Failed state is terminal and retains failure reason', () {
      final p = const RebootExecutionProgress().copyWith(
        state: RebootExecutionState.failed,
        message: 'Partition switch failed',
        failureReason: 'Bootloader reverted',
      );
      expect(p.isFailed, isTrue);
      expect(p.isTerminal, isTrue);
      expect(p.isBusy, isFalse);
      expect(p.failureReason, equals('Bootloader reverted'));
    });

    test(
      'OutcomeUnknown state is terminal and retains uncertainty explanation',
      () {
        final p = const RebootExecutionProgress().copyWith(
          state: RebootExecutionState.outcomeUnknown,
          message: 'Router did not respond after reboot',
          failureReason: 'Polling timeout',
        );
        expect(p.isOutcomeUnknown, isTrue);
        expect(p.isTerminal, isTrue);
        expect(p.isBusy, isFalse);
        expect(p.failureReason, equals('Polling timeout'));
      },
    );

    test('Cancelled state is terminal', () {
      final p = const RebootExecutionProgress().copyWith(
        state: RebootExecutionState.cancelled,
        message: 'User cancelled operation',
      );
      expect(p.isCancelled, isTrue);
      expect(p.isTerminal, isTrue);
      expect(p.isBusy, isFalse);
    });

    test(
      'State machine transitions cleanly through full successful lifecycle',
      () {
        var p = const RebootExecutionProgress();
        expect(p.isIdle, isTrue);

        p = p.copyWith(
          state: RebootExecutionState.preflight,
          operation: RebootOperationType.alternatePartitionBoot,
          targetSlot: '2',
          canCancel: true,
        );
        expect(p.isPreflight, isTrue);

        p = p.copyWith(state: RebootExecutionState.executing, canCancel: false);
        expect(p.isExecuting, isTrue);

        p = p.copyWith(state: RebootExecutionState.waitingForDisconnect);
        expect(p.isWaitingForDisconnect, isTrue);

        p = p.copyWith(
          state: RebootExecutionState.reconnecting,
          pollAttempt: 1,
        );
        expect(p.isReconnecting, isTrue);

        p = p.copyWith(state: RebootExecutionState.verifying);
        expect(p.isVerifying, isTrue);

        p = p.copyWith(
          state: RebootExecutionState.succeeded,
          message: 'Reboot to Slot 2 verified successfully.',
        );
        expect(p.isSucceeded, isTrue);
        expect(p.isTerminal, isTrue);
      },
    );
  });
}
