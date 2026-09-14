// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

String? parseFlexibleMacAddress(String input) {
  final trimmed = input.trim();
  final pairReg = RegExp(r'(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}');
  final matchPair = pairReg.firstMatch(trimmed);
  if (matchPair != null) {
    return matchPair.group(0)!.toUpperCase().replaceAll('-', ':');
  }

  final ciscoReg = RegExp(r'[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}');
  final matchCisco = ciscoReg.firstMatch(trimmed);
  if (matchCisco != null) {
    final cleaned = matchCisco.group(0)!.replaceAll('.', '');
    final sb = StringBuffer();
    for (int i = 0; i < 12; i += 2) {
      if (i > 0) sb.write(':');
      sb.write(cleaned.substring(i, i + 2).toUpperCase());
    }
    return sb.toString();
  }

  final raw12Reg = RegExp(r'\b[0-9a-fA-F]{12}\b');
  final match12 = raw12Reg.firstMatch(trimmed);
  if (match12 != null) {
    final cleaned = match12.group(0)!;
    final sb = StringBuffer();
    for (int i = 0; i < 12; i += 2) {
      if (i > 0) sb.write(':');
      sb.write(cleaned.substring(i, i + 2).toUpperCase());
    }
    return sb.toString();
  }

  return null;
}

void main() {
  group('Flexible MAC Address Copy-Paste Parsing Tests', () {
    test('Standard colon format is preserved and upper-cased', () {
      expect(
        parseFlexibleMacAddress('aa:bb:cc:dd:ee:ff'),
        equals('AA:BB:CC:DD:EE:FF'),
      );
      expect(
        parseFlexibleMacAddress('AA:BB:CC:DD:EE:FF'),
        equals('AA:BB:CC:DD:EE:FF'),
      );
    });

    test('Hyphen-separated format is converted to colon format', () {
      expect(
        parseFlexibleMacAddress('aa-bb-cc-dd-ee-ff'),
        equals('AA:BB:CC:DD:EE:FF'),
      );
      expect(
        parseFlexibleMacAddress('AA-BB-CC-DD-EE-FF'),
        equals('AA:BB:CC:DD:EE:FF'),
      );
    });

    test(
      'Cisco dot-separated format (aabb.ccdd.eeff) is converted to colon format',
      () {
        expect(
          parseFlexibleMacAddress('aabb.ccdd.eeff'),
          equals('AA:BB:CC:DD:EE:FF'),
        );
        expect(
          parseFlexibleMacAddress('AABB.CCDD.EEFF'),
          equals('AA:BB:CC:DD:EE:FF'),
        );
      },
    );

    test(
      'Raw 12-character hex string (aabbccddeeff) is converted to colon format',
      () {
        expect(
          parseFlexibleMacAddress('aabbccddeeff'),
          equals('AA:BB:CC:DD:EE:FF'),
        );
        expect(
          parseFlexibleMacAddress('AABBCCDDEEFF'),
          equals('AA:BB:CC:DD:EE:FF'),
        );
      },
    );

    test(
      'Space-separated and bracketed MAC strings are converted correctly',
      () {
        expect(
          parseFlexibleMacAddress('[AA:BB:CC:DD:EE:FF]'),
          equals('AA:BB:CC:DD:EE:FF'),
        );
        expect(
          parseFlexibleMacAddress('mac: aabbccddeeff (eth0)'),
          equals('AA:BB:CC:DD:EE:FF'),
        );
      },
    );

    test('Invalid MAC strings return null', () {
      expect(parseFlexibleMacAddress('invalid_mac'), isNull);
      expect(parseFlexibleMacAddress('12345'), isNull);
      expect(parseFlexibleMacAddress(''), isNull);
    });
  });
}
