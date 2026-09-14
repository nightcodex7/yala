// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/screens/more_screen.dart';
import 'package:yet_another_luci_app/screens/settings_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GPLv3 Compliance & Attribution Tests', () {
    test(
      'AppConfig defines proper GPLv3 metadata, copyleft disclaimer, and upstream credits',
      () {
        expect(
          AppConfig.licenseName,
          contains('GNU General Public License v3.0'),
        );
        expect(AppConfig.licenseSpdx, equals('GPL-3.0-or-later'));
        expect(AppConfig.upstreamAuthor, equals('cogwheel0'));
        expect(
          AppConfig.upstreamRepositoryUrl,
          contains('cogwheel0/luci-mobile'),
        );
        expect(AppConfig.copyrightNotice, contains('cogwheel0'));
        expect(AppConfig.copyrightNotice, contains('@nightcodex7'));
        expect(
          AppConfig.gplWarrantyDisclaimer,
          contains('WITHOUT ANY WARRANTY'),
        );
        expect(
          AppConfig.gplWarrantyDisclaimer,
          contains('GNU General Public License'),
        );
      },
    );

    test(
      'LicenseRegistry includes yet_another_luci_app entry with full GPL copyleft text',
      () async {
        LicenseRegistry.addLicense(() async* {
          yield const LicenseEntryWithLineBreaks(
            ['yet_another_luci_app (yala)'],
            '''Yet Another LuCI App (yala)
Original work Copyright (C) 2025-2026 cogwheel0
Modifications Copyright (C) 2026 @nightcodex7

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.''',
          );
        });

        final entries = await LicenseRegistry.licenses.toList();
        final yalaEntry = entries.firstWhere(
          (e) => e.packages.any((p) => p.contains('yet_another_luci_app')),
        );

        expect(yalaEntry, isNotNull);
        final paragraphs = yalaEntry.paragraphs.map((p) => p.text).join('\n');
        expect(paragraphs, contains('cogwheel0'));
        expect(paragraphs, contains('@nightcodex7'));
        expect(paragraphs, contains('GNU General Public License'));
        expect(paragraphs, contains('WITHOUT ANY WARRANTY'));
      },
    );

    testWidgets(
      'MoreScreen displays Settings and About tiles while License & Attribution is located under Settings',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final appState = AppState.instance;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const MaterialApp(home: MoreScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // MoreScreen has Settings and About
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('About'), findsOneWidget);

        // Direct License & Attribution tile is not on the main More tab (kept under Settings)
        expect(find.text('License & Attribution'), findsNothing);
      },
    );

    testWidgets(
      'SettingsScreen displays License & Attribution tile and opens GPLv3 dialog',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        SharedPreferences.setMockInitialValues({});
        final appState = AppState.instance;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const MaterialApp(home: SettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        final legalTile = find.text('License & Attribution (GPLv3)');
        await tester.scrollUntilVisible(
          legalTile,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(legalTile, findsOneWidget);

        await tester.tap(legalTile);
        await tester.pumpAndSettle();

        expect(find.text('License & Copyleft (GPLv3)'), findsOneWidget);
        expect(find.textContaining('cogwheel0 (luci-mobile)'), findsOneWidget);
        expect(find.textContaining('@nightcodex7'), findsOneWidget);
        expect(find.textContaining('WITHOUT ANY WARRANTY'), findsOneWidget);

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      },
    );
  });
}
