import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:training_timer/features/outdoor/data/models/outdoor_models.dart';
import 'package:training_timer/features/outdoor/data/repositories/outdoor_preset_repository.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

// Each test gets a unique box name so they don't interfere with each other.
var _boxCounter = 0;

HiveOutdoorPresetRepository _makeRepo() =>
    HiveOutdoorPresetRepository(boxName: 'outdoor_presets_${_boxCounter++}');

OutdoorWorkoutPreset _makePreset({
  required String id,
  String name = 'Test Workout',
  int createdAt = 0,
}) {
  return OutdoorWorkoutPreset(
    id: id,
    name: name,
    workout: const OutdoorWorkout(
      elements: [
        OutdoorElement.segment(OutdoorSegment.timed(
          seconds: 240,
          tag: OutdoorSegmentTag.work(),
        )),
      ],
    ),
    createdAt: createdAt,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_outdoor_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('HiveOutdoorPresetRepository', () {
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

    test('JSON round-trip preserves all fields including groups', () async {
      final repo = _makeRepo();

      const work = OutdoorSegment.timed(
        seconds: 240,
        tag: OutdoorSegmentTag.work(),
        name: 'Hard effort',
      );
      const rest = OutdoorSegment.timed(
        seconds: 180,
        tag: OutdoorSegmentTag.rest(),
        name: 'Active recovery',
      );
      const group = OutdoorGroup(segments: [work, rest], repeats: 4);

      const preset = OutdoorWorkoutPreset(
        id: 'rt',
        name: 'Round Trip',
        workout: OutdoorWorkout(
          elements: [
            OutdoorElement.segment(OutdoorSegment.distance(
              metres: 1000,
              tag: OutdoorSegmentTag.warmUp(),
            )),
            OutdoorElement.group(group),
          ],
        ),
        createdAt: 9999,
      );

      await repo.save(preset);
      final loaded = (await repo.getAll()).first;

      expect(loaded.id, 'rt');
      expect(loaded.name, 'Round Trip');
      expect(loaded.createdAt, 9999);
      expect(loaded.workout.elements, hasLength(2));

      final g = loaded.workout.elements[1].when(
        segment: (_) => throw StateError('expected group'),
        group: (g) => g,
      );
      expect(g.repeats, 4);
      expect(g.segments, hasLength(2));
      expect(g.segments[0].name, 'Hard effort');
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
