// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class Router {
  final String id;
  final String ipAddress;
  final String username;
  final String password;
  final bool useHttps;
  final String? lastKnownHostname;
  final String? name;

  Router({
    required this.id,
    required this.ipAddress,
    required this.username,
    required this.password,
    required this.useHttps,
    this.lastKnownHostname,
    this.name,
  });

  factory Router.fromJson(Map<String, dynamic> json) {
    return Router(
      id: json['id'] as String,
      ipAddress: json['ipAddress'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      useHttps: json['useHttps'] == true || json['useHttps'] == 'true',
      lastKnownHostname: json['lastKnownHostname'] as String?,
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ipAddress': ipAddress,
    'username': username,
    'password': password,
    'useHttps': useHttps,
    if (lastKnownHostname != null) 'lastKnownHostname': lastKnownHostname,
    if (name != null) 'name': name,
  };

  String get displayName {
    if (name != null && name!.trim().isNotEmpty) return name!.trim();
    if (lastKnownHostname != null && lastKnownHostname!.trim().isNotEmpty) {
      return lastKnownHostname!.trim();
    }
    return ipAddress;
  }

  Router copyWith({
    String? id,
    String? ipAddress,
    String? username,
    String? password,
    bool? useHttps,
    String? lastKnownHostname,
    String? name,
    bool clearName = false,
  }) {
    return Router(
      id: id ?? this.id,
      ipAddress: ipAddress ?? this.ipAddress,
      username: username ?? this.username,
      password: password ?? this.password,
      useHttps: useHttps ?? this.useHttps,
      lastKnownHostname: lastKnownHostname ?? this.lastKnownHostname,
      name: clearName ? null : (name ?? this.name),
    );
  }
}
