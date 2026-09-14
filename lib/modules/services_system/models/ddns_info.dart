// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class DdnsProviderPreset {
  final String serviceName;
  final String label;
  final String requiredPackage;
  final String usernameHint;
  final String passwordHint;
  final String domainHint;
  final String lookupHostHint;
  final bool requiresCustomUrl;

  const DdnsProviderPreset({
    required this.serviceName,
    required this.label,
    required this.requiredPackage,
    required this.usernameHint,
    required this.passwordHint,
    required this.domainHint,
    required this.lookupHostHint,
    this.requiresCustomUrl = false,
  });
}

/// Curated preset catalogue of popular DDNS service providers supported by OpenWrt.
const List<DdnsProviderPreset> kDdnsProviderPresets = [
  DdnsProviderPreset(
    serviceName: 'cloudflare.com-v4',
    label: 'Cloudflare (v4 API)',
    requiredPackage: 'ddns-scripts-cloudflare',
    usernameHint: 'Cloudflare Email or "Bearer" (if using API Token)',
    passwordHint: 'Global API Key or Scoped API Token',
    domainHint: 'Zone or domain name e.g. example.com',
    lookupHostHint: 'Full hostname to update e.g. home.example.com',
  ),
  DdnsProviderPreset(
    serviceName: 'no-ip.com',
    label: 'No-IP.com',
    requiredPackage: 'ddns-scripts-noip',
    usernameHint: 'No-IP Account Username or Email',
    passwordHint: 'No-IP Account Password or DDNS Key',
    domainHint: 'Full hostname e.g. myrouter.ddns.net',
    lookupHostHint: 'Full hostname e.g. myrouter.ddns.net',
  ),
  DdnsProviderPreset(
    serviceName: 'duckdns.org',
    label: 'DuckDNS.org',
    requiredPackage: 'ddns-scripts-duckdns',
    usernameHint: 'Optional (set to "token" or leave blank)',
    passwordHint: 'DuckDNS Account Token',
    domainHint: 'DuckDNS Subdomain e.g. myrouter (without .duckdns.org)',
    lookupHostHint: 'Full hostname e.g. myrouter.duckdns.org',
  ),
  DdnsProviderPreset(
    serviceName: 'dyndns.org',
    label: 'DynDNS.org',
    requiredPackage: 'ddns-scripts',
    usernameHint: 'DynDNS Username',
    passwordHint: 'DynDNS Password or Update Token',
    domainHint: 'Registered DynDNS Hostname',
    lookupHostHint: 'Registered DynDNS Hostname',
  ),
  DdnsProviderPreset(
    serviceName: 'freedns.afraid.org',
    label: 'FreeDNS (afraid.org)',
    requiredPackage: 'ddns-scripts-freedns',
    usernameHint: 'FreeDNS User ID or Token',
    passwordHint: 'FreeDNS Password or Direct Token Key',
    domainHint: 'FreeDNS Domain e.g. myhost.mooo.com',
    lookupHostHint: 'FreeDNS Domain e.g. myhost.mooo.com',
  ),
  DdnsProviderPreset(
    serviceName: 'godaddy.com',
    label: 'GoDaddy.com',
    requiredPackage: 'ddns-scripts-godaddy',
    usernameHint: 'GoDaddy API Key',
    passwordHint: 'GoDaddy API Secret',
    domainHint: 'Domain Name e.g. example.com',
    lookupHostHint: 'Full FQDN e.g. home.example.com',
  ),
  DdnsProviderPreset(
    serviceName: 'custom',
    label: 'Custom Update URL / Script',
    requiredPackage: 'ddns-scripts',
    usernameHint: 'Optional Auth Username / Header',
    passwordHint: 'Optional Auth Password / Key',
    domainHint: 'Target Domain Name',
    lookupHostHint: 'Target Lookup Hostname',
    requiresCustomUrl: true,
  ),
];

/// Represents a single DDNS service instance configuration in OpenWrt (/etc/config/ddns).
class DdnsInstance {
  final String name;
  final bool enabled;
  final String serviceName;
  final String lookupHost;
  final String domain;
  final String username;
  final String password;
  final String interface;
  final String ipSource;
  final String ipNetwork;
  final String ipUrl;
  final String updateUrl;
  final String updateScript;
  final bool useHttps;
  final int checkInterval;
  final String checkUnit;
  final int forceInterval;
  final String forceUnit;
  final String? statusStr;
  final String? lastUpdate;

  const DdnsInstance({
    required this.name,
    this.enabled = true,
    required this.serviceName,
    required this.lookupHost,
    required this.domain,
    this.username = '',
    this.password = '',
    this.interface = 'wan',
    this.ipSource = 'web',
    this.ipNetwork = 'wan',
    this.ipUrl = 'http://checkip.dyndns.com',
    this.updateUrl = '',
    this.updateScript = '',
    this.useHttps = true,
    this.checkInterval = 10,
    this.checkUnit = 'minutes',
    this.forceInterval = 24,
    this.forceUnit = 'hours',
    this.statusStr,
    this.lastUpdate,
  });

