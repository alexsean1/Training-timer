import 'package:freezed_annotation/freezed_annotation.dart';

part 'workout_history.freezed.dart';
part 'workout_history.g.dart';

@freezed
abstract class WorkoutHistoryEntry with _$WorkoutHistoryEntry {
  const factory WorkoutHistoryEntry({
    required String id,
    required String workoutName,

    /// Unix epoch milliseconds when the workout started.
    required int startedAt,

    /// Actual time elapsed in seconds (paused time excluded).
    required int durationSeconds,

    /// True when all segments ran to completion; false if stopped early.
    @Default(true) bool completed,
  }) = _WorkoutHistoryEntry;

  factory WorkoutHistoryEntry.fromJson(Map<String, dynamic> json) =>
      _$WorkoutHistoryEntryFromJson(json);
}
