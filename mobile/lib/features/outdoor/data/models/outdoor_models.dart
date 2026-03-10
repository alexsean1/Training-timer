import 'package:freezed_annotation/freezed_annotation.dart';

part 'outdoor_models.freezed.dart';
part 'outdoor_models.g.dart';

// ─── Tag ─────────────────────────────────────────────────────────────────────

/// Describes the purpose of an [OutdoorSegment].
///
/// The four predefined variants cover the standard training phases.
/// Use [OutdoorSegmentTag.custom] for anything else (e.g. "Strides",
/// "Hill repeats").
@freezed
abstract class OutdoorSegmentTag with _$OutdoorSegmentTag {
  const factory OutdoorSegmentTag.warmUp() = OutdoorTagWarmUp;
  const factory OutdoorSegmentTag.work() = OutdoorTagWork;
  const factory OutdoorSegmentTag.rest() = OutdoorTagRest;
  const factory OutdoorSegmentTag.coolDown() = OutdoorTagCoolDown;
  const factory OutdoorSegmentTag.custom({required String label}) =
      OutdoorTagCustom;

  factory OutdoorSegmentTag.fromJson(Map<String, dynamic> json) =>
      _$OutdoorSegmentTagFromJson(json);
}

/// Human-readable label for display in the UI.
extension OutdoorSegmentTagDisplay on OutdoorSegmentTag {
  String get displayLabel => when(
        warmUp: () => 'Warm-up',
        work: () => 'Work',
        rest: () => 'Rest',
        coolDown: () => 'Cool-down',
        custom: (label) => label,
      );

  /// True for segments where the user should be working hard (not resting).
  bool get isEffort => when(
        warmUp: () => false,
        work: () => true,
        rest: () => false,
        coolDown: () => false,
        custom: (_) => false,
      );
}

// ─── Segment ──────────────────────────────────────────────────────────────────

/// A single phase of an outdoor workout.
///
/// - [OutdoorSegment.distance]: GPS tracks position; the segment ends when
///   the target [metres] has been covered.
/// - [OutdoorSegment.timed]: a countdown timer runs for [seconds]; distance
///   covered during that time is recorded.
@freezed
abstract class OutdoorSegment with _$OutdoorSegment {
  const factory OutdoorSegment.distance({
    /// Target distance in whole metres (GPS resolution is sufficient).
    required int metres,
    required OutdoorSegmentTag tag,

    /// Optional display name, e.g. "Warm-up jog". Defaults to empty.
    @Default('') String name,
  }) = OutdoorDistanceSegment;

  const factory OutdoorSegment.timed({
    /// Duration in seconds.
    required int seconds,
    required OutdoorSegmentTag tag,

    /// Optional display name, e.g. "Hard effort". Defaults to empty.
    @Default('') String name,
  }) = OutdoorTimedSegment;

  factory OutdoorSegment.fromJson(Map<String, dynamic> json) =>
      _$OutdoorSegmentFromJson(json);
}

/// Convenience display helpers for a segment.
extension OutdoorSegmentDisplay on OutdoorSegment {
  /// Short human-readable value string, e.g. "2 km", "800 m", "4:00".
  String get displayValue => when(
        distance: (metres, _, __) {
          if (metres >= 1000 && metres % 1000 == 0) {
            return '${metres ~/ 1000} km';
          }
          if (metres >= 1000) {
            final km = metres / 1000.0;
            return '${km.toStringAsFixed(1)} km';
          }
          return '$metres m';
        },
        timed: (seconds, _, __) {
          final m = seconds ~/ 60;
          final s = seconds.remainder(60);
          return m > 0
              ? '$m:${s.toString().padLeft(2, '0')}'
              : '${s}s';
        },
      );

  OutdoorSegmentTag get tag => when(
        distance: (_, tag, __) => tag,
        timed: (_, tag, __) => tag,
      );

  String get name => when(
        distance: (_, __, name) => name,
        timed: (_, __, name) => name,
      );
}

// ─── Group ────────────────────────────────────────────────────────────────────

/// A set of [OutdoorSegment]s repeated [repeats] times consecutively.
@freezed
abstract class OutdoorGroup with _$OutdoorGroup {
  const factory OutdoorGroup({
    required List<OutdoorSegment> segments,
    @Default(1) int repeats,
  }) = _OutdoorGroup;

  factory OutdoorGroup.fromJson(Map<String, dynamic> json) =>
      _$OutdoorGroupFromJson(json);
}

// ─── Element ──────────────────────────────────────────────────────────────────

/// One item in an [OutdoorWorkout]'s ordered list — either a bare segment or
/// a repeating group of segments.
@freezed
abstract class OutdoorElement with _$OutdoorElement {
  const factory OutdoorElement.segment(OutdoorSegment segment) =
      OutdoorElementSegment;
  const factory OutdoorElement.group(OutdoorGroup group) = OutdoorElementGroup;

  factory OutdoorElement.fromJson(Map<String, dynamic> json) =>
      _$OutdoorElementFromJson(json);
}

// ─── Workout ──────────────────────────────────────────────────────────────────

/// An ordered sequence of outdoor training elements.
@freezed
abstract class OutdoorWorkout with _$OutdoorWorkout {
  const factory OutdoorWorkout({
    required List<OutdoorElement> elements,
    @Default('') String notes,
  }) = _OutdoorWorkout;

  factory OutdoorWorkout.fromJson(Map<String, dynamic> json) =>
      _$OutdoorWorkoutFromJson(json);
}

// ─── Preset ───────────────────────────────────────────────────────────────────

/// A saved outdoor workout with user-facing metadata.
@freezed
abstract class OutdoorWorkoutPreset with _$OutdoorWorkoutPreset {
  const factory OutdoorWorkoutPreset({
    required String id,
    required String name,
    required OutdoorWorkout workout,

    /// Unix epoch milliseconds — set once at creation, never updated.
    @Default(0) int createdAt,
  }) = _OutdoorWorkoutPreset;

  factory OutdoorWorkoutPreset.fromJson(Map<String, dynamic> json) =>
      _$OutdoorWorkoutPresetFromJson(json);
}
