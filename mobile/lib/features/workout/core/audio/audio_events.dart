/// Events emitted by [WorkoutTimerNotifier] that the UI layer translates
/// into audio playback via [WorkoutAudioService].
sealed class WorkoutAudioEvent {
  const WorkoutAudioEvent();
}

/// Fired when the segment has 3, 2, or 1 seconds remaining.
/// Triggers a beep tone.  [nextIsWork] tells the audio service which
/// pitch/tone family to use so the countdown already "feels" like what's
/// coming next.
final class CountdownBeepEvent extends WorkoutAudioEvent {
  const CountdownBeepEvent({required this.count, required this.nextIsWork});

  /// Seconds remaining: 3, 2, or 1.
  final int count;

  /// Whether the NEXT segment (after the transition) is a work segment.
  final bool nextIsWork;
}

/// Fired at the moment a segment transition occurs.
/// Triggers the spoken "Go!" / "Rest!" / "Next round!" announcement.
final class TransitionAnnouncementEvent extends WorkoutAudioEvent {
  const TransitionAnnouncementEvent({
    required this.isWork,
    this.isNewRound = false,
  });

  /// Whether the NEW (incoming) segment is a work segment.
  final bool isWork;

  /// True when entering a new round of a repeated group.
  final bool isNewRound;
}

/// Fired once per segment when the halfway point is crossed.
/// Triggers a single halfway-marker beep.
final class HalfwayBeepEvent extends WorkoutAudioEvent {
  const HalfwayBeepEvent();
}

/// Fired when the entire workout finishes.
/// Triggers the completion melody + "Workout complete!" announcement.
final class WorkoutCompleteEvent extends WorkoutAudioEvent {
  const WorkoutCompleteEvent();
}
