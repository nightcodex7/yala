// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

void main() {
  group('Localization Coverage Validation Tests', () {
    test(
      '1. Verify Chinese (zh) translations exist and match expected texts',
      () async {
        final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

        expect(l10n.routerSecuritySection, equals('路由器安全与访问'));
        expect(l10n.changePasswordSubtitle, equals('更新当前活动路由器的 root/admin 密码'));
        expect(l10n.rpcPermissionsVerified, equals('RPC 权限与执行模块已验证'));
        expect(l10n.privacyPolicyTitle, equals('隐私政策'));
        expect(l10n.privacyPolicySubtitle, equals('阅读我们本地优先的零遥测隐私策略'));
        expect(l10n.licenseAttributionTitle, equals('许可与版权信息 (GPLv3)'));
        expect(l10n.openSourceLicensesTitle, equals('开源许可'));

        // RPC Dialog strings
        expect(
          l10n.rpcDialogVerifiedSubtitle,
          equals('路由器 RPC 模块与后端执行权限已通过验证并正常运行。'),
        );
        expect(l10n.rpcStatusLuciRpc, equals('LuCI RPC 模块'));
        expect(l10n.rpcStatusBackendExec, equals('后端执行权限'));
        expect(l10n.rpcStatusUciAccess, equals('UCI 配置访问'));
        expect(l10n.rpcManualSetupScript, equals('手动安装 / 验证脚本'));
        expect(l10n.rpcBtnReverifyRepair, equals('重新验证 / 修复'));
      },
    );

    test(
      '2. Verify Russian (ru) translations exist and match expected texts',
      () async {
        final l10n = await AppLocalizations.delegate.load(const Locale('ru'));

        expect(
          l10n.routerSecuritySection,
          equals('БЕЗОПАСНОСТЬ И ДОСТУП К РОУТЕРУ'),
        );
        expect(l10n.privacyPolicyTitle, equals('Политика конфиденциальности'));
        expect(l10n.termsAndConditionsTitle, equals('Условия использования'));
        expect(
          l10n.loginFailedSession('ncxTest (192.168.1.1)'),
          equals('Не удалось установить сессию с ncxTest (192.168.1.1).'),
        );
        expect(
          l10n.loginInvalidCredentials,
          equals(
            'Вход не удался: неверные учетные данные или хост недоступен.',
          ),
        );
        expect(l10n.rpcBtnReverifyRepair, equals('Повторить / Восстановить'));
      },
    );

    test(
      '2b. Verify Ukrainian (uk) translations exist and match expected texts',
      () async {
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(
          l10n.routerSecuritySection,
          equals('БЕЗПЕКА ТА ДОСТУП ДО МАРШРУТИЗАТОРА'),
        );
        expect(l10n.privacyPolicyTitle, equals('Політика конфіденційності'));
        expect(l10n.termsAndConditionsTitle, equals('Умови використання'));
        expect(
          l10n.loginFailedSession('ncxTest (192.168.1.1)'),
          equals('Не вдалося встановити сеанс із ncxTest (192.168.1.1).'),
        );
        expect(
          l10n.rpcBtnReverifyRepair,
          equals('Перевірити знову / Відновити'),
        );
      },
    );

    test(
      '3. Verify all 10 supported locales load all new keys without missing any',
      () async {
        for (final locale in AppLocalizations.supportedLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);

          expect(l10n.routerSecuritySection.isNotEmpty, isTrue);
          expect(l10n.changePasswordSubtitle.isNotEmpty, isTrue);
          expect(l10n.rpcPermissionsVerified.isNotEmpty, isTrue);
          expect(l10n.privacyPolicyTitle.isNotEmpty, isTrue);
          expect(l10n.privacyPolicySubtitle.isNotEmpty, isTrue);
          expect(l10n.licenseAttributionTitle.isNotEmpty, isTrue);
          expect(l10n.openSourceLicensesTitle.isNotEmpty, isTrue);
          expect(l10n.rpcDialogVerifiedSubtitle.isNotEmpty, isTrue);
          expect(l10n.rpcStatusLuciRpc.isNotEmpty, isTrue);
          expect(l10n.rpcStatusBackendExec.isNotEmpty, isTrue);
          expect(l10n.rpcStatusUciAccess.isNotEmpty, isTrue);
          expect(l10n.rpcManualSetupScript.isNotEmpty, isTrue);
          expect(l10n.rpcBtnReverifyRepair.isNotEmpty, isTrue);
          expect(l10n.loginFailedSession('router').isNotEmpty, isTrue);
          expect(l10n.loginInvalidCredentials.isNotEmpty, isTrue);
          expect(l10n.checkForUpdatesSubtitleIpa.isNotEmpty, isTrue);
          expect(l10n.updateAvailableIosBetaTitle.isNotEmpty, isTrue);
          expect(l10n.updateAvailableIosBetaDesc.isNotEmpty, isTrue);
          expect(l10n.updateRedirectToRelease.isNotEmpty, isTrue);
          expect(l10n.updateNoBetaReleasesFound.isNotEmpty, isTrue);
          expect(l10n.updateUpToDateIosDesc('2.5.1').isNotEmpty, isTrue);
          expect(l10n.updateNoBetaUpdateRequired('2.5.1').isNotEmpty, isTrue);
        }
      },
    );

    testWidgets('4. Widget renders Chinese localized strings cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
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
                final l10n = AppLocalizations.of(context)!;
                return Column(
                  children: [
                    Text(l10n.routerSecuritySection),
                    Text(l10n.privacyPolicyTitle),
                    Text(l10n.rpcDialogVerifiedSubtitle),
                    Text(l10n.rpcBtnReverifyRepair),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('路由器安全与访问'), findsOneWidget);
      expect(find.text('隐私政策'), findsOneWidget);
      expect(find.text('路由器 RPC 模块与后端执行权限已通过验证并正常运行。'), findsOneWidget);
      expect(find.text('重新验证 / 修复'), findsOneWidget);
    });

    testWidgets(
      '5. Widget renders Russian localized login error banner cleanly',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ru'),
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
                  final l10n = AppLocalizations.of(context)!;
                  return Column(
                    children: [
                      Text(l10n.loginFailedSession('ncxTest (192.168.1.1)')),
                      Text(l10n.privacyPolicyTitle),
                      Text(l10n.termsAndConditionsTitle),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Не удалось установить сессию с ncxTest (192.168.1.1).'),
          findsOneWidget,
        );
        expect(find.text('Политика конфиденциальности'), findsOneWidget);
        expect(find.text('Условия использования'), findsOneWidget);
      },
    );
  });
}
