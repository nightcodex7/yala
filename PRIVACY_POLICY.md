# Privacy Policy

**Yet Another LuCI App**
Last updated: November 11, 2026

I am committed to protecting your privacy. This Privacy Policy explains how Yet Another LuCI App ("App") handles your information when you use the App to manage your OpenWrt/LuCI routers and local AdGuard Home instances.

---

## 1. Local Network Data & Local-First Architecture

### a. Local Router Credentials & Configuration Data

- The App requires your router's (and, where configured, local or private AdGuard Home instance's) IP address, port, username, and password to establish direct connections over your local Wi-Fi or private VPN network.
- All router, SSH, and AdGuard Home credentials, as well as saved SSH command snippets, are stored locally on your device using hardware-backed secure storage (Android Keystore / iOS Keychain via `flutter_secure_storage`) and local application preferences.
- Credentials and network layout data are used **exclusively** for direct HTTP/HTTPS, JSON-RPC, ubus, REST API, and SSH communication between your mobile device and your target router or local service.
- Router diagnostics, system/kernel logs (`logread` / `dmesg`), SQM telemetry, and live interface/client metrics are processed in volatile memory on-device. When using JSON Config Export, sensitive secrets and private keys are automatically redacted locally.
- I do **not** collect, transmit, upload, or store your router credentials, IP addresses, network topology, logs, or router configurations on any external server or developer database.

### b. Network Permissions & User-Initiated External Queries

- **Local Network Access (`ACCESS_LOCAL_NETWORK`):** On modern Android versions (Android 15+) and iOS/iPadOS, the App requests local network access strictly to discover and connect directly to local gateway IP addresses (such as `192.168.1.1` or `10.0.0.1`).
- **`INTERNET`:** Required to open local socket connections to your router and, only when explicitly initiated by the user, to check official OpenWrt firmware release APIs (in Firmware Upgrade Center) or official GitHub Releases for Community Edition updates (disabled in F-Droid builds).

---

## 2. Edition Breakdown & Third-Party Services

### a. Community Edition (GitHub Releases / F-Droid / FOSS)

- **100% Free & Ad-Free**: Contains zero advertisements, does not collect Advertising IDs (`AD_ID`), and does not integrate third-party ad networks.
- **No In-App Purchases**: Fully open-source under the GNU General Public License v3.0 (GPL-3.0-or-later) with unlimited router profiles.
- **Zero Telemetry or Analytics**: Contains no background tracking, crash telemetry, or third-party analytics SDKs.
- **F-Droid Compliance**: F-Droid builds (`FDROID_BUILD=true`) disable in-app GitHub update checking and external binary prompts.

### b. Play Store / Official Edition (Google Play)

- **100% Free & Ad-Free**:
  - The App is completely **Free** and **Ad-Free** across all builds and channels.
  - **No In-App Purchases**: Contains zero paywalls, locked features, or billing SDKs.
  - **Zero Ad Identifiers**: The App does not collect, process, or transmit Advertising IDs (`AD_ID`), device identifiers for advertising, or user tracking metrics.
- **Zero Telemetry or Analytics**: Contains no background tracking, crash telemetry, or third-party analytics SDKs.

### c. iOS / iPadOS Beta (GitHub IPA)

- Built with the same local-first architecture, storing router and service credentials exclusively in the Apple iOS Keychain with zero analytics or tracking SDKs.

---

## 3. Data Sharing and Disclosure

- **Zero Router Data Sharing**: Router passwords, IP addresses, UCI configurations, and connected device logs are **never shared** with any third party.
- **Zero Third-Party SDKs**: No analytics SDKs, advertising networks, or third-party data brokers are integrated into the App.

---

## 4. Security

- Router passwords and session tokens (`sysauth`) remain stored securely in device hardware-backed storage.
- The App supports HTTPS protocol connections, custom ports, and SSL verification options to secure local network and VPN traffic.

---

## 5. Children's Privacy (Age 3+ Compliance)

- **Rated Age 3+ (Suitable for All Ages)**: Yet Another LuCI App is listed and rated **Age 3+** on the Google Play Store, making it suitable for users of all ages, including children under 13.
- **Zero Personal Data Collection**: The App operates with a local-first architecture and does not collect, store, or transmit any personal information, personal identifiers, device IDs, location data, or network details from children or any other users.
- **Ad-Free & Family Safe**: The App displays zero advertisements and includes no analytics or user tracking, providing a safe, privacy-focused experience for all family members.

---

## 6. Play Console Data Safety Compliance

This Privacy Policy matches the declarations in the Google Play Console Data Safety form:

- **Local Data Only**: Router credentials and network data remain strictly on the user's local device.
- **100% Ad-Free**: No Advertising IDs (`AD_ID`) or ad tracking metrics are collected or processed.
- **Zero In-App Purchases**: No billing data or payment metrics are collected.

---

## 7. Contact & Official Policy Links

If you have questions, concerns, or requests regarding this Privacy Policy, please contact me:

- **Privacy Inquiries**: <yala+privacy@nightcode.co.in>
- **General Support**: <yala+support@nightcode.co.in>
- **Website Privacy Policy**: [https://nightcode.co.in/privacy-policy.html](https://nightcode.co.in/privacy-policy.html)
- **Terms & Conditions**: [https://nightcode.co.in/terms.html](https://nightcode.co.in/terms.html)
- **GitHub Repository**: [https://github.com/nightcodex7/yala](https://github.com/nightcodex7/yala)
