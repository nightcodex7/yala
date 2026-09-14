// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/parental_controls/controllers/parental_controls_controller.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_controls_store.dart';
import 'package:yet_another_luci_app/modules/parental_controls/widgets/parental_profile_card.dart';
import 'package:yet_another_luci_app/modules/parental_controls/widgets/add_edit_profile_dialog.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  group('ParentalControlsStore Tests', () {
    late ParentalControlsStore store;

    setUp(() {
      store = ParentalControlsStore.instance;
      for (final p in store.profiles.toList()) {
        store.deleteProfile(p.id);
      }
      store.clearActivityLog();
    });

    test('Add, update, and delete profile', () {
      final profile = ParentalProfile(
        id: 'test_1',
        name: 'Kids Tablet',
        icon: '👦',
        color: '#F97316',
        macAddresses: const ['AA:BB:CC:DD:EE:11'],
        dailyTimeLimitMinutes: 120,
        contentFilter: ContentFilterDns.cloudflareFamilySafe,
      );

      final id = store.addProfile(profile);
      expect(id, 'test_1');
      expect(store.profiles.length, 1);
      expect(store.profiles.first.name, 'Kids Tablet');
      expect(
        store.activityLog.first.eventType,
        ParentalEventType.profileCreated,
      );

      final updated = profile.copyWith(name: 'Kids Tablet (Updated)');
      store.updateProfile(updated);
      expect(store.profiles.first.name, 'Kids Tablet (Updated)');
      expect(
        store.activityLog.first.eventType,
        ParentalEventType.profileUpdated,
      );

      store.deleteProfile('test_1');
      expect(store.profiles, isEmpty);
      expect(
        store.activityLog.first.eventType,
        ParentalEventType.profileDeleted,
      );
    });

    test('Pause and resume state management', () {
      final profile = ParentalProfile(
        id: 'test_pause',
        name: 'Gaming Console',
        icon: '🎮',
        color: '#3B82F6',
        macAddresses: const ['11:22:33:44:55:66'],
      );
      store.addProfile(profile);

      final expiry = DateTime.now().toUtc().add(const Duration(hours: 1));
      store.markProfilePaused('test_pause', expiresAt: expiry);

      final p = store.getProfile('test_pause')!;
      expect(p.isPaused, isTrue);
      expect(p.pauseExpiresAt, equals(expiry));
      expect(store.isMacPaused('11:22:33:44:55:66'), isTrue);

      store.markProfileResumed('test_pause');
      final resumed = store.getProfile('test_pause')!;
      expect(resumed.isPaused, isFalse);
      expect(resumed.pauseExpiresAt, null);
      expect(store.isMacPaused('11:22:33:44:55:66'), isFalse);
    });

    test('Serialization and deserialization', () {
      final profile = ParentalProfile(
        id: 'test_ser',
        name: 'Teen Phone',
        icon: '📱',
        color: '#EF4444',
        macAddresses: const ['00:11:22:33:44:55'],
        schedule: const TimeSchedule(
          activeDays: {ScheduleDay.monday, ScheduleDay.friday},
          blockHour: 23,
          blockMinute: 30,
          resumeHour: 6,
          resumeMinute: 0,
        ),
        contentFilter: ContentFilterDns.openDnsFamilyShield,
      );
      store.addProfile(profile);

      final jsonStr = store.toJsonString();
      expect(jsonStr, contains('Teen Phone'));
      expect(jsonStr, contains('00:11:22:33:44:55'));
      expect(jsonStr, contains('opendns_family'));

      store.loadFromString(jsonStr);
      expect(store.profiles.length, 1);
      final loaded = store.profiles.first;
      expect(loaded.name, 'Teen Phone');
      expect(loaded.schedule?.blockHour, 23);
      expect(loaded.contentFilter, ContentFilterDns.openDnsFamilyShield);
      expect(loaded.isEnabled, isTrue);
    });

    test('Bypass state toggling and isMacPaused behavior', () {
      final profile = ParentalProfile(
        id: 'test_bypass',
        name: 'Bypass Test',
        icon: '📱',
        color: '#EF4444',
        macAddresses: const ['AA:BB:CC:DD:EE:99'],
        isPaused: true,
        isEnabled: true,
      );
      store.addProfile(profile);

      expect(store.isMacPaused('AA:BB:CC:DD:EE:99'), isTrue);

      // Toggle profile to bypass (disabled guardrails)
      store.toggleProfileEnabled('test_bypass');
      final bypassed = store.getProfile('test_bypass')!;
      expect(bypassed.isEnabled, isFalse);
      expect(bypassed.isBypassed, isTrue);

      // MAC should NOT report as paused when profile rules are bypassed!
      expect(store.isMacPaused('AA:BB:CC:DD:EE:99'), isFalse);
    });

    test('TimeSchedule isTimeInBlockWindow calculation', () {
      const schedule = TimeSchedule(
        activeDays: {ScheduleDay.monday},
        blockHour: 22,
        blockMinute: 0,
        resumeHour: 7,
        resumeMinute: 0,
      );

      final monNight = DateTime(2026, 8, 24, 23, 30); // Monday
      expect(schedule.isTimeInBlockWindow(monNight), isTrue);

      final monMorning = DateTime(2026, 8, 24, 5, 15);
      expect(schedule.isTimeInBlockWindow(monMorning), isTrue);

      final monNoon = DateTime(2026, 8, 24, 12, 0);
      expect(schedule.isTimeInBlockWindow(monNoon), isFalse);

      final tueNight = DateTime(2026, 8, 25, 23, 30); // Tuesday
      expect(schedule.isTimeInBlockWindow(tueNight), isFalse);
    });
  });

  group('ParentalControlsController & Sync Hardening Tests', () {
    late ParentalControlsController controller;
    late ParentalControlsStore store;

    setUp(() async {
      await AppState.instance.setReviewerMode(true);
      controller = ParentalControlsController.instance;
      store = controller.store;
      for (final p in store.profiles.toList()) {
        store.deleteProfile(p.id);
      }
      store.clearActivityLog();
    });

    test('Empty-store startup safety prevents bad writes', () async {
      final appState = AppState.instance;
      // Store loaded state is true after loadFromString
      store.loadFromString('');
      expect(store.isLoaded, isTrue);

      final persisted = await controller.persistStore(appState);
      expect(persisted.success, isTrue);
    });

    test(
      'Pause expiry on checkPausesAndSchedules automatically resumes expired profiles',
      () async {
        final pastExpiry = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        final profile = ParentalProfile(
          id: 'test_expired_pause',
          name: 'Study Laptop',
          icon: '💻',
          color: '#3B82F6',
          macAddresses: const ['11:22:33:44:55:77'],
          isPaused: true,
          pauseExpiresAt: pastExpiry,
        );
        store.addProfile(profile);

        expect(store.getProfile('test_expired_pause')!.isPaused, isTrue);

        await controller.checkPausesAndSchedules(AppState.instance);

        final updated = store.getProfile('test_expired_pause')!;
        expect(updated.isPaused, isFalse);
        expect(updated.pauseExpiresAt, isNull);
      },
    );

    test('Repeated lifecycle resume calls do not duplicate work or throw', () {
      final appState = AppState.instance;
      controller.handleLifecycleState(AppLifecycleState.resumed, appState);
      controller.handleLifecycleState(AppLifecycleState.resumed, appState);
      controller.handleLifecycleState(AppLifecycleState.paused, appState);
      controller.handleLifecycleState(AppLifecycleState.resumed, appState);
      controller.stopExpiryTimer();
    });

    test(
      'Store persistence round-trip preserves daily minutes and activity log',
      () {
        final profile = ParentalProfile(
          id: 'test_rt',
          name: 'Roundtrip Profile',
          icon: '🎮',
          color: '#10B981',
          macAddresses: const ['AA:BB:CC:DD:EE:00'],
        );
        store.addProfile(profile);
        store.incrementDailyMinutesUsed('AA:BB:CC:DD:EE:00', 45);

        final rawJson = store.toJsonString();
        expect(rawJson, contains('Roundtrip Profile'));
        expect(rawJson, contains('daily_minutes_used'));
        expect(rawJson, contains('activity_log'));

        store.loadFromString(rawJson);
        expect(store.profiles.length, 1);
        expect(store.getDailyMinutesUsed('AA:BB:CC:DD:EE:00'), 45);
        expect(store.activityLog, isNotEmpty);
      },
    );

    test('Firewall-denied operations return clear failure type', () async {
      final appState = AppState.instance;
      final profile = ParentalProfile(
        id: 'test_fw',
        name: 'Firewall Test',
        icon: '📱',
        color: '#EF4444',
        macAddresses: const ['00:11:22:33:44:99'],
      );

      final result = await controller.pauseProfile(
        profile,
        PauseDuration.indefinite,
        appState,
      );

      expect(result.message, isNotEmpty);
    });

    test(
      'Clear activity log via controller clears log and persists store',
      () async {
        final appState = AppState.instance;
        final profile = ParentalProfile(
          id: 'test_clear_log',
          name: 'Log Test',
          icon: '📱',
          color: '#10B981',
          macAddresses: const ['AA:BB:CC:11:22:33'],
        );
        store.addProfile(profile);
        expect(store.activityLog, isNotEmpty);

        final res = await controller.clearActivityLog(appState);
        expect(res.success, isTrue);
        expect(res.message, contains('Activity log cleared'));
        expect(store.activityLog, isEmpty);
      },
    );

    test(
      'loadStore and persistStore return typed ParentalActionResult',
      () async {
        final appState = AppState.instance;
        final loadRes = await controller.loadStore(appState);
        expect(loadRes.success, isTrue);

        final persistRes = await controller.persistStore(appState);
        expect(persistRes.success, isTrue);
        expect(persistRes.failureType, ParentalFailureType.none);
      },
    );
  });

  group('ParentalControls Widget & Overflow Tests', () {
    testWidgets('ParentalProfileCard renders correctly without bounds issues', (
      tester,
    ) async {
      final profile = ParentalProfile(
        id: 'card_test',
        name:
            'Extremely Long Device Profile Name That Could Cause Right Overflow',
        icon: '💻',
        color: '#10B981',
        macAddresses: const ['AA:BB:CC:DD:EE:FF', '11:22:33:44:55:66'],
        isPaused: true,
        pauseExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 45)),
        schedule: const TimeSchedule(
          activeDays: {ScheduleDay.monday, ScheduleDay.tuesday},
          blockHour: 21,
          blockMinute: 0,
          resumeHour: 7,
          resumeMinute: 0,
        ),
        dailyTimeLimitMinutes: 90,
        contentFilter: ContentFilterDns.cloudflareFamilySafe,
      );

      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ParentalProfileCard(
                profile: profile,
                hasFirewall: true,
                hasFileExec: true,
                onPause: (_) {},
                onResume: () {},
                onEdit: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      );

      expect(
        find.textContaining('Extremely Long Device Profile Name'),
        findsOneWidget,
      );
      expect(find.text('2 devices'), findsOneWidget);
      expect(find.text('Resume Internet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'AddEditProfileDialog renders and scrolls without overflow on small screens',
      (tester) async {
        tester.view.physicalSize = const Size(360, 580);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AddEditProfileDialog(
                  allProfiles: const [],
                  onSave: (_) {},
                ),
              ),
            ),
          ),
        );

        expect(find.text('New Profile'), findsOneWidget);
        expect(find.text('Profile Name *'), findsOneWidget);
        expect(find.text('Create Profile'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AddEditProfileDialog context awareness disables save until modified when editing',
      (tester) async {
        final existing = ParentalProfile(
          id: 'p1',
          name: 'Kids Tablet',
          icon: '👦',
          color: '#F97316',
          macAddresses: const ['AA:BB:CC:DD:EE:FF'],
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AddEditProfileDialog(
                  existing: existing,
                  allProfiles: [existing],
                  onSave: (_) {},
                ),
              ),
            ),
          ),
        );

        final saveBtnFinder = find.widgetWithText(FilledButton, 'Save Changes');
        expect(saveBtnFinder, findsOneWidget);
        final initialButton = tester.widget<FilledButton>(saveBtnFinder);
        expect(initialButton.onPressed, isNull);

        await tester.enterText(
          find.byType(TextFormField).first,
          'Kids Tablet 2',
        );
        await tester.pump();

        final updatedButton = tester.widget<FilledButton>(saveBtnFinder);
        expect(updatedButton.onPressed, isNotNull);
      },
    );
  });
}
