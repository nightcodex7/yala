// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ARB Localization Parity Tests', () {
    late Map<String, dynamic> enData;
    late List<String> enKeys;
    final variableRegex = RegExp(r'\{(\w+)\}');
    final icuPluralRegex = RegExp(r'\{(\w+),\s*plural,');

    const locales = [
      'de',
      'es',
      'fr',
      'id',
      'it',
      'ja',
      'pt',
      'pt_BR',
      'ru',
      'uk',
      'zh',
    ];

    setUpAll(() {
      final enFile = File('lib/l10n/app_en.arb');
      expect(enFile.existsSync(), isTrue, reason: 'app_en.arb must exist');
      enData = json.decode(enFile.readAsStringSync()) as Map<String, dynamic>;
      enKeys = enData.keys.where((k) => !k.startsWith('@')).toList();
    });

    test(
      'All locales have 100% key parity with app_en.arb (no missing or extra keys)',
      () {
        final enKeySet = enKeys.toSet();

        for (final loc in locales) {
          final locFile = File('lib/l10n/app_$loc.arb');
          expect(
            locFile.existsSync(),
            isTrue,
            reason: 'app_$loc.arb must exist',
          );

          final locData =
              json.decode(locFile.readAsStringSync()) as Map<String, dynamic>;
          final locKeys = locData.keys.where((k) => !k.startsWith('@')).toSet();

          final missingKeys = enKeySet.difference(locKeys);
          final extraKeys = locKeys.difference(enKeySet);

          expect(
            missingKeys,
            isEmpty,
            reason: '$loc is missing ${missingKeys.length} keys: $missingKeys',
          );
          expect(
            extraKeys,
            isEmpty,
            reason: '$loc has ${extraKeys.length} extra keys: $extraKeys',
          );
          expect(
            locKeys.length,
            equals(enKeySet.length),
            reason: '$loc must have exactly ${enKeySet.length} keys',
          );
        }
      },
    );

    test('No locale contains empty or whitespace-only translation strings', () {
      for (final loc in locales) {
        final locFile = File('lib/l10n/app_$loc.arb');
        final locData =
            json.decode(locFile.readAsStringSync()) as Map<String, dynamic>;

        for (final entry in locData.entries) {
          if (entry.key.startsWith('@')) continue;
          final value = entry.value;
          expect(
            value,
            isA<String>(),
            reason: '$loc [${entry.key}] value must be String',
          );
          expect(
            (value as String).trim(),
            isNotEmpty,
            reason: '$loc [${entry.key}] must not be empty or blank',
          );
        }
      }
    });

    test('All locales have exact placeholder variable parity with English', () {
      for (final loc in locales) {
        final locFile = File('lib/l10n/app_$loc.arb');
        final locData =
            json.decode(locFile.readAsStringSync()) as Map<String, dynamic>;

        for (final key in enKeys) {
          final enVal = enData[key] as String;
          final locVal = locData[key] as String;

          // Check ICU plurals
          final enIcu = icuPluralRegex
              .allMatches(enVal)
              .map((m) => m.group(1))
              .toSet();
          final locIcu = icuPluralRegex
              .allMatches(locVal)
              .map((m) => m.group(1))
              .toSet();

          expect(
            locIcu,
            equals(enIcu),
            reason: '$loc [$key] ICU plural mismatch: EN=$enIcu, LOC=$locIcu',
          );

          // Check standard variables {name}
          final enVars = variableRegex
              .allMatches(enVal)
              .map((m) => m.group(1))
              .toSet();
          final locVars = variableRegex
              .allMatches(locVal)
              .map((m) => m.group(1))
              .toSet();

          expect(
            locVars,
            equals(enVars),
            reason: '$loc [$key] variables mismatch: EN=$enVars, LOC=$locVars',
          );
        }
      }
    });

    test(
      'AppLocalizations successfully loads every supported locale and delegates',
      () async {
        for (final locale in AppLocalizations.supportedLocales) {
          expect(AppLocalizations.delegate.isSupported(locale), isTrue);
          final instance = await AppLocalizations.delegate.load(locale);
          expect(instance, isNotNull);
          expect(instance.appTitle, isNotEmpty);
          expect(instance.navDashboard, isNotEmpty);
          expect(instance.navInterfaces, isNotEmpty);
          expect(instance.navClients, isNotEmpty);
          expect(instance.navSettings, isNotEmpty);
          expect(instance.actionSave, isNotEmpty);
          expect(instance.actionCancel, isNotEmpty);
        }
      },
    );
  });
}
