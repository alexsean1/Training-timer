import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../core/foreground_service.dart';
import '../../core/audio/audio_events.dart';
import '../../core/audio/workout_audio_service.dart';
import '../../core/workout_timer.dart';
import '../../data/models/workout_history.dart';
import '../../data/models/workout_models.dart';
import '../../data/repositories/workout_history_repository.dart';

/// Full-screen workout timer widget.
///
/// Visual features:
/// - Large countdown display that pulses during the last 10 seconds.
/// - 3-2-1 countdown overlay numbers during the last 3 seconds of a segment.
/// - Segment-type label (EMOM / AMRAP / FOR TIME / REST).
/// - Green (work) / red (rest) background colour.
/// - Round progress indicator for grouped segments.
/// - Linear progress bar across the whole workout.
/// - Start / Pause-Resume / Reset controls.
/// - "Go!" / "Rest!" announcement overlay on segment transitions.
///
/// Audio features (via [WorkoutAudioService]):
/// - Beep tones for 3-2-1 countdown before each transition.
/// - Spoken "Go!" / "Rest!" / "Next round" after each transition.
/// - Single beep at the halfway point of every segment.
/// - Ascending fanfare + "Workout complete" at the end.
///
/// History: automatically records a [WorkoutHistoryEntry] when the workout
/// finishes or when the screen is dismissed mid-workout.
class TimerScreen extends ConsumerStatefulWidget {
  final WorkoutPreset? preset;
  const TimerScreen({super.key, this.preset});

  @override
  ConsumerState<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends ConsumerState<TimerScreen>
    with SingleTickerProviderStateMixin {
  static const _uuid = Uuid();

  // ── Effective workout (set once in initState) ─────────────────────────────
  late final Workout _workout;

  // ── History tracking ──────────────────────────────────────────────────────
  int? _startedAt; // epoch ms when Start was first tapped
  bool _hasRecordedHistory = false;
  late final WorkoutHistoryRepository _historyRepo;
  late final WorkoutAudioService _audioService;

  /// Cached from the most-recent build so it's safe to read in dispose().
  Duration _elapsed = Duration.zero;

  // ── Pulse animation (last 10 seconds) ────────────────────────────────────
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  // ── Background / lifecycle ────────────────────────────────────────────────
  AppLifecycleListener? _lifecycleListener;

  // ── Announcement overlay ──────────────────────────────────────────────────
  String? _announcement;
  Timer? _announcementTimer;

  // ── Notes sheet ───────────────────────────────────────────────────────────
  void _showNotesSheet(String notes) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Workout Notes',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            SelectableText(
              notes,
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  // ── Derived: whether pulse is currently active ────────────────────────────
  bool _pulsingEnabled = false;

  static const Workout _sampleWorkout = Workout(elements: [
    // Two rounds of AMRAP + rest
    WorkoutElement.group(
      WorkoutGroup(
        segments: [
          WorkoutSegment.amrap(duration: Duration(minutes: 3)),
          WorkoutSegment.rest(duration: Duration(minutes: 2)),
        ],
        repeats: 2,
      ),
    ),
    // Then EMOM 10 minutes
    WorkoutElement.segment(
      WorkoutSegment.emom(duration: Duration(minutes: 10)),
    ),
  ]);

  @override
  void initState() {
    super.initState();

    _workout = widget.preset?.workout ?? _sampleWorkout;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.addStatusListener(_onPulseStatus);

    // Cache repo reference so _recordHistory() can be called safely in dispose().
    _historyRepo = ref.read(workoutHistoryRepositoryProvider);

    // Cache audio service so it's safe to call in dispose() (ref is gone by then).
    _audioService = ref.read(workoutAudioServiceProvider);

    // Initialise the audio service eagerly so the first beep has no delay.
    _audioService.init();

    // Keep the screen on while this screen is visible.
    WakelockPlus.enable().ignore();

    // Request Android 13+ notification permission for the FG service banner.
    FlutterForegroundTask.requestNotificationPermission();

    // Route notification button presses (Pause/Resume/Stop) to this screen.
    FlutterForegroundTask.addTaskDataCallback(_onForegroundTaskData);

    // Sync timer with wall clock when the app returns from the background.
    _lifecycleListener = AppLifecycleListener(onResume: _onAppResume);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onForegroundTaskData);
    _lifecycleListener?.dispose();
    WakelockPlus.disable().ignore();

    _pulseController.removeStatusListener(_onPulseStatus);
    _pulseController.dispose();
    _announcementTimer?.cancel();

    // Record an early-stop entry if the workout started but didn't complete.
    // Uses the cached _elapsed (safe — no ref.read() calls after unmount).
    if (_startedAt != null && !_hasRecordedHistory) {
      _recordHistory(completed: false, elapsed: _elapsed);
    }

    // Stop foreground service and keepalive if workout was in progress.
    if (_startedAt != null) {
      WorkoutForegroundService.stop().ignore();
      _audioService.stopKeepalive().ignore();
    }

    super.dispose();
  }

