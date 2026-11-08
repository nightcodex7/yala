// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/diagnostics/controllers/speed_test_controller.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/speed_test_models.dart';
import 'package:yet_another_luci_app/modules/diagnostics/services/speed_test_service.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';

class _FakeSpeedTestService implements ISpeedTestService {
  final StreamController<SpeedTestProgress> _controller =
      StreamController<SpeedTestProgress>.broadcast();
  bool isCancelled = false;
  bool shouldFail = false;
  bool failUploadOnly = false;
  int runCount = 0;

  @override
  Stream<SpeedTestProgress> get progressStream => _controller.stream;

  @override
  void cancel() {
    isCancelled = true;
    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.cancelled,
        statusMessage: 'Cancelled',
      ),
    );
  }

  @override
  Future<String> detectTransportType() async => 'Wi-Fi';

  @override
  Future<SpeedTestResult> runRouterSpeedTest({
    required IApiService api,
    required String routerIp,
    required String sysauth,
    bool useHttps = false,
    String? wanInterface,
    Duration timeout = const Duration(seconds: 30),
    RouterCapabilities? capabilities,
  }) async {
    return runTest();
  }

  @override
  Future<SpeedTestResult> runTest({
    int downloadByteTarget = 15000000,
    int uploadByteTarget = 4000000,
    int latencyProbes = 5,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    runCount++;
    isCancelled = false;

    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.measuringLatency,
        currentLatencyMs: 12.5,
        currentJitterMs: 1.2,
      ),
    );

    if (shouldFail) {
      _controller.add(
        const SpeedTestProgress(
          stage: SpeedTestStage.failed,
          statusMessage: 'Server unreachable (500)',
        ),
      );
      return SpeedTestResult(
        stage: SpeedTestStage.failed,
        timestamp: DateTime.now(),
        errorMessage: 'Server unreachable (500)',
      );
    }

    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.measuringDownload,
        currentSpeedMbps: 85.4,
        progressPercent: 0.5,
      ),
    );

    if (failUploadOnly) {
      return SpeedTestResult(
        downloadSpeedMbps: 85.4,
        idleLatencyMs: 12.5,
        jitterMs: 1.2,
        stage: SpeedTestStage.failed,
        timestamp: DateTime.now(),
        errorMessage: 'Upload failed: timeout',
      );
    }

    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.measuringUpload,
        currentSpeedMbps: 42.1,
        progressPercent: 0.8,
      ),
    );

    final res = SpeedTestResult(
      downloadSpeedMbps: 85.4,
      uploadSpeedMbps: 42.1,
      idleLatencyMs: 12.5,
      jitterMs: 1.2,
      loadedLatencyMs: 18.3,
      connectionType: 'Wi-Fi',
      vantagePoint: 'Device Internet Speed Test',
      serverName: 'Cloudflare Anycast (speed.cloudflare.com)',
      timestamp: DateTime.now(),
      downloadBytes: downloadByteTarget,
      uploadBytes: uploadByteTarget,
      downloadDurationMs: 1400,
      uploadDurationMs: 760,
      latencySamples: const [12.0, 13.0, 12.5],
      stage: SpeedTestStage.completed,
    );

    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.completed,
        progressPercent: 1.0,
      ),
    );

    return res;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpeedTestService Math & Formula Tests', () {
    test(
      'calculateThroughputMbps converts bytes to decimal Mbps accurately',
      () {
        // 12,500,000 bytes = 100,000,000 bits.
        // In 1 second: 100,000,000 / 1,000,000 = 100.0 Mbps
        final mbps = SpeedTestService.calculateThroughputMbps(12500000, 1.0);
        expect(mbps, equals(100.0));

        // In 2 seconds: 50.0 Mbps
        final mbps2 = SpeedTestService.calculateThroughputMbps(12500000, 2.0);
        expect(mbps2, equals(50.0));

        // 0 or negative duration returns 0.0
        expect(
          SpeedTestService.calculateThroughputMbps(12500000, 0.0),
          equals(0.0),
        );
        expect(
          SpeedTestService.calculateThroughputMbps(12500000, -1.0),
          equals(0.0),
        );
      },
    );

    test(
      'calculateMedian computes correct median for odd and even length samples',
      () {
        expect(SpeedTestService.calculateMedian([]), equals(0.0));

        // Single item
        expect(SpeedTestService.calculateMedian([15.0]), equals(15.0));

        // Odd length sorted
        expect(
          SpeedTestService.calculateMedian([10.0, 15.0, 20.0]),
          equals(15.0),
        );

        // Even length sorted: average of middle two
        expect(
          SpeedTestService.calculateMedian([10.0, 14.0, 16.0, 20.0]),
          equals(15.0),
        );
      },
    );

    test(
      'calculateJitter computes RFC mean absolute difference between consecutive samples',
      () {
        // Less than 2 samples: jitter 0.0
        expect(SpeedTestService.calculateJitter([]), equals(0.0));
        expect(SpeedTestService.calculateJitter([10.0]), equals(0.0));

        // Samples: [10.0, 12.0, 11.0, 14.0]
        // Diffs: |12 - 10| = 2.0, |11 - 12| = 1.0, |14 - 11| = 3.0
        // Sum = 6.0, Count = 3 -> Jitter = 2.0 ms
        final jitter = SpeedTestService.calculateJitter([
          10.0,
          12.0,
          11.0,
          14.0,
        ]);
        expect(jitter, equals(2.0));
      },
    );

    test(
      'calculatePercentile computes accurate percentile with linear interpolation',
      () {
        expect(SpeedTestService.calculatePercentile([], 0.90), equals(0.0));
        expect(
          SpeedTestService.calculatePercentile([100.0], 0.90),
          equals(100.0),
        );

        // [100.0, 200.0, 250.0, 280.0]
        // 90th percentile rank = (4 - 1) * 0.9 = 2.7 -> 250*0.3 + 280*0.7 = 75 + 196 = 271.0
        final p90 = SpeedTestService.calculatePercentile([
          100.0,
          200.0,
          250.0,
          280.0,
        ], 0.90);
        expect(p90, closeTo(271.0, 0.001));

        // 50th percentile matches median
        final p50 = SpeedTestService.calculatePercentile([
          10.0,
          20.0,
          30.0,
        ], 0.50);
        expect(p50, equals(20.0));
      },
    );
  });

  group('SpeedTestResult Model Tests', () {
    test('JSON serialization roundtrip preserves all metrics', () {
      final now = DateTime.now();
      final original = SpeedTestResult(
        downloadSpeedMbps: 124.5,
        uploadSpeedMbps: 58.2,
        idleLatencyMs: 14.3,
        jitterMs: 1.8,
        loadedLatencyMs: 22.1,
        packetLossPercent: null, // Validly omitted
        connectionType: 'Wi-Fi',
        vantagePoint: 'Device Internet Speed Test',
        serverName: 'Cloudflare Anycast (speed.cloudflare.com)',
        timestamp: now,
        downloadBytes: 15000000,
        uploadBytes: 4000000,
        downloadDurationMs: 963,
        uploadDurationMs: 550,
        latencySamples: const [13.5, 14.3, 15.1],
        stage: SpeedTestStage.completed,
      );

      final json = original.toJson();
      final parsed = SpeedTestResult.fromJson(json);

      expect(parsed.downloadSpeedMbps, equals(124.5));
      expect(parsed.uploadSpeedMbps, equals(58.2));
      expect(parsed.idleLatencyMs, equals(14.3));
      expect(parsed.jitterMs, equals(1.8));
      expect(parsed.loadedLatencyMs, equals(22.1));
      expect(parsed.packetLossPercent, isNull);
      expect(parsed.connectionType, equals('Wi-Fi'));
      expect(parsed.vantagePoint, equals('Device Internet Speed Test'));
      expect(parsed.isSuccess, isTrue);
    });

    test('Failed result preserves partial measurements and reports error', () {
      final failed = SpeedTestResult(
        downloadSpeedMbps: 85.0,
        uploadSpeedMbps: null, // Upload failed
        idleLatencyMs: 12.0,
        stage: SpeedTestStage.failed,
        errorMessage: 'Upload failed: server 503',
        timestamp: DateTime.now(),
      );

      expect(failed.isSuccess, isFalse);
      expect(failed.downloadSpeedMbps, equals(85.0));
      expect(failed.uploadSpeedMbps, isNull);
      expect(failed.errorMessage, contains('server 503'));
      expect(failed.isRpcPermissionError, isFalse);
    });

    test(
      'isRpcPermissionError detects ACL status 6 and actionable error message',
      () {
        final aclDenied = SpeedTestResult(
          stage: SpeedTestStage.failed,
          errorMessage:
              'Router WAN speed test requires RPC execution permissions. Run RPC Setup in Settings',
          isPermissionDenied: true,
          timestamp: DateTime.now(),
        );

        expect(aclDenied.isSuccess, isFalse);
        expect(aclDenied.isPermissionDenied, isTrue);
        expect(aclDenied.isRpcPermissionError, isTrue);

        final msgOnly = SpeedTestResult(
          stage: SpeedTestStage.failed,
          errorMessage:
              'Router WAN speed test requires RPC execution permissions. Run RPC Setup in Settings',
          timestamp: DateTime.now(),
        );
        expect(msgOnly.isRpcPermissionError, isTrue);
      },
    );
  });

  group('RouterCapabilities Execution ACL Tests', () {
    test(
      'Default LuCI file permissions without /bin/sh report hasFileExec as false',
      () {
        // Standard OpenWrt LuCI only whitelists /bin/ping and /bin/traceroute
        final defaultLuciCaps = RouterCapabilities(
          routerId: 'test_router',
          ubusObjects: const {'file', 'system', 'luci-rpc'},
          ubusMethods: const {
            'file': ['exec', 'read', 'stat'],
          },
          filePermissions: const {
            '/bin/ping': ['exec'],
            '/usr/bin/ping': ['exec'],
            '/bin/traceroute': ['exec'],
          },
          probedAt: DateTime.now(),
        );

        expect(defaultLuciCaps.hasLuciRpc, isTrue);
        expect(defaultLuciCaps.canExecCommand('/bin/ping'), isTrue);
        expect(defaultLuciCaps.canExecCommand('/bin/sh'), isFalse);
        expect(defaultLuciCaps.canExecCommand('/usr/bin/curl'), isFalse);
        expect(defaultLuciCaps.hasFileExec, isFalse);
        expect(defaultLuciCaps.isRpcComplete, isFalse);
      },
    );

    test(
      'Yala custom ACL file permits /bin/sh and /usr/bin/curl with hasFileExec as true',
      () {
        final yalaAclCaps = RouterCapabilities(
          routerId: 'test_router',
          ubusObjects: const {'file', 'system', 'luci-rpc'},
          ubusMethods: const {
            'file': ['exec', 'read', 'stat'],
          },
          filePermissions: const {
            '/bin/*': ['exec'],
            '/usr/bin/*': ['exec'],
            '/bin/sh': ['exec'],
            '/usr/bin/curl': ['exec'],
          },
          probedAt: DateTime.now(),
        );

        expect(yalaAclCaps.canExecCommand('/bin/sh'), isTrue);
        expect(yalaAclCaps.canExecCommand('/usr/bin/curl'), isTrue);
        expect(yalaAclCaps.hasFileExec, isTrue);
        expect(yalaAclCaps.isRpcComplete, isTrue);
      },
    );
  });

  group('SpeedTestController Tests', () {
    test('startTest executes test and emits progress events', () async {
      final fake = _FakeSpeedTestService();
      final controller = SpeedTestController(fake);

      expect(controller.state.isRunning, isFalse);
      expect(controller.state.result, isNull);

      final future = controller.startTest();
      expect(controller.state.isRunning, isTrue);

      await future;

      expect(controller.state.isRunning, isFalse);
      expect(controller.state.result, isNotNull);
      expect(controller.state.result!.downloadSpeedMbps, equals(85.4));
      expect(controller.state.result!.uploadSpeedMbps, equals(42.1));
      expect(
        controller.state.result!.vantagePoint,
        equals('Device Internet Speed Test'),
      );
      expect(controller.state.result!.isSuccess, isTrue);
      expect(fake.runCount, equals(1));
    });

    test(
      'Single-flight lock prevents duplicate concurrent test runs',
      () async {
        final fake = _FakeSpeedTestService();
        final controller = SpeedTestController(fake);

        final f1 = controller.startTest();
        // Concurrent second invocation
        final f2 = controller.startTest();

        await Future.wait([f1, f2]);
        // Only 1 execution should have taken place
        expect(fake.runCount, equals(1));
      },
    );

    test('Cancellation stops test and marks state correctly', () async {
      final fake = _FakeSpeedTestService();
      final controller = SpeedTestController(fake);

      final future = controller.startTest();
      controller.cancelTest();

      await future;
      expect(fake.isCancelled, isTrue);
      expect(controller.state.isRunning, isFalse);
    });

    test(
      'Handles upload failure while preserving completed download',
      () async {
        final fake = _FakeSpeedTestService()..failUploadOnly = true;
        final controller = SpeedTestController(fake);

        await controller.startTest();

        expect(controller.state.isRunning, isFalse);
        expect(controller.state.result?.downloadSpeedMbps, equals(85.4));
        expect(controller.state.result?.uploadSpeedMbps, isNull);
        expect(
          controller.state.result?.errorMessage,
          contains('Upload failed'),
        );
      },
    );
  });

  group('SpeedTestController Router Profile Isolation Tests', () {
    setUp(() {
      SpeedTestController.clearCache();
    });

    tearDown(() {
      SpeedTestController.clearCache();
    });

    test(
      'Results are scoped per router profile and do not leak when switching profiles',
      () async {
        final fakeService = _FakeSpeedTestService();

        // 1. Production router ('router-prod-1') runs speed test
        final prodController = SpeedTestController(
          fakeService,
          null,
          'router-prod-1',
        );
        expect(prodController.state.result, isNull);

        await prodController.startTest();
        expect(prodController.state.result, isNotNull);
        expect(prodController.state.result?.downloadSpeedMbps, equals(85.4));
        expect(SpeedTestController.getCachedResult('router-prod-1'), isNotNull);

        // 2. Switch to Test Router profile ('router-test-2')
        final testController = SpeedTestController(
          fakeService,
          null,
          'router-test-2',
        );
        // Must NOT leak production router results!
        expect(testController.state.result, isNull);
        expect(testController.state.isRunning, isFalse);
        expect(SpeedTestController.getCachedResult('router-test-2'), isNull);

        // 3. Switch back to Production Router profile ('router-prod-1')
        final prodRestoredController = SpeedTestController(
          fakeService,
          null,
          'router-prod-1',
        );
        // Must restore production router result!
        expect(prodRestoredController.state.result, isNotNull);
        expect(
          prodRestoredController.state.result?.downloadSpeedMbps,
          equals(85.4),
        );
      },
    );

    test('clearCache clears all router profiles', () async {
      final fakeService = _FakeSpeedTestService();
      final c1 = SpeedTestController(fakeService, null, 'router-1');
      await c1.startTest();

      final c2 = SpeedTestController(fakeService, null, 'router-2');
      await c2.startTest();

      expect(SpeedTestController.getCachedResult('router-1'), isNotNull);
      expect(SpeedTestController.getCachedResult('router-2'), isNotNull);

      SpeedTestController.clearCache();

      expect(SpeedTestController.getCachedResult('router-1'), isNull);
      expect(SpeedTestController.getCachedResult('router-2'), isNull);
    });

    test('reset clears only the active router cached result', () async {
      final fakeService = _FakeSpeedTestService();
      final c1 = SpeedTestController(fakeService, null, 'router-1');
      await c1.startTest();

      final c2 = SpeedTestController(fakeService, null, 'router-2');
      await c2.startTest();

      expect(SpeedTestController.getCachedResult('router-1'), isNotNull);
      expect(SpeedTestController.getCachedResult('router-2'), isNotNull);

      c1.reset();

      expect(c1.state.result, isNull);
      expect(SpeedTestController.getCachedResult('router-1'), isNull);
      // router-2 must remain cached!
      expect(SpeedTestController.getCachedResult('router-2'), isNotNull);
    });
  });

  group('SpeedTestService Dynamic Upload Sizing Math Tests', () {
    test('computeSafeLimitBytes returns 0 when tmpfsFreeKb < 4096', () {
      final limit = SpeedTestService.computeSafeLimitBytes(
        tmpfsFreeKb: 3608,
        memAvailKb: 17204,
        memTotalKb: 55796,
      );
      expect(limit, equals(0));
    });

    test(
      'computeSafeLimitBytes calculates exact safe limit for test router',
      () {
        // tmpfs: 26084, avail: 17204, total: 55796
        // T = floor(0.50 * (26084 - 3072)) = 11506
        // R = floor(0.30 * (17204 - 10240)) = 2089
        // safeLimitKb = min(11506, 2089, 65536) = 2089
        // safeLimitBytes = 2089 * 1024 = 2139136 (~2.04 MiB)
        final limit = SpeedTestService.computeSafeLimitBytes(
          tmpfsFreeKb: 26084,
          memAvailKb: 17204,
          memTotalKb: 55796,
        );
        expect(limit, equals(2089 * 1024));
      },
    );

    test(
      'computeSafeLimitBytes calculates exact safe limit for production router',
      () {
        // tmpfs: 120904, avail: 68892, total: 246112
        // T = floor(0.50 * (120904 - 3072)) = 58916
        // R = floor(0.30 * (68892 - 10240)) = 17595
        // safeLimitKb = min(58916, 17595, 65536) = 17595
        // safeLimitBytes = 17595 * 1024 = 18017280 (~17.18 MiB)
        final limit = SpeedTestService.computeSafeLimitBytes(
          tmpfsFreeKb: 120904,
          memAvailKb: 68892,
          memTotalKb: 246112,
        );
        expect(limit, equals(17595 * 1024));
      },
    );

    test(
      'computeSafeLimitBytes caps safe limit at 64 MiB for high-end router',
      () {
        // tmpfs: 1500000, avail: 2000000, total: 4000000
        // safeLimitKb = 65536
        // safeLimitBytes = 65536 * 1024 = 67108864 (64.0 MiB)
        final limit = SpeedTestService.computeSafeLimitBytes(
          tmpfsFreeKb: 1500000,
          memAvailKb: 2000000,
          memTotalKb: 4000000,
        );
        expect(limit, equals(65536 * 1024));
      },
    );

    test(
      'computeSafeLimitBytes falls back to 8% of MemTotal when MemAvailable is 0',
      () {
        // tmpfs: 50000, avail: 0, total: 65536
        // T = floor(0.50 * (50000 - 3072)) = 23464
        // R = floor(0.08 * 65536) = 5242
        // safeLimitKb = min(23464, 5242, 65536) = 5242
        final limit = SpeedTestService.computeSafeLimitBytes(
          tmpfsFreeKb: 50000,
          memAvailKb: 0,
          memTotalKb: 65536,
        );
        expect(limit, equals(5242 * 1024));
      },
    );

    test('computeSafeLimitBytes returns 0 when safeLimitKb < 1024', () {
      // tmpfs: 4500, avail: 11000, total: 65536
      // T = floor(0.50 * (4500 - 3072)) = 714
      // safeLimitKb = min(714, ...) = 714 < 1024 -> 0
      final limit = SpeedTestService.computeSafeLimitBytes(
        tmpfsFreeKb: 4500,
        memAvailKb: 11000,
        memTotalKb: 65536,
      );
      expect(limit, equals(0));
    });
  });

  group('UploadStrategy Determination Tests', () {
    test('returns fileBased when safeLimitBytes >= 1 MiB', () {
      expect(
        SpeedTestService.determineUploadStrategy(
          safeLimitBytes: 1048576,
          hasCurl: false,
        ),
        equals(UploadStrategy.fileBased),
      );
      expect(
        SpeedTestService.determineUploadStrategy(
          safeLimitBytes: 2097152,
          hasCurl: true,
        ),
        equals(UploadStrategy.fileBased),
      );
    });

    test(
      'returns chunkedStream when safeLimitBytes < 1 MiB and hasCurl is true',
      () {
        expect(
          SpeedTestService.determineUploadStrategy(
            safeLimitBytes: 0,
            hasCurl: true,
          ),
          equals(UploadStrategy.chunkedStream),
        );
        expect(
          SpeedTestService.determineUploadStrategy(
            safeLimitBytes: 500000,
            hasCurl: true,
          ),
          equals(UploadStrategy.chunkedStream),
        );
      },
    );

    test(
      'returns unavailable when safeLimitBytes < 1 MiB and hasCurl is false',
      () {
        expect(
          SpeedTestService.determineUploadStrategy(
            safeLimitBytes: 0,
            hasCurl: false,
          ),
          equals(UploadStrategy.unavailable),
        );
        expect(
          SpeedTestService.determineUploadStrategy(
            safeLimitBytes: 500000,
            hasCurl: false,
          ),
          equals(UploadStrategy.unavailable),
        );
      },
    );
  });

  group('Upload Target Sizing Tests', () {
    test('returns 0 for unavailable strategy', () {
      final bytes = SpeedTestService.computeUploadTargetBytes(
        strategy: UploadStrategy.unavailable,
        safeLimitBytes: 0,
        detectedSpeedMbps: 50.0,
      );
      expect(bytes, equals(0));
    });

    test(
      'bounds desired bytes to safe limit on high-speed line for low-memory router',
      () {
        // 1 Gbps line on test router (safeLimit = 2,139,136 bytes)
        // Desired = 1000 * 125,000 * 4 = 500 MB
        // Must be capped at safeLimitBytes
        const safeLimit = 2089 * 1024;
        final bytes = SpeedTestService.computeUploadTargetBytes(
          strategy: UploadStrategy.fileBased,
          safeLimitBytes: safeLimit,
          detectedSpeedMbps: 1000.0,
        );
        expect(bytes, equals(safeLimit));
      },
    );

    test(
      'bounds desired bytes to reasonable size on slow line for high-memory router',
      () {
        // 5 Mbps line on production router (safeLimit = 18,017,280 bytes)
        // Desired = 5 * 125,000 * 4 = 2,500,000 bytes (~2.5 MB)
        // Must not allocate full 18 MB!
        const safeLimit = 17595 * 1024;
        final bytes = SpeedTestService.computeUploadTargetBytes(
          strategy: UploadStrategy.fileBased,
          safeLimitBytes: safeLimit,
          detectedSpeedMbps: 5.0,
        );
        expect(bytes, equals(2500000));
      },
    );

    test('uses 4 MiB baseline for chunkedStream when speed is unknown', () {
      final bytes = SpeedTestService.computeUploadTargetBytes(
        strategy: UploadStrategy.chunkedStream,
        safeLimitBytes: 0,
        detectedSpeedMbps: null,
      );
      expect(bytes, equals(4194304));
    });

    test('never throws ArgumentError for edge case inputs', () {
      expect(
        () => SpeedTestService.computeUploadTargetBytes(
          strategy: UploadStrategy.fileBased,
          safeLimitBytes: 0,
          detectedSpeedMbps: null,
        ),
        returnsNormally,
      );
      expect(
        () => SpeedTestService.computeUploadTargetBytes(
          strategy: UploadStrategy.fileBased,
          safeLimitBytes: 500000,
          detectedSpeedMbps: 0.1,
        ),
        returnsNormally,
      );
    });
  });

  group('SpeedTestService Router WAN Tests', () {
    test(
      'Executes uclient-fetch fallback when curl is missing (exit code 127)',
      () async {
        final executedCommands = <String>[];
        final api = _StubRouterSpeedTestApiService(
          onFileExec: (command, args) async {
            final cmd = args.join(' ');
            executedCommands.add(cmd);
            if (cmd.contains('df -k /tmp') || cmd.contains('/proc/meminfo')) {
              return [
                0,
                {
                  'code': 0,
                  'stdout': '26084\n55796 17204\nmips\n0\n1\n',
                  'stderr': '',
                },
              ];
            }
            if (cmd.contains('curl')) {
              // Simulate missing curl on router
              return [
                0,
                {'code': 127, 'stdout': '', 'stderr': 'ash: curl: not found'},
              ];
            }
            if (cmd.contains('uclient-fetch') || cmd.contains('wget')) {
              // Simulate realistic network delay for Stopwatch
              await Future.delayed(const Duration(milliseconds: 60));
              return [
                0,
                {
                  'code': 0,
                  'stdout': '',
                  'stderr': 'real 0.40\nuser 0.05\nsys 0.25\n',
                },
              ];
            }
            return [
              0,
              {'code': 0, 'stdout': '', 'stderr': ''},
            ];
          },
        );

        final service = SpeedTestService();
        final result = await service.runRouterSpeedTest(
          api: api,
          routerIp: '192.168.1.1',
          sysauth: 'test_token',
          useHttps: false,
        );

        expect(result.stage, equals(SpeedTestStage.completed));
        expect(result.downloadSpeedMbps, isNotNull);
        expect(result.uploadSpeedMbps, isNotNull);
        expect(result.uploadSpeedMbps! > 0, isTrue);
        // Verify uclient-fetch / wget was invoked for upload
        expect(
          executedCommands.any(
            (c) =>
                c.contains('speed_up') &&
                (c.contains('uclient-fetch') || c.contains('wget')),
          ),
          isTrue,
        );
      },
    );

    test(
      'Upload failure sets uploadSpeedMbps to null and preserves download without throwing',
      () async {
        final api = _StubRouterSpeedTestApiService(
          onFileExec: (command, args) async {
            final cmd = args.join(' ');
            if (cmd.contains('df -k /tmp') || cmd.contains('/proc/meminfo')) {
              return [
                0,
                {
                  'code': 0,
                  'stdout': '26084\n55796 17204\nmips\n0\n1\n',
                  'stderr': '',
                },
              ];
            }
            if (cmd.contains('speed_up')) {
              // All upload attempts fail
              return [
                0,
                {'code': 127, 'stdout': '', 'stderr': 'ash: command not found'},
              ];
            }
            // Download succeeds
            if (cmd.contains('__down')) {
              await Future.delayed(const Duration(milliseconds: 60));
              return [
                0,
                {'code': 0, 'stdout': '', 'stderr': ''},
              ];
            }
            return [
              0,
              {'code': 0, 'stdout': '', 'stderr': ''},
            ];
          },
        );

        final service = SpeedTestService();
        final result = await service.runRouterSpeedTest(
          api: api,
          routerIp: '192.168.1.1',
          sysauth: 'test_token',
          useHttps: false,
        );

        expect(result.stage, equals(SpeedTestStage.completed));
        expect(result.downloadSpeedMbps, isNotNull);
        expect(result.uploadSpeedMbps, isNull);
        expect(result.errorMessage, contains('upload measurement failed'));
      },
    );

    test(
      'Executes chunked streaming via curl when tmpfs is low and curl is present',
      () async {
        final executedCommands = <String>[];
        final api = _StubRouterSpeedTestApiService(
          onFileExec: (command, args) async {
            final cmd = args.join(' ');
            executedCommands.add(cmd);
            if (cmd.contains('df -k /tmp') || cmd.contains('/proc/meminfo')) {
              // Free tmpfs 2000 KiB (< 4096 KiB) but curl is present
              return [
                0,
                {
                  'code': 0,
                  'stdout': '2000\n246112 68892\narmv7l\n1\n4\n',
                  'stderr': '',
                },
              ];
            }
            if (cmd.contains('__down')) {
              await Future.delayed(const Duration(milliseconds: 60));
              return [
                0,
                {
                  'code': 0,
                  'stdout': '0.25 0.02 10000000 40000000 200',
                  'stderr': '',
                },
              ];
            }
            if (cmd.contains('-X POST -T -')) {
              // Chunked streaming upload succeeds
              return [
                0,
                {
                  'code': 0,
                  'stdout': '0.28 0.02 4194304 15000000 200',
                  'stderr': '',
                },
              ];
            }
            return [
              0,
              {'code': 0, 'stdout': '', 'stderr': ''},
            ];
          },
        );

        final service = SpeedTestService();
        final result = await service.runRouterSpeedTest(
          api: api,
          routerIp: '192.168.1.1',
          sysauth: 'test_token',
          useHttps: false,
        );

        expect(result.stage, equals(SpeedTestStage.completed));
        expect(result.downloadSpeedMbps, isNotNull);
        expect(result.uploadSpeedMbps, isNotNull);
        expect(result.uploadSpeedMbps! > 0, isTrue);
        // Verify curl streaming was used
        expect(executedCommands.any((c) => c.contains('-X POST -T -')), isTrue);
        // Verify no temp file was written into tmpfs
        expect(
          executedCommands.any((c) => c.contains('of=/tmp/speed_up')),
          isFalse,
        );
      },
    );

    test(
      'Safely marks upload as unavailable when tmpfs is low and curl is missing',
      () async {
        final executedCommands = <String>[];
        final api = _StubRouterSpeedTestApiService(
          onFileExec: (command, args) async {
            final cmd = args.join(' ');
            executedCommands.add(cmd);
            if (cmd.contains('df -k /tmp') || cmd.contains('/proc/meminfo')) {
              // Free tmpfs 2000 KiB (< 4096 KiB) and curl is missing
              return [
                0,
                {
                  'code': 0,
                  'stdout': '2000\n55796 17204\nmips\n0\n1\n',
                  'stderr': '',
                },
              ];
            }
            if (cmd.contains('__down')) {
              await Future.delayed(const Duration(milliseconds: 60));
              return [
                0,
                {
                  'code': 0,
                  'stdout': '0.30 0.03 10000000 33000000 200',
                  'stderr': '',
                },
              ];
            }
            return [
              0,
              {'code': 0, 'stdout': '', 'stderr': ''},
            ];
          },
        );

        final service = SpeedTestService();
        final result = await service.runRouterSpeedTest(
          api: api,
          routerIp: '192.168.1.1',
          sysauth: 'test_token',
          useHttps: false,
        );

        expect(result.stage, equals(SpeedTestStage.completed));
        expect(result.downloadSpeedMbps, isNotNull);
        expect(result.uploadSpeedMbps, isNull);
        expect(result.errorMessage, contains('insufficient router memory'));
        // Verify no upload transfer command was executed (excluding final cleanup)
        expect(
          executedCommands.any(
            (c) =>
                (c.contains('dd') && c.contains('speed_up')) ||
                c.contains('-X POST -T -') ||
                c.contains('--post-file='),
          ),
          isFalse,
        );
      },
    );

    test(
      'Rejects zero-byte upload transfer even if process exits with 0',
      () async {
        final api = _StubRouterSpeedTestApiService(
          onFileExec: (command, args) async {
            final cmd = args.join(' ');
            if (cmd.contains('df -k /tmp') || cmd.contains('/proc/meminfo')) {
              return [
                0,
                {
                  'code': 0,
                  'stdout': '26084\n55796 17204\nmips\n1\n1\n',
                  'stderr': '',
                },
              ];
            }
            if (cmd.contains('__down')) {
              return [
                0,
                {
                  'code': 0,
                  'stdout': '0.25 0.02 10000000 40000000 200',
                  'stderr': '',
                },
              ];
            }
            if (cmd.contains('speed_up')) {
              // Simulates zero-byte upload returning exit code 0
              return [
                0,
                {'code': 0, 'stdout': '0.10 0.01 0 0 200', 'stderr': ''},
              ];
            }
            return [
              0,
              {'code': 0, 'stdout': '', 'stderr': ''},
            ];
          },
        );

        final service = SpeedTestService();
        final result = await service.runRouterSpeedTest(
          api: api,
          routerIp: '192.168.1.1',
          sysauth: 'test_token',
          useHttps: false,
        );

        expect(result.stage, equals(SpeedTestStage.completed));
        expect(result.downloadSpeedMbps, isNotNull);
        // Upload sample of 0 bytes must be rejected!
        expect(result.uploadSpeedMbps, isNull);
      },
    );
  });
}

class _StubRouterSpeedTestApiService extends MockApiService {
  final dynamic Function(String command, List<String> args) onFileExec;

  _StubRouterSpeedTestApiService({required this.onFileExec});

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    if (object == 'file' && method == 'exec') {
      final command = params?['command'] as String? ?? '';
      final paramsList =
          ((params?['params'] ?? params?['args']) as List?)?.cast<String>() ??
          [];
      return onFileExec(command, paramsList);
    }
    return super.call(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }
}
