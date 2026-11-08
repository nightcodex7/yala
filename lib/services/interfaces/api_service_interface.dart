// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/modules/services_system/models/ddns_info.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_queue.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/internet_reachability.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/ping_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/traceroute_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/dns_lookup_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/routing_neighbor_info.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/diagnostic_report.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/flush_dns_result.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dnsmasq_service_result.dart';
import 'package:yet_another_luci_app/modules/log_viewer/models/log_fetch_result.dart';
import 'package:yet_another_luci_app/modules/bandwidth_monitor/models/bandwidth_data.dart';
import 'package:yet_another_luci_app/models/network_access_policy.dart';
import 'package:yet_another_luci_app/models/client_speed_limit.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';

enum AuthStatus { success, invalidCredentials, unreachable, unknownError }

class AuthResult {
  final AuthStatus status;
  final String? token;
  final bool actualUseHttps;
  final String? errorMessage;

  const AuthResult({
    required this.status,
    this.token,
    this.actualUseHttps = false,
    this.errorMessage,
  });

  factory AuthResult.success(String token, {bool actualUseHttps = false}) =>
      AuthResult(
        status: AuthStatus.success,
        token: token,
        actualUseHttps: actualUseHttps,
      );

  factory AuthResult.invalidCredentials([String? message]) => AuthResult(
    status: AuthStatus.invalidCredentials,
    errorMessage: message ?? 'Invalid username or password',
  );

  factory AuthResult.unreachable([String? message]) => AuthResult(
    status: AuthStatus.unreachable,
    errorMessage:
        message ??
        'Router unreachable. Check network connection and IP address.',
  );

  factory AuthResult.unknownError(String message) =>
      AuthResult(status: AuthStatus.unknownError, errorMessage: message);

  bool get isSuccess => status == AuthStatus.success;
}

class SetPasswordRpcResponse {
  final bool isSuccess;
  final bool isRejected;
  final bool isNetworkError;
  final String? message;

  const SetPasswordRpcResponse.success()
    : isSuccess = true,
      isRejected = false,
      isNetworkError = false,
      message = null;

  const SetPasswordRpcResponse.rejected([this.message])
    : isSuccess = false,
      isRejected = true,
      isNetworkError = false;

  const SetPasswordRpcResponse.networkError([this.message])
    : isSuccess = false,
      isRejected = false,
      isNetworkError = true;
}

