import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:training_timer/features/outdoor/data/models/outdoor_history_models.dart';
import 'package:training_timer/features/outdoor/data/repositories/outdoor_history_repository.dart';
import 'package:training_timer/features/outdoor/presentation/screens/outdoor_results_screen.dart';

// ─── Fake history repository ──────────────────────────────────────────────────

class _FakeHistoryRepo implements OutdoorHistoryRepository {
  final _store = <String, OutdoorWorkoutHistoryEntry>{};

  @override
  Future<List<OutdoorWorkoutHistoryEntry>> getAll() async =>
      _store.values.toList();

  @override
  Future<void> save(OutdoorWorkoutHistoryEntry entry) async {
    _store[entry.id] = entry;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }
}

// ─── Test entries ─────────────────────────────────────────────────────────────

// An entry with two work segments to exercise interval comparison.
const _entryWithIntervals = OutdoorWorkoutHistoryEntry(
  id: 'test-id',
  workoutName: 'Norwegian 4×4',
  startedAt: 0, // epoch 0 — Jan 1, 1970
  durationSeconds: 2550, // 42:30
  totalDistanceMetres: 8200,
  segments: [
    OutdoorSegmentHistoryEntry(
      tagLabel: 'Warm-up',
      name: 'Warm-up jog',
      durationSeconds: 750,
      distanceMetres: 2050,
      avgBpm: 125,
      maxBpm: 140,
    ),
    OutdoorSegmentHistoryEntry(
      tagLabel: 'Work',
      name: 'Hard effort',
      durationSeconds: 240,
      distanceMetres: 1050,
      avgBpm: 172,
      maxBpm: 182,
    ),
    OutdoorSegmentHistoryEntry(
      tagLabel: 'Rest',
      name: 'Active recovery',
      durationSeconds: 180,
      distanceMetres: 450,
      avgBpm: 148,
      maxBpm: 155,
    ),
    OutdoorSegmentHistoryEntry(
      tagLabel: 'Work',
      name: 'Hard effort',
      durationSeconds: 252, // slightly slower
      distanceMetres: 1020,
      avgBpm: 175,
      maxBpm: 185,
    ),
  ],
  avgBpm: 155,
  maxBpm: 185,
);

// A minimal entry with no HR data and a single work segment (no interval table).
const _minimalEntry = OutdoorWorkoutHistoryEntry(
  id: 'min',
  workoutName: 'Easy Run',
  startedAt: 0,
  durationSeconds: 1800,
  totalDistanceMetres: 5000,
  segments: [
    OutdoorSegmentHistoryEntry(
      tagLabel: 'Work',
      name: 'Run',
      durationSeconds: 1800,
      distanceMetres: 5000,
    ),
  ],
);

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late _FakeHistoryRepo historyRepo;

  setUp(() {
    historyRepo = _FakeHistoryRepo();
  });

  Widget buildWidget({OutdoorWorkoutHistoryEntry entry = _entryWithIntervals}) {
    return ProviderScope(
      overrides: [
        outdoorHistoryRepositoryProvider.overrideWithValue(historyRepo),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/results',
          routes: [
            GoRoute(
              path: '/results',
              pageBuilder: (_, __) => NoTransitionPage(
                child: OutdoorResultsScreen(entry: entry),
              ),
            ),
            GoRoute(
              path: '/outdoor',
              pageBuilder: (_, __) => const NoTransitionPage(
                child: Scaffold(body: Center(child: Text('Outdoor Home'))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('shows workout name in header', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(find.text('Norwegian 4×4'), findsOneWidget);
  });

  testWidgets('shows "Workout Complete" AppBar title', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(find.text('Workout Complete'), findsOneWidget);
  });

  testWidgets('overview shows total time and distance', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(find.text('42:30'), findsOneWidget);
    expect(find.text('8.20 km'), findsOneWidget);
  });

  testWidgets('overview shows avg HR and max HR when present', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(find.text('155 bpm'), findsOneWidget); // avg
    expect(find.text('185 bpm'), findsOneWidget); // max
  });

  testWidgets('overview omits HR fields when absent', (tester) async {
    await tester.pumpWidget(buildWidget(entry: _minimalEntry));
    await tester.pump();

    expect(find.text('AVG HR'), findsNothing);
    expect(find.text('MAX HR'), findsNothing);
  });

  testWidgets('segment breakdown shows numbered segment titles', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    // Single-occurrence tag has no ordinal; repeated tags get ordinals.
    expect(find.text('Warm-up'), findsOneWidget);
    expect(find.text('Work 1'), findsOneWidget);
    expect(find.text('Rest'), findsOneWidget);
    expect(find.text('Work 2'), findsOneWidget);
  });

  testWidgets('segment breakdown shows segment stats', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    // Warm-up stats: 12:30 duration, 2.05 km distance.
    expect(find.text('12:30'), findsOneWidget);
    expect(find.text('2.05 km'), findsOneWidget);
  });

  testWidgets('segment breakdown shows avg and max BPM per segment',
      (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(find.text('avg 172 bpm'), findsOneWidget);
    expect(find.text('max 182 bpm'), findsOneWidget);
  });

  testWidgets('shows interval comparison when there are 2+ work segments',
      (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(find.text('INTERVAL COMPARISON'), findsOneWidget);
    expect(find.text('Interval 1'), findsOneWidget);
    expect(find.text('Interval 2'), findsOneWidget);
  });

  testWidgets('no interval comparison with only one work segment',
      (tester) async {
    await tester.pumpWidget(buildWidget(entry: _minimalEntry));
    await tester.pump();

    expect(find.text('INTERVAL COMPARISON'), findsNothing);
  });

  testWidgets('Save saves entry to repo and navigates to outdoor home',
      (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    await tester.tap(find.text('Save to History'));
    await tester.pump(); // save future starts
    await tester.pump(); // future completes + context.go

    expect(find.text('Outdoor Home'), findsOneWidget);

    final saved = await historyRepo.getAll();
    expect(saved, hasLength(1));
    expect(saved.first.id, 'test-id');
  });

  testWidgets('Discard navigates to outdoor home without saving', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    await tester.tap(find.text('Discard'));
    await tester.pump();
    await tester.pump(); // GoRouter navigates

    expect(find.text('Outdoor Home'), findsOneWidget);

    final saved = await historyRepo.getAll();
    expect(saved, isEmpty);
  });

  testWidgets('Copy button is present', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(find.text('Copy'), findsOneWidget);
  });
}
