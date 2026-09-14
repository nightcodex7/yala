// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

/// Days of week for schedule configuration.
enum ScheduleDay {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}

extension ScheduleDayExtension on ScheduleDay {
  String get shortLabel {
    switch (this) {
      case ScheduleDay.monday:
        return 'Mon';
      case ScheduleDay.tuesday:
        return 'Tue';
      case ScheduleDay.wednesday:
        return 'Wed';
      case ScheduleDay.thursday:
        return 'Thu';
      case ScheduleDay.friday:
        return 'Fri';
      case ScheduleDay.saturday:
        return 'Sat';
      case ScheduleDay.sunday:
        return 'Sun';
    }
  }

  String get longLabel {
    switch (this) {
      case ScheduleDay.monday:
        return 'Monday';
      case ScheduleDay.tuesday:
        return 'Tuesday';
      case ScheduleDay.wednesday:
        return 'Wednesday';
      case ScheduleDay.thursday:
        return 'Thursday';
      case ScheduleDay.friday:
        return 'Friday';
      case ScheduleDay.saturday:
        return 'Saturday';
      case ScheduleDay.sunday:
        return 'Sunday';
    }
  }

  /// Cron day-of-week (0=Sunday…6=Saturday in cron, but we normalize to 0=Sunday)
  int get cronIndex {
    switch (this) {
      case ScheduleDay.sunday:
        return 0;
      case ScheduleDay.monday:
        return 1;
      case ScheduleDay.tuesday:
        return 2;
      case ScheduleDay.wednesday:
        return 3;
      case ScheduleDay.thursday:
        return 4;
      case ScheduleDay.friday:
        return 5;
      case ScheduleDay.saturday:
        return 6;
    }
  }

  static ScheduleDay fromIndex(int index) => ScheduleDay.values[index];
}

/// Preset family-safe DNS upstream options.
enum ContentFilterDns {
  none,
  cloudflareFamilySafe,
  openDnsFamilyShield,
  custom,
}

extension ContentFilterDnsExtension on ContentFilterDns {
  String get label {
    switch (this) {
      case ContentFilterDns.none:
        return 'None (Router Default)';
      case ContentFilterDns.cloudflareFamilySafe:
        return 'Cloudflare Family (1.1.1.3)';
      case ContentFilterDns.openDnsFamilyShield:
        return 'OpenDNS Family Shield';
      case ContentFilterDns.custom:
        return 'Custom DNS';
    }
  }

  List<String> get primaryServers {
    switch (this) {
      case ContentFilterDns.none:
        return [];
      case ContentFilterDns.cloudflareFamilySafe:
        return ['1.1.1.3', '1.0.0.3'];
      case ContentFilterDns.openDnsFamilyShield:
        return ['208.67.222.123', '208.67.220.123'];
      case ContentFilterDns.custom:
        return [];
    }
  }

  String get description {
    switch (this) {
      case ContentFilterDns.none:
        return 'Devices use router default DNS — no content filtering applied.';
      case ContentFilterDns.cloudflareFamilySafe:
        return 'Blocks malware, adult content. Uses Cloudflare 1.1.1.3 / 1.0.0.3.';
      case ContentFilterDns.openDnsFamilyShield:
        return 'Blocks adult content via OpenDNS 208.67.222.123 / 208.67.220.123.';
      case ContentFilterDns.custom:
        return 'Use custom upstream DNS addresses for this profile.';
    }
  }

  String toStorageString() {
    switch (this) {
      case ContentFilterDns.none:
        return 'none';
      case ContentFilterDns.cloudflareFamilySafe:
        return 'cloudflare_family';
      case ContentFilterDns.openDnsFamilyShield:
        return 'opendns_family';
      case ContentFilterDns.custom:
        return 'custom';
    }
  }
}

/// Top-level helper to parse ContentFilterDns from a stored string.
ContentFilterDns contentFilterDnsFromString(String? value) {
  switch (value) {
    case 'cloudflare_family':
      return ContentFilterDns.cloudflareFamilySafe;
    case 'opendns_family':
      return ContentFilterDns.openDnsFamilyShield;
    case 'custom':
      return ContentFilterDns.custom;
    default:
      return ContentFilterDns.none;
  }
}

/// A time-based block schedule for a parental profile.
class TimeSchedule {
  /// Which days this schedule is active.
  final Set<ScheduleDay> activeDays;

  /// Hour of day when internet is BLOCKED (0–23).
  final int blockHour;
  final int blockMinute;

  /// Hour of day when internet is RESUMED (0–23).
  final int resumeHour;
  final int resumeMinute;

  /// Whether this schedule is currently enabled.
  final bool enabled;

