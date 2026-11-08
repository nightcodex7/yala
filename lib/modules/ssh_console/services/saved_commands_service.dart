// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/utils/logger.dart';
import '../models/saved_ssh_command.dart';

enum SaveResult { ok, limitReached, validationError, storageError }

class SavedCommandsService {
  final SecureStorageService _storage;

  // Async serialization queue — no operation is ever silently dropped.
  // Each call chains onto the previous Future, ensuring sequential execution.
  Future<void> _queue = Future.value();

  SavedCommandsService({SecureStorageService? storage})
    : _storage = storage ?? SecureStorageService();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        final result = await operation();
        completer.complete(result);
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
    });
    return completer.future;
  }

  static String _key(String routerId) => 'ssh_saved_commands_$routerId';

  Future<List<SavedSshCommand>> getAll(String routerId) async {
    try {
      final raw = await _storage.readValue(_key(routerId));
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SavedSshCommand.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Logger.warning('SavedCommandsService.getAll failed: $e');
      return [];
    }
  }

  Future<SaveResult> save(String routerId, SavedSshCommand cmd) =>
      _serialize(() => _saveInternal(routerId, cmd));

  Future<SaveResult> _saveInternal(String routerId, SavedSshCommand cmd) async {
    if (cmd.name.trim().isEmpty || cmd.command.trim().isEmpty) {
      return SaveResult.validationError;
    }
    if (cmd.name.length > 80 || cmd.command.length > 500) {
      return SaveResult.validationError;
    }

    try {
      final all = await getAll(routerId);
      final existingIdx = all.indexWhere((c) => c.id == cmd.id);
      if (existingIdx >= 0) {
        all[existingIdx] = cmd; // update in-place
      } else {
        if (all.length >= 50) return SaveResult.limitReached;
        all.add(cmd);
      }
      await _storage.writeValue(
        _key(routerId),
        jsonEncode(all.map((c) => c.toJson()).toList()),
      );
      return SaveResult.ok;
    } catch (e, stack) {
      Logger.exception('SavedCommandsService.save failed', e, stack);
      return SaveResult.storageError;
    }
  }

  Future<void> delete(String routerId, String id) =>
      _serialize(() => _deleteInternal(routerId, id));

  Future<void> _deleteInternal(String routerId, String id) async {
    try {
      final all = await getAll(routerId);
      all.removeWhere((c) => c.id == id);
      await _storage.writeValue(
        _key(routerId),
        jsonEncode(all.map((c) => c.toJson()).toList()),
      );
    } catch (e, stack) {
      Logger.exception('SavedCommandsService.delete failed', e, stack);
    }
  }

  Future<void> updateLastRun(String routerId, String id) =>
      _serialize(() => _updateLastRunInternal(routerId, id));

  Future<void> _updateLastRunInternal(String routerId, String id) async {
    try {
      final all = await getAll(routerId);
      final idx = all.indexWhere((c) => c.id == id);
      if (idx >= 0) {
        all[idx] = all[idx].copyWith(lastRunAt: DateTime.now());
        await _storage.writeValue(
          _key(routerId),
          jsonEncode(all.map((c) => c.toJson()).toList()),
        );
      }
    } catch (e, stack) {
      Logger.exception('SavedCommandsService.updateLastRun failed', e, stack);
    }
  }

  /// Imports commands from a JSON string into router storage.
  /// Handles:
  /// - Direct JSON Array: `[{"name": "...", "command": "..."}, ...]`
  /// - Single Category JSON: `{"data": [...]}`
  /// - Full Config Export JSON: `{"categories": {"sshSavedCommands": {"data": [...]}}}`
  /// Returns the number of successfully imported or updated commands.
  Future<int> importFromJson(String routerId, String jsonContent) =>
      _serialize(() => _importInternal(routerId, jsonContent));

  Future<int> _importInternal(String routerId, String jsonContent) async {
    try {
      final decoded = jsonDecode(jsonContent);
      List<dynamic>? rawList;

      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map<String, dynamic>) {
        if (decoded['data'] is List) {
          rawList = decoded['data'] as List;
        } else if (decoded['categories'] is Map &&
            decoded['categories']['sshSavedCommands'] is Map &&
            decoded['categories']['sshSavedCommands']['data'] is List) {
          rawList = decoded['categories']['sshSavedCommands']['data'] as List;
        }
      }

      if (rawList == null || rawList.isEmpty) return 0;

      final all = await getAll(routerId);
      int importedCount = 0;

      for (final item in rawList) {
        if (item is! Map<String, dynamic>) continue;
        final name = item['name']?.toString().trim() ?? '';
        final command = item['command']?.toString().trim() ?? '';

        if (name.isEmpty || command.isEmpty) continue;
        if (name.length > 80 || command.length > 500) continue;

        final id = (item['id'] != null && item['id'].toString().isNotEmpty)
            ? item['id'].toString()
            : SavedSshCommand.generateId(routerId);
        DateTime? lastRunAt;
        if (item['lastRunAt'] != null) {
          lastRunAt = DateTime.tryParse(item['lastRunAt'].toString());
        }
        DateTime createdAt = DateTime.now();
        if (item['createdAt'] != null) {
          createdAt =
              DateTime.tryParse(item['createdAt'].toString()) ?? createdAt;
        }

        final parsed = SavedSshCommand(
          id: id,
          routerId: routerId,
          name: name,
          command: command,
          createdAt: createdAt,
          lastRunAt: lastRunAt,
        );

        final existingIdx = all.indexWhere(
          (c) =>
              c.id == parsed.id ||
              (c.name == parsed.name && c.command == parsed.command),
        );

        if (existingIdx >= 0) {
          final existing = all[existingIdx];
          if (existing.name == parsed.name &&
              existing.command == parsed.command) {
            // Identical command already exists — skip duplicate
            continue;
          }
          all[existingIdx] = parsed.copyWith(id: existing.id);
          importedCount++;
        } else {
          if (all.length >= 50) break; // Maximum 50 commands per router
          all.add(parsed);
          importedCount++;
        }
      }

      if (importedCount > 0) {
        await _storage.writeValue(
          _key(routerId),
          jsonEncode(all.map((c) => c.toJson()).toList()),
        );
      }

      return importedCount;
    } catch (e, stack) {
      Logger.exception('SavedCommandsService.importFromJson failed', e, stack);
      return 0;
    }
  }
}

final savedCommandsServiceProvider = Provider<SavedCommandsService>(
  (ref) => SavedCommandsService(),
);
