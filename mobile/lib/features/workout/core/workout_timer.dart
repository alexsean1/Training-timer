import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/workout_models.dart';
import 'audio/audio_events.dart';

part 'workout_timer.freezed.dart';

/// Progress information for a segment that lives inside a repeated group.
class GroupProgress {
  const GroupProgress({required this.round, required this.totalRounds});

  /// 1-based index of the current round.
  final int round;

  /// Total number of rounds for the enclosing group.
  final int totalRounds;
}

/// Internal flattened entry used by the timer engine.
class SegmentEntry {
  const SegmentEntry(this.segment, this.groupProgress);

  final WorkoutSegment segment;
  final GroupProgress? groupProgress;
}

@freezed
abstract class WorkoutTimerState with _$WorkoutTimerState {
  const factory WorkoutTimerState({
    /// Currently active segment (or null if not started).
    required WorkoutSegment? currentSegment,

    /// 0-based index in the flattened sequence.
    required int currentIndex,

    /// Total number of segments in the flattened workout.
    required int totalSegments,

    /// Time remaining in the current segment.
    required Duration remaining,

    /// Total elapsed time since start (does not include paused time).
    required Duration elapsed,

    /// Whether the timer is currently running.
    required bool isRunning,

    /// Whether the timer is paused.
    required bool isPaused,

    /// Whether the workout has finished.
    required bool isCompleted,

    /// True for any non-rest segment.
    required bool isWork,

    /// If the current segment belongs to a repeated group, this will be
    /// non-null and indicate the current/total round.
    required GroupProgress? groupProgress,
  }) = _WorkoutTimerState;

  factory WorkoutTimerState.initial() => const WorkoutTimerState(
        currentSegment: null,
        currentIndex: 0,
        totalSegments: 0,
        remaining: Duration.zero,
        elapsed: Duration.zero,
        isRunning: false,
        isPaused: false,
        isCompleted: false,
        isWork: false,
        groupProgress: null,
      );
}

/// Notifier that drives the workout timer.  Clients can call [start],
/// [pause], [resume], [reset] and manually invoke [tick] (useful in tests).
///
/// Audio events are broadcast on [audioEvents] so that the presentation layer
/// can trigger the appropriate sounds without this class knowing about audio.
class WorkoutTimerNotifier extends StateNotifier<WorkoutTimerState> {
  WorkoutTimerNotifier(this._workout) : super(WorkoutTimerState.initial()) {
    _entries = _flatten(_workout);
    debugEntries = _entries;
  }

  final Workout _workout;
  late final List<SegmentEntry> _entries;
  Timer? _timer;

  // Wall-clock references for drift correction on foreground return.
  DateTime? _wallClockBase;
  DateTime? _pausedAt;
  Duration _totalPausedDuration = Duration.zero;

  // Audio event broadcast stream
  final _audioController = StreamController<WorkoutAudioEvent>.broadcast();

  /// Stream of audio events emitted by the timer.  Subscribe in the UI layer
  /// to drive [WorkoutAudioService].
  Stream<WorkoutAudioEvent> get audioEvents => _audioController.stream;

  // Halfway-beep tracking — reset each time a new segment starts.
  Duration _currentSegmentDuration = Duration.zero;
  bool _halfwayFired = false;

  /// For tests: the flattened sequence of segments that will be played.
  @visibleForTesting
  late final List<SegmentEntry> debugEntries;

  /// Expose workout (immutable).
  Workout get workout => _workout;

  /// Starts the timer from the beginning.  If already running it will be
  /// reset first.
  void start() {
    reset();
    if (_entries.isEmpty) return;
    _wallClockBase = DateTime.now();
    _totalPausedDuration = Duration.zero;
    _setEntry(0);
    _startClock();
  }

  /// Pauses the clock.  Remaining time is preserved.
  void pause() {
    if (!state.isRunning || state.isPaused) return;
    _pausedAt = DateTime.now();
    _timer?.cancel();
    state = state.copyWith(isPaused: true);
  }

  /// Resumes after a pause.
  void resume() {
    if (!state.isRunning || !state.isPaused) return;
    if (_pausedAt != null) {
      _totalPausedDuration += DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
    }
    state = state.copyWith(isPaused: false);
    _startClock();
  }

  /// Cancels and returns to initial state (nothing running).
  void reset() {
    _timer?.cancel();
    _wallClockBase = null;
    _pausedAt = null;
    _totalPausedDuration = Duration.zero;
    state = WorkoutTimerState.initial();
  }

  /// Compares the wall-clock elapsed time with the timer's recorded elapsed
  /// time and fast-forwards by any drift ≥ 2 seconds.
  ///
  /// Call from [AppLifecycleListener.onResume] to re-sync after the app
  /// returns from the background (e.g. after a phone lock/unlock).
  void syncFromWallClock() {
    if (!state.isRunning || state.isPaused || _wallClockBase == null) return;
    final wallElapsed =
        DateTime.now().difference(_wallClockBase!) - _totalPausedDuration;
    final drift = wallElapsed - state.elapsed;
    if (drift >= const Duration(seconds: 2)) {
      tick(step: drift);
    }
  }

