// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/log_viewer/models/log_entry.dart';
import 'package:yet_another_luci_app/modules/log_viewer/models/log_fetch_result.dart';
import 'package:yet_another_luci_app/services/api_service.dart';

class TestableRealApiService extends RealApiService {
  Future<dynamic> Function({
    required String object,
    required String method,
    Map<String, dynamic>? params,
  })?
  onCall;

  @override
  Future<dynamic> callWithContext(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    dynamic context,
    bool isRetry = false,
  }) async {
    if (onCall != null) {
      return onCall!(object: object, method: method, params: params);
    }
    return [
      0,
      {'code': 0, 'stdout': '', 'stderr': ''},
    ];
  }
}

void main() {
  late TestableRealApiService api;

  setUp(() {
    api = TestableRealApiService();
  });

  group('RealApiService.fetchSyslog', () {
    test(
      'successfully unpacks RPC [0, {code: 0, stdout: ...}] and parses entries',
      () async {
        const sampleStdout =
            'Mon Nov  9 17:21:59 2026 daemon.notice hostapd: Unexpected Link measurement report, token 1\n'
            'Mon Nov  9 17:22:00 2026 cron.err crond[15562]: USER root pid 9047 cmd /bin/sh /usr/bin/parental_guard\n';

        api.onCall = ({required object, required method, params}) async {
          expect(object, equals('file'));
          expect(method, equals('exec'));
          return [
            0,
            {'code': 0, 'stdout': sampleStdout, 'stderr': ''},
          ];
        };

        final result = await api.fetchSyslog('192.168.1.1', 'token', false);
        expect(result, isA<LogFetchSuccess>());
        final success = result as LogFetchSuccess;
        expect(success.entries.length, equals(2));
        expect(success.entries[0].tag, equals('hostapd'));
        expect(success.entries[0].level, equals(LogLevel.notice));
        expect(success.entries[1].level, equals(LogLevel.error));
      },
    );

    test('truncates log lines to requested lines parameter', () async {
      final lines = List.generate(
        10,
        (i) => 'Mon Nov  9 17:00:0$i 2026 daemon.info daemon[$i]: line $i',
      ).join('\n');

      api.onCall = ({required object, required method, params}) async {
        return [
          0,
          {'code': 0, 'stdout': lines},
        ];
      };

      final result = await api.fetchSyslog(
        '192.168.1.1',
        'token',
        false,
        lines: 3,
      );
      expect(result, isA<LogFetchSuccess>());
      final success = result as LogFetchSuccess;
      expect(success.entries.length, equals(3));
      expect(success.entries.last.message, contains('line 9'));
    });

    test(
      'falls back to bare logread if -l flag fails with error code',
      () async {
        var callCount = 0;
        api.onCall = ({required object, required method, params}) async {
          callCount++;
          final commandParams = params?['params'] as List?;
          if (commandParams != null && commandParams.contains('-l')) {
            // Emulate busybox rejecting -l
            return [
              0,
              {'code': 1, 'stdout': '', 'stderr': 'unrecognized option: -l'},
            ];
          }
          return [
            0,
            {
              'code': 0,
              'stdout':
                  'Mon Nov  9 17:22:00 2026 daemon.info sys: fallback succeeded',
            },
          ];
        };

        final result = await api.fetchSyslog('192.168.1.1', 'token', false);
        expect(result, isA<LogFetchSuccess>());
        final success = result as LogFetchSuccess;
        expect(success.entries.length, equals(1));
        expect(success.entries.first.message, contains('fallback succeeded'));
        expect(callCount, greaterThan(1));
      },
    );

    test('returns LogFetchBinaryMissing when exit code is 127', () async {
      api.onCall = ({required object, required method, params}) async {
        return [
          0,
          {'code': 127, 'stdout': '', 'stderr': 'logread: not found'},
        ];
      };

      final result = await api.fetchSyslog('192.168.1.1', 'token', false);
      expect(result, isA<LogFetchBinaryMissing>());
    });

    test(
      'returns LogFetchPermissionError when access denied (code 6)',
      () async {
        api.onCall = ({required object, required method, params}) async {
          return [6]; // rpcd Access Denied
        };

        final result = await api.fetchSyslog('192.168.1.1', 'token', false);
        expect(result, isA<LogFetchPermissionError>());
      },
    );

    test('returns LogFetchTimeout when timeout exception is thrown', () async {
      api.onCall = ({required object, required method, params}) async {
        throw Exception('Connection timeout after 10000ms');
      };

      final result = await api.fetchSyslog('192.168.1.1', 'token', false);
      expect(result, isA<LogFetchTimeout>());
    });
  });

  group('RealApiService.fetchKernelLog', () {
    test(
      'successfully unpacks RPC [0, {code: 0, stdout: ...}] and parses dmesg lines',
      () async {
        const sampleStdout =
            '<6>[    0.000000] Booting Linux on physical CPU 0x0\n'
            '<5>[    0.000000] Linux version 6.12.112 (arm-openwrt-linux-muslgnueabi)\n'
            '<3>[    1.234567] init: failed to initialize device driver\n';

        api.onCall = ({required object, required method, params}) async {
          expect(object, equals('file'));
          expect(method, equals('exec'));
          return [
            0,
            {'code': 0, 'stdout': sampleStdout, 'stderr': ''},
          ];
        };

        final result = await api.fetchKernelLog('192.168.1.1', 'token', false);
        expect(result, isA<LogFetchSuccess>());
        final success = result as LogFetchSuccess;
        expect(success.entries.length, equals(3));
        expect(success.entries[0].level, equals(LogLevel.info));
        expect(success.entries[1].level, equals(LogLevel.notice));
        expect(success.entries[2].level, equals(LogLevel.error));
      },
    );

    test('falls back to bare dmesg if -r flag fails', () async {
      var callCount = 0;
      api.onCall = ({required object, required method, params}) async {
        callCount++;
        final commandParams = params?['params'] as List?;
        if (commandParams != null && commandParams.contains('-r')) {
          return [
            0,
            {'code': 1, 'stdout': '', 'stderr': 'invalid option -r'},
          ];
        }
        return [
          0,
          {'code': 0, 'stdout': '[    0.000000] Linux version 6.12.112\n'},
        ];
      };

      final result = await api.fetchKernelLog('192.168.1.1', 'token', false);
      expect(result, isA<LogFetchSuccess>());
      final success = result as LogFetchSuccess;
      expect(success.entries.length, equals(1));
      expect(callCount, greaterThan(1));
    });

    test(
      'returns LogFetchBinaryMissing when dmesg is not found (code 127)',
      () async {
        api.onCall = ({required object, required method, params}) async {
          return [
            0,
            {'code': 127, 'stdout': '', 'stderr': 'dmesg: command not found'},
          ];
        };

        final result = await api.fetchKernelLog('192.168.1.1', 'token', false);
        expect(result, isA<LogFetchBinaryMissing>());
      },
    );

    test(
      'returns LogFetchPermissionError when permission denied string is thrown',
      () async {
        api.onCall = ({required object, required method, params}) async {
          throw Exception('Access Denied (code: 6)');
        };

        final result = await api.fetchKernelLog('192.168.1.1', 'token', false);
        expect(result, isA<LogFetchPermissionError>());
      },
    );
  });
}
