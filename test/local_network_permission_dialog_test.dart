// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/widgets/local_network_permission_dialog.dart';

void main() {
  Widget buildTestWidget({
    bool isPermanentlyDenied = false,
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                onPressed: () {
                  LocalNetworkPermissionDialog.show(
                    context,
                    isPermanentlyDenied: isPermanentlyDenied,
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );
  }

  group('LocalNetworkPermissionDialog Widget Tests', () {
    testWidgets(
      'Displays educational prominent disclosure dialog with privacy bullets and Continue/Not Now buttons',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Check title and description
        expect(find.text('Local Network Permission'), findsOneWidget);
        expect(
          find.textContaining(
            'Yet Another LuCI App connects directly to your OpenWrt router gateway',
          ),
          findsOneWidget,
        );

        // Check privacy & security bullet points
        expect(find.textContaining('No internet exfiltration'), findsOneWidget);
        expect(find.textContaining('Privacy preserved'), findsOneWidget);

        // Check buttons
        expect(find.text('Continue'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        // Tap Cancel dismisses sheet
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Local Network Permission'), findsNothing);
      },
    );

    testWidgets(
      'Displays settings recovery dialog when isPermanentlyDenied is true',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(isPermanentlyDenied: true));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Local Network Access Denied'), findsOneWidget);
        expect(
          find.textContaining(
            'Yala requires this permission to communicate with your router gateway',
          ),
          findsOneWidget,
        );
        expect(find.text('Open App Settings'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        // Tap Cancel dismisses sheet
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Local Network Access Denied'), findsNothing);
      },
    );

    testWidgets('Renders translated strings in German (de)', (tester) async {
      await tester.pumpWidget(buildTestWidget(locale: const Locale('de')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Lokale Netzwerkberechtigung'), findsOneWidget);
      expect(find.text('Weiter'), findsOneWidget);
      expect(find.text('Abbrechen'), findsOneWidget);
    });

    testWidgets('Renders translated strings in Chinese (zh)', (tester) async {
      await tester.pumpWidget(buildTestWidget(locale: const Locale('zh')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('本地网络权限'), findsOneWidget);
      expect(find.text('继续'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });
  });
}
