import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/outdoor_models.dart';

// ─── Abstract interface ───────────────────────────────────────────────────────

abstract class OutdoorPresetRepository {
  Future<List<OutdoorWorkoutPreset>> getAll();
  Future<void> save(OutdoorWorkoutPreset preset);
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
class HiveOutdoorPresetRepository implements OutdoorPresetRepository {
  HiveOutdoorPresetRepository({this.boxName = 'outdoor_presets'});

  final String boxName;
  Box<String>? _box;

  Future<Box<String>> _getBox() async =>
      _box ??= await Hive.openBox<String>(boxName);

  @override
  Future<List<OutdoorWorkoutPreset>> getAll() async {
    final box = await _getBox();
    return box.values
        .map((json) => OutdoorWorkoutPreset.fromJson(
            jsonDecode(json) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
  }

  @override
  Future<void> save(OutdoorWorkoutPreset preset) async {
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

final outdoorPresetRepositoryProvider =
    Provider<OutdoorPresetRepository>((ref) {
  return HiveOutdoorPresetRepository();
});

class OutdoorPresetsNotifier
    extends AsyncNotifier<List<OutdoorWorkoutPreset>> {
  @override
  Future<List<OutdoorWorkoutPreset>> build() =>
      ref.read(outdoorPresetRepositoryProvider).getAll();

  Future<void> save(OutdoorWorkoutPreset preset) async {
    await ref.read(outdoorPresetRepositoryProvider).save(preset);
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    await ref.read(outdoorPresetRepositoryProvider).delete(id);
    ref.invalidateSelf();
  }
}

final outdoorPresetsProvider = AsyncNotifierProvider<OutdoorPresetsNotifier,
    List<OutdoorWorkoutPreset>>(
  OutdoorPresetsNotifier.new,
);