  /// Advances the timer by the given duration.  This is used by the internal
  /// clock but also exposed for unit tests so they don't have to wait real time.
  void tick({Duration step = const Duration(seconds: 1)}) {
    if (!state.isRunning || state.isPaused || state.isCompleted) return;

    final rem = state.remaining - step;
    final elapsed = state.elapsed + step;

    if (rem > Duration.zero) {
      // ── Halfway-beep ───────────────────────────────────────────────────────
      if (!_halfwayFired && _currentSegmentDuration > Duration.zero) {
        final halfSec = _currentSegmentDuration.inSeconds ~/ 2;
        if (halfSec > 0 &&
            state.remaining.inSeconds > halfSec &&
            rem.inSeconds <= halfSec) {
          _halfwayFired = true;
          _audioController.add(const HalfwayBeepEvent());
        }
      }

      // ── Countdown beeps (last 3 seconds of segment) ────────────────────────
      final remSec = rem.inSeconds;
      if (remSec >= 1 && remSec <= 3) {
        _audioController.add(
          CountdownBeepEvent(count: remSec, nextIsWork: _nextIsWork()),
        );
      }

      state = state.copyWith(remaining: rem, elapsed: elapsed);
    } else {
      // Time to switch segments; carry the overflow into the next segment so
      // that multi-second steps in tests still work correctly.
      _advanceSegment(
        elapsedOverflow: elapsed,
        overflow: step - state.remaining,
      );
    }
  }

  // ─── Internal helpers ───────────────────────────────────────────────────────

  void _startClock() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    state = state.copyWith(isRunning: true, isPaused: false);
  }

  void _advanceSegment({
    required Duration elapsedOverflow,
    required Duration overflow,
  }) {
    final nextIndex = state.currentIndex + 1;

    if (nextIndex < _entries.length) {
      final nextEntry = _entries[nextIndex];
      final nextIsWork = _isWork(nextEntry.segment);

      // Detect new-round transitions inside a repeated group.
      final isNewRound = nextEntry.groupProgress != null &&
          state.groupProgress != null &&
          nextEntry.groupProgress!.round != state.groupProgress!.round &&
          nextIsWork;

      _audioController.add(TransitionAnnouncementEvent(
        isWork: nextIsWork,
        isNewRound: isNewRound,
      ));

      _setEntry(nextIndex);
      state = state.copyWith(elapsed: elapsedOverflow);

      if (overflow > Duration.zero) {
        tick(step: overflow);
      }
    } else {
      // Workout finished.
      _timer?.cancel();
      _audioController.add(const WorkoutCompleteEvent());
      state = state.copyWith(
        remaining: Duration.zero,
        elapsed: elapsedOverflow,
        isRunning: false,
        isCompleted: true,
      );
    }
  }

  void _setEntry(int index) {
    final entry = _entries[index];
    final duration = entry.segment.when(
      emom: (d) => d,
      amrap: (d) => d,
      forTime: (d) => d,
      rest: (d) => d,
    );
    _currentSegmentDuration = duration;
    _halfwayFired = false;

    state = state.copyWith(
      currentSegment: entry.segment,
      currentIndex: index,
      totalSegments: _entries.length,
      remaining: duration,
      elapsed: state.elapsed,
      isWork: _isWork(entry.segment),
      groupProgress: entry.groupProgress,
    );
  }

  bool _isWork(WorkoutSegment segment) => segment.when(
        emom: (_) => true,
        amrap: (_) => true,
        forTime: (_) => true,
        rest: (_) => false,
      );

  /// Returns whether the NEXT segment (after the current one) is a work
  /// segment. Falls back to [false] when the current segment is the last one.
  bool _nextIsWork() {
    final nextIdx = state.currentIndex + 1;
    if (nextIdx >= _entries.length) return false;
    return _isWork(_entries[nextIdx].segment);
  }

  /// Flattens a [Workout] into a linear list of [SegmentEntry] objects.
  List<SegmentEntry> _flatten(Workout workout) {
    final out = <SegmentEntry>[];

    void handleElement(WorkoutElement element, {GroupProgress? gp}) {
      element.map(
        segment: (s) => out.add(SegmentEntry(s.segment, gp)),
        group: (g) {
          final repeats = g.group.repeats;
          for (var r = 1; r <= repeats; r++) {
            for (final seg in g.group.segments) {
              handleElement(
                WorkoutElement.segment(seg),
                gp: GroupProgress(round: r, totalRounds: repeats),
              );
            }
          }
        },
      );
    }

    for (final el in workout.elements) {
      handleElement(el);
    }

    return out;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioController.close();
    super.dispose();
  }
}

/// Provider for the audio-events stream scoped to a specific workout.
/// The [TimerScreen] subscribes to this to drive [WorkoutAudioService].
final workoutAudioEventsProvider =
    StreamProvider.family<WorkoutAudioEvent, Workout>(
  (ref, workout) =>
      ref.watch(workoutTimerProvider(workout).notifier).audioEvents,
);

/// Riverpod provider which creates a notifier for a specific workout.
final workoutTimerProvider = StateNotifierProvider.family<WorkoutTimerNotifier,
    WorkoutTimerState, Workout>(
  (ref, workout) => WorkoutTimerNotifier(workout),
);
