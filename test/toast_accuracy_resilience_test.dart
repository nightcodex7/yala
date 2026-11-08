// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/flush_dns_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'readAll') {
            return <String, String>{'reviewer_mode_enabled': 'true'};
          }
          if (methodCall.method == 'read') {
            return methodCall.arguments['key'] == 'reviewer_mode_enabled'
                ? 'true'
                : null;
          }
          if (methodCall.method == 'write') {
            return null;
          }
          return null;
        });
  });

  group('Toast Accuracy & Resilience Tests', () {
    test(
      'isUciSuccessful correctly identifies success and failure results',
      () {
        final api = ApiService();

        // Null or empty
        expect(api.isUciSuccessful(null), isFalse);

        // JSON-RPC error field
        expect(
          api.isUciSuccessful({
            'error': {'code': -32000, 'message': 'Access denied'},
          }),
          isFalse,
        );
        expect(api.isUciSuccessful({'error': 'UCI parse error'}), isFalse);

        // Array return codes: [0] = success, [1] = failure
        expect(api.isUciSuccessful([0]), isTrue);
        expect(api.isUciSuccessful([0, 'OK']), isTrue);
        expect(api.isUciSuccessful([1]), isFalse);
        expect(api.isUciSuccessful([4, 'Entry not found']), isFalse);

        // Map return codes
        expect(api.isUciSuccessful({'code': 0}), isTrue);
        expect(api.isUciSuccessful({'rc': 0}), isTrue);
        expect(api.isUciSuccessful({'code': 1}), isFalse);
        expect(api.isUciSuccessful({'rc': 255}), isFalse);

        // Map with error key and no code
        expect(
          api.isUciSuccessful({
            'result': 'failed',
            'error': 'Ubus call timed out',
          }),
          isFalse,
        );
      },
    );

    test(
      'isExpectedServiceDisconnect distinguishes expected severed connections from real failures',
      () {
        final api = ApiService();

        // Network-critical service with socket connection reset / abort
        const socketResetErr = SocketException('Connection reset by peer');
        const brokenPipeErr = SocketException('Broken pipe');
        const httpClosedErr = HttpException(
          'Connection closed before full header was received',
        );
        final dioConnErr = DioException(
          requestOptions: RequestOptions(path: '/ubus'),
          type: DioExceptionType.connectionError,
          message: 'SocketException: OS Error: Connection reset by peer',
        );

        // Critical services
        expect(
          api.isExpectedServiceDisconnect('network', socketResetErr),
          isTrue,
        );
        expect(
          api.isExpectedServiceDisconnect('uhttpd', brokenPipeErr),
          isTrue,
        );
        expect(
          api.isExpectedServiceDisconnect('firewall', httpClosedErr),
          isTrue,
        );
        expect(api.isExpectedServiceDisconnect('dropbear', dioConnErr), isTrue);

        // Non-critical services: disconnecting unexpectedly should NOT be treated as success
        expect(
          api.isExpectedServiceDisconnect('samba', socketResetErr),
          isFalse,
        );
        expect(api.isExpectedServiceDisconnect('sqm', socketResetErr), isFalse);
        expect(api.isExpectedServiceDisconnect('ddns', brokenPipeErr), isFalse);

        // Unrelated error on critical service (e.g. 403 Forbidden or 404) should NOT be treated as expected disconnect
        final dio403Err = DioException(
          requestOptions: RequestOptions(path: '/ubus'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/ubus'),
            statusCode: 403,
          ),
        );
        expect(api.isExpectedServiceDisconnect('network', dio403Err), isFalse);
      },
    );

    test(
      'AppState.flushDns returns a valid simulated FlushDnsResult in reviewer mode',
      () async {
        final appState = AppState.instance;
        await appState.setReviewerMode(true);

        final res = await appState.flushDns();
        expect(res, isA<FlushDnsResult>());
        expect(res.isSuccess, isTrue);
        expect(res.flushedResolvers, contains('dnsmasq'));
        expect(res.message, contains('simulated'));
      },
    );

    test(
      'FlushDnsResult model serialization and factories preserve success state',
      () {
        final successResult = FlushDnsResult.success(
          flushedResolvers: ['dnsmasq', 'odhcpd'],
          message: 'Flushed 2 resolvers',
        );
        expect(successResult.isSuccess, isTrue);
        expect(successResult.flushedResolvers, equals(['dnsmasq', 'odhcpd']));
        expect(successResult.message, equals('Flushed 2 resolvers'));

        final json = successResult.toJson();
        final roundtrip = FlushDnsResult.fromJson(json);
        expect(roundtrip.isSuccess, isTrue);
        expect(roundtrip.flushedResolvers, equals(['dnsmasq', 'odhcpd']));

        final failureResult = FlushDnsResult.failure(
          'Command failed with code 127',
        );
        expect(failureResult.isSuccess, isFalse);
        expect(failureResult.message, contains('127'));
      },
    );

    test(
      'LuciToastManager.parseErrorReason correctly classifies technical errors',
      () {
        // Permission denied & Auth
        expect(
          LuciToastManager.parseErrorReason(
            Exception('Permission denied (ubus code 6)'),
          ),
          contains('Permission denied'),
        );
        expect(
          LuciToastManager.parseErrorReason(Exception('Access denied by ACL')),
          contains('Permission denied'),
        );
        expect(
          LuciToastManager.parseErrorReason(
            Exception('Failed to call RPC: HTTP 401 Unauthorized'),
          ),
          contains('Session expired or unauthorized'),
        );
        expect(
          LuciToastManager.parseErrorReason(Exception('HTTP 403 Forbidden')),
          contains('Permission denied'),
        );

        // Network unreachable
        expect(
          LuciToastManager.parseErrorReason(
            const SocketException('Connection refused'),
          ),
          contains('Router unreachable'),
        );
        expect(
          LuciToastManager.parseErrorReason(
            Exception('Failed to reach RPC endpoint'),
          ),
          contains('Router unreachable'),
        );

        // Missing RPC endpoint
        expect(
          LuciToastManager.parseErrorReason(
            Exception('Failed to call RPC: HTTP 404 Not Found'),
          ),
          contains('RPC endpoint not found'),
        );

        // Timeout
        expect(
          LuciToastManager.parseErrorReason(
            Exception('Operation timed out on router (ubus error 7)'),
          ),
          contains('Request timed out'),
        );

        // Binary not found
        expect(
          LuciToastManager.parseErrorReason(
            Exception('/bin/sh: iw: command not found (exit code 127)'),
          ),
          contains('Required binary not found'),
        );

        // Insufficient storage
        expect(
          LuciToastManager.parseErrorReason(
            Exception('write error: no space left on device'),
          ),
          contains('Router storage is full'),
        );

        // OOM
        expect(
          LuciToastManager.parseErrorReason(
            Exception('Process killed: out of memory'),
          ),
          contains('Router ran out of memory'),
        );
      },
    );

    test(
      'RpcResult.userFriendlyActionError provides accurate actionable error summaries',
      () {
        expect(
          RpcResult.permissionDenied('ACL prohibited').userFriendlyActionError,
          contains('Permission denied'),
        );
        expect(
          RpcResult.networkError('No route to host').userFriendlyActionError,
          contains('Router unreachable'),
        );
        expect(
          RpcResult.methodNotFound('file.exec').userFriendlyActionError,
          contains('RPC method or service not available'),
        );
        expect(
          const RpcResult(
            status: RpcCallStatus.methodNotFound,
            errorCode: 127,
            errorMessage: 'iw: command not found',
          ).userFriendlyActionError,
          contains('Required binary not found'),
        );
        expect(
          RpcResult.failed(
            'write: No space left on device',
          ).userFriendlyActionError,
          contains('Router storage is full'),
        );
        expect(
          RpcResult.failed('killed').userFriendlyActionError,
          contains('Router ran out of memory'),
        );
        expect(
          RpcResult.failed('timed out', code: 7).userFriendlyActionError,
          contains('Request timed out'),
        );
        expect(
          RpcResult.failed(
            'ubus status code 6',
            code: 6,
          ).userFriendlyActionError,
          contains('Permission denied'),
        );
      },
    );

    testWidgets(
      'LuciToastManager.parseErrorReason returns localized message when context has locale',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            home: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dePermissionMsg = LuciToastManager.parseErrorReason(
          Exception('Permission denied'),
          capturedContext,
        );
        expect(dePermissionMsg, contains('Zugriff verweigert'));

        final deTimeoutMsg = LuciToastManager.parseErrorReason(
          Exception('Operation timed out on router (ubus error 7)'),
          capturedContext,
        );
        expect(deTimeoutMsg, contains('Zeitüberschreitung'));

        final deUnreachableMsg = LuciToastManager.parseErrorReason(
          const SocketException('Connection refused'),
          capturedContext,
        );
        expect(deUnreachableMsg, contains('Router nicht erreichbar'));
      },
    );
  });
}
