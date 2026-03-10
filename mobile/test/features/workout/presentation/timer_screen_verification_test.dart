/// Lightweight verification that TimerScreen builds without errors.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:training_timer/features/workout/data/models/workout_history.dart';
import 'package:training_timer/features/workout/data/repositories/workout_history_repository.dart';
import 'package:training_timer/features/workout/presentation/screens/timer_screen.dart';

class _FakeHistoryRepo implements WorkoutHistoryRepository {
  @override
  Future<List<WorkoutHistoryEntry>> getAll() async => [];
  @override
  Future<void> add(WorkoutHistoryEntry entry) async {}
  @override
  Future<void> clear() async {}
}

Widget _buildApp() {
  return ProviderScope(
    overrides: [
      workoutHistoryRepositoryProvider.overrideWithValue(_FakeHistoryRepo()),
    ],
    child: const MaterialApp(home: TimerScreen()),
  );
}

void main() {
  group('TimerScreen Build Verification', () {
    testWidgets('TimerScreen builds without errors', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.byType(TimerScreen), findsOneWidget);
    });

    testWidgets('TimerScreen displays countdown text', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('TimerScreen displays control buttons', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.byType(ElevatedButton), findsWidgets);
    });

    testWidgets('TimerScreen has progress indicator', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });

    testWidgets('TimerScreen Start button can be tapped', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      final buttons = find.byType(ElevatedButton);
      expect(buttons, findsWidgets);
      await tester.tap(buttons.first);
      await tester.pump();
    });
  });
}