  DdnsInstance copyWith({
    String? name,
    bool? enabled,
    String? serviceName,
    String? lookupHost,
    String? domain,
    String? username,
    String? password,
    String? interface,
    String? ipSource,
    String? ipNetwork,
    String? ipUrl,
    String? updateUrl,
    String? updateScript,
    bool? useHttps,
    int? checkInterval,
    String? checkUnit,
    int? forceInterval,
    String? forceUnit,
    String? statusStr,
    String? lastUpdate,
  }) {
    return DdnsInstance(
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      serviceName: serviceName ?? this.serviceName,
      lookupHost: lookupHost ?? this.lookupHost,
      domain: domain ?? this.domain,
      username: username ?? this.username,
      password: password ?? this.password,
      interface: interface ?? this.interface,
      ipSource: ipSource ?? this.ipSource,
      ipNetwork: ipNetwork ?? this.ipNetwork,
      ipUrl: ipUrl ?? this.ipUrl,
      updateUrl: updateUrl ?? this.updateUrl,
      updateScript: updateScript ?? this.updateScript,
      useHttps: useHttps ?? this.useHttps,
      checkInterval: checkInterval ?? this.checkInterval,
      checkUnit: checkUnit ?? this.checkUnit,
      forceInterval: forceInterval ?? this.forceInterval,
      forceUnit: forceUnit ?? this.forceUnit,
      statusStr: statusStr ?? this.statusStr,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }

  factory DdnsInstance.fromUci(String sectionName, Map<String, dynamic> json) {
    bool parseBool(dynamic val, {bool defaultValue = false}) {
      if (val == null) return defaultValue;
      if (val is bool) return val;
      final str = val.toString().trim();
      return str == '1' ||
          str.toLowerCase() == 'true' ||
          str.toLowerCase() == 'yes';
    }

    int parseInt(dynamic val, {int defaultValue = 10}) {
      if (val == null) return defaultValue;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? defaultValue;
    }

    return DdnsInstance(
      name: sectionName,
      enabled: parseBool(json['enabled'], defaultValue: true),
      serviceName: json['service_name']?.toString() ?? 'cloudflare.com-v4',
      lookupHost: json['lookup_host']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      interface: json['interface']?.toString() ?? 'wan',
      ipSource: json['ip_source']?.toString() ?? 'web',
      ipNetwork: json['ip_network']?.toString() ?? 'wan',
      ipUrl: json['ip_url']?.toString() ?? 'http://checkip.dyndns.com',
      updateUrl: json['update_url']?.toString() ?? '',
      updateScript: json['update_script']?.toString() ?? '',
      useHttps: parseBool(json['use_https'], defaultValue: true),
      checkInterval: parseInt(json['check_interval'], defaultValue: 10),
      checkUnit: json['check_unit']?.toString() ?? 'minutes',
      forceInterval: parseInt(json['force_interval'], defaultValue: 24),
      forceUnit: json['force_unit']?.toString() ?? 'hours',
      statusStr: json['status']?.toString(),
      lastUpdate: json['last_update']?.toString(),
    );
  }

  Map<String, dynamic> toUciParams() {
    final params = <String, dynamic>{
      'enabled': enabled ? '1' : '0',
      'service_name': serviceName,
      'lookup_host': lookupHost,
      'domain': domain,
      'username': username,
      'password': password,
      'interface': interface,
      'ip_source': ipSource,
      'ip_network': ipNetwork,
      'use_https': useHttps ? '1' : '0',
      'check_interval': checkInterval.toString(),
      'check_unit': checkUnit,
      'force_interval': forceInterval.toString(),
      'force_unit': forceUnit,
    };

    if (ipSource == 'web' && ipUrl.isNotEmpty) {
      params['ip_url'] = ipUrl;
    }
    if (serviceName == 'custom') {
      if (updateUrl.isNotEmpty) params['update_url'] = updateUrl;
      if (updateScript.isNotEmpty) params['update_script'] = updateScript;
    }
    return params;
  }
}

/// Overview descriptor for Dynamic DNS state on the router.
class DdnsOverview {
  final bool isInstalled;
  final bool isGlobalEnabled;
  final List<String> installedPackages;
  final List<DdnsInstance> instances;

  const DdnsOverview({
    required this.isInstalled,
    required this.isGlobalEnabled,
    required this.installedPackages,
    required this.instances,
  });

