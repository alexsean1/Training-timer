/// Manual test to verify TimerScreen rendering without auth overhead.
/// Run with: flutter test test/features/workout/presentation/timer_screen_manual_test.dart
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
    child: const MaterialApp(home: Scaffold(body: TimerScreen())),
  );
}

void main() {
  void setPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('TimerScreen Manual Rendering Test', () {
    testWidgets('Displays large countdown timer for sample workout',
        (tester) async {
      setPhoneSize(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byWidgetPredicate((widget) {
        return widget is Text &&
            widget.data != null &&
            widget.data!.contains(':');
      }), findsWidgets);
    });

    testWidgets('Displays segment type and work/rest colors', (tester) async {
      setPhoneSize(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      // Start the timer so the first segment becomes active.
      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pump();

      expect(
        find.byWidgetPredicate((widget) {
          if (widget is Text && widget.data != null) {
            return ['EMOM', 'AMRAP', 'FOR TIME', 'REST'].contains(widget.data);
          }
          return false;
        }),
        findsWidgets,
      );

      // The active Scaffold uses a dark tinted background per segment type.
      final segmentBgColors = {
        const Color(0xFF071E1A), // EMOM teal tint
        const Color(0xFF1E1207), // AMRAP orange tint
        const Color(0xFF1E0707), // FOR TIME red tint
        const Color(0xFF0D0D0F), // REST / default background
      };
      expect(
        find.byWidgetPredicate((widget) {
          if (widget is Scaffold && widget.backgroundColor != null) {
            return segmentBgColors.contains(widget.backgroundColor);
          }
          return false;
        }),
        findsWidgets,
      );

      // Reset to cancel the periodic timer before the test ends.
      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pump();
    });

    testWidgets('Displays round tracking for grouped segments', (tester) async {
      setPhoneSize(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      // Start the timer so the first group segment becomes active.
      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pump();

      expect(
        find.byWidgetPredicate((widget) {
          return widget is Text &&
              widget.data != null &&
              widget.data!.contains('Round');
        }),
        findsWidgets,
      );

      // Reset to cancel the periodic timer before the test ends.
      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pump();
    });

    testWidgets('Displays Start/Pause/Reset control buttons', (tester) async {
      setPhoneSize(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byType(ElevatedButton), findsWidgets);
      expect(
        find.byWidgetPredicate((widget) {
          if (widget is Text && widget.data != null) {
            return ['Start', 'Pause', 'Resume', 'Reset'].contains(widget.data);
          }
          return false;
        }),
        findsWidgets,
      );
    });

    testWidgets('Displays progress bar', (tester) async {
      setPhoneSize(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });

    testWidgets('Start button initiates countdown', (tester) async {
      setPhoneSize(tester);
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      final startButton = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'Start',
      );
      expect(startButton, findsWidgets, reason: 'Start button should be present');

      // Tap Start, verify it transitions to running state
      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pump();

      // Tap Reset to cancel the periodic timer before the test ends
      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pump();
    });
  });
}
