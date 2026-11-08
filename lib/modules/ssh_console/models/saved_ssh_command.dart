// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class SavedSshCommand {
  final String id;
  final String routerId;
  final String name;
  final String command;
  final DateTime createdAt;
  final DateTime? lastRunAt;

  const SavedSshCommand({
    required this.id,
    required this.routerId,
    required this.name,
    required this.command,
    required this.createdAt,
    this.lastRunAt,
  });

  SavedSshCommand copyWith({
    String? id,
    String? routerId,
    String? name,
    String? command,
    DateTime? createdAt,
    DateTime? lastRunAt,
    bool clearLastRunAt = false,
  }) {
    return SavedSshCommand(
      id: id ?? this.id,
      routerId: routerId ?? this.routerId,
      name: name ?? this.name,
      command: command ?? this.command,
      createdAt: createdAt ?? this.createdAt,
      lastRunAt: clearLastRunAt ? null : (lastRunAt ?? this.lastRunAt),
    );
  }

  factory SavedSshCommand.fromJson(Map<String, dynamic> json) {
    return SavedSshCommand(
      id: json['id'] as String? ?? '',
      routerId: json['routerId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      command: json['command'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastRunAt: json['lastRunAt'] != null
          ? DateTime.tryParse(json['lastRunAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'routerId': routerId,
      'name': name,
      'command': command,
      'createdAt': createdAt.toIso8601String(),
      if (lastRunAt != null) 'lastRunAt': lastRunAt!.toIso8601String(),
    };
  }

  static int _counter = 0;

  static String generateId(String routerId) {
    _counter++;
    return '${routerId}_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }
}
