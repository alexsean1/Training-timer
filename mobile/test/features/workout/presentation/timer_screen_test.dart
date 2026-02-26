import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:training_timer/features/workout/presentation/screens/timer_screen.dart';

void main() {
  testWidgets('TimerScreen shows initial time and buttons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TimerScreen()));

    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
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
