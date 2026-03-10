import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:training_timer/features/workout/data/models/workout_history.dart';
import 'package:training_timer/features/workout/data/models/workout_models.dart';
import 'package:training_timer/features/workout/data/repositories/workout_history_repository.dart';
import 'package:training_timer/features/workout/presentation/screens/timer_screen.dart';

// ── Fake history repository ────────────────────────────────────────────────────

class _FakeHistoryRepo implements WorkoutHistoryRepository {
  @override
  Future<List<WorkoutHistoryEntry>> getAll() async => [];

  @override
  Future<void> add(WorkoutHistoryEntry entry) async {}

  @override
  Future<void> clear() async {}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

WorkoutPreset _makePreset(Duration d) {
  return WorkoutPreset(
    id: 'test',
    name: 'Test',
    workout: Workout(elements: [
      WorkoutElement.segment(WorkoutSegment.forTime(duration: d)),
    ]),
  );
}

Widget _buildApp({WorkoutPreset? preset}) {
  return ProviderScope(
    overrides: [
      workoutHistoryRepositoryProvider.overrideWithValue(_FakeHistoryRepo()),
    ],
    child: MaterialApp(home: TimerScreen(preset: preset)),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('TimerScreen shows initial time and buttons', (tester) async {
    await tester.pumpWidget(_buildApp());
    // allow provider to prepare initial state
    await tester.pump();

    // sample workout begins at 03:00 so we look for that
    expect(find.text('03:00'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('TimerScreen uses workout durations when provided', (tester) async {
    await tester.pumpWidget(
        _buildApp(preset: _makePreset(const Duration(seconds: 5))));
    await tester.pump();

    expect(find.text('05'), findsOneWidget);
  });

  testWidgets('Start button begins countdown', (tester) async {
    await tester.pumpWidget(
        _buildApp(preset: _makePreset(const Duration(seconds: 10))));
    await tester.pump();

    await tester.tap(find.text('Start'));
    await tester.pump();

    // advance one second
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('09'), findsOneWidget);
  });

  testWidgets('Reset button returns to initial time', (tester) async {
    await tester.pumpWidget(
        _buildApp(preset: _makePreset(const Duration(seconds: 8))));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Reset'));
    await tester.pump();

    expect(find.text('08'), findsOneWidget);
  });
}
