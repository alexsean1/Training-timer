import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/workout_history.dart';

// ─── Abstract interface ───────────────────────────────────────────────────────

abstract class WorkoutHistoryRepository {
  Future<List<WorkoutHistoryEntry>> getAll();
  Future<void> add(WorkoutHistoryEntry entry);
  Future<void> clear();
}

// ─── Hive implementation ──────────────────────────────────────────────────────

/// Stores history entries as JSON strings in a Hive box keyed by entry ID.
///
/// The [boxName] parameter exists for test isolation: tests can pass a unique
/// name per test so each test starts with an empty box without closing Hive.
class HiveWorkoutHistoryRepository implements WorkoutHistoryRepository {
  HiveWorkoutHistoryRepository({this.boxName = 'workout_history'});

  final String boxName;
  Box<String>? _box;

  Future<Box<String>> _getBox() async =>
      _box ??= await Hive.openBox<String>(boxName);

  @override
  Future<List<WorkoutHistoryEntry>> getAll() async {
    final box = await _getBox();
    return box.values
        .map((json) => WorkoutHistoryEntry.fromJson(
            jsonDecode(json) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt)); // newest first
  }

  @override
  Future<void> add(WorkoutHistoryEntry entry) async {
    final box = await _getBox();
    await box.put(entry.id, jsonEncode(entry.toJson()));
  }

  @override
  Future<void> clear() async {
    final box = await _getBox();
    await box.clear();
  }
}

// ─── Riverpod providers ───────────────────────────────────────────────────────

final workoutHistoryRepositoryProvider =
    Provider<WorkoutHistoryRepository>((ref) {
  return HiveWorkoutHistoryRepository();
});

class WorkoutHistoryNotifier
    extends AsyncNotifier<List<WorkoutHistoryEntry>> {
  @override
  Future<List<WorkoutHistoryEntry>> build() =>
      ref.read(workoutHistoryRepositoryProvider).getAll();

  Future<void> add(WorkoutHistoryEntry entry) async {
    await ref.read(workoutHistoryRepositoryProvider).add(entry);
    ref.invalidateSelf();
  }
}

final workoutHistoryProvider =
    AsyncNotifierProvider<WorkoutHistoryNotifier, List<WorkoutHistoryEntry>>(
  WorkoutHistoryNotifier.new,
);