  // ── Background / lifecycle callbacks ──────────────────────────────────────

  void _onAppResume() {
    ref.read(workoutTimerProvider(_workout).notifier).syncFromWallClock();
  }

  void _onForegroundTaskData(Object data) {
    if (data case {'action': final String action}) {
      final notifier = ref.read(workoutTimerProvider(_workout).notifier);
      switch (action) {
        case 'pause_resume':
          final s = ref.read(workoutTimerProvider(_workout));
          if (s.isPaused) {
            notifier.resume();
          } else {
            notifier.pause();
          }
        case 'stop':
          notifier.reset();
          WorkoutForegroundService.stop().ignore();
          ref.read(workoutAudioServiceProvider).stopKeepalive().ignore();
      }
    }
  }

  // ── History recording ─────────────────────────────────────────────────────

  void _recordHistory({required bool completed, required Duration elapsed}) {
    if (_hasRecordedHistory || _startedAt == null || elapsed.inSeconds == 0) {
      return;
    }
    _hasRecordedHistory = true;
    final entry = WorkoutHistoryEntry(
      id: _uuid.v4(),
      workoutName: widget.preset?.name ?? 'Quick Workout',
      startedAt: _startedAt!,
      durationSeconds: elapsed.inSeconds,
      completed: completed,
    );
    // Fire-and-forget: uses cached ref-free repo so dispose() can call this.
    unawaited(_historyRepo.add(entry));
  }

  // ── Animation helpers ─────────────────────────────────────────────────────

  void _startPulse() {
    if (_pulsingEnabled) return;
    _pulsingEnabled = true;
    _pulseController.forward();
  }

  void _stopPulse() {
    if (!_pulsingEnabled) return;
    _pulsingEnabled = false;
    _pulseController.stop();
    _pulseController.value = 0.0;
  }

  void _onPulseStatus(AnimationStatus status) {
    if (!_pulsingEnabled) return;
    if (status == AnimationStatus.completed) {
      _pulseController.reverse();
    } else if (status == AnimationStatus.dismissed) {
      _pulseController.forward();
    }
  }

  // ── Audio event handler ───────────────────────────────────────────────────

  void _handleAudioEvent(WorkoutAudioEvent event) {
    final audio = ref.read(workoutAudioServiceProvider);
    switch (event) {
      case CountdownBeepEvent():
        audio.handleEvent(event);

      case TransitionAnnouncementEvent(:final isWork, :final isNewRound):
        audio.handleEvent(event);
        _showAnnouncement(
          isNewRound ? 'Next round!' : (isWork ? 'Go!' : 'Rest!'),
        );

      case HalfwayBeepEvent():
        audio.handleEvent(event);

      case WorkoutCompleteEvent():
        audio.handleEvent(event);
        _showAnnouncement(
          'Workout\ncomplete!',
          duration: const Duration(seconds: 3),
        );
        _recordHistory(completed: true, elapsed: _elapsed);
    }
  }

  void _showAnnouncement(
    String text, {
    Duration duration = const Duration(seconds: 2),
  }) {
    _announcementTimer?.cancel();
    setState(() => _announcement = text);
    _announcementTimer = Timer(duration, () {
      if (mounted) setState(() => _announcement = null);
    });
  }

  // ── Formatting ────────────────────────────────────────────────────────────

  String _format(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return min == '00' ? sec : '$min:$sec';
  }

