// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Localization and Supported Locales Unit Tests', () {
    test('Supported locales list contains only the approved locales', () {
      const supportedLocales = AppLocalizations.supportedLocales;

      // Extract language & country pairs
      final formatted = supportedLocales.map((l) {
        return l.countryCode != null && l.countryCode!.isNotEmpty
            ? '${l.languageCode}-${l.countryCode}'
            : l.languageCode;
      }).toSet();

      // Expected supported locales:
      // ru, es, pt-BR (and pt fallback), de, id, fr, zh, uk, it, ja, and base en
      final expectedLocales = {
        'ru',
        'es',
        'pt-BR',
        'pt',
        'de',
        'id',
        'fr',
        'zh',
        'uk',
        'it',
        'ja',
        'en',
      };

      expect(formatted, equals(expectedLocales));
      // Ensure exactly 12 entries (11 languages + 1 regional variant)
      expect(supportedLocales.length, 12);
    });

    test('All ARB files exist on filesystem with exact naming', () {
      const arbFiles = [
        'lib/l10n/app_en.arb',
        'lib/l10n/app_ru.arb',
        'lib/l10n/app_es.arb',
        'lib/l10n/app_pt_BR.arb',
        'lib/l10n/app_pt.arb',
        'lib/l10n/app_de.arb',
        'lib/l10n/app_id.arb',
        'lib/l10n/app_fr.arb',
        'lib/l10n/app_zh.arb',
        'lib/l10n/app_uk.arb',
        'lib/l10n/app_it.arb',
        'lib/l10n/app_ja.arb',
      ];

      for (final filePath in arbFiles) {
        final file = File(filePath);
        expect(file.existsSync(), isTrue, reason: 'File $filePath must exist');
      }
    });

    test('Android locales_config.xml exists and matches target locales', () {
      final file = File('android/app/src/main/res/xml/locales_config.xml');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('<locale android:name="en"/>'));
      expect(content, contains('<locale android:name="ru"/>'));
      expect(content, contains('<locale android:name="es"/>'));
      expect(content, contains('<locale android:name="pt-BR"/>'));
      expect(content, contains('<locale android:name="de"/>'));
      expect(content, contains('<locale android:name="id"/>'));
      expect(content, contains('<locale android:name="fr"/>'));
      expect(content, contains('<locale android:name="zh"/>'));
      expect(content, contains('<locale android:name="uk"/>'));
      expect(content, contains('<locale android:name="it"/>'));
      expect(content, contains('<locale android:name="ja"/>'));

      // Ensure no unauthorized languages are present
      expect(content, isNot(contains('<locale android:name="ar"/>')));
    });

    test(
      'Android res values directories and build.gradle.kts cover all 12 locales',
      () {
        const androidLocales = [
          'en',
          'ru',
          'es',
          'pt',
          'pt-rBR',
          'de',
          'id',
          'fr',
          'zh',
          'uk',
          'it',
          'ja',
        ];

        for (final loc in androidLocales) {
          final stringsFile = File(
            'android/app/src/main/res/values-$loc/strings.xml',
          );
          expect(
            stringsFile.existsSync(),
            isTrue,
            reason:
                'values-$loc/strings.xml must exist for Play Store bundle localization detection',
          );
        }

        final gradleFile = File('android/app/build.gradle.kts');
        expect(gradleFile.existsSync(), isTrue);
        final gradleContent = gradleFile.readAsStringSync();
        for (final loc in [
          'en',
          'ru',
          'es',
          'pt',
          'de',
          'id',
          'fr',
          'zh',
          'uk',
          'it',
          'ja',
        ]) {
          expect(
            gradleContent,
            contains('"$loc"'),
            reason:
                'build.gradle.kts resourceConfigurations must include "$loc"',
          );
        }
      },
    );

    test(
      'AppLocalizations delegate loads each target locale properly',
      () async {
        final targetLocales = [
          const Locale('en'),
          const Locale('ru'),
          const Locale('es'),
          const Locale('pt', 'BR'),
          const Locale('de'),
          const Locale('id'),
          const Locale('fr'),
          const Locale('zh'),
          const Locale('uk'),
          const Locale('it'),
          const Locale('ja'),
        ];

        for (final locale in targetLocales) {
          expect(AppLocalizations.delegate.isSupported(locale), isTrue);
          final l10n = await AppLocalizations.delegate.load(locale);
          expect(l10n.appTitle, isNotEmpty);
          expect(l10n.navDashboard, isNotEmpty);
          expect(l10n.navInterfaces, isNotEmpty);
          expect(l10n.navClients, isNotEmpty);
          expect(l10n.navSettings, isNotEmpty);
          expect(l10n.actionSave, isNotEmpty);
          expect(l10n.actionCancel, isNotEmpty);
          expect(l10n.statusConnected, isNotEmpty);
          expect(l10n.languageTitle, isNotEmpty);
        }
      },
    );

    test('Translations match language specific terms', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final ru = await AppLocalizations.delegate.load(const Locale('ru'));
      final es = await AppLocalizations.delegate.load(const Locale('es'));
      final ptBr = await AppLocalizations.delegate.load(
        const Locale('pt', 'BR'),
      );
      final de = await AppLocalizations.delegate.load(const Locale('de'));
      final id = await AppLocalizations.delegate.load(const Locale('id'));
      final fr = await AppLocalizations.delegate.load(const Locale('fr'));
      final it = await AppLocalizations.delegate.load(const Locale('it'));
      final ja = await AppLocalizations.delegate.load(const Locale('ja'));

      // Russian verification
      expect(ru.navDashboard, 'Панель');
      expect(ru.navWireless, 'Wi-Fi');
      expect(ru.colorPalette, 'Цветовая палитра');
      expect(ru.exitDialogTitle, 'Выйти из Yala?');
      expect(ru.actionSave, 'Сохранить');
      expect(ru.actionCancel, 'Отмена');
      expect(ru.actionDismiss, 'Отклонить');
      expect(ru.languageTitle, 'Язык');
      expect(ru.languageSystemDefault, 'Язык системы');

      // Spanish verification
      expect(es.navDashboard, 'Panel');
      expect(es.navWireless, 'Inalámbrico');
      expect(es.colorPalette, 'Paleta de colores');
      expect(es.exitDialogTitle, '¿Salir de Yala?');
      expect(es.actionSave, 'Guardar');
      expect(es.actionCancel, 'Cancelar');
      expect(es.actionDismiss, 'Descartar');
      expect(es.statusOffline, 'Fuera de línea');
      expect(es.languageTitle, 'Idioma');

      // Brazilian Portuguese verification
      expect(ptBr.navDashboard, 'Painel');
      expect(ptBr.navClients, 'Clientes');
      expect(ptBr.navWireless, 'Sem fio');
      expect(ptBr.colorPalette, 'Paleta de cores');
      expect(ptBr.exitDialogTitle, 'Sair do Yala?');
      expect(ptBr.actionSave, 'Salvar');
      expect(ptBr.actionCancel, 'Cancelar');
      expect(ptBr.actionDismiss, 'Dispensar');
      expect(ptBr.languageTitle, 'Idioma');

      // German verification
      expect(de.navDashboard, 'Übersicht');
      expect(de.navWireless, 'WLAN');
      expect(de.colorPalette, 'Farbpalette');
      expect(de.exitDialogTitle, 'Yala beenden?');
      expect(de.actionSave, 'Speichern');
      expect(de.actionCancel, 'Abbrechen');
      expect(de.actionDismiss, 'Verwerfen');
      expect(de.actionRetry, 'Erneut versuchen');
      expect(de.languageTitle, 'Sprache');

      // Indonesian verification
      expect(id.navDashboard, 'Dasbor');
      expect(id.navWireless, 'Nirkabel');
      expect(id.colorPalette, 'Palet Warna');
      expect(id.exitDialogTitle, 'Keluar dari Yala?');
      expect(id.actionSave, 'Simpan');
      expect(id.actionCancel, 'Batal');
      expect(id.actionDismiss, 'Abaikan');
      expect(id.loginAuthenticating, 'Mengautentikasi...');
      expect(id.loginRequiredField, 'Kolom ini wajib diisi');
      expect(id.languageTitle, 'Bahasa');

      // French verification
      expect(fr.navDashboard, 'Tableau');
      expect(fr.navWireless, 'Sans fil');
      expect(fr.colorPalette, 'Palette de couleurs');
      expect(fr.exitDialogTitle, 'Quitter Yala ?');
      expect(fr.actionSave, 'Enregistrer');
      expect(fr.actionCancel, 'Annuler');
      expect(fr.actionDismiss, 'Ignorer');
      expect(fr.languageTitle, 'Langue');

      // Italian verification
      expect(it.navDashboard, 'Dashboard');
      expect(it.navInterfaces, 'Interfacce');
      expect(it.navMore, 'Altro');
      expect(it.settingsTitle, 'Impostazioni');
      expect(it.actionSave, 'Salva');
      expect(it.actionCancel, 'Annulla');
      expect(it.actionDismiss, 'Ignora');
      expect(it.languageTitle, 'Lingua');
      expect(it.logViewerTitle, 'Log di sistema e kernel');
      expect(it.sshTerminalTitle, 'Terminale SSH');
      expect(it.dnsmasqReloadTitle, 'Ricarica servizio DHCP e DNS');

      // Japanese verification
      expect(ja.navDashboard, 'ダッシュボード');
      expect(ja.navInterfaces, 'インターフェース');
      expect(ja.navMore, 'その他');
      expect(ja.settingsTitle, '設定');
      expect(ja.actionSave, '保存');
      expect(ja.actionCancel, 'キャンセル');
      expect(ja.actionDismiss, '閉じる');
      expect(ja.languageTitle, '言語');
      expect(ja.logViewerTitle, 'システム・カーネルログ');
      expect(ja.sshTerminalTitle, 'SSH ターミナル');
      expect(ja.dnsmasqReloadTitle, 'DHCP・DNS サービスの再読み込み');

      // English baseline
      expect(en.navDashboard, 'Dashboard');
      expect(en.navWireless, 'Wireless');
      expect(en.colorPalette, 'Color Palette');
      expect(en.exitDialogTitle, 'Exit Yala?');
      expect(en.diagnosticsSection, 'Router Diagnostics & Features');
      expect(en.actionSave, 'Save');
      expect(en.actionCancel, 'Cancel');
      expect(en.actionDismiss, 'Dismiss');
      expect(en.languageTitle, 'Language');

      // Newly added keys across all target locales
      expect(en.secDeviceManagement, 'Device Management');
      expect(ru.secDeviceManagement, 'Управление устройством');
      expect(es.secDeviceManagement, 'Gestión del dispositivo');
      expect(ptBr.secDeviceManagement, 'Gerenciamento do dispositivo');
      expect(de.secDeviceManagement, 'Geräteverwaltung');
      expect(id.secDeviceManagement, 'Manajemen Perangkat');
      expect(fr.secDeviceManagement, 'Gestion des appareils');

      expect(en.cardQuickActions, 'Quick Actions Bar');
      expect(ru.cardQuickActions, 'Панель быстрых действий');
      expect(es.cardQuickActions, 'Barra de acciones rápidas');
      expect(ptBr.cardQuickActions, 'Barra de ações rápidas');
      expect(de.cardQuickActions, 'Schnellaktionsleiste');
      expect(id.cardQuickActions, 'Bilah Aksi Cepat');
      expect(fr.cardQuickActions, 'Barre d\'actions rapides');

      expect(en.modSystemMonitoringName, 'System Monitoring');
      expect(ru.modSystemMonitoringName, 'Мониторинг системы');
      expect(es.modSystemMonitoringName, 'Monitorización del sistema');
      expect(ptBr.modSystemMonitoringName, 'Monitoramento do sistema');
      expect(de.modSystemMonitoringName, 'Systemüberwachung');
      expect(id.modSystemMonitoringName, 'Pemantauan Sistem');
      expect(fr.modSystemMonitoringName, 'Surveillance du système');

      // Phase 1: Clients & Interfaces additions
      expect(en.bannedClientsHubTitle, 'Banned Clients Hub');
      expect(ru.bannedClientsHubTitle, 'Центр заблокированных клиентов');
      expect(de.bannedClientsHubTitle, 'Hub für gesperrte Clients');
      expect(es.bannedClientsHubTitle, 'Centro de clientes bloqueados');
      expect(fr.bannedClientsHubTitle, 'Hub des clients bloqués');
      expect(id.bannedClientsHubTitle, 'Pusat Klien yang Diblokir');
      expect(ptBr.bannedClientsHubTitle, 'Central de Clientes Bloqueados');

      // Phase 2: Dialogs & Shared Components
      expect(en.addStaticLeaseTitle, 'Add Static Lease');
      expect(ru.addStaticLeaseTitle, 'Добавить статическую аренду');
      expect(de.addStaticLeaseTitle, 'Statisches Lease hinzufügen');
      expect(es.addStaticLeaseTitle, 'Añadir concesión estática');
      expect(fr.addStaticLeaseTitle, 'Ajouter un bail statique');
      expect(id.addStaticLeaseTitle, 'Tambah Sewa Statis');
      expect(ptBr.addStaticLeaseTitle, 'Adicionar concessão estática');

      expect(en.banClientFromWifi, 'Ban Client from Wi-Fi');
      expect(ru.banClientFromWifi, 'Заблокировать клиента в Wi-Fi');
      expect(de.banClientFromWifi, 'Client aus dem WLAN sperren');
      expect(es.banClientFromWifi, 'Bloquear cliente de Wi-Fi');
      expect(fr.banClientFromWifi, 'Bannir le client du Wi-Fi');
      expect(id.banClientFromWifi, 'Blokir Klien dari Wi-Fi');
      expect(ptBr.banClientFromWifi, 'Bloquear cliente do Wi-Fi');

      expect(en.rpcdPermissionDenied, 'Permission Denied (RPCD ACL)');
      expect(ru.rpcdPermissionDenied, 'Доступ запрещён (RPCD ACL)');
      expect(de.rpcdPermissionDenied, 'Zugriff verweigert (RPCD-ACL)');
      expect(es.rpcdPermissionDenied, 'Permiso denegado (RPCD ACL)');
      expect(fr.rpcdPermissionDenied, 'Permission refusée (RPCD ACL)');
      expect(id.rpcdPermissionDenied, 'Izin Ditolak (RPCD ACL)');
      expect(ptBr.rpcdPermissionDenied, 'Permissão negada (RPCD ACL)');

      expect(en.switchTopologyUnavailable, 'Switch Topology Unavailable');
      expect(ru.switchTopologyUnavailable, 'Топология коммутатора недоступна');
      expect(de.switchTopologyUnavailable, 'Switch-Topologie nicht verfügbar');
      expect(es.switchTopologyUnavailable, 'Topología de switch no disponible');
      expect(fr.switchTopologyUnavailable, 'Topologie de switch indisponible');
      expect(id.switchTopologyUnavailable, 'Topologi Switch Tidak Tersedia');
      expect(
        ptBr.switchTopologyUnavailable,
        'Topologia do switch indisponível',
      );

      // Phase 3: Wireless, Network & Security Management additions
      expect(en.wirelessOverview, 'Wireless Overview');
      expect(ru.wirelessOverview, 'Обзор беспроводной сети');
      expect(de.wirelessOverview, 'WLAN-Übersicht');
      expect(es.wirelessOverview, 'Resumen inalámbrico');
      expect(fr.wirelessOverview, 'Vue d\'ensemble sans fil');
      expect(id.wirelessOverview, 'Ringkasan Nirkabel');
      expect(ptBr.wirelessOverview, 'Visão geral do Wi-Fi');

      expect(en.guestWifiMasterControl, 'Guest Wi-Fi Master Control');
      expect(ru.guestWifiMasterControl, 'Главное управление гостевым Wi-Fi');
      expect(de.guestWifiMasterControl, 'Gast-WLAN-Hauptsteuerung');
      expect(
        es.guestWifiMasterControl,
        'Control maestro de Wi-Fi de invitados',
      );
      expect(fr.guestWifiMasterControl, 'Contrôle maître Wi-Fi Invité');
      expect(id.guestWifiMasterControl, 'Kontrol Utama Wi-Fi Tamu');
      expect(
        ptBr.guestWifiMasterControl,
        'Controle Mestre de Wi-Fi de Convidados',
      );

      expect(en.wifiAccessControlTitle, 'Wi-Fi Access Control');
      expect(ru.wifiAccessControlTitle, 'Контроль доступа Wi-Fi');
      expect(de.wifiAccessControlTitle, 'WLAN-Zugriffskontrolle');
      expect(es.wifiAccessControlTitle, 'Control de acceso Wi-Fi');
      expect(fr.wifiAccessControlTitle, 'Contrôle d\'accès Wi-Fi');
      expect(id.wifiAccessControlTitle, 'Kontrol Akses Wi-Fi');
      expect(ptBr.wifiAccessControlTitle, 'Controle de Acesso Wi-Fi');

      expect(en.dhcpDnsTitle, 'DHCP & DNS Management');
      expect(ru.dhcpDnsTitle, 'Управление DHCP и DNS');
      expect(de.dhcpDnsTitle, 'DHCP- & DNS-Verwaltung');
      expect(es.dhcpDnsTitle, 'Gestión de DHCP y DNS');
      expect(fr.dhcpDnsTitle, 'Gestion DHCP & DNS');
      expect(id.dhcpDnsTitle, 'Manajemen DHCP & DNS');
      expect(ptBr.dhcpDnsTitle, 'Gerenciamento DHCP & DNS');

      expect(en.firewallTitle, 'Firewall & Security');
      expect(ru.firewallTitle, 'Брандмауэр и безопасность');
      expect(de.firewallTitle, 'Firewall & Sicherheit');
      expect(es.firewallTitle, 'Firewall y seguridad');
      expect(fr.firewallTitle, 'Pare-feu & Sécurité');
      expect(id.firewallTitle, 'Firewall & Keamanan');
      expect(ptBr.firewallTitle, 'Firewall & Segurança');

      expect(en.vpnConnectivityTitle, 'VPN Connectivity');
      expect(ru.vpnConnectivityTitle, 'VPN-подключения');
      expect(de.vpnConnectivityTitle, 'VPN-Konnektivität');
      expect(es.vpnConnectivityTitle, 'Conectividad VPN');
      expect(fr.vpnConnectivityTitle, 'Connectivité VPN');
      expect(id.vpnConnectivityTitle, 'Konektivitas VPN');
      expect(ptBr.vpnConnectivityTitle, 'Conectividade VPN');

      // Phase 4: Diagnostics, Charting, System & Storage Monitoring
      expect(en.diagNetworkDiagnostics, 'Network Diagnostics');
      expect(ru.diagNetworkDiagnostics, 'Сетевая диагностика');
      expect(de.diagNetworkDiagnostics, 'Netzwerkdiagnose');
      expect(es.diagNetworkDiagnostics, 'Diagnóstico de red');
      expect(fr.diagNetworkDiagnostics, 'Diagnostics réseau');
      expect(id.diagNetworkDiagnostics, 'Diagnostik Jaringan');
      expect(ptBr.diagNetworkDiagnostics, 'Diagnóstico de Rede');

      expect(en.chartingTitle, 'Real-Time Metrics');
      expect(ru.chartingTitle, 'Метрики в реальном времени');
      expect(de.chartingTitle, 'Echtzeit-Metriken');
      expect(es.chartingTitle, 'Métricas en tiempo real');
      expect(fr.chartingTitle, 'Métriques en temps réel');
      expect(id.chartingTitle, 'Metrik Waktu Nyata');
      expect(ptBr.chartingTitle, 'Métricas em Tempo Real');

      expect(en.sysMonTitle, 'System Monitoring');
      expect(ru.sysMonTitle, 'Мониторинг системы');
      expect(de.sysMonTitle, 'Systemüberwachung');
      expect(es.sysMonTitle, 'Monitorización del sistema');
      expect(fr.sysMonTitle, 'Surveillance du système');
      expect(id.sysMonTitle, 'Pemantauan Sistem');
      expect(ptBr.sysMonTitle, 'Monitoramento do Sistema');

      expect(en.storageMonTitle, 'Storage Monitoring');
      expect(ru.storageMonTitle, 'Мониторинг накопителей');
      expect(de.storageMonTitle, 'Speicherüberwachung');
      expect(es.storageMonTitle, 'Monitorización de almacenamiento');
      expect(fr.storageMonTitle, 'Surveillance du stockage');
      expect(id.storageMonTitle, 'Pemantauan Penyimpanan');
      expect(ptBr.storageMonTitle, 'Monitoramento de Armazenamento');

      // Phase 5: Package Manager, Services System, Backup & Upgrade, Parental Controls
      expect(en.pkgCardTitle, 'OPKG/APK Packages');
      expect(ru.pkgCardTitle, 'Пакеты OPKG/APK');
      expect(de.pkgCardTitle, 'OPKG/APK-Pakete');
      expect(es.pkgCardTitle, 'Paquetes OPKG/APK');
      expect(fr.pkgCardTitle, 'Paquets OPKG/APK');
      expect(id.pkgCardTitle, 'Paket OPKG/APK');
      expect(ptBr.pkgCardTitle, 'Pacotes OPKG/APK');

      expect(en.servicesSysTitle, 'Services & System');
      expect(ru.servicesSysTitle, 'Службы и система');
      expect(de.servicesSysTitle, 'Dienste & System');
      expect(es.servicesSysTitle, 'Servicios y sistema');
      expect(fr.servicesSysTitle, 'Services et système');
      expect(id.servicesSysTitle, 'Layanan & Sistem');
      expect(ptBr.servicesSysTitle, 'Serviços e Sistema');

      expect(en.sysUpgradeTitle, 'Backup / Flash Firmware');
      expect(ru.sysUpgradeTitle, 'Резервная копия / Прошивка');
      expect(de.sysUpgradeTitle, 'Sicherung / Firmware flashen');
      expect(es.sysUpgradeTitle, 'Copia de seguridad / Actualizar firmware');
      expect(fr.sysUpgradeTitle, 'Sauvegarde / Flasher le firmware');
      expect(id.sysUpgradeTitle, 'Cadangan / Flash Firmware');
      expect(ptBr.sysUpgradeTitle, 'Backup / Gravar Firmware');

      expect(en.parentalControlsTitle, 'Parental Controls');
      expect(ru.parentalControlsTitle, 'Родительский контроль');
      expect(de.parentalControlsTitle, 'Kindersicherung');
      expect(es.parentalControlsTitle, 'Control parental');
      expect(fr.parentalControlsTitle, 'Contrôle parental');
      expect(id.parentalControlsTitle, 'Kontrol Orang Tua');
      expect(ptBr.parentalControlsTitle, 'Controle dos Pais');
    });

    test(
      'More tab modules have complete localization across locales',
      () async {
        final ru = await AppLocalizations.delegate.load(const Locale('ru'));
        final en = await AppLocalizations.delegate.load(const Locale('en'));
        final de = await AppLocalizations.delegate.load(const Locale('de'));
        final es = await AppLocalizations.delegate.load(const Locale('es'));

        // Russian More tab modules
        expect(ru.modVpnName, 'VPN и подключения');
        expect(ru.modFirewallName, 'Брандмауэр и безопасность');
        expect(ru.modServicesName, 'Службы и система');
        expect(ru.modPackagesName, 'Менеджер пакетов OPKG/APK');
        expect(ru.modBackupName, 'Резервное копирование и прошивка');

        // English baseline
        expect(en.modVpnName, 'VPN & Connectivity');
        expect(en.modFirewallName, 'Firewall & Security');
        expect(en.modServicesName, 'Services & System');
        expect(en.modPackagesName, 'OPKG/APK Package Manager');
        expect(en.modBackupName, 'Backup & Flash Firmware');

        // German & Spanish
        expect(de.modVpnName, 'VPN & Konnektivität');
        expect(es.modVpnName, 'VPN y conectividad');
      },
    );

    test(
      'Login screen labels, tooltips, and helpers are fully localized',
      () async {
        final ru = await AppLocalizations.delegate.load(const Locale('ru'));
        final en = await AppLocalizations.delegate.load(const Locale('en'));

        expect(ru.loginDirectLanBadge, 'ПРЯМОЕ LAN-ПОДКЛЮЧЕНИЕ');
        expect(en.loginDirectLanBadge, 'DIRECT LAN CONNECTION');
        expect(ru.loginTargetEndpoint, 'КОНЕЧНАЯ ТОЧКА МАРШРУТИЗАТОРА');
        expect(en.loginTargetEndpoint, 'TARGET ROUTER ENDPOINT');
        expect(ru.loginProfileNameOptional, 'Имя профиля (необязательно)');
        expect(en.loginProfileNameOptional, 'Profile Name (Optional)');
        expect(ru.loginRouterProfilesHeader, 'ПРОФИЛИ РОУТЕРОВ');
        expect(en.loginRouterProfilesHeader, 'ROUTER PROFILES');
        expect(ru.loginManageProfiles, 'Управление');
        expect(en.loginManageProfiles, 'Manage');
        expect(ru.loginNewRouterChip, 'Новый роутер');
        expect(en.loginNewRouterChip, 'New Router');
        expect(ru.loginNeedHelp, 'Нужна помощь?');
        expect(en.loginNeedHelp, 'Need help?');
      },
    );

    test(
      'Dashboard and Clients screen cards and toasts are localized',
      () async {
        final ru = await AppLocalizations.delegate.load(const Locale('ru'));
        final en = await AppLocalizations.delegate.load(const Locale('en'));

        expect(ru.cardWiredClients, 'Проводные клиенты');
        expect(en.cardWiredClients, 'Wired Clients');
        expect(ru.cardWirelessClients, 'Беспроводные клиенты');
        expect(en.cardWirelessClients, 'Wireless Clients');
        expect(ru.clientsConnectedCount(3), '3 подключено');
        expect(en.clientsConnectedCount(3), '3 Connected');
        expect(ru.cardClientsCount(1), '1 клиент');
        expect(ru.cardClientsCount(5), '5 клиентов');
        expect(en.cardClientsCount(1), '1 client');
        expect(en.cardClientsCount(5), '5 clients');
        expect(ru.cardTapForClients, 'Нажмите для списка клиентов');
        expect(en.cardTapForClients, 'Tap for clients');
        expect(ru.toastItemCopied('IP'), 'IP скопировано');
        expect(en.toastItemCopied('IP'), 'IP copied');
        expect(ru.toastCopiedToClipboard, 'Скопировано в буфер обмена.');
        expect(en.toastCopiedToClipboard, 'Copied to clipboard.');
      },
    );

    test(
      'Wireless card and backup screen keys are localized across locales',
      () async {
        final ru = await AppLocalizations.delegate.load(const Locale('ru'));
        final en = await AppLocalizations.delegate.load(const Locale('en'));
        final de = await AppLocalizations.delegate.load(const Locale('de'));
        final es = await AppLocalizations.delegate.load(const Locale('es'));
        final fr = await AppLocalizations.delegate.load(const Locale('fr'));
        final ptBr = await AppLocalizations.delegate.load(
          const Locale('pt', 'BR'),
        );

        // Guest Network pill badge
        expect(en.pillGuestNetwork, 'Guest Network');
        expect(ru.pillGuestNetwork, 'Гостевая сеть');
        expect(de.pillGuestNetwork, 'Gastnetzwerk');
        expect(es.pillGuestNetwork, 'Red de invitados');
        expect(fr.pillGuestNetwork, 'Réseau invité');
        expect(ptBr.pillGuestNetwork, 'Rede de Convidados');

        // Hidden status badge
        expect(en.statusHidden, 'HIDDEN');
        expect(ru.statusHidden, 'СКРЫТЫЙ');
        expect(de.statusHidden, 'VERSTECKT');
        expect(es.statusHidden, 'OCULTA');
        expect(fr.statusHidden, 'MASQUÉ');
        expect(ptBr.statusHidden, 'OCULTO');

        // Hardware detection state
        expect(en.detectingHardware, 'Detecting hardware…');
        expect(ru.detectingHardware, 'Определение оборудования…');
        expect(de.detectingHardware, 'Hardware wird erkannt…');

        // Wireless technical parameters section
        expect(en.wifiTechParams, 'Wireless Interface Parameters');
        expect(ru.wifiTechParams, 'Параметры беспроводного интерфейса');
      },
    );

    test(
      'Wi-Fi QR, Cron Job, and Dashboard Settings keys are properly localized',
      () async {
        final en = await AppLocalizations.delegate.load(const Locale('en'));
        final ru = await AppLocalizations.delegate.load(const Locale('ru'));
        final de = await AppLocalizations.delegate.load(const Locale('de'));
        final es = await AppLocalizations.delegate.load(const Locale('es'));
        final fr = await AppLocalizations.delegate.load(const Locale('fr'));
        final id = await AppLocalizations.delegate.load(const Locale('id'));
        final pt = await AppLocalizations.delegate.load(const Locale('pt'));
        final ptBr = await AppLocalizations.delegate.load(
          const Locale('pt', 'BR'),
        );

        // Wi-Fi QR Copy Password & Payload
        expect(en.wifiCopyPassword, 'Copy Password');
        expect(ru.wifiCopyPassword, 'Копировать пароль');
        expect(de.wifiCopyPassword, 'Passwort kopieren');
        expect(es.wifiCopyPassword, 'Copiar contraseña');
        expect(fr.wifiCopyPassword, 'Copier le mot de passe');
        expect(id.wifiCopyPassword, 'Salin Kata Sandi');
        expect(pt.wifiCopyPassword, 'Copiar palavra-passe');
        expect(ptBr.wifiCopyPassword, 'Copiar senha');

        expect(en.wifiCopyQrPayload, 'Copy QR Payload');
        expect(ru.wifiCopyQrPayload, 'Копировать данные QR');

        // Cron Scheduled Tasks
        expect(en.cronSchedulePreset, 'Schedule Preset');
        expect(ru.cronSchedulePreset, 'Шаблон расписания');
        expect(en.cronPresetCustomExpression, 'Custom Expression');
        expect(ru.cronPresetCustomExpression, 'Пользовательское выражение');
        expect(en.cronTaskActiveState, 'Task Active State');
        expect(ru.cronTaskActiveState, 'Состояние задачи');
        expect(en.cronChipRebootRouter, 'Reboot Router');
        expect(ru.cronChipRebootRouter, 'Перезагрузка роутера');
        expect(en.cronChipPingCheck, 'Ping Check');
        expect(ru.cronChipPingCheck, 'Проверка пинга');

        // Dynamic Cron Descriptions
        expect(en.cronRunsEveryMinute, 'Runs every minute');
        expect(ru.cronRunsEveryMinute, 'Выполняется каждую минуту');
        expect(en.cronRunsEveryDayAt('7:00 AM'), 'Runs every day at 7:00 AM');
        expect(
          ru.cronRunsEveryDayAt('07:00'),
          'Выполняется каждый день в 07:00',
        );

        // Dashboard Settings
        expect(
          en.rdSettingsQuickActionsSubtitle,
          contains('Select shortcut action buttons'),
        );
        expect(
          ru.rdSettingsQuickActionsSubtitle,
          contains('Выберите быстрые кнопки действий'),
        );
        expect(
          en.rdSettingsSystemVitalsSubtitle,
          contains('Choose hardware performance metrics'),
        );
        expect(
          ru.rdSettingsSystemVitalsSubtitle,
          contains('Выберите показатели оборудования'),
        );
        expect(
          en.rdSettingsTrafficSectionTitle,
          'Traffic & Throughput Settings',
        );
        expect(
          ru.rdSettingsTrafficSectionTitle,
          'Настройки трафика и пропускной способности',
        );
        expect(en.rdSettingsNetworkPrivacyTitle, 'Network & Privacy Options');
        expect(
          ru.rdSettingsNetworkPrivacyTitle,
          'Параметры сети и конфиденциальности',
        );
        expect(en.rdSettingsWirelessNetworksTitle, 'Wireless Networks');
        expect(ru.rdSettingsWirelessNetworksTitle, 'Беспроводные сети');
        expect(en.rdSettingsWiredInterfacesTitle, 'Wired & Virtual Interfaces');
        expect(
          ru.rdSettingsWiredInterfacesTitle,
          'Проводные и виртуальные интерфейсы',
        );

        // Network Diagnostics Segments & Strings
        expect(en.diagSegmentRoutes, 'Routes');
        expect(ru.diagSegmentRoutes, 'Маршруты');
        expect(de.diagSegmentRoutes, 'Routen');
        expect(es.diagSegmentRoutes, 'Rutas');
        expect(fr.diagSegmentRoutes, 'Routes');
        expect(id.diagSegmentRoutes, 'Rute');
        expect(ptBr.diagSegmentRoutes, 'Rotas');

        expect(en.diagSegmentArp, 'ARP');
        expect(ru.diagSegmentArp, 'ARP');
        expect(en.diagSegmentConntrack, 'Conntrack');
        expect(ru.diagSegmentConntrack, 'Соединения');

        expect(en.diagMetricWanInterface, 'WAN Interface');
        expect(ru.diagMetricWanInterface, 'Интерфейс WAN');
        expect(en.diagFlushDnsTitle, 'Flush DNS Cache');
        expect(ru.diagFlushDnsTitle, 'Очистить кэш DNS');
        expect(en.diagExportCardTitle, 'Generate Diagnostic Report');
        expect(ru.diagExportCardTitle, 'Создать диагностический отчет');
      },
    );

    test('Portuguese (pt) resolves to European Portuguese', () async {
      final pt = await AppLocalizations.delegate.load(const Locale('pt'));
      expect(pt.appTitle, 'Yet Another LuCI App');
      expect(pt.navDashboard, 'Dashboard');
      expect(pt.navClients, 'Clientes');
      expect(pt.navWireless, 'Sem fios');
      expect(pt.actionSave, 'Guardar');
      expect(pt.actionCancel, 'Cancelar');
    });

    test(
      'Chinese (zh) resolves to Simplified Chinese with accurate LuCI terminology',
      () async {
        final zh = await AppLocalizations.delegate.load(const Locale('zh'));
        expect(zh.appTitle, 'Yet Another LuCI App');
        expect(zh.appDescription, 'OpenWrt 路由器管理应用');
        expect(zh.navDashboard, '概览');
        expect(zh.navInterfaces, '接口');
        expect(zh.navClients, '客户端');
        expect(zh.navWireless, '无线');
        expect(zh.navSettings, '设置');
        expect(zh.actionSave, '保存');
        expect(zh.actionCancel, '取消');
        expect(zh.actionApply, '应用');
        expect(zh.actionDelete, '删除');
        expect(zh.statusConnected, '已连接');
        expect(zh.firewallTitle, '防火墙与安全');
        expect(zh.firewallZonesOverviewTitle, '防火墙区域概览');
        expect(zh.firewallZonesCount(5), '5 个区域');
        expect(zh.firewallInputPolicy, '入站数据策略 (Input)');
        expect(zh.firewallOutputPolicy, '出站数据策略 (Output)');
        expect(zh.firewallForwardPolicy, '转发数据策略 (Forward)');
        expect(zh.vpnWireguardSectionTitle, 'WireGuard VPN 接口与对端 (Peers)');
        expect(zh.servicesSysTestingDdns, '正在测试 DDNS 查询与解析...');
        expect(zh.updateAvailableTitle, '发现新版本');
      },
    );
  });
}
