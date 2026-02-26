import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:training_timer/features/workout/data/models/workout_models.dart';
import 'package:training_timer/features/workout/presentation/screens/timer_screen.dart';
import 'package:training_timer/features/workout/presentation/screens/workout_editor_screen.dart';

void main() {
  testWidgets('WorkoutEditorScreen form and navigation', (tester) async {
    final router = GoRouter(
      initialLocation: '/editor',
      routes: [
        GoRoute(
          path: '/editor',
          builder: (context, state) => const WorkoutEditorScreen(),
        ),
        GoRoute(
          path: '/timer',
          builder: (context, state) {
            final workout = state.extra as Workout?;
            return TimerScreen(workout: workout);
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // ensure editor fields present
    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(find.text('Work (seconds)'), findsOneWidget);

    // fill in values
    await tester.enterText(find.widgetWithText(TextFormField, 'Work (seconds)'), '3');
    await tester.enterText(find.widgetWithText(TextFormField, 'Rest (seconds)'), '2');
    await tester.enterText(find.widgetWithText(TextFormField, 'Rounds'), '1');

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    // after navigation we should be on TimerScreen with 3-second initial
    expect(find.text('00:03'), findsOneWidget);
  });
}
