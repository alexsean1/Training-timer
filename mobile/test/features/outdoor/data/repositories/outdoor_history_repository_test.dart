import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:training_timer/features/outdoor/data/models/outdoor_history_models.dart';
import 'package:training_timer/features/outdoor/data/repositories/outdoor_history_repository.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

var _boxCounter = 0;

HiveOutdoorHistoryRepository _makeRepo() =>
    HiveOutdoorHistoryRepository(boxName: 'outdoor_history_${_boxCounter++}');

OutdoorWorkoutHistoryEntry _makeEntry({
  required String id,
  String workoutName = 'Test Run',
  int startedAt = 0,
  int durationSeconds = 1800,
  double totalDistanceMetres = 5000,
  List<OutdoorSegmentHistoryEntry> segments = const [],
  int? avgBpm,
  int? maxBpm,
}) {
  return OutdoorWorkoutHistoryEntry(
    id: id,
    workoutName: workoutName,
    startedAt: startedAt,
    durationSeconds: durationSeconds,
    totalDistanceMetres: totalDistanceMetres,
    segments: segments,
    avgBpm: avgBpm,
    maxBpm: maxBpm,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_outdoor_history_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('HiveOutdoorHistoryRepository', () {
    test('getAll returns empty list on a fresh box', () async {
      final repo = _makeRepo();
      expect(await repo.getAll(), isEmpty);
    });

    test('save persists an entry; getAll returns it', () async {
      final repo = _makeRepo();
      await repo.save(_makeEntry(id: 'a'));

      final result = await repo.getAll();
      expect(result, hasLength(1));
      expect(result.first.id, 'a');
    });

    test('save with the same id overwrites the existing entry', () async {
      final repo = _makeRepo();
      await repo.save(_makeEntry(id: 'a', workoutName: 'Original'));
      await repo.save(_makeEntry(id: 'a', workoutName: 'Updated'));

      final result = await repo.getAll();
      expect(result, hasLength(1));
      expect(result.first.workoutName, 'Updated');
    });

    test('delete removes the matching entry', () async {
      final repo = _makeRepo();
      await repo.save(_makeEntry(id: 'keep'));
      await repo.save(_makeEntry(id: 'remove'));
      await repo.delete('remove');

      final result = await repo.getAll();
      expect(result, hasLength(1));
      expect(result.first.id, 'keep');
    });

    test('delete on a non-existent id is a no-op', () async {
      final repo = _makeRepo();
      await repo.save(_makeEntry(id: 'x'));
      await repo.delete('does-not-exist');

      expect(await repo.getAll(), hasLength(1));
    });

    test('getAll returns entries sorted newest-first by startedAt', () async {
      final repo = _makeRepo();
      await repo.save(_makeEntry(id: 'old', startedAt: 100));
      await repo.save(_makeEntry(id: 'new', startedAt: 200));

      final result = await repo.getAll();
      expect(result.first.id, 'new');
      expect(result.last.id, 'old');
    });

    test('JSON round-trip preserves all fields including segments', () async {
      final repo = _makeRepo();

      const segments = [
        OutdoorSegmentHistoryEntry(
          tagLabel: 'Warm-up',
          name: 'Easy jog',
          durationSeconds: 300,
          distanceMetres: 1200.5,
          avgBpm: 130,
          maxBpm: 142,
        ),
        OutdoorSegmentHistoryEntry(
          tagLabel: 'Work',
          name: 'Hard effort',
          durationSeconds: 240,
          distanceMetres: 800.0,
          avgBpm: 168,
          maxBpm: 185,
        ),
      ];

      const entry = OutdoorWorkoutHistoryEntry(
        id: 'rt',
        workoutName: 'Round Trip',
        startedAt: 9999,
        durationSeconds: 540,
        totalDistanceMetres: 2000.5,
        segments: segments,
        avgBpm: 149,
        maxBpm: 185,
      );

      await repo.save(entry);
      final loaded = (await repo.getAll()).first;

      expect(loaded.id, 'rt');
      expect(loaded.workoutName, 'Round Trip');
      expect(loaded.startedAt, 9999);
      expect(loaded.durationSeconds, 540);
      expect(loaded.totalDistanceMetres, closeTo(2000.5, 0.01));
      expect(loaded.avgBpm, 149);
      expect(loaded.maxBpm, 185);
      expect(loaded.segments, hasLength(2));
      expect(loaded.segments[0].tagLabel, 'Warm-up');
      expect(loaded.segments[0].name, 'Easy jog');
      expect(loaded.segments[0].durationSeconds, 300);
      expect(loaded.segments[0].distanceMetres, closeTo(1200.5, 0.01));
      expect(loaded.segments[0].avgBpm, 130);
      expect(loaded.segments[0].maxBpm, 142);
      expect(loaded.segments[1].avgBpm, 168);
      expect(loaded.segments[1].maxBpm, 185);
    });

    test('multiple entries coexist independently', () async {
      final repo = _makeRepo();
      await repo.save(_makeEntry(id: '1', startedAt: 300));
      await repo.save(_makeEntry(id: '2', startedAt: 200));
      await repo.save(_makeEntry(id: '3', startedAt: 100));

      final result = await repo.getAll();
      expect(result.map((e) => e.id).toList(), const ['1', '2', '3']);
    });
  });
}
