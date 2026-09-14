// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'parental_profile.dart';

/// Persistent store for all parental control state.
/// Serialized to/from SecureStorage as a single JSON blob.
class ParentalControlsStore extends ChangeNotifier {
  static ParentalControlsStore? _instance;
  static ParentalControlsStore get instance =>
      _instance ??= ParentalControlsStore._();
  ParentalControlsStore._();

  static const int _maxActivityLogEntries = 100;

  List<ParentalProfile> _profiles = [];
  Map<String, int> _dailyMinutesUsed = {}; // mac → minutes used today
  DateTime? _lastResetDate;
  List<ParentalActivityLog> _activityLog = [];

  List<ParentalProfile> get profiles => List.unmodifiable(_profiles);
  List<ParentalActivityLog> get activityLog => List.unmodifiable(_activityLog);
  Map<String, int> get dailyMinutesUsed => Map.unmodifiable(_dailyMinutesUsed);

  /// Returns whether the store has been loaded.
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  // ─── Persistence ────────────────────────────────────────────────────────────

  /// Load state from a serialized JSON string (from SecureStorage).
  void loadFromString(String? raw) {
    if (raw == null || raw.isEmpty) {
      _profiles = [];
      _dailyMinutesUsed = {};
      _lastResetDate = null;
      _activityLog = [];
      _isLoaded = true;
      _maybeResetDailyCounters();
      notifyListeners();
      return;
    }
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _profiles = ((json['profiles'] as List?) ?? [])
          .map(
            (e) =>
                ParentalProfile.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();

      _dailyMinutesUsed = Map<String, int>.from(
        (json['daily_minutes_used'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            {},
      );

      final lastResetStr = json['last_reset_date']?.toString();
      _lastResetDate = lastResetStr != null
          ? DateTime.tryParse(lastResetStr)?.toUtc()
          : null;

      _activityLog = ((json['activity_log'] as List?) ?? [])
          .map(
            (e) => ParentalActivityLog.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('ParentalControlsStore: load error — $e');
    }
    _isLoaded = true;
    _maybeResetDailyCounters();
    notifyListeners();
  }

  String toJsonString() {
    return jsonEncode({
      'profiles': _profiles.map((p) => p.toJson()).toList(),
      'daily_minutes_used': _dailyMinutesUsed,
      'last_reset_date': (_lastResetDate ?? DateTime.now().toUtc())
          .toIso8601String(),
      'activity_log': _activityLog
          .take(_maxActivityLogEntries)
          .map((e) => e.toJson())
          .toList(),
    });
  }

  // ─── Daily Counter Management ───────────────────────────────────────────────

  void _maybeResetDailyCounters() {
    final today = DateTime.now().toUtc();
    final todayDate = DateTime.utc(today.year, today.month, today.day);
    if (_lastResetDate == null || _lastResetDate!.isBefore(todayDate)) {
      _dailyMinutesUsed = {};
      _lastResetDate = todayDate;
    }
  }

  int getDailyMinutesUsed(String mac) {
    return _dailyMinutesUsed[mac.toUpperCase()] ?? 0;
  }

  void incrementDailyMinutesUsed(String mac, int minutes) {
    _maybeResetDailyCounters();
    final key = mac.toUpperCase();
    _dailyMinutesUsed[key] = (_dailyMinutesUsed[key] ?? 0) + minutes;
    notifyListeners();
  }

  void resetDailyMinutesUsed(String mac) {
    _dailyMinutesUsed.remove(mac.toUpperCase());
    notifyListeners();
  }

  void setProfiles(List<ParentalProfile> profiles) {
    _profiles = List.from(profiles);
    notifyListeners();
  }

  /// Creates a new profile and returns its id.
  String addProfile(ParentalProfile profile) {
    _profiles.add(profile);
    _logEvent(
      ParentalActivityLog(
        profileId: profile.id,
        profileName: profile.name,
        eventType: ParentalEventType.profileCreated,
        timestamp: DateTime.now().toUtc(),
      ),
    );
    notifyListeners();
    return profile.id;
  }

  void updateProfile(ParentalProfile updated) {
    final idx = _profiles.indexWhere((p) => p.id == updated.id);
    if (idx < 0) return;
    _profiles[idx] = updated;
    _logEvent(
      ParentalActivityLog(
        profileId: updated.id,
        profileName: updated.name,
        eventType: ParentalEventType.profileUpdated,
        timestamp: DateTime.now().toUtc(),
      ),
    );
    notifyListeners();
  }

  void deleteProfile(String id) {
    final profile = _profiles.firstWhere(
      (p) => p.id == id,
      orElse: () => const ParentalProfile(
        id: '',
        name: '',
        icon: '',
        color: '',
        macAddresses: [],
      ),
    );
    _profiles.removeWhere((p) => p.id == id);
    if (profile.id.isNotEmpty) {
      _logEvent(
        ParentalActivityLog(
          profileId: id,
          profileName: profile.name,
          eventType: ParentalEventType.profileDeleted,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
    notifyListeners();
  }

  ParentalProfile? getProfile(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ─── Pause State Management ─────────────────────────────────────────────────

  void markProfilePaused(String id, {DateTime? expiresAt}) {
    final idx = _profiles.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _profiles[idx] = _profiles[idx].copyWith(
      isPaused: true,
      pauseExpiresAt: expiresAt,
    );
    _logEvent(
      ParentalActivityLog(
        profileId: id,
        profileName: _profiles[idx].name,
        eventType: ParentalEventType.paused,
        timestamp: DateTime.now().toUtc(),
        detail: expiresAt != null
            ? 'Until ${_formatTime(expiresAt)}'
            : 'Indefinite',
      ),
    );
    notifyListeners();
  }

  void markProfileResumed(String id) {
    final idx = _profiles.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _profiles[idx] = _profiles[idx].copyWith(
      isPaused: false,
      pauseExpiresAt: null,
    );
    _logEvent(
      ParentalActivityLog(
        profileId: id,
        profileName: _profiles[idx].name,
        eventType: ParentalEventType.resumed,
        timestamp: DateTime.now().toUtc(),
      ),
    );
    notifyListeners();
  }

  // ─── Activity Log ───────────────────────────────────────────────────────────

  void _logEvent(ParentalActivityLog event) {
    _activityLog.insert(0, event);
    // Trim only when the list has actually grown beyond the cap
    if (_activityLog.length > _maxActivityLogEntries) {
      _activityLog.removeRange(_maxActivityLogEntries, _activityLog.length);
    }
  }

  void clearActivityLog() {
    _activityLog.clear();
    notifyListeners();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  static String generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(8, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} '
        '${local.day}/${local.month}/${local.year}';
  }

  /// Returns all profiles that contain this MAC address.
  List<ParentalProfile> profilesForMac(String mac) {
    final normMac = mac.toUpperCase();
    return _profiles
        .where((p) => p.macAddresses.any((m) => m.toUpperCase() == normMac))
        .toList();
  }

  void toggleProfileEnabled(String id, {bool? enabled}) {
    final idx = _profiles.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final newEnabled = enabled ?? !_profiles[idx].isEnabled;
    _profiles[idx] = _profiles[idx].copyWith(isEnabled: newEnabled);
    _logEvent(
      ParentalActivityLog(
        profileId: id,
        profileName: _profiles[idx].name,
        eventType: ParentalEventType.profileUpdated,
        timestamp: DateTime.now().toUtc(),
        detail: newEnabled ? 'Rules Enabled' : 'Rules Bypassed (Unrestricted)',
      ),
    );
    notifyListeners();
  }

  /// Returns whether any ACTIVE (non-bypassed) profile is currently blocked (paused or schedule blocked) and contains this MAC.
  bool isMacPaused(String mac) {
    return profilesForMac(mac).any((p) => p.isCurrentlyBlocked);
  }
}
