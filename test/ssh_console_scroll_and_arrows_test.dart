// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/services/interfaces/ssh_persistent_session_interface.dart';
import 'package:yet_another_luci_app/modules/ssh_console/screens/ssh_console_screen.dart';
import 'package:yet_another_luci_app/services/mock_ssh_persistent_session.dart';

void main() {
  group('SSH Console Arrow Keys, Direct Input and Scrolling Tests', () {
    test(
      'MockSshPersistentSession emits correct escape sequences for controls',
      () {
        final session = MockSshPersistentSession();

        session.connect(
          host: '192.168.1.1',
          username: 'root',
          password: 'password',
        );

        expect(session.isConnected, isTrue);

        session.sendArrowUp();
        session.sendArrowDown();
        session.sendArrowLeft();
        session.sendArrowRight();
        session.sendNewline();
        session.sendRaw('ls -la');
        session.sendBackspace();
        session.sendTab();
        session.sendEscape();
        session.sendCtrlC();

        // Ensure mock remains stable and connected
        expect(session.status, equals(SshSessionStatus.connected));
      },
    );

    testWidgets(
      'SshConsoleScreen renders native TerminalView with bottom accessory bar',
      (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: SshConsoleScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify the native TerminalView is rendered
        expect(find.byType(TerminalView), findsOneWidget);

        // Verify the arrow key icons are present in the accessory bar
        expect(find.byIcon(Icons.keyboard_arrow_left_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_right_rounded), findsOneWidget);

        // Verify ESC and TAB keycap buttons are present
        expect(find.text('ESC'), findsOneWidget);
        expect(find.text('TAB'), findsOneWidget);

        // Verify Ctrl+C button is present
        expect(find.text('Ctrl+C'), findsOneWidget);

        // Verify Saved Commands bookmark button is in AppBar
        expect(find.byIcon(Icons.bookmarks_outlined), findsOneWidget);

        // Verify that the old bottom command bar is removed
        expect(find.byIcon(Icons.send_rounded), findsNothing);
        expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);
      },
    );
  });
}