  factory DdnsOverview.fromDashboardData(
    Map<String, dynamic>? data, {
    bool isReviewerMode = false,
  }) {
    if (isReviewerMode) {
      return const DdnsOverview(
        isInstalled: true,
        isGlobalEnabled: true,
        installedPackages: [
          'ddns-scripts',
          'ddns-scripts-cloudflare',
          'ddns-scripts-noip',
          'luci-app-ddns',
        ],
        instances: [
          DdnsInstance(
            name: 'myddns_ipv4',
            enabled: true,
            serviceName: 'cloudflare.com-v4',
            lookupHost: 'home.example.com',
            domain: 'example.com',
            username: 'Bearer',
            password: 'cf_api_token_sample_key_987',
            interface: 'wan',
            ipSource: 'web',
            useHttps: true,
            checkInterval: 10,
            checkUnit: 'minutes',
            forceInterval: 24,
            forceUnit: 'hours',
            statusStr: 'Synced (192.0.2.45)',
            lastUpdate: '10 min ago',
          ),
          DdnsInstance(
            name: 'backup_noip',
            enabled: false,
            serviceName: 'no-ip.com',
            lookupHost: 'myrouter.ddns.net',
            domain: 'myrouter.ddns.net',
            username: 'admin@example.com',
            password: 'noip_password_sample',
            interface: 'wan',
            ipSource: 'network',
            useHttps: true,
            checkInterval: 15,
            checkUnit: 'minutes',
            statusStr: 'Disabled',
            lastUpdate: 'Never',
          ),
        ],
      );
    }

    if (data == null || data['ddns'] == null) {
      return const DdnsOverview(
        isInstalled: false,
        isGlobalEnabled: false,
        installedPackages: [],
        instances: [],
      );
    }

    final ddnsData = data['ddns'] as Map<String, dynamic>;
    final installedPkgs =
        (data['installedPackages'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    bool installed =
        installedPkgs.any(
          (p) => p.contains('ddns-scripts') || p.contains('ddns'),
        ) ||
        ddnsData.isNotEmpty;
    bool? explicitGlobalEnabled;

    final instList = <DdnsInstance>[];

    ddnsData.forEach((key, value) {
      if (key == 'global' && value is Map) {
        final ge = value['is_enabled'] ?? value['enabled'];
        if (ge != null) {
          explicitGlobalEnabled =
              ge == '1' ||
              ge == 1 ||
              ge == true ||
              ge.toString().toLowerCase() == 'true';
        }
      } else if (value is Map &&
          (value['.type'] == 'service' ||
              value['service_name'] != null ||
              value['domain'] != null)) {
        instList.add(
          DdnsInstance.fromUci(key, Map<String, dynamic>.from(value)),
        );
      }
    });

    bool globalEnabled;
    if (explicitGlobalEnabled != null) {
      globalEnabled = explicitGlobalEnabled!;
    } else {
      // Check init.d or procd service status for 'ddns' if UCI global section is absent
      final initScripts = data['initScripts'] as Map<String, dynamic>?;
      final services = data['services'] as Map<String, dynamic>?;

      if (services != null && services['ddns'] is Map) {
        final ddnsSvc = services['ddns'] as Map;
        final running =
            ddnsSvc['running'] == true ||
            ddnsSvc['running'] == 1 ||
            ddnsSvc['running'] == '1';
        final enabled =
            ddnsSvc['enabled'] == true ||
            ddnsSvc['enabled'] == 1 ||
            ddnsSvc['enabled'] == '1';
        globalEnabled = running || enabled;
      } else if (initScripts != null && initScripts['ddns'] is Map) {
        final ddnsInit = initScripts['ddns'] as Map;
        final running =
            ddnsInit['running'] == true ||
            ddnsInit['running'] == 1 ||
            ddnsInit['running'] == '1';
        final enabled =
            ddnsInit['enabled'] == true ||
            ddnsInit['enabled'] == 1 ||
            ddnsInit['enabled'] == '1';
        globalEnabled = running || enabled;
      } else if (instList.isNotEmpty) {
        // Default to true if any instance is enabled, otherwise false
        globalEnabled = instList.any((inst) => inst.enabled);
      } else {
        globalEnabled = false;
      }
    }

    instList.sort((a, b) {
      if (a.enabled != b.enabled) {
        return a.enabled ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });

    return DdnsOverview(
      isInstalled: installed,
      isGlobalEnabled: globalEnabled,
      installedPackages: installedPkgs,
      instances: instList,
    );
  }
}

/// Validation result container for pre-save and live test operations.
class DdnsValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? testOutput;

  const DdnsValidationResult({
    required this.isValid,
    this.errorMessage,
    this.testOutput,
  });

  factory DdnsValidationResult.success({String? testOutput}) {
    return DdnsValidationResult(isValid: true, testOutput: testOutput);
  }

  factory DdnsValidationResult.failure(String message, {String? testOutput}) {
    return DdnsValidationResult(
      isValid: false,
      errorMessage: message,
      testOutput: testOutput,
    );
  }
}