  const TimeSchedule({
    required this.activeDays,
    required this.blockHour,
    required this.blockMinute,
    required this.resumeHour,
    required this.resumeMinute,
    this.enabled = true,
  });

  String get blockTimeFormatted =>
      '${blockHour.toString().padLeft(2, '0')}:${blockMinute.toString().padLeft(2, '0')}';

  String get resumeTimeFormatted =>
      '${resumeHour.toString().padLeft(2, '0')}:${resumeMinute.toString().padLeft(2, '0')}';

  String get activeDaysLabel {
    if (activeDays.length == 7) {
      return 'Every day';
    }
    if (activeDays.containsAll([ScheduleDay.saturday, ScheduleDay.sunday]) &&
        activeDays.length == 2) {
      return 'Weekends';
    }
    if (activeDays
                .where(
                  (d) => d != ScheduleDay.saturday && d != ScheduleDay.sunday,
                )
                .length ==
            5 &&
        !activeDays.contains(ScheduleDay.saturday) &&
        !activeDays.contains(ScheduleDay.sunday)) {
      return 'Weekdays';
    }
    final sorted = activeDays.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return sorted.map((d) => d.shortLabel).join(', ');
  }

  /// Returns whether a given local time falls within this block schedule window.
  bool isTimeInBlockWindow([DateTime? now]) {
    if (!enabled || activeDays.isEmpty) return false;
    final dt = (now ?? DateTime.now()).toLocal();
    final dayOfWeek = dt.weekday; // 1=Mon, ..., 7=Sun
    final scheduleDay = ScheduleDay.values[(dayOfWeek - 1) % 7];
    if (!activeDays.contains(scheduleDay)) return false;

    final currentMin = dt.hour * 60 + dt.minute;
    final blockMin = blockHour * 60 + blockMinute;
    final resumeMin = resumeHour * 60 + resumeMinute;

    if (blockMin < resumeMin) {
      // Daytime block schedule (e.g. 14:00 to 17:00)
      return currentMin >= blockMin && currentMin < resumeMin;
    } else if (blockMin > resumeMin) {
      // Overnight block schedule (e.g. 22:00 to 07:00)
      return currentMin >= blockMin || currentMin < resumeMin;
    } else {
      // Equal times = 24-hour block on active days
      return true;
    }
  }

