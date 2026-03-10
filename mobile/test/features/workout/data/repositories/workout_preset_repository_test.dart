import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:training_timer/features/workout/data/models/workout_models.dart';
import 'package:training_timer/features/workout/data/repositories/workout_preset_repository.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

// Each test gets a unique box name so they don't interfere with each other,
// with no need to close/reopen Hive between tests.
var _boxCounter = 0;

HiveWorkoutPresetRepository _makeRepo() =>
    HiveWorkoutPresetRepository(boxName: 'presets_${_boxCounter++}');

WorkoutPreset _makePreset({
  required String id,
  String name = 'Test Workout',
  int createdAt = 0,
  String notes = '',
}) {
  return WorkoutPreset(
    id: id,
    name: name,
    workout: Workout(
      elements: const [
        WorkoutElement.segment(
          WorkoutSegment.amrap(duration: Duration(minutes: 5)),
        ),
      ],
      notes: notes,
    ),
    createdAt: createdAt,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('HiveWorkoutPresetRepository', () {
    test('getAll returns empty list on a fresh box', () async {
      final repo = _makeRepo();
      expect(await repo.getAll(), isEmpty);
    });

    test('save persists a preset; getAll returns it', () async {
      final repo = _makeRepo();
      await repo.save(_makePreset(id: 'a'));

      final result = await repo.getAll();
      expect(result, hasLength(1));
      expect(result.first.id, 'a');
    });

    test('save with the same id overwrites the existing preset', () async {
      final repo = _makeRepo();
      await repo.save(_makePreset(id: 'a', name: 'Original'));
      await repo.save(_makePreset(id: 'a', name: 'Updated'));

      final result = await repo.getAll();
      expect(result, hasLength(1));
      expect(result.first.name, 'Updated');
    });

    test('delete removes the matching preset', () async {
      final repo = _makeRepo();
      await repo.save(_makePreset(id: 'keep'));
      await repo.save(_makePreset(id: 'remove'));
      await repo.delete('remove');

      final result = await repo.getAll();
      expect(result, hasLength(1));
      expect(result.first.id, 'keep');
    });

    test('delete on a non-existent id is a no-op', () async {
      final repo = _makeRepo();
      await repo.save(_makePreset(id: 'x'));
      await repo.delete('does-not-exist');

      expect(await repo.getAll(), hasLength(1));
    });

    test('getAll returns presets sorted newest-first by createdAt', () async {
      final repo = _makeRepo();
      await repo.save(_makePreset(id: 'old', createdAt: 100));
      await repo.save(_makePreset(id: 'new', createdAt: 200));

      final result = await repo.getAll();
      expect(result.first.id, 'new');
      expect(result.last.id, 'old');
    });

    test('JSON round-trip preserves all fields including notes and groups',
        () async {
      final repo = _makeRepo();

      const emom = WorkoutSegment.emom(duration: Duration(minutes: 3));
      const rest = WorkoutSegment.rest(duration: Duration(minutes: 1));
      const group = WorkoutGroup(segments: [emom, rest], repeats: 4);

      const preset = WorkoutPreset(
        id: 'rt',
        name: 'Round Trip',
        workout: Workout(
          elements: [
            WorkoutElement.segment(emom),
            WorkoutElement.group(group),
          ],
          notes: 'Some notes here',
        ),
        createdAt: 9999,
      );

      await repo.save(preset);
      final loaded = (await repo.getAll()).first;

      expect(loaded.id, 'rt');
      expect(loaded.name, 'Round Trip');
      expect(loaded.createdAt, 9999);
      expect(loaded.workout.notes, 'Some notes here');
      expect(loaded.workout.elements, hasLength(2));

      final group0 = loaded.workout.elements[1].when(
        segment: (_) => throw StateError('expected group'),
        group: (g) => g,
      );
      expect(group0.repeats, 4);
      expect(group0.segments, hasLength(2));
    });

    test('multiple presets can coexist independently', () async {
      final repo = _makeRepo();
      await repo.save(_makePreset(id: '1', name: 'A', createdAt: 300));
      await repo.save(_makePreset(id: '2', name: 'B', createdAt: 200));
      await repo.save(_makePreset(id: '3', name: 'C', createdAt: 100));

      final result = await repo.getAll();
      expect(result.map((p) => p.id).toList(), const ['1', '2', '3']);
    });
  });
}
