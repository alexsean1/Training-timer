import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:training_timer/features/workout/data/models/workout_history.dart';
import 'package:training_timer/features/workout/data/repositories/workout_history_repository.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

var _boxCounter = 0;

HiveWorkoutHistoryRepository _makeRepo() =>
    HiveWorkoutHistoryRepository(boxName: 'history_${_boxCounter++}');

WorkoutHistoryEntry _makeEntry({
  required String id,
  String workoutName = 'Test Workout',
  int startedAt = 1000,
  int durationSeconds = 300,
  bool completed = true,
}) {
  return WorkoutHistoryEntry(
    id: id,
    workoutName: workoutName,
    startedAt: startedAt,
    durationSeconds: durationSeconds,
    completed: completed,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_history_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('HiveWorkoutHistoryRepository', () {
    test('getAll returns empty list on a fresh box', () async {
      final repo = _makeRepo();
      expect(await repo.getAll(), isEmpty);
    });

    test('add persists an entry; getAll returns it', () async {
      final repo = _makeRepo();
      await repo.add(_makeEntry(id: 'a'));

      final result = await repo.getAll();
      expect(result, hasLength(1));
      expect(result.first.id, 'a');
    });

    test('getAll returns entries sorted newest-first by startedAt', () async {
      final repo = _makeRepo();
      await repo.add(_makeEntry(id: 'old', startedAt: 1000));
      await repo.add(_makeEntry(id: 'new', startedAt: 2000));

      final result = await repo.getAll();
      expect(result.first.id, 'new');
      expect(result.last.id, 'old');
    });

    test('completed flag defaults to true', () async {
      final repo = _makeRepo();
      await repo.add(_makeEntry(id: 'x'));
      expect((await repo.getAll()).first.completed, isTrue);
    });

    test('completed: false is preserved across JSON round-trip', () async {
      final repo = _makeRepo();
      await repo.add(_makeEntry(id: 'y', completed: false));
      expect((await repo.getAll()).first.completed, isFalse);
    });

    test('all fields survive a JSON round-trip', () async {
      final repo = _makeRepo();
      const original = WorkoutHistoryEntry(
        id: 'rt',
        workoutName: 'Round Trip Workout',
        startedAt: 9999999,
        durationSeconds: 1234,
        completed: false,
      );

      await repo.add(original);
      final loaded = (await repo.getAll()).first;

      expect(loaded.id, 'rt');
      expect(loaded.workoutName, 'Round Trip Workout');
      expect(loaded.startedAt, 9999999);
      expect(loaded.durationSeconds, 1234);
      expect(loaded.completed, isFalse);
    });

    test('multiple entries can coexist', () async {
      final repo = _makeRepo();
      await repo.add(_makeEntry(id: '1', startedAt: 300));
      await repo.add(_makeEntry(id: '2', startedAt: 200));
      await repo.add(_makeEntry(id: '3', startedAt: 100));

      final result = await repo.getAll();
      expect(result.map((e) => e.id).toList(), ['1', '2', '3']);
    });

    test('clear removes all entries', () async {
      final repo = _makeRepo();
      await repo.add(_makeEntry(id: 'a'));
      await repo.add(_makeEntry(id: 'b'));
      await repo.clear();

      expect(await repo.getAll(), isEmpty);
    });
  });
}
