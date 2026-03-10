import 'package:flutter_test/flutter_test.dart';
import 'package:training_timer/features/workout/core/workout_timer.dart';
import 'package:training_timer/features/workout/data/models/workout_models.dart';

void main() {
  group('WorkoutTimerNotifier', () {
    Workout simpleWorkout() => const Workout(elements: [
          WorkoutElement.segment(WorkoutSegment.emom(duration: Duration(seconds: 3))),
          WorkoutElement.segment(WorkoutSegment.rest(duration: Duration(seconds: 2))),
        ]);

    test('counts down and transitions through segments', () {
      final notifier = WorkoutTimerNotifier(simpleWorkout());
      notifier.start();

      // initial state should be first segment
      expect(notifier.state.currentIndex, 0);
      expect(notifier.state.currentSegment is EmomSegment, isTrue);
      expect(notifier.state.remaining, const Duration(seconds: 3));

      // tick once: 2 seconds left
      notifier.tick();
      expect(notifier.state.remaining, const Duration(seconds: 2));
      expect(notifier.state.elapsed, const Duration(seconds: 1));

      // tick twice more -> segment should finish and advance
      notifier.tick();
      notifier.tick();
      expect(notifier.state.currentIndex, 1);
      expect(notifier.state.currentSegment is RestSegment, isTrue);
      expect(notifier.state.remaining, const Duration(seconds: 2));

      // finish workout
      notifier.tick();
      notifier.tick();
      expect(notifier.state.isCompleted, isTrue);
      expect(notifier.state.isRunning, isFalse);
    });

    test('grouped segments repeat correctly and round is tracked', () {
      // group of two segments repeated 3 times
      const group = WorkoutGroup(
        segments: [
          WorkoutSegment.emom(duration: Duration(seconds: 1)),
          WorkoutSegment.rest(duration: Duration(seconds: 1)),
        ],
        repeats: 3,
      );
      const workout = Workout(elements: [WorkoutElement.group(group)]);
      final notifier = WorkoutTimerNotifier(workout);
      notifier.start();

      // total segments flattened = 6
      expect(notifier.state.totalSegments, 6);

      // inspect flattened entries directly for sanity
      expect(notifier.debugEntries.length, 6);
      expect(notifier.debugEntries.map((e) => e.groupProgress?.round).toList(),
          [1, 1, 2, 2, 3, 3]);

      // step through the workout one segment at a time and record rounds
      final seenRounds = <int>[];
      while (!notifier.state.isCompleted) {
        seenRounds.add(notifier.state.groupProgress!.round);
        notifier.tick();
      }
      expect(seenRounds, [1, 1, 2, 2, 3, 3]);
      expect(notifier.state.isCompleted, isTrue);
      expect(notifier.state.groupProgress?.round, 3);
    });

    test('pause and resume preserve remaining time', () {
      final notifier = WorkoutTimerNotifier(simpleWorkout());
      notifier.start();
      notifier.tick();
      final after1 = notifier.state.remaining;
      notifier.pause();
      // ticks during pause shouldn't change
      notifier.tick();
      expect(notifier.state.remaining, after1);
      notifier.resume();
      notifier.tick();
      expect(notifier.state.remaining, after1 - const Duration(seconds: 1));
    });

    test('reset returns to initial state', () {
      final notifier = WorkoutTimerNotifier(simpleWorkout());
      notifier.start();
      notifier.tick();
      notifier.reset();
      expect(notifier.state, WorkoutTimerState.initial());
    });
  });
}
