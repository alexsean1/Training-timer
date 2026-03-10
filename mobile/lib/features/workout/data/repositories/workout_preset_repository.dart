import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/workout_models.dart';

// ─── Abstract interface ───────────────────────────────────────────────────────

abstract class WorkoutPresetRepository {
  Future<List<WorkoutPreset>> getAll();
  Future<void> save(WorkoutPreset preset);
  Future<void> delete(String id);
}

// ─── Hive implementation ──────────────────────────────────────────────────────

/// Stores presets as JSON strings in a Hive box keyed by preset ID.
///
/// Using raw JSON (not Hive TypeAdapters) means Freezed's `@Default`
/// annotations handle schema evolution automatically — new fields get their
/// defaults when old data is read, and removed fields are silently ignored.
/// No manual Hive adapter version bumps are ever needed.
///
/// The [boxName] parameter exists for test isolation: tests can pass a unique
/// name per test so each test starts with an empty box without closing Hive.
class HiveWorkoutPresetRepository implements WorkoutPresetRepository {
  HiveWorkoutPresetRepository({this.boxName = 'workout_presets'});

  final String boxName;
  Box<String>? _box;

  Future<Box<String>> _getBox() async =>
      _box ??= await Hive.openBox<String>(boxName);

  @override
  Future<List<WorkoutPreset>> getAll() async {
    final box = await _getBox();
    return box.values
        .map((json) =>
            WorkoutPreset.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
  }

  @override
  Future<void> save(WorkoutPreset preset) async {
    final box = await _getBox();
    await box.put(preset.id, jsonEncode(preset.toJson()));
  }

  @override
  Future<void> delete(String id) async {
    final box = await _getBox();
    await box.delete(id);
  }
}

// ─── Riverpod providers ───────────────────────────────────────────────────────

final workoutPresetRepositoryProvider = Provider<WorkoutPresetRepository>((ref) {
  return HiveWorkoutPresetRepository();
});

class WorkoutPresetsNotifier
    extends AsyncNotifier<List<WorkoutPreset>> {
  @override
  Future<List<WorkoutPreset>> build() =>
      ref.read(workoutPresetRepositoryProvider).getAll();

  Future<void> save(WorkoutPreset preset) async {
    await ref.read(workoutPresetRepositoryProvider).save(preset);
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    await ref.read(workoutPresetRepositoryProvider).delete(id);
    ref.invalidateSelf();
  }
}

final workoutPresetsProvider =
    AsyncNotifierProvider<WorkoutPresetsNotifier, List<WorkoutPreset>>(
  WorkoutPresetsNotifier.new,
);