/// API service interface for LuCI RPC communication.
///
/// All RPC methods that return dynamic data follow the LuCI RPC response format:
/// [status, data] where:
/// - status: Integer (0 = success, non-zero = error)
/// - data: The actual response data (varies by method)
///
/// Example: [0, {"hostname": "router", "model": "TP-Link"}]
abstract class IApiService {
  Future<AuthResult> authenticate(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  });
  Future<String> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  });
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  });
  // Simplified call method for reviewer mode
  Future<dynamic> callSimple(
    String object,
    String method,
    Map<String, dynamic> params,
  );
  Future<bool> reboot(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<Map<String, dynamic>?> fetchWireGuardPeers({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  });
  Future<Map<String, Set<String>>> fetchAssociatedStations();
  Future<List<String>> fetchAssociatedStationsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  });
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchAllAssociatedWirelessStationsWithDetailsContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });
  Future<Map<String, Map<String, dynamic>>> fetchHostHintsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, String> values,
    BuildContext? context,
  });
  Future<List<String>> fetchNetworkInterfaces({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  });
  Future<dynamic> uciRevert(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  });
  Future<bool> uciApply(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    bool rollback = true,
    int timeout = 30,
  });
  Future<bool> uciConfirm(String ipAddress, String sysauth, bool useHttps);
  Future<SetPasswordRpcResponse> setRouterPassword(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String username = 'root',
    required String newPassword,
  });
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    BuildContext? context,
  });
  bool execSucceeded(dynamic res);
  Future<bool> disconnectWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  });
  Future<bool> setSsidEnabled(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String ifaceSection,
    required bool enabled,
    BuildContext? context,
  });
  Future<bool> toggleWirelessRadio(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required bool enabled,
    BuildContext? context,
  });
  Future<bool> updateWirelessInterfaceConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> values,
    List<String>? deleteOptions,
    BuildContext? context,
  });
  Future<bool> revertWirelessInterfaceConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> priorValues,
    BuildContext? context,
  });
  Future<bool> updateWirelessRadioConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> values,
    List<String>? deleteOptions,
    BuildContext? context,
  });
  Future<bool> revertWirelessRadioConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> priorValues,
    BuildContext? context,
  });
  Future<bool> addWirelessInterface(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    required String network,
    Map<String, String>? extraOptions,
    BuildContext? context,
  });
  Future<bool> deleteWirelessInterface(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    BuildContext? context,
  });
  Future<bool> updateInterfaceDhcpConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String interface,
    required Map<String, dynamic> values,
    BuildContext? context,
  });
  Future<bool> provisionGuestNetwork(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    String guestIp = '192.168.2.1',
    bool isolateClients = true,
    String network = 'guest',
    // Advanced radio settings
    String? country,
    String? channel,
    String? htMode,
    String? txPower,
    // Fast roaming (802.11r/k/v)
    bool ieee80211r = false,
    bool ftOverDs = false,
    bool ftPskGenerateLocal = false,
    String? mobilityDomain,
    // Wireless advanced settings
    bool wmm = true,
    bool hidden = false,
    int? dtimPeriod,
    int? gtkRekey,
    int? inactivityLimit,
    int? maxListenInterval,
    bool disassocLowAck = true,
    bool multicastToUnicast = false,
    bool wds = false,
    // MAC filtering
    String? macfilter,
    List<String>? maclist,
    BuildContext? context,
  });
  Future<bool> setWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required Map<String, List<String>> maclistByIface,
    required Map<String, String> macfilterByIface,
    BuildContext? context,
  });
  Future<bool> confirmWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> revertWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required Map<String, List<String>> maclistByIface,
    required Map<String, String> macfilterByIface,
    BuildContext? context,
  });
  Future<bool> autoFixPermissions(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> manageServiceAction(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String serviceName,
    required String action,
    BuildContext? context,
  });
  Future<bool> pauseClientInternet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    required bool pause,
    BuildContext? context,
  });
  Future<bool> addFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallPortForwarding portForward,
    BuildContext? context,
  });
  Future<bool> updateFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallPortForwarding portForward,
    BuildContext? context,
  });
  Future<bool> deleteFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionKey,
    BuildContext? context,
  });
  Future<bool> addFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallCustomRule rule,
    BuildContext? context,
  });
  Future<bool> updateFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallCustomRule rule,
    BuildContext? context,
  });
  Future<bool> deleteFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionKey,
    BuildContext? context,
  });
  Future<bool> reorderFirewallCustomRules(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String targetSectionKey,
    required String siblingSectionKey,
    required List<String> expectedRuleOrder,
    BuildContext? context,
  });
  Future<bool> applyPerDeviceNetworkAccessPolicy(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required NetworkAccessPolicy policy,
    required RouterCapabilities capabilities,
    BuildContext? context,
  });
  Future<bool> applyClientSpeedLimits(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<ClientSpeedLimit> limits,
    required RouterCapabilities capabilities,
    BuildContext? context,
  });
  Future<Set<int>> discoverManagementPorts(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> banWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  });
  Future<bool> unbanWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    BuildContext? context,
  });
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchRestrictedAndBannedClientsLive(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> addStaticLease(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    required String targetIp,
    required String hostname,
    String? targetIp6,
    String? duid,
    String? leaseTime,
    BuildContext? context,
  });
  Future<bool> deleteStaticLease(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? targetIp,
    String? hostname,
    String? duid,
    BuildContext? context,
  });
  Future<bool> refreshClientConnection(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    BuildContext? context,
  });
  Future<int> deleteUnusedDhcpLeases(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<String> macsToFlush,
    BuildContext? context,
  });
  Future<Map<String, String?>> fetchPublicIps(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> forceRefreshDhcpLeases(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> saveCronJobs(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<String> cronLines,
    BuildContext? context,
  });
  Future<bool> saveDdnsInstance(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required DdnsInstance instance,
    BuildContext? context,
  });
  Future<bool> deleteDdnsInstance(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String instanceName,
    BuildContext? context,
  });
  Future<DdnsValidationResult> testDdnsConfiguration(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required DdnsInstance instance,
    BuildContext? context,
  });
  Future<bool> toggleGlobalDdns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required bool enable,
    BuildContext? context,
  });
  Future<bool> saveSqmQueue(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required SqmQueue queue,
    BuildContext? context,
  });
  Future<bool> deleteSqmQueue(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    BuildContext? context,
  });
  Future<bool> toggleSqmService(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required bool enable,
    BuildContext? context,
  });

  /// Fetches hardware-supported encryptions and ciphers from iwinfo for a wireless device
  Future<Map<String, List<Map<String, String>>>>
  fetchWirelessHardwareCapabilities({
    required String sectionName,
    String? radioName,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });

  /// Fetches physical radio hardware capabilities (countrylist, freqlist, htmodelist, txpowerlist) from iwinfo for a wireless radio
  Future<Map<String, dynamic>> fetchWirelessRadioCapabilities({
    required String radioName,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });

  Future<int> migrateAnonymousWirelessSections(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<bool> applyParentalProfileDns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String profileId,
    required List<String> macAddresses,
    required List<String>? dnsServers,
    BuildContext? context,
  });

  Future<List<ParentalProfile>?> fetchParentalProfiles(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<bool> saveParentalProfile(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required ParentalProfile profile,
    BuildContext? context,
  });

  Future<bool> deleteParentalProfile(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String profileId,
    BuildContext? context,
  });

  /// Installs the native lightweight OpenWrt temperature RPC handler and ACL rule
  Future<bool> installNativeTemperatureHandler(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Executes ping command on router via rpcd file.exec
  Future<PingResult> executePing(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String target,
    int count = 3,
    int timeoutSec = 2,
    bool isIpv6 = false,
    BuildContext? context,
  });

  /// Executes traceroute on router via rpcd file.exec
  Future<TracerouteResult> executeTraceroute(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String target,
    int maxHops = 15,
    int timeoutSec = 1,
    bool isIpv6 = false,
    BuildContext? context,
  });

  /// Executes DNS resolution check via rpcd file.exec (nslookup)
  Future<DnsLookupResult> executeDnsLookup(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String host,
    String? server,
    BuildContext? context,
  });

  /// Tests router WAN internet reachability (gateway, public DNS, and DNS lookup)
  Future<InternetReachability> testInternetReachability(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Fetches the kernel routing table via ip -4 route
  Future<List<RouteEntry>> fetchRoutingTable(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Fetches the ARP neighbor table via ip -4 neigh
  Future<List<NeighborEntry>> fetchNeighborTable(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Fetches conntrack table count and max
  Future<ConntrackInfo?> fetchConntrackInfo(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Generates a full diagnostic report bundle
  Future<DiagnosticReport> generateFullDiagnosticReport(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Flushes DNS resolver cache (dnsmasq / unbound / smartdns) and reloads local hosts
  Future<FlushDnsResult> flushDns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Reloads the dnsmasq service (DHCP & DNS) to apply configuration changes and refresh service state.
  Future<DnsmasqServiceResult> reloadDnsmasq(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Fetches system log entries (logread / syslog) from the router.
  Future<LogFetchResult> fetchSyslog(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    int lines = 200,
    BuildContext? context,
  });

  /// Fetches kernel log entries (dmesg ring buffer) from the router.
  Future<LogFetchResult> fetchKernelLog(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    int lines = 200,
    BuildContext? context,
  });

  /// Executes a system command directly via LuCI's streaming CGI endpoint (/cgi-bin/cgi-exec)
  /// without rpcd's 256KB buffer ceiling (RPC_FILE_MAX_SIZE).
  Future<String?> execDirectCgi(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String>? params,
    int stderr = 0,
    BuildContext? context,
  });

  /// Fetches native time-series traffic stats from LuCI's luci-bwc daemon
  /// mode: 'interface' (with device e.g. 'eth0', 'br-lan') or 'wireless' (with device e.g. 'phy0-ap0')
  Future<List<RealtimeTrafficPoint>> fetchRealtimeStats(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String mode,
    String? device,
    BuildContext? context,
  });

  /// Checks if nlbwmon (Netlink Bandwidth Monitor) is installed and available
  Future<bool> checkNlbwmonInstalled(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Fetches persistent per-client traffic accounting from nlbwmon
  Future<NlbwmonReport?> fetchNlbwmonData(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String groupBy = 'mac',
    String? period,
    BuildContext? context,
  });

  /// Fetches list of available historical database periods from nlbwmon
  Future<List<String>> fetchNlbwmonPeriods(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Sets the router system hostname in UCI (/etc/config/system) and applies changes.
  Future<bool> setRouterHostname(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String newHostname, {
    BuildContext? context,
  });

  /// Retrieves the list of globally blocked domains in dnsmasq via UCI (`dhcp.@dnsmasq[*].address`).
  Future<List<String>> getDnsmasqBlockedDomains(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Adds a domain to the global blocked list in dnsmasq via UCI (`dhcp.@dnsmasq.address`).
  ///
  /// Uses server-side rollback (`uciApply(rollback: true, timeout: 30)`), authenticated reachability
  /// verification (`uci.get`), and `uciConfirm()`.
  Future<bool> addDnsmasqBlockedDomain(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String domain, {
    BuildContext? context,
  });

  /// Removes a domain from the global blocked list in dnsmasq via UCI (`dhcp.@dnsmasq.address`).
  ///
  /// Uses server-side rollback (`uciApply(rollback: true, timeout: 30)`), authenticated reachability
  /// verification (`uci.get`), and `uciConfirm()`.
  Future<bool> removeDnsmasqBlockedDomain(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String domain, {
    BuildContext? context,
  });
}
