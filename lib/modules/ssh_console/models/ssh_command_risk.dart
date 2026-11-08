// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

enum SshCommandRisk { normal, elevated, destructive }

class SshCommandClassifier {
  static final _destructivePatterns = [
    RegExp(r'\brm\s+-[a-zA-Z]*r[a-zA-Z]*f?\b', caseSensitive: false),
    RegExp(r'\bsysupgrade\b', caseSensitive: false),
    RegExp(r'\bfirstboot\b', caseSensitive: false),
    RegExp(r'\bmtd\s+(erase|write)\b', caseSensitive: false),
    RegExp(r'\bdd\s+if=.*of=/dev/', caseSensitive: false),
    RegExp(r'\bmkfs\b', caseSensitive: false),
  ];

  static final _elevatedPatterns = [
    RegExp(r'\breboot\b', caseSensitive: false),
    RegExp(r'\b(poweroff|halt)\b', caseSensitive: false),
    RegExp(r'\buci\s+commit\b', caseSensitive: false),
    RegExp(r'\bopkg\s+(remove|install)\b', caseSensitive: false),
    RegExp(r'\bpasswd\b', caseSensitive: false),
    RegExp(r'\b(iptables|ip6tables)\s+-F\b', caseSensitive: false),
    RegExp(r'\bnft\s+flush\b', caseSensitive: false),
    RegExp(r'/etc/init\.d/\S+\s+(stop|restart|reload)\b', caseSensitive: false),
  ];

  static SshCommandRisk classify(String command) {
    final trimmed = command.trim();
    for (final pattern in _destructivePatterns) {
      if (pattern.hasMatch(trimmed)) {
        return SshCommandRisk.destructive;
      }
    }
    for (final pattern in _elevatedPatterns) {
      if (pattern.hasMatch(trimmed)) {
        return SshCommandRisk.elevated;
      }
    }
    return SshCommandRisk.normal;
  }
}
