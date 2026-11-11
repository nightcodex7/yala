# Changelog

All notable changes to **yala** will be documented in this file.

## [2.8.10+237] - 2026-11-09

### Hotfix
- **Log Viewer**: Fixed `fetchSyslog` and `fetchKernelLog` 2-tuple RPC result unpacking and added BusyBox flag/path fallbacks for `logread` and `dmesg`.
- **Wi-Fi Access Control**: Resolved `Set<String>` typecast crash in `_loadClients()`, removed fallback client guessing in `_detectPhoneMac()`, and made self-device lockout prevention interface/SSID-aware.
- **Dashboard Startup Resilience**: Coerced string-typed `rc.list` / `service.list` priority indexes (`index`, `start`, `stop`) and hardened defensive model parsing across cards to fix the indefinite blank grey box on affected OpenWrt 25.x firmware builds.

## [2.8.9+236] - 2026-11-08

### Added & Changed
- **Parental Controls Overhaul**: Rebuilt profile management with customizable avatars, detailed schedule/rule sheets, scheduled firewall enforcement, domain filtering, and quick bypass overrides.
- **SSH Terminal**: Interactive persistent `xterm`-based SSH console with quick shortcut keys, risk classification, command history, and importable/exportable saved commands.
- **Client Bandwidth Limits**: Per-device download and upload speed throttling controls with a dedicated throttling summary screen.
- **Advanced Reboot**: Capability-based dual-firmware partition switching (U-Boot/UBI), ACPI/PMIC hardware power-off, and read-only boot environment diagnostics.
- **System & Kernel Log Viewer**: Dual-tab viewer for router syslog (`logread`) and kernel ring buffer (`dmesg`) with severity badges, filtering, and clipboard copy.
- **Account & Access Inspector**: Read-only router account, effective ubus/RPCD permissions, and SSH reachability diagnostics.
- **Translations**: Added Italian (`it`), Japanese (`ja`), and Ukrainian (`uk`) localizations (expanding support to 12 locales).
- **UI & Fixes**: Material 3 dynamic color updates, chart/SQM telemetry improvements, and general bug fixes.

## [2.6.0+232] - 2026-10-25

### Added & Changed
- **Firmware Upgrade Center**: Official OpenWrt release checks, preserved file & storage impact review, SHA256 verification, and safe sysupgrade flashing.
- **JSON Config Export**: Clean JSON export for router configuration (firewall, DHCP, Wi-Fi, DDNS) with automatic privacy redactions.
- **Router Speed Test**: Native router-side WAN speed test engine with multi-stage sampling.
- **UI & Performance**: Redesigned setup wizards, improved dialog responsiveness, high refresh rate & edge-to-edge fixes, and extended localization coverage.

## [2.5.1+227] - 2026-10-16

### Added & Changed
- **AdGuard Home**: Network-wide DNS sinkhole management, filter lists, query statistics, top lists, DNS pipeline topology card, and multi-instance profiles.
- **Advanced Firewall**: Enhanced firewall rule creation and management across `fw3` (iptables) and `fw4` (nftables).
- **Device Access Controls**: Granular per-device IPv4 and IPv6 internet access toggles.
- **Security & Reliability**: Hardened privileged RPC operations, self-lockout guardrails, and certificate trust validation.

## [2.2.5+225] - 2026-10-06

### Added & Changed
- **Bandwidth Monitor**: Real-time per-client Rx/Tx traffic rate monitoring.
- **Smart Queue Management (SQM QoS)**: Complete bufferbloat mitigation supporting Cake and FQ-CoDel queue disciplines with link-layer adaptation.
- **Storage & Disk Monitoring**: Live capacity tracking across root/overlay flash and mounted USB drives with low-space alerts.
- **DHCP/DNS & Multi-Router Hardening**: Responsive UI overhaul, fixed static lease validation/deletion, live router hostname editor, granular RPC permissions dialog, and isolated multi-router credentials.
- **F-Droid & FOSS Compliance**: Locally bundled Geist and Geist Mono fonts with zero runtime network fetching, and update checker suppression for F-Droid builds.

## [2.1.0+224] - 2026-10-01

### Added & Changed
- **OPKG & APK Package Manager**: Filter, search, batch upgrade (`Upgrade All`), and install packages via custom URLs.
- **Network Diagnostics Suite**: Integrated router-side ping, visual traceroute, DNS lookup, and exportable reports.
- **Hardware Temperature**: Live SoC thermal zone monitoring (°C / °F).
- **Multi-Language Support (Beta)**: Initial 9 locales (`EN`, `DE`, `ES`, `FR`, `ID`, `PT`, `PT-BR`, `RU`, `ZH`).

## [2.0.0+220] - 2026-09-14

### Note
If you don't know which one to install, then install the universal one.

### Overview
This release consolidates interface navigation fixes, limits UI color schemes to Material You and Yala Amber, resolves static DHCP lease deletion on OpenWrt routers, and adds full Android 15 compatibility.

### Key Changes
- Theme: Restricted theme selection strictly to Material You (dynamic device palette) and Yala Amber. Removed unused and redundant color palettes.
- Navigation: Fixed an issue where pressing the Android system back button on secondary tabs abruptly closed the app and could result in a black screen on reopen. Back navigation now properly steps back through visited tabs to the Dashboard before showing an exit confirmation dialog.
- DHCP & Clients: Fixed static DHCP lease deletion failing on certain OpenWrt RPC endpoints. Improved client disconnection handling and live list synchronization.
- Android 15 & System UI: Updated window insets handling for Android 15 edge-to-edge support and eliminated deprecated display cutout mode calls.
- Privacy & Cleanup: Removed obsolete payment and donation endpoints from app configuration. The application contains zero tracking, no telemetry, and no advertising SDKs.
- Licensing: Full GNU General Public License v3.0 (GPLv3) compliance with dual attribution for upstream cogwheel0/luci-mobile and subsequent modifications by @nightcodex7.

### Package Downloads
- yala-v2.0.0-arm64-v8a.apk: Modern 64-bit ARM devices (most newer phones and tablets).
- yala-v2.0.0-armeabi-v7a.apk: Older 32-bit ARM devices.
- yala-v2.0.0-x86_64.apk: 64-bit x86 Android emulators and Intel/AMD tablets.
- yala-v2.0.0-universal.apk: Compatible with all supported Android architectures.

## [1.2.1-yala] - 2026-09-06

### Licensing Correction & Upstream Integration
- **Licensing Correction**: Formally corrected project licensing to GNU General Public License v3.0 (GPLv3) as a fork of [`cogwheel0/luci-mobile`](https://github.com/cogwheel0/luci-mobile). (Note: Previous distribution under Apache-2.0 was incorrect and has been retired).
- **Upstream Sync**: Synchronized local fork branch with upstream `cogwheel0/luci-mobile` latest release (`v1.2.1`).
- **Feature Reintegration**: Reintegrated accumulated feature modules including DHCP/DNS management, firewall rules, package manager, wireless access control, parental controls, system backup/restore, and UI enhancements into the unified GPLv3 repository.
