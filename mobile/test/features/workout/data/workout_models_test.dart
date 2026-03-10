import 'package:flutter_test/flutter_test.dart';
import 'package:training_timer/features/workout/data/models/workout_models.dart';

void main() {
  group('WorkoutSegment serialization', () {
    final segments = [
      const WorkoutSegment.emom(duration: Duration(minutes: 1)),
      const WorkoutSegment.amrap(duration: Duration(seconds: 90)),
      const WorkoutSegment.forTime(duration: Duration(minutes: 2)),
      const WorkoutSegment.rest(duration: Duration(seconds: 30)),
    ];

    for (final segment in segments) {
      test('${segment.runtimeType} round-trips', () {
        final json = segment.toJson();
        final parsed = WorkoutSegment.fromJson(json);
        expect(parsed, equals(segment));
      });
    }
  });

  test('WorkoutGroup serialization with repeats', () {
    const group = WorkoutGroup(
      segments: [
        WorkoutSegment.rest(duration: Duration(seconds: 20)),
        WorkoutSegment.forTime(duration: Duration(minutes: 1)),
      ],
      repeats: 3,
    );
    final json = group.toJson();
    final parsed = WorkoutGroup.fromJson(json);
    expect(parsed, equals(group));
  });

  test('WorkoutElement union serialization', () {
    const seg = WorkoutElement.segment(
      WorkoutSegment.amrap(duration: Duration(minutes: 3)),
    );
    const grp = WorkoutElement.group(
      WorkoutGroup(segments: [
        WorkoutSegment.rest(duration: Duration(seconds: 10)),
      ], repeats: 2),
    );
    final roundtripSeg = WorkoutElement.fromJson(seg.toJson());
    final roundtripGrp = WorkoutElement.fromJson(grp.toJson());
    expect(roundtripSeg, equals(seg));
    expect(roundtripGrp, equals(grp));
  });

  test('Workout serialization with mixed elements', () {
    const workout = Workout(elements: [
      WorkoutElement.segment(
          WorkoutSegment.emom(duration: Duration(minutes: 10))),
      WorkoutElement.group(
        WorkoutGroup(
          segments: [
            WorkoutSegment.amrap(duration: Duration(minutes: 3)),
            WorkoutSegment.rest(duration: Duration(minutes: 2)),
          ],
          repeats: 2,
        ),
      ),
      WorkoutElement.segment(
          WorkoutSegment.rest(duration: Duration(seconds: 30))),
    ]);
    final json = workout.toJson();
    final parsed = Workout.fromJson(json);
    expect(parsed, equals(workout));
  });

  test('WorkoutPreset serialization', () {
    const preset = WorkoutPreset(
      id: 'test-id',
      name: 'Test preset',
      workout: Workout(elements: [
        WorkoutElement.segment(
            WorkoutSegment.forTime(duration: Duration(minutes: 5))),
      ]),
    );
    final json = preset.toJson();
    final parsed = WorkoutPreset.fromJson(json);
    expect(parsed, equals(preset));
  });
}
