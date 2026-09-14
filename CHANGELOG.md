# Changelog

All notable changes to **yala** will be documented in this file.

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