  /// Before the timer starts, show the first segment's duration so the user
  /// can see what they're about to start.  Falls back to Duration.zero if
  /// the workout is empty.
  Duration _firstSegmentDuration() {
    if (_workout.elements.isEmpty) return Duration.zero;
    return _workout.elements.first.when(
      segment: (seg) => seg.when(
        emom: (d) => d,
        amrap: (d) => d,
        forTime: (d) => d,
        rest: (d) => d,
      ),
      group: (g) {
        if (g.segments.isEmpty) return Duration.zero;
        return g.segments.first.when(
          emom: (d) => d,
          amrap: (d) => d,
          forTime: (d) => d,
          rest: (d) => d,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workoutTimerProvider(_workout));
    _elapsed = state.elapsed; // cache so dispose() can use it without ref
    final notifier = ref.read(workoutTimerProvider(_workout).notifier);

    // ── Subscribe to audio events ────────────────────────────────────────────
    ref.listen<AsyncValue<WorkoutAudioEvent>>(
      workoutAudioEventsProvider(_workout),
      (_, next) => next.whenData(_handleAudioEvent),
    );

    // Before start / after reset: show the first segment's duration so the
    // user knows what they're about to begin.
    final displayRemaining = state.currentSegment == null
        ? _firstSegmentDuration()
        : state.remaining;

    // ── Manage pulse animation ───────────────────────────────────────────────
    final remSec = state.remaining.inSeconds;
    final inCountdownZone =
        state.isRunning && !state.isPaused && remSec <= 10 && remSec > 0;
    if (inCountdownZone) {
      _startPulse();
    } else {
      _stopPulse();
    }

    // ── Derived display values ───────────────────────────────────────────────
    // Subtle tinted background per segment type; rest uses the plain scaffold bg.
    final bgColor = state.currentSegment == null
        ? AppColors.background
        : state.currentSegment!.when(
            emom: (_) => const Color(0xFF071E1A),
            amrap: (_) => const Color(0xFF1E1207),
            forTime: (_) => const Color(0xFF1E0707),
            rest: (_) => AppColors.background,
          );

    // Accent colour for the segment label and progress bar.
    final segmentColor = state.currentSegment == null
        ? Colors.white
        : state.currentSegment!.when(
            emom: (_) => AppColors.emom,
            amrap: (_) => AppColors.amrap,
            forTime: (_) => AppColors.forTime,
            rest: (_) => AppColors.gymRest,
          );

    final segmentLabel = state.currentSegment == null
        ? ''
        : state.currentSegment!.when(
            emom: (_) => 'EMOM',
            amrap: (_) => 'AMRAP',
            forTime: (_) => 'FOR TIME',
            rest: (_) => 'REST',
          );

    final roundText = state.groupProgress == null
        ? ''
        : 'Round ${state.groupProgress!.round} of '
            '${state.groupProgress!.totalRounds}';

    final progress = state.totalSegments == 0
        ? 0.0
        : (state.currentIndex +
                (state.remaining > Duration.zero ? 0 : 1)) /
            state.totalSegments;

    // Show visual 3-2-1 overlay during the last 3 seconds of a running segment.
    final showCountdownOverlay =
        state.isRunning && !state.isPaused && remSec >= 1 && remSec <= 3;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Workout Timer'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_workout.notes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.description_outlined),
              tooltip: 'View workout notes',
              onPressed: () => _showNotesSheet(_workout.notes),
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── Main layout ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Segment type label
                Text(
                  segmentLabel,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: segmentColor,
                  ),
                ),
                const SizedBox(height: 8),

                // Large countdown with pulse animation during last 10 s
                ScaleTransition(
                  scale: _pulseScale,
                  child: Text(
                    _format(displayRemaining),
                    style: AppTheme.timerStyle(
                      fontSize: 80,
                      // Shift towards danger red in last 10 seconds.
                      color: inCountdownZone ? AppColors.danger : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Round tracker (only shown for grouped segments)
                if (roundText.isNotEmpty)
                  Text(
                    roundText,
                    style: const TextStyle(fontSize: 18, color: Colors.white70),
                  ),

                const SizedBox(height: 24),

                // Overall workout progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(segmentColor),
                  ),
                ),
                const SizedBox(height: 32),

                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        if (state.isRunning) {
                          notifier.pause();
                        } else if (state.isPaused) {
                          notifier.resume();
                        } else {
                          _startedAt ??=
                              DateTime.now().millisecondsSinceEpoch;
                          notifier.start();
                        }
                      },
                      icon: Icon(state.isRunning
                          ? Icons.pause
                          : Icons.play_arrow),
                      label: Text(state.isRunning
                          ? 'Pause'
                          : state.isPaused
                              ? 'Resume'
                              : 'Start'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: notifier.reset,
                      icon: const Icon(Icons.replay),
                      label: const Text('Reset'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── 3-2-1 visual countdown overlay ────────────────────────────────
          if (showCountdownOverlay)
            Center(child: _CountdownNumber(seconds: remSec)),

          // ── Announcement overlay ("Go!", "Rest!", etc.) ────────────────────
          if (_announcement != null)
            IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _announcement!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Animated countdown number that zooms in — displayed during the last
/// 3 seconds of any segment.
class _CountdownNumber extends StatefulWidget {
  const _CountdownNumber({required this.seconds});
  final int seconds;

  @override
  State<_CountdownNumber> createState() => _CountdownNumberState();
}

class _CountdownNumberState extends State<_CountdownNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _scale = Tween<double>(begin: 2.0, end: 1.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void didUpdateWidget(_CountdownNumber old) {
    super.didUpdateWidget(old);
    if (old.seconds != widget.seconds) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Text(
            '${widget.seconds}',
            style: const TextStyle(
              fontSize: 120,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [Shadow(blurRadius: 12, color: Colors.black54)],
            ),
          ),
        ),
      ),
    );
  }
}
