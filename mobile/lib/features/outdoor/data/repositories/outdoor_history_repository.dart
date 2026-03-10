import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/outdoor_history_models.dart';

// ─── Abstract interface ───────────────────────────────────────────────────────

abstract class OutdoorHistoryRepository {
  Future<List<OutdoorWorkoutHistoryEntry>> getAll();
  Future<void> save(OutdoorWorkoutHistoryEntry entry);
  Future<void> delete(String id);
}

// ─── Hive implementation ──────────────────────────────────────────────────────

/// Stores history entries as JSON strings in a Hive box keyed by entry ID.
///
/// Raw JSON (no TypeAdapters) means Freezed's `@Default` annotations handle
/// schema evolution automatically — no manual adapter version bumps needed.
///
/// The [boxName] parameter exists for test isolation.
class HiveOutdoorHistoryRepository implements OutdoorHistoryRepository {
  HiveOutdoorHistoryRepository({this.boxName = 'outdoor_history'});

  final String boxName;
  Box<String>? _box;

  Future<Box<String>> _getBox() async =>
      _box ??= await Hive.openBox<String>(boxName);

  @override
  Future<List<OutdoorWorkoutHistoryEntry>> getAll() async {
    final box = await _getBox();
    return box.values
        .map((json) => OutdoorWorkoutHistoryEntry.fromJson(
            jsonDecode(json) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt)); // newest first
  }

  @override
  Future<void> save(OutdoorWorkoutHistoryEntry entry) async {
    final box = await _getBox();
    await box.put(entry.id, jsonEncode(entry.toJson()));
  }

  @override
  Future<void> delete(String id) async {
    final box = await _getBox();
    await box.delete(id);
  }
}

// ─── Riverpod providers ───────────────────────────────────────────────────────

final outdoorHistoryRepositoryProvider =
    Provider<OutdoorHistoryRepository>((ref) {
  return HiveOutdoorHistoryRepository();
});

class OutdoorHistoryNotifier
    extends AsyncNotifier<List<OutdoorWorkoutHistoryEntry>> {
  @override
  Future<List<OutdoorWorkoutHistoryEntry>> build() =>
      ref.read(outdoorHistoryRepositoryProvider).getAll();

  Future<void> save(OutdoorWorkoutHistoryEntry entry) async {
    await ref.read(outdoorHistoryRepositoryProvider).save(entry);
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    await ref.read(outdoorHistoryRepositoryProvider).delete(id);
    ref.invalidateSelf();
  }
}

final outdoorHistoryProvider = AsyncNotifierProvider<OutdoorHistoryNotifier,
    List<OutdoorWorkoutHistoryEntry>>(
  OutdoorHistoryNotifier.new,
);