  TimeSchedule copyWith({
    Set<ScheduleDay>? activeDays,
    int? blockHour,
    int? blockMinute,
    int? resumeHour,
    int? resumeMinute,
    bool? enabled,
  }) {
    return TimeSchedule(
      activeDays: activeDays ?? this.activeDays,
      blockHour: blockHour ?? this.blockHour,
      blockMinute: blockMinute ?? this.blockMinute,
      resumeHour: resumeHour ?? this.resumeHour,
      resumeMinute: resumeMinute ?? this.resumeMinute,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'active_days': activeDays.map((d) => d.index).toList(),
    'block_hour': blockHour,
    'block_minute': blockMinute,
    'resume_hour': resumeHour,
    'resume_minute': resumeMinute,
    'enabled': enabled,
  };

  factory TimeSchedule.fromJson(Map<String, dynamic> json) {
    final rawDays =
        (json['active_days'] as List?)
            ?.map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toList() ??
        [];
    return TimeSchedule(
      activeDays: rawDays
          .where((d) => d >= 0 && d < ScheduleDay.values.length)
          .map((d) => ScheduleDay.values[d])
          .toSet(),
      blockHour: (json['block_hour'] as num?)?.toInt() ?? 22,
      blockMinute: (json['block_minute'] as num?)?.toInt() ?? 0,
      resumeHour: (json['resume_hour'] as num?)?.toInt() ?? 7,
      resumeMinute: (json['resume_minute'] as num?)?.toInt() ?? 0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// Pause duration options for on-demand internet pause.
enum PauseDuration {
  fifteenMinutes,
  thirtyMinutes,
  oneHour,
  untilTomorrow,
  indefinite,
}

extension PauseDurationExtension on PauseDuration {
  String get label {
    switch (this) {
      case PauseDuration.fifteenMinutes:
        return '15 Minutes';
      case PauseDuration.thirtyMinutes:
        return '30 Minutes';
      case PauseDuration.oneHour:
        return '1 Hour';
      case PauseDuration.untilTomorrow:
        return 'Until Tomorrow';
      case PauseDuration.indefinite:
        return 'Until I Resume';
    }
  }

  Duration? get duration {
    switch (this) {
      case PauseDuration.fifteenMinutes:
        return const Duration(minutes: 15);
      case PauseDuration.thirtyMinutes:
        return const Duration(minutes: 30);
      case PauseDuration.oneHour:
        return const Duration(hours: 1);
      case PauseDuration.untilTomorrow:
        return null; // calculated separately
      case PauseDuration.indefinite:
        return null;
    }
  }
}

/// Emoji icons for parental profiles.
const List<String> kProfileIcons = [
  '👦',
  '👧',
  '👶',
  '🧒',
  '👩',
  '👨',
  '🎮',
  '📱',
  '💻',
  '🖥',
  '📺',
  '🎵',
  '⭐',
  '🌟',
  '🏠',
  '🐱',
  '🐶',
  '🐰',
  '🦁',
  '🐼',
];

/// A named group of devices with associated parental controls.
class ParentalProfile {
  final String id;
  final String name;
  final String icon;
  final String color; // hex color string e.g. '#FF5722'

  /// MAC addresses of devices assigned to this profile.
  final List<String> macAddresses;

  /// Whether internet access is currently paused for this profile.
  final bool isPaused;

  /// Whether rules/guardrails for this profile are active (true) or bypassed (false).
  final bool isEnabled;

  /// If non-null, the timestamp (UTC) when a timed pause expires.
  final DateTime? pauseExpiresAt;

  /// Optional recurring block schedule.
  final TimeSchedule? schedule;

  /// Daily time limit in minutes (null = no limit).
  final int? dailyTimeLimitMinutes;

  /// Content filtering DNS preset for this profile.
  final ContentFilterDns contentFilter;

  /// Custom DNS servers (only used when contentFilter == ContentFilterDns.custom).
  final List<String> customDnsServers;

  const ParentalProfile({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.macAddresses,
    this.isPaused = false,
    this.isEnabled = true,
    this.pauseExpiresAt,
    this.schedule,
    this.dailyTimeLimitMinutes,
    this.contentFilter = ContentFilterDns.none,
    this.customDnsServers = const [],
  });

  bool get hasMacs => macAddresses.isNotEmpty;
  bool get isBypassed => !isEnabled;
  bool get hasSchedule =>
      schedule != null && schedule!.enabled && schedule!.activeDays.isNotEmpty;
  bool get isScheduleBlocked => hasSchedule && schedule!.isTimeInBlockWindow();
  bool get isCurrentlyBlocked => isEnabled && (isPaused || isScheduleBlocked);
  bool get hasTimeLimit =>
      dailyTimeLimitMinutes != null && dailyTimeLimitMinutes! > 0;
  bool get hasContentFilter => contentFilter != ContentFilterDns.none;

  bool get isTimedPause =>
      isPaused &&
      pauseExpiresAt != null &&
      pauseExpiresAt!.isAfter(DateTime.now().toUtc());

  Duration? get timeRemainingInPause {
    if (!isTimedPause || pauseExpiresAt == null) return null;
    final remaining = pauseExpiresAt!.difference(DateTime.now().toUtc());
    return remaining.isNegative ? null : remaining;
  }

  ParentalProfile copyWith({
    String? name,
    String? icon,
    String? color,
    List<String>? macAddresses,
    bool? isPaused,
    bool? isEnabled,
    Object? pauseExpiresAt = _sentinel,
    Object? schedule = _sentinel,
    int? dailyTimeLimitMinutes,
    Object? clearDailyLimit = _sentinel,
    ContentFilterDns? contentFilter,
    List<String>? customDnsServers,
  }) {
    return ParentalProfile(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      macAddresses: macAddresses ?? this.macAddresses,
      isPaused: isPaused ?? this.isPaused,
      isEnabled: isEnabled ?? this.isEnabled,
      pauseExpiresAt: pauseExpiresAt == _sentinel
          ? this.pauseExpiresAt
          : pauseExpiresAt as DateTime?,
      schedule: schedule == _sentinel
          ? this.schedule
          : schedule as TimeSchedule?,
      dailyTimeLimitMinutes: clearDailyLimit != _sentinel
          ? null
          : (dailyTimeLimitMinutes ?? this.dailyTimeLimitMinutes),
      contentFilter: contentFilter ?? this.contentFilter,
      customDnsServers: customDnsServers ?? this.customDnsServers,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'color': color,
    'mac_addresses': macAddresses,
    'is_paused': isPaused,
    'is_enabled': isEnabled,
    'pause_expires_at': pauseExpiresAt?.toUtc().toIso8601String(),
    'schedule': schedule?.toJson(),
    'daily_time_limit_minutes': dailyTimeLimitMinutes,
    'content_filter': contentFilter.toStorageString(),
    'custom_dns_servers': customDnsServers,
  };

  factory ParentalProfile.fromJson(
    Map<String, dynamic> json, [
    String? fallbackId,
  ]) {
    DateTime? expiresAt;
    final rawExpiry = (json['pause_expires_at'] ?? json['pauseExpiresAt'])
        ?.toString();
    if (rawExpiry != null && rawExpiry.isNotEmpty) {
      expiresAt = DateTime.tryParse(rawExpiry)?.toUtc();
    }

    final List<String> macs = [];
    final rawMacs = json['mac_addresses'] ?? json['mac'];
    if (rawMacs is List) {
      macs.addAll(rawMacs.map((e) => e.toString()));
    } else if (rawMacs is String && rawMacs.isNotEmpty) {
      macs.addAll(rawMacs.split(RegExp(r'\s+')));
    }

    final List<String> customDns = [];
    final rawDns = json['custom_dns_servers'] ?? json['custom_dns'];
    if (rawDns is List) {
      customDns.addAll(rawDns.map((e) => e.toString()));
    } else if (rawDns is String && rawDns.isNotEmpty) {
      customDns.addAll(rawDns.split(RegExp(r'\s+')));
    }

    final rawPaused = json['is_paused'];
    final bool isPaused =
        rawPaused == true || rawPaused == '1' || rawPaused == 'true';

    final rawEnabled = json['is_enabled'];
    final bool isEnabled =
        rawEnabled != false && rawEnabled != '0' && rawEnabled != 'false';

    return ParentalProfile(
      id:
          json['id']?.toString() ??
          json['.name']?.toString() ??
          fallbackId ??
          '',
      name: json['name']?.toString() ?? 'Profile',
      icon: json['icon']?.toString() ?? '👦',
      color: json['color']?.toString() ?? '#F97316',
      macAddresses: macs,
      isPaused: isPaused,
      isEnabled: isEnabled,
      pauseExpiresAt: expiresAt,
      schedule: json['schedule'] != null
          ? TimeSchedule.fromJson(
              Map<String, dynamic>.from(json['schedule'] as Map),
            )
          : null,
      dailyTimeLimitMinutes:
          (json['daily_time_limit_minutes'] as num?)?.toInt() ??
          int.tryParse(json['daily_time_limit_minutes']?.toString() ?? ''),
      contentFilter: contentFilterDnsFromString(
        json['content_filter']?.toString(),
      ),
      customDnsServers: customDns,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ParentalProfile.fromJsonString(String s) =>
      ParentalProfile.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
}

// Sentinel for copyWith optional nullable fields
const Object _sentinel = Object();

/// Activity log event types.
enum ParentalEventType {
  paused,
  resumed,
  schedulePaused,
  scheduleResumed,
  limitReached,
  limitOverridden,
  profileCreated,
  profileDeleted,
  profileUpdated,
  contentFilterApplied,
}

extension ParentalEventTypeExtension on ParentalEventType {
  String get label {
    switch (this) {
      case ParentalEventType.paused:
        return 'Paused';
      case ParentalEventType.resumed:
        return 'Resumed';
      case ParentalEventType.schedulePaused:
        return 'Schedule: Blocked';
      case ParentalEventType.scheduleResumed:
        return 'Schedule: Unblocked';
      case ParentalEventType.limitReached:
        return 'Daily Limit Reached';
      case ParentalEventType.limitOverridden:
        return 'Limit Overridden (+30 min)';
      case ParentalEventType.profileCreated:
        return 'Profile Created';
      case ParentalEventType.profileDeleted:
        return 'Profile Deleted';
      case ParentalEventType.profileUpdated:
        return 'Profile Updated';
      case ParentalEventType.contentFilterApplied:
        return 'Content Filter Applied';
    }
  }
}

/// A single audit log entry for parental control actions.
class ParentalActivityLog {
  final String profileId;
  final String profileName;
  final ParentalEventType eventType;
  final DateTime timestamp;
  final String? detail;

  const ParentalActivityLog({
    required this.profileId,
    required this.profileName,
    required this.eventType,
    required this.timestamp,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
    'profile_id': profileId,
    'profile_name': profileName,
    'event_type': eventType.name,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'detail': detail,
  };

  factory ParentalActivityLog.fromJson(Map<String, dynamic> json) {
    final typeStr = json['event_type']?.toString() ?? '';
    final eventType = ParentalEventType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => ParentalEventType.paused,
    );
    return ParentalActivityLog(
      profileId: json['profile_id']?.toString() ?? '',
      profileName: json['profile_name']?.toString() ?? '',
      eventType: eventType,
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      detail: json['detail']?.toString(),
    );
  }
}
