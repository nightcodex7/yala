# YALA (Yet Another LuCI App)

<div align="center">
  <img src="assets/images/app_logo_transparent.png" width="120" alt="App Logo" />
  <h2>Modern OpenWrt & LuCI Router Manager</h2>

  [![Version](https://img.shields.io/github/v/release/nightcodex7/yala?style=for-the-badge&logo=github&color=blue&label=Version)](https://github.com/nightcodex7/yala/releases/latest)
  [![Downloads](https://img.shields.io/github/downloads/nightcodex7/yala/total.svg?style=for-the-badge&logo=github&color=blue)](https://github.com/nightcodex7/yala/releases)
  [![Page Views](https://api.visitorbadge.io/api/visitors?path=nightcodex7%2Fyala&label=Page%20Views&style=for-the-badge&labelColor=555555&countColor=0175C2)](https://github.com/nightcodex7/yala)
  [![Platform Android](https://img.shields.io/badge/Platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://play.google.com/store/apps/details?id=com.nightcode.luci)
  [![Platform iOS](https://img.shields.io/badge/Platform-iOS_(Beta)-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/nightcodex7/yala/releases)
  [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](LICENSE)
  [![OpenWrt](https://img.shields.io/badge/OpenWrt-19.07--25.x-1589F0?style=for-the-badge&logo=openwrt&logoColor=white)](https://openwrt.org)

  <br>

  <a href="https://play.google.com/store/apps/details?id=com.nightcode.luci&referrer=utm_source%3Dgithub%26utm_medium%3Dreadme%26utm_campaign%3Dplay_badge">
    <img src="store-badges/google.webp" alt="Get it on Google Play" height="60" />
  </a>
  &nbsp;&nbsp;
  <a href="https://github.com/nightcodex7/yala/releases/latest">
    <img src="store-badges/github.webp" alt="Get it on GitHub" height="60" />
  </a>

  <p>
    <a href="https://github.com/nightcodex7/yala/releases/tag/v2.6.0-beta-ipa">
      <b>iOS Beta IPA Available on GitHub Releases</b>
    </a>
  </p>
  <!-- &nbsp;&nbsp;
  <a href="https://f-droid.org/packages/com.nightcode.luci/">
    <img src="store-badges/fdroid.webp" alt="Get it on F-Droid" height="60" />
  </a> -->

  <br><br>

  <h3>Dashboard Preview (Light & Dark Theme)</h3>
  <p>
    <img src="assets/screenshots/1_dashboard-light.jpeg" width="340" alt="Dashboard Light Mode" />
    &nbsp;&nbsp;&nbsp;&nbsp;
    <img src="assets/screenshots/2_dashboard-dark.jpeg" width="340" alt="Dashboard Dark Mode" />
  </p>
</div>

<br>

**YALA (Yet Another LuCI App)** is an open-source mobile client for managing OpenWrt routers. It connects directly to your router using LuCI JSON-RPC, ubus, and standard OpenWrt system services, allowing you to monitor real-time bandwidth, manage connected devices, run network diagnostics, configure wireless radios, manage AdGuard Home DNS sinkhole, monitor VPN tunnels (WireGuard, OpenVPN, Tailscale), control Smart Queue Management (SQM/QoS), inspect storage, and update packages directly from your phone or tablet.

---

## Supported Devices & Scope

YALA is purpose-built for mobile, tablet, and touch-first form factors:

- **Smartphones:** Android (Android 8.0 Oreo up to Android 15/16) and Apple iPhone (iOS 14.0+).
- **Tablets & iPads:** Android Tablets and Apple iPads with dedicated wide-screen multi-column layouts and adaptive split views.
- **Foldables & Dual-Screen Devices:** Adaptive layouts with screen hinge and fold awareness (including Samsung Galaxy Fold/Flip series and Apple Duo / foldable layouts).
- **Chromebooks:** Supported through the ChromeOS Android runtime.
- **Android XR:** Spatial Android XR support.

> [!NOTE]
> **Platform Scope:** YALA is tailored specifically for phone, tablet, and handheld interfaces. Desktop and laptop operating systems (native Windows, macOS, or desktop Linux) are outside the scope of this project, except for Chromebooks running Android apps.

---

## Key Features

| Feature | Highlights |
|---|---|
| **Dashboard & Real-Time Vitals** | Live CPU/RAM/Swap gauges, Rx/Tx throughput graph, interface status cards |
| **Firmware Upgrade Center** | Official OpenWrt update checks, preservation impact review, safe sysupgrade flashing |
| **Router Speed Test** | Router WAN speed test engine with multi-stage sampling directly on the router |
| **Multi-Router Management** | Multiple router profiles, hardware-backed credential vault, resilient auth fallback |
| **Connected Clients** | Unified DHCP + ARP + wireless view, OUI vendor lookup, static lease management, IPv6 |
| **Wireless & Guest Wi-Fi** | 2.4/5/6 GHz multi-band, station metrics, MAC ACL, guest isolation, QR code sharing |
| **AdGuard Home** | DNS sinkhole management, filter lists, top lists, topology card, multi-instance profiles |
| **VPN & Connectivity** | WireGuard, OpenVPN, Tailscale, NextDNS, Cloudflare Tunnels |
| **Firewall & Port Forwarding** | Zone rules, NAT, traffic rules, DNAT port forwarding |
| **Package Manager** | Dual OPKG/APK engine, package search & install, LuCI app finder |
| **SQM / QoS** | Bufferbloat control with Cake & FQ-CoDel, per-interface shaping |
| **Bandwidth Monitor** | Per-client real-time Rx/Tx traffic rates |
| **Parental Controls** | Device profiles, timed access windows, domain filtering |
| **Services & Cron** | procd service control, crontab editor, DDNS management, SSH |
| **Storage & Backup** | Flash/USB storage, JSON config export with redaction, backup/restore, sysupgrade |
| **Network Diagnostics** | Router-side ping, traceroute, DNS lookup, ARP, conntrack, routes |
| **Design & Localization** | Material 3 / Material You, responsive UI revamps, tablet & foldable layouts, 9 languages |

<details>
<summary><b>Show Full Feature Details</b></summary>
<br>

### Multi-Router Management & Secure Vault

- **Multiple Router Profiles:** Save and switch between multiple OpenWrt routers with isolated credentials.
- **Hardware-Backed Vault:** Router IP addresses, credentials, and session tokens are encrypted locally using native secure storage (`flutter_secure_storage` with Android KeyStore and iOS Keychain).
- **Resilient Authentication Stack:** Automatic fallback chain supporting LuCI JSON-RPC (`/cgi-bin/luci/rpc/auth`), ubus JSON-RPC (`session.login`), and redirect-aware CGI form authentication (`sysauth` cookies and `stok` tokens).
- **HTTPS & Custom Ports:** Connect over HTTP or HTTPS with custom port configurations and optional self-signed SSL certificate acceptance for local home networks.

### Dashboard & Real-Time Vitals

- **Animated Gauges:** Live visual gauges for CPU load, RAM usage, Swap space, and flash root (`/`) filesystem capacity.
- **Real-Time Throughput Graph:** Smooth live chart displaying router network transfer rates (Rx/Tx) with customizable polling intervals.
- **Interface Status Cards:** Overview cards for WAN, LAN, and WWAN showing IP addresses, MACs, protocols, and WAN public IP verification.
- **Quick Actions:** Instant shortcuts to reboot the router, access network diagnostics, or inspect connected clients.

### Connected Clients & Lease Management

- **Unified Client List:** Merges active DHCP leases, ARP neighbor entries, and wireless stations into a single clear view.
- **Device Details:** Displays hostname, assigned IP, MAC address, vendor OUI lookup, connected SSID, and radio band badges.
- **IPv6 Management:** Cleanly displays deduplicated IPv6 address lists with expandable views for multiple private or link-local addresses.
- **Static DHCP Leases:** View, add, edit, and delete static IP reservations with immediate router synchronization.

### Wireless Networks & Guest Wi-Fi

- **Multi-Band Monitoring:** Monitor 2.4 GHz, 5 GHz, and 6 GHz radios with channel, frequency, transmit power, and channel width details.
- **Connected Stations:** Live station list per radio showing connected devices, signal strength (dBm), and bitrate metrics.
- **Wi-Fi Access Control:** Enforce MAC address allowlists or denylists with direct router UCI synchronization.
- **One-Click Guest Wi-Fi:** Provision guest Wi-Fi SSIDs with automatic AP client isolation (`ap_isolate=1`) and dedicated firewall zone isolation.
- **Wi-Fi QR Code Sharing:** Generate on-screen QR codes to help family and visitors connect without typing passwords.

### AdGuard Home DNS Sinkhole Management

- **Network-Wide Ad & Tracker Blocking:** Manage AdGuard Home instances running locally on the router or hosted externally with full service lifecycle control.
- **Multi-Instance Profiles:** Switch between multiple AdGuard Home instances (local router or external host) with isolated credential vaults per profile.
- **DNS Topology Awareness:** Visual DNS pipeline card showing the flow from clients → AdGuard Home → upstream resolvers, with router DNS redirect status and one-tap auto-configure / revert for `/etc/config/dhcp`.
- **Statistics & Top Lists:** Live query statistics, blocked request counters, top blocked domains, and top queried domains with per-client breakdown.
- **Filtering Rules:** Manage blocklists and allowlists, add custom filtering rules and exceptions directly from the app.
- **Protection Controls:** Toggle global protection on/off, pause blocking with a configurable timer, and inspect real-time blocking status.
- **Process Telemetry (Local Only):** Monitor AdGuard Home memory, CPU usage, and uptime when running as a router-local `procd` service.

### VPN & Connectivity

- **WireGuard Tunnels:** Monitor interface status, endpoint details, last handshake times, peer-level data transfer counters, and allowed IP routes for all WireGuard interfaces.
- **OpenVPN:** View active OpenVPN client and server instance status, connection state, and basic configuration details.
- **Tailscale Mesh VPN:** Inspect Tailscale node status, assigned Tailscale IP, connected peers, and exit node configuration.
- **NextDNS:** Monitor NextDNS integration status, profile linkage, and DNS-over-HTTPS/TLS configuration.
- **Cloudflare Tunnels (cloudflared):** View `cloudflared` tunnel service status and connectivity state.
- **Smart Sorting:** Active and configured VPN connections are automatically sorted and surfaced above unconfigured stubs.

### Smart Queue Management (SQM / QoS)

- **Bufferbloat Mitigation:** Configure and monitor SQM queue disciplines to eliminate bufferbloat and improve latency under load.
- **Queue Disciplines:** Supports `cake` and `fq_codel` schedulers with link-layer adaptation options (`ethernet`, `atm`, `overhead`).
- **Per-Interface QoS:** Apply SQM rules independently to WAN and internal interfaces with customizable download/upload shaping rates.
- **Live Telemetry:** Real-time queue status polling with load indicators and applied configuration summaries.
- **SQM Install Helper:** Detects whether `luci-app-sqm` and `sqm-scripts` are installed and guides one-tap installation via the package manager.

### Client Bandwidth Monitor

- **Per-Client Traffic Rates:** Real-time ingress and egress throughput per connected device, updated on configurable polling intervals.
- **Live Traffic Dashboard:** See which devices are actively consuming bandwidth at a glance with live Rx/Tx speed indicators.

### Dual Package Managers (OPKG & APK)

- **Smart Engine Detection:** Automatically detects and switches between `opkg` (OpenWrt 19.07–23.05) and modern `apk` (OpenWrt 24.10+ and 25.x snapshots).
- **Package Management:** Search repository feeds, update package lists, and install or remove packages directly.
- **LuCI App Companion Finder:** Discover, install, and manage installed vs available LuCI web extension modules (`luci-app-*`).

### Parental Controls & Timed Access

- **Device Profiling:** Group household devices under customizable profiles.
- **Automated Access Windows:** Enforce firewall blocking rules during scheduled restriction hours (such as study or bedtime) and restore access automatically.
- **Domain Filtering & Overrides:** Filter specific domains per profile or toggle instant unrestricted bypass overrides when needed.

### System Services, Cron & Dynamic DNS (DDNS)

- **Services Control:** View active `procd` daemons and `/etc/init.d/` startup scripts; start, stop, restart, enable, or disable services remotely.
- **Cron Scheduler:** View, add, edit, or delete scheduled crontab jobs (`/etc/crontabs/root`).
- **Dynamic DNS:** Monitor DDNS sync status, trigger forced IP updates, and view service status.
- **Optional SSH Service:** Connect via SSH for advanced router maintenance and SoC thermal sensor monitoring.

### Firmware Upgrade Center

- **Official OpenWrt Upgrade Checks:** Directly query official OpenWrt release APIs to check for available stable and snapshot updates matching your router's board target and architecture.
- **Preservation & Impact Review:** Inspect retained configuration files, review disk space impact, and examine package changes prior to flashing.
- **Safe Sysupgrade Flashing:** Download, verify SHA256 checksums, and flash official sysupgrade firmware directly from the mobile app with safety validations.

### Storage, Partitions & Backup/Restore

- **Storage Breakdown:** Inspect disk space usage across root `/`, `/overlay`, `/tmp`, and mounted external USB drives.
- **JSON Config Export:** Export clean JSON snapshots of router configuration (firewall, DHCP, Wi-Fi, DDNS) with intelligent privacy redactions to protect credentials and private keys.
- **Pre-Restore Validation:** Validates gzip headers (`0x1F 0x8B`) and `tar` archive structures before uploading to prevent corrupt backup restores.
- **Preserved File Viewer:** Inspect files marked for retention during sysupgrade operations (`sysupgrade -l`).
- **MTD Partition Dumper:** Save binary `mtdblock` partition images directly from `/proc/mtd`.
- **System Maintenance:** Trigger remote system reboot or clean factory reset (`firstboot -y`).

### Network Diagnostics Suite

- **Router WAN Speed Test:** Native router-side speed test engine with multi-stage sampling to benchmark accurate WAN throughput directly from the gateway, bypassing mobile Wi-Fi limitations.
- **Router-Side Ping:** Send ICMP ECHO_REQUEST packets directly from the router to any target IP or hostname with packet count selection, IPv6 toggle, and live min/avg/max latency calculation.
- **Visual Traceroute:** Trace network hops from the router with customizable hop limits and IPv6 support.
- **DNS Lookup / NSLookup:** Test domain name resolution against default upstream resolvers or custom DNS servers.
- **Routes, ARP & Conntrack:** Inspect kernel routing tables, active ARP neighbor caches, and live network connection tracking entries.
- **One-Tap Diagnostic Export:** Generate and copy clean, formatted diagnostic summaries for easy troubleshooting and sharing.

### Safety Guardrails & Atomic Rollbacks

- **Self-Device Guard:** Automatically detects the managing phone's local IP and MAC address to prevent accidental self-lockouts during access rule changes.
- **Atomic UCI Rollback:** Automatically executes `uci revert` across target configuration files if an intermediate multi-step RPC request fails.

### Adaptive Design, Theming & Localization

- **Material 3 & Material You:** Dynamic wallpaper-extracted color palettes on supported Android devices, along with the signature YALA Amber theme.
- **Theme Modes:** Full Light and Dark mode support.
- **Responsive UI Revamps:** Redesigned wizards, cleaner dialog layouts, improved responsiveness across various screen sizes, and performance optimizations.
- **Localization:** Available in English, German, Spanish, French, Indonesian, Portuguese, Brazilian Portuguese, Russian, and Chinese with extended coverage.
- **Tablet & Foldable Optimization:** Responsive two-column and three-column layouts designed for tablets, foldables, and Chromebooks.

</details>

---

## Screenshots


<div align="center">
  <p><b>Explore full resolution screenshots of Yet Another LuCI App features:</b></p>
</div>

<table>
  <tr>
    <td width="25%" align="center" valign="top">
      <b>Login Screen</b><br/><br/>
      <img src="assets/screenshots/3_login_page.jpeg" width="165" height="350" alt="Login Screen"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Dashboard (Light)</b><br/><br/>
      <img src="assets/screenshots/1_dashboard-light.jpeg" width="165" height="350" alt="Dashboard Light Mode"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Dashboard (Dark)</b><br/><br/>
      <img src="assets/screenshots/2_dashboard-dark.jpeg" width="165" height="350" alt="Dashboard Dark Mode"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>System Vitals</b><br/><br/>
      <img src="assets/screenshots/4_dashboard-2.jpeg" width="165" height="350" alt="System Vitals"/>
    </td>
  </tr>
  <tr>
    <td width="25%" align="center" valign="top">
      <b>Network Cards</b><br/><br/>
      <img src="assets/screenshots/5_dashboard-3.jpeg" width="165" height="350" alt="Network Cards"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Connected Clients</b><br/><br/>
      <img src="assets/screenshots/6_clients.jpeg" width="165" height="350" alt="Connected Clients"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Interfaces</b><br/><br/>
      <img src="assets/screenshots/7_interfaces.jpeg" width="165" height="350" alt="Interfaces"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Interface Details</b><br/><br/>
      <img src="assets/screenshots/8_interfaces-1.jpeg" width="165" height="350" alt="Interface Details"/>
    </td>
  </tr>
  <tr>
    <td width="25%" align="center" valign="top">
      <b>Wireless Radios</b><br/><br/>
      <img src="assets/screenshots/9_wireless.jpeg" width="165" height="350" alt="Wireless Radios"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>System Info</b><br/><br/>
      <img src="assets/screenshots/10_system.jpeg" width="165" height="350" alt="System Info"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Storage Monitor</b><br/><br/>
      <img src="assets/screenshots/11_storage.jpeg" width="165" height="350" alt="Storage Monitor"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Real-Time Charts</b><br/><br/>
      <img src="assets/screenshots/12_realtime_charts.jpeg" width="165" height="350" alt="Real-Time Charts"/>
    </td>
  </tr>
  <tr>
    <td width="25%" align="center" valign="top">
      <b>DHCP & DNS</b><br/><br/>
      <img src="assets/screenshots/13_dhcp_dns.jpeg" width="165" height="350" alt="DHCP & DNS"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Firewall Rules</b><br/><br/>
      <img src="assets/screenshots/14_firewall.jpeg" width="165" height="350" alt="Firewall Rules"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Port Forwarding</b><br/><br/>
      <img src="assets/screenshots/15_firewall-1.jpeg" width="165" height="350" alt="Port Forwarding"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Services & System</b><br/><br/>
      <img src="assets/screenshots/16_services_system.jpeg" width="165" height="350" alt="Services & System"/>
    </td>
  </tr>
  <tr>
    <td width="25%" align="center" valign="top">
      <b>Parental Controls</b><br/><br/>
      <img src="assets/screenshots/17_parental_controls.jpeg" width="165" height="350" alt="Parental Controls"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Parental Rules</b><br/><br/>
      <img src="assets/screenshots/18_parental_controls-1.jpeg" width="165" height="350" alt="Parental Rules"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Settings (PlayStore)</b><br/><br/>
      <img src="assets/screenshots/20-settings-playstore.jpeg" width="165" height="350" alt="Settings PlayStore"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Settings (Community)</b><br/><br/>
      <img src="assets/screenshots/20-settings-community.jpeg" width="165" height="350" alt="Settings Community"/>
    </td>
  </tr>
  <tr>
    <td colspan="2" width="50%" align="center" valign="top">
      <b>Tools & More Menu</b><br/><br/>
      <img src="assets/screenshots/21-more.jpeg" width="165" height="350" alt="Tools & More Menu"/>
    </td>
    <td colspan="2" width="50%" align="center" valign="top">
      <b>Network Diagnostics</b><br/><br/>
      <img src="assets/screenshots/19_diagnostic.jpeg" width="165" height="350" alt="Network Diagnostics"/>
    </td>
  </tr>
  <tr>
    <td colspan="2" width="50%" align="center" valign="top">
      <b>Package Manager (Tablet)</b><br/><br/>
      <img src="assets/screenshots/19_packagemanager.png" width="340" style="max-width: 100%; height: auto;" alt="Package Manager Tablet"/>
    </td>
    <td colspan="2" width="50%" align="center" valign="top">
      <b>About & App Info (Tablet)</b><br/><br/>
      <img src="assets/screenshots/22-about.png" width="340" style="max-width: 100%; height: auto;" alt="About & App Info Tablet"/>
    </td>
  </tr>
</table>

<br>

<details>
  <summary><b>Show More Tablet & Large Screen Screenshots (8 Views)</b></summary>
  <br>
  <p>YALA automatically adapts its layout on tablets, iPads, foldables, and Chromebooks to take full advantage of wider screens:</p>
  <table>
    <tr>
      <td width="50%" align="center" valign="top">
        <b>Multi-Router Profiles & Quick Switch</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_1.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Login & Profiles"/>
      </td>
      <td width="50%" align="center" valign="top">
        <b>Connected Clients & Device Details</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_2.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Connected Clients"/>
      </td>
    </tr>
    <tr>
      <td width="50%" align="center" valign="top">
        <b>Network Interfaces & DSA Switch Topology</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_3.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Network Interfaces"/>
      </td>
      <td width="50%" align="center" valign="top">
        <b>Wireless Overview & Multi-Radio Management</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_4.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Wireless Management"/>
      </td>
    </tr>
    <tr>
      <td width="50%" align="center" valign="top">
        <b>Device Management & Modules Menu</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_5.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Device Management Menu"/>
      </td>
      <td width="50%" align="center" valign="top">
        <b>DHCP & DNS Management</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_6.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet DHCP and DNS"/>
      </td>
    </tr>
    <tr>
      <td width="50%" align="center" valign="top">
        <b>Services, Init Scripts, Cron & Dynamic DNS</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_7.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Services and System"/>
      </td>
      <td width="50%" align="center" valign="top">
        <b>App Settings & Customization</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_8.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Settings"/>
      </td>
    </tr>
  </table>
</details>

<br>

<div align="center">
  <p><i>Browse <a href="assets/screenshots/">assets/screenshots/</a> to view the full resolution collection of screenshots.</i></p>
</div>

---

## Repository Structure

<details>
<summary><b>Show Directory Layout</b></summary>
<br>

```
yala/
├── .github/                   # CI/CD workflows (including unsigned iOS IPA build)
├── android/                   # Android native platform code & signing configs
├── assets/                    # Static app assets
│   ├── fonts/                 # Bundled Geist & Geist Mono font families (FOSS)
│   ├── icons/                 # App launcher icons
│   ├── images/                # Brand graphics & logos
│   ├── mock/                  # Mock diagnostic data for review modes
│   └── screenshots/           # Full app screenshots (including Tab/ tablet gallery)
├── fastlane/                  # Google Play Store release metadata & changelogs
├── fdroid-metadata/           # F-Droid build metadata
├── ios/                       # iOS/iPadOS platform runner & build configurations
├── lib/                       # Main Flutter codebase
│   ├── config/                # Design tokens, themes, app routes, and constants
│   ├── design/                # LuciTheme, breakpoints, responsive layouts & typography
│   ├── l10n/                  # Multi-language localization resources
│   ├── models/                # Data models (Client, Interface, Router, etc.)
│   ├── modules/               # Feature modules
│   │   ├── adguard_home/      # AdGuard Home DNS sinkhole management & telemetry
│   │   ├── bandwidth_monitor/ # Per-client real-time traffic rate monitoring
│   │   ├── charting/          # Real-time throughput charts & graph widgets
│   │   ├── dhcp_dns/          # DHCP leases, static reservations & DNS settings
│   │   ├── diagnostics/       # Ping, traceroute, DNS lookup, routes, ARP, conntrack
│   │   ├── domain_blocking/   # Domain-level blocking rules & per-profile overrides
│   │   ├── firewall_security/ # Firewall zones, rules, NAT & port forwarding
│   │   ├── package_manager/   # OPKG/APK dual-engine package management
│   │   ├── parental_controls/ # Device profiles, timed access & domain filtering
│   │   ├── services_system/   # Init scripts, cron scheduler & Dynamic DNS
│   │   ├── sqm/               # Smart Queue Management (SQM/QoS) bufferbloat control
│   │   ├── storage_monitoring/# Root/overlay flash & external USB storage tracking
│   │   ├── system_backup_upgrade/ # Config backup, sysupgrade & MTD partition tools
│   │   ├── system_monitoring/ # CPU, RAM, swap gauges & system info
│   │   ├── vpn_connectivity/  # WireGuard, OpenVPN, Tailscale, NextDNS & Cloudflare
│   │   └── wireless_management/ # Wireless radios, stations, QR share & MAC ACL
│   ├── screens/               # Core screens (Dashboard, Clients, Interfaces, Login, Settings, More)
│   ├── services/              # API communication layer, JSON-RPC client, SSH service, secure vault
│   ├── state/                 # State management engine (Riverpod controllers)
│   ├── utils/                 # Security guardrails, HTTP client managers, platform utilities
│   ├── widgets/               # Reusable UI widgets, animated gauges, throughput charts, topology map
│   └── main.dart              # Application entry point
├── store-badges/              # App store and release download badges
├── test/                      # Unit, widget, and integration test suite
├── pubspec.yaml               # Flutter package specification & dependencies
├── CHANGELOG.md               # Version history & sync logs
├── CONTRIBUTING.md            # Guidelines for open-source contributors
├── LICENSE                    # GNU General Public License v3.0 (GPLv3)
├── PRIVACY_POLICY.md          # Privacy policy disclosure
└── README.md                  # Project documentation
```

</details>

---

## Router Requirements & Setup

YALA connects directly to your OpenWrt router over HTTP or HTTPS. To ensure full compatibility with all dashboard and monitoring features, install the standard LuCI and RPC modules on your router.

### For OpenWrt 19.07 to 23.05 (OPKG)

SSH into your router and run:

```bash
opkg update
opkg install luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status
/etc/init.d/rpcd restart
```

### For OpenWrt 24.10, 25.x & Snapshots (APK)

OpenWrt 24.10 and newer versions use the `apk` package manager:

```bash
apk update
apk add rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status
/etc/init.d/rpcd restart
```

> [!TIP]
> If your router already has standard LuCI web interface installed, most of these modules (`rpcd-mod-luci`, `luci-mod-status`) are usually already present. YALA automatically detects the available endpoints on your router.

---

## Security & Privacy Highlights

- **Zero Telemetry or Analytics:** No user tracking, no crash telemetry, and no third-party analytics SDKs are bundled into the application.
- **Local Credential Storage:** Router IP addresses, credentials, and session tokens are encrypted locally on your device inside hardware-backed storage (Android KeyStore / iOS Keychain).
- **Self-Device Protection:** Prevents you from accidentally blocking your own phone while configuring firewall rules or MAC filtering.
- **Atomic UCI Rollback:** If a multi-step configuration change fails midway, changes are automatically reverted (`uci revert`) to avoid breaking your router setup.
- **Secure Encrypted Connections:** Supports HTTPS endpoints and custom ports, with an optional self-signed certificate toggle for local subnets.

---

## Building & Running

<details>
<summary><b>Prerequisites, Quick Run & Release Package Instructions</b></summary>
<br>

### Prerequisites

- **Flutter SDK:** 3.27.0+ (or Flutter 3.32+)
- **Dart SDK:** 3.8.1+
- **JDK:** OpenJDK 17 or higher
- **Android Studio / Android SDK:** API level 35/36 (for Android builds)
- **Xcode:** 15.0+ (optional, for macOS/iOS builds)

### Quick Local Run

```bash
# 1. Clone repository
git clone https://github.com/nightcodex7/yala.git
cd yala

# 2. Install dependencies
flutter pub get

# 3. Analyze code quality
flutter analyze

# 4. Run test suite
flutter test

# 5. Run application on connected device
flutter run
```

### Building Release Packages

- **Android APK (split by ABI):**
  ```bash
  flutter build apk --split-per-abi
  ```
  *(Outputs architecture-specific APKs: `arm64-v8a`, `armeabi-v7a`, and `x86_64`)*

- **iOS Unsigned IPA (Local / CI):**
  ```bash
  flutter build ios --no-codesign --release
  ```
  *(Or trigger the manual GitHub Actions workflow `.github/workflows/build-ipa.yml` to produce an unsigned `.ipa` artifact for testing. Pre-built packages are also available on [GitHub Releases](https://github.com/nightcodex7/yala/releases/tag/v2.1.0-beta-ipa))*

</details>

---

## Contributing

Contributions, bug reports, and suggestions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting pull requests.

1. Fork this repository on GitHub (`nightcodex7/yala`).
2. Create your feature branch (`git checkout -b feature/your-feature-name`).
3. Commit your changes (`git commit -m 'feat: description of change'`).
4. Push to the branch (`git push origin feature/your-feature-name`).
5. Open a Pull Request.

---

## Disclaimer & Trademarks

> [!NOTE]
> **YALA is an independent, community-developed open-source project. It is not affiliated with, endorsed by, or sponsored by any of the following organizations or projects:**
>
> - **OpenWrt Project** — YALA communicates with OpenWrt-based routers via their published LuCI JSON-RPC and ubus APIs. "OpenWrt" is a registered trademark of the OpenWrt Project.
> - **AdGuard Ltd.** — The AdGuard Home module manages AdGuard Home instances via their published REST API. "AdGuard" and "AdGuard Home" are trademarks of AdGuard Ltd.
> - **WireGuard LLC** — YALA reads WireGuard interface status from the kernel. "WireGuard" is a registered trademark of Jason A. Donenfeld.
> - **Tailscale Inc.** — YALA reads Tailscale status output exposed through the router. "Tailscale" is a trademark of Tailscale Inc.
> - **Cloudflare, Inc.** — YALA reads `cloudflared` tunnel service status. "Cloudflare" is a trademark of Cloudflare, Inc.
> - **NextDNS Inc.** — YALA reads NextDNS integration status from the router. "NextDNS" is a trademark of NextDNS Inc.
> - **Apple Inc.** — iOS, iPadOS, iPhone, iPad are trademarks of Apple Inc.
> - **Google LLC** — Android, Google Play are trademarks of Google LLC.
>
> All product names, logos, brands, trademarks, and registered trademarks are the property of their respective owners and are used here for identification purposes only.

---

## Origin, Attribution & Licensing

> [!IMPORTANT]
> **YALA** is an independent, standalone project originally based on [`cogwheel0/luci-mobile`](https://github.com/cogwheel0/luci-mobile), created and authored by **cogwheel0**.
>
> Since diverging from the original codebase, YALA has been extensively refactored, modernized, and expanded by **@nightcodex7** with new capabilities including dual package managers (`apk` / `opkg`), a complete network diagnostics suite, tablet & foldable responsive layouts, hardware thermal monitoring, atomic rollbacks, and multi-language support.
>
> The complete codebase — including original upstream code and all subsequent modifications — is licensed under the [GNU General Public License v3.0 (GPL-3.0-or-later)](LICENSE).
>
> I express my sincere thanks to **cogwheel0** for creating the original foundation for mobile LuCI management.

> [!NOTE]
> **Licensing Historical Correction:**  
> Early releases of this project were inadvertently published with an Apache-2.0 identifier. That has since been completely corrected. The project is strictly licensed under GPL-3.0-or-later in accordance with the original project's copyleft terms.

### Copyright

- Original work Copyright (C) 2025–2026 cogwheel0.
- Modifications and enhancements Copyright (C) 2026 @nightcodex7.
