// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/modules/services_system/models/services_system_info.dart';
import 'package:yet_another_luci_app/modules/services_system/screens/services_system_screen.dart';

Widget _buildCronTestHarness({
  required List<CronJob> cronJobs,
  Function(int index, bool val)? onToggle,
  Function(int index)? onEdit,
  Function(int index)? onDelete,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _CronCardsWidget(
            cronJobs: cronJobs,
            onToggle: onToggle,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ),
      ),
    ),
  );
}

class _CronCardsWidget extends StatelessWidget {
  final List<CronJob> cronJobs;
  final Function(int index, bool val)? onToggle;
  final Function(int index)? onEdit;
  final Function(int index)? onDelete;

  const _CronCardsWidget({
    required this.cronJobs,
    this.onToggle,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      children: cronJobs.asMap().entries.map((entry) {
        final index = entry.key;
        final cron = entry.value;
        final isEnabled = !cron.isCommented;
        final scheduleText = CronValidator.describeSchedule(
          cron.expression,
          l10n,
        );

        return Card(
          key: ValueKey('cron_${index}_${cron.rawLine}'),
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isEnabled
                  ? theme.colorScheme.primary.withValues(alpha: 0.25)
                  : theme.dividerColor.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: isEnabled
                          ? theme.colorScheme.primary.withValues(alpha: 0.15)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.schedule_rounded,
                        color: isEnabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.38,
                              ),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.25,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              cron.expression,
                              style: GoogleFonts.geistMono(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isEnabled
                                  ? LuciStatusColors.connected.withValues(
                                      alpha: 0.15,
                                    )
                                  : Colors.grey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isEnabled
                                  ? (l10n?.statusActive ?? 'ACTIVE')
                                  : (l10n?.statusDisabled ?? 'DISABLED'),
                              style: TextStyle(
                                color: isEnabled
                                    ? LuciStatusColors.connected
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: isEnabled,
                      onChanged: onToggle != null
                          ? (val) => onToggle!(index, val)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_repeat_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          scheduleText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Icon(
                          Icons.terminal_rounded,
                          size: 15,
                          color: isEnabled
                              ? theme.colorScheme.primary
                              : theme.disabledColor,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          cron.command,
                          style: GoogleFonts.geistMono(
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: isEnabled
                                ? theme.colorScheme.onSurface
                                : theme.disabledColor,
                            decoration: isEnabled
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 15),
                        tooltip:
                            l10n?.addRpcHandlerCopyCommand ?? 'Copy Command',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: cron.command));
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: onEdit != null ? () => onEdit!(index) : null,
                      icon: const Icon(Icons.edit_outlined, size: 15),
                      label: Text(
                        l10n?.actionEdit ?? 'Edit',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: onDelete != null
                          ? () => onDelete!(index)
                          : null,
                      icon: Icon(
                        Icons.delete_outline,
                        size: 15,
                        color: theme.colorScheme.error,
                      ),
                      label: Text(
                        l10n?.actionDelete ?? 'Delete',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.error,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cron Job Cards Visibility & Usability Tests', () {
    const longCommand =
        '/bin/nice -n 19 /usr/bin/ionice -c 3 taskset -c 0 /usr/sbin/fstrim -v /mnt/ssd >> /mnt/ssd/system/logs/fstrim.log 2>&1';
    const testJob1 = CronJob(
      expression: '0 3 * * 0',
      command: longCommand,
      isCommented: false,
      rawLine: '0 3 * * 0 $longCommand',
    );
    const testJob2 = CronJob(
      expression: '30 2 * * *',
      command: '/etc/led-off.sh',
      isCommented: true,
      rawLine: '# 30 2 * * * /etc/led-off.sh',
    );

    testWidgets(
      'Full long command is visible in SelectableText without truncation',
      (tester) async {
        await tester.pumpWidget(
          _buildCronTestHarness(cronJobs: [testJob1, testJob2]),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Verify the full command text is displayed
        expect(find.text(longCommand), findsOneWidget);
        expect(find.text('/etc/led-off.sh'), findsOneWidget);

        // Verify expression badges
        expect(find.text('0 3 * * 0'), findsOneWidget);
        expect(find.text('30 2 * * *'), findsOneWidget);

        // Verify active vs disabled badges
        expect(find.text('ACTIVE'), findsOneWidget);
        expect(find.text('DISABLED'), findsOneWidget);
      },
    );

    testWidgets('Copy command button correctly puts command into clipboard', (
      tester,
    ) async {
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            copiedText = (methodCall.arguments as Map)['text'];
            return null;
          }
          return null;
        },
      );

      await tester.pumpWidget(_buildCronTestHarness(cronJobs: [testJob1]));
      await tester.pumpAndSettle();

      final copyButton = find.byIcon(Icons.copy_rounded);
      expect(copyButton, findsOneWidget);
      await tester.tap(copyButton);
      await tester.pumpAndSettle();

      expect(copiedText, equals(longCommand));
    });

    testWidgets('Toggle, Edit, and Delete action callbacks are triggered', (
      tester,
    ) async {
      bool? toggledVal;
      int? editedIndex;
      int? deletedIndex;

      await tester.pumpWidget(
        _buildCronTestHarness(
          cronJobs: [testJob1],
          onToggle: (index, val) => toggledVal = val,
          onEdit: (index) => editedIndex = index,
          onDelete: (index) => deletedIndex = index,
        ),
      );
      await tester.pumpAndSettle();

      // Test toggle
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      expect(toggledVal, isFalse);

      // Test edit button
      final editBtn = find.text('Edit');
      expect(editBtn, findsOneWidget);
      await tester.tap(editBtn);
      expect(editedIndex, equals(0));

      // Test delete button
      final deleteBtn = find.text('Delete');
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      expect(deletedIndex, equals(0));
    });

    testWidgets('Renders cleanly on narrow screen (320px) without overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildCronTestHarness(cronJobs: [testJob1, testJob2]),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text(longCommand), findsOneWidget);
    });

    testWidgets('Cron Jobs header and Add Task button render on the same row', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.schedule_outlined, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cron Jobs',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'Add Task',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titleFinder = find.text('Cron Jobs');
      final buttonFinder = find.text('Add Task');

      expect(titleFinder, findsOneWidget);
      expect(buttonFinder, findsOneWidget);

      final titleCenter = tester.getCenter(titleFinder);
      final buttonCenter = tester.getCenter(buttonFinder);

      // Verify vertically aligned on the same row (centers aligned within 6 pixels)
      expect((titleCenter.dy - buttonCenter.dy).abs(), lessThan(6.0));
      // Verify button is to the right of title
      expect(buttonCenter.dx, greaterThan(titleCenter.dx));
    });
  });
}
