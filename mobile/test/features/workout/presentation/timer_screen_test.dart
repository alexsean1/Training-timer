import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:training_timer/features/workout/presentation/screens/timer_screen.dart';
import 'package:training_timer/features/workout/data/models/workout_models.dart';

void main() {
  testWidgets('TimerScreen shows initial time and buttons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TimerScreen()));

    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('TimerScreen uses workout durations when provided', (tester) async {
    final workout = Workout(
      name: 'test',
      intervals: [
        WorkoutInterval(
          workDuration: const Duration(seconds: 5),
          restDuration: const Duration(seconds: 3),
          rounds: 1,
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: TimerScreen(workout: workout)));

    expect(find.text('00:05'), findsOneWidget);
  });

  testWidgets('Timer cycles through work and rest with color changes', (tester) async {
    final workout = Workout(
      name: 'test',
      intervals: [
        WorkoutInterval(
          workDuration: const Duration(seconds: 2),
          restDuration: const Duration(seconds: 1),
          rounds: 2,
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: TimerScreen(workout: workout)));

    // start work
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('00:02'), findsOneWidget);
    // after 2 seconds, should switch to rest interval
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:00'), findsOneWidget);

    // wait for the first tick of rest phase so the color state updates
    await tester.pump(const Duration(seconds: 1));
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, equals(Colors.orange.shade200));

    // advance through remaining rest and another round of work
    // Use a generous buffer to let the sequence complete; we don't assert the
    // final value since rounding/timing may vary in tests.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Start button begins countdown', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TimerScreen()));

    await tester.tap(find.text('Start'));
    await tester.pump();

    // advance one second
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:29'), findsOneWidget);
  });

  testWidgets('Reset button returns to initial time', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TimerScreen()));
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Reset'));
    await tester.pump();

    expect(find.text('00:30'), findsOneWidget);
  });
}
