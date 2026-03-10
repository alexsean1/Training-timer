import 'package:freezed_annotation/freezed_annotation.dart';

part 'outdoor_history_models.freezed.dart';
part 'outdoor_history_models.g.dart';

// ─── Per-segment breakdown ────────────────────────────────────────────────────

/// A snapshot of one segment's performance within a completed outdoor workout.
@freezed
abstract class OutdoorSegmentHistoryEntry
    with _$OutdoorSegmentHistoryEntry {
  const factory OutdoorSegmentHistoryEntry({
    /// Display label derived from the segment's tag (e.g. "Warm-up", "Work").
    required String tagLabel,

    /// Optional user-provided name for the segment (may be empty).
    @Default('') String name,

    /// Actual time the user spent in this segment, in seconds.
    required int durationSeconds,

    /// GPS distance covered during this segment, in metres.
    @Default(0.0) double distanceMetres,

    /// Average heart rate during this segment, in BPM; null when no HR monitor.
    int? avgBpm,

    /// Peak heart rate recorded during this segment, in BPM.
    int? maxBpm,
  }) = _OutdoorSegmentHistoryEntry;

  factory OutdoorSegmentHistoryEntry.fromJson(Map<String, dynamic> json) =>
      _$OutdoorSegmentHistoryEntryFromJson(json);
}

// ─── Full workout record ──────────────────────────────────────────────────────

/// A record of a completed outdoor workout, stored in Hive history.
@freezed
abstract class OutdoorWorkoutHistoryEntry
    with _$OutdoorWorkoutHistoryEntry {
  const factory OutdoorWorkoutHistoryEntry({
    required String id,

    /// Name of the workout (preset name, or empty for ad-hoc sessions).
    required String workoutName,

    /// Unix epoch milliseconds when the workout started.
    required int startedAt,

    /// Total elapsed time in seconds.
    required int durationSeconds,

    /// Total GPS distance covered during the workout, in metres.
    @Default(0.0) double totalDistanceMetres,

    /// Per-segment breakdown; ordered as they were executed.
    @Default([]) List<OutdoorSegmentHistoryEntry> segments,

    /// Overall average heart rate across the whole workout, in BPM.
    int? avgBpm,

    /// Peak heart rate recorded during the whole workout, in BPM.
    int? maxBpm,
  }) = _OutdoorWorkoutHistoryEntry;

  factory OutdoorWorkoutHistoryEntry.fromJson(Map<String, dynamic> json) =>
      _$OutdoorWorkoutHistoryEntryFromJson(json);
}
