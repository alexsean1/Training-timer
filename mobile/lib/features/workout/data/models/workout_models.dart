import 'package:freezed_annotation/freezed_annotation.dart';

part 'workout_models.freezed.dart';
part 'workout_models.g.dart';

/// Converts a [Duration] to/from an integer number of seconds for JSON.
class DurationConverter implements JsonConverter<Duration, int> {
  const DurationConverter();

  @override
  Duration fromJson(int seconds) => Duration(seconds: seconds);

  @override
  int toJson(Duration duration) => duration.inSeconds;
}

@freezed
abstract class WorkoutPreset with _$WorkoutPreset {
  const factory WorkoutPreset({
    required String id,
    required String name,
    required Workout workout,
    /// Unix epoch milliseconds — set once on creation, never updated.
    @Default(0) int createdAt,
  }) = _WorkoutPreset;

  factory WorkoutPreset.fromJson(Map<String, dynamic> json) =>
      _$WorkoutPresetFromJson(json);
}

@freezed
abstract class Workout with _$Workout {
  const factory Workout({
    required List<WorkoutElement> elements,
    @Default('') String notes,
  }) = _Workout;

  factory Workout.fromJson(Map<String, dynamic> json) =>
      _$WorkoutFromJson(json);
}

@freezed
abstract class WorkoutElement with _$WorkoutElement {
  const factory WorkoutElement.segment(WorkoutSegment segment) =
      _WorkoutElementSegment;
  const factory WorkoutElement.group(WorkoutGroup group) =
      _WorkoutElementGroup;

  factory WorkoutElement.fromJson(Map<String, dynamic> json) =>
      _$WorkoutElementFromJson(json);
}

@freezed
abstract class WorkoutGroup with _$WorkoutGroup {
  const factory WorkoutGroup({
    required List<WorkoutSegment> segments,
    @Default(1) int repeats,
  }) = _WorkoutGroup;

  factory WorkoutGroup.fromJson(Map<String, dynamic> json) =>
      _$WorkoutGroupFromJson(json);
}

@freezed
abstract class WorkoutSegment with _$WorkoutSegment {
  const factory WorkoutSegment.emom({
    @DurationConverter() required Duration duration,
  }) = EmomSegment;
  const factory WorkoutSegment.amrap({
    @DurationConverter() required Duration duration,
  }) = AmrapSegment;
  const factory WorkoutSegment.forTime({
    @DurationConverter() required Duration duration,
  }) = ForTimeSegment;
  const factory WorkoutSegment.rest({
    @DurationConverter() required Duration duration,
  }) = RestSegment;

  factory WorkoutSegment.fromJson(Map<String, dynamic> json) =>
      _$WorkoutSegmentFromJson(json);
}
