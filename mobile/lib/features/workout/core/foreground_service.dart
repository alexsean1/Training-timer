import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../features/outdoor/core/outdoor_workout_engine.dart';
import '../../../features/outdoor/data/models/outdoor_models.dart';
import '../../workout/data/models/workout_models.dart';
import 'workout_timer.dart';

/// Top-level callback required by [flutter_foreground_task].
/// Must be a top-level function annotated with `@pragma('vm:entry-point')`.
/// The handler just keeps the foreground service alive — all timer and audio
/// logic continues to run in the main isolate.
@pragma('vm:entry-point')
void _foregroundTaskEntryPoint() {
  FlutterForegroundTask.setTaskHandler(_WorkoutTaskHandler());
}

class _WorkoutTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  /// Routes notification button presses to the main isolate so the timer
  /// screen can handle pause/resume/stop without being in the foreground.
  @override
  void onNotificationButtonPressed(String id) {
    FlutterForegroundTask.sendDataToMain({'action': id});
  }
}

/// Helper that starts / updates / stops the Android foreground service
/// (and the equivalent iOS background task) that keeps the process alive
/// while a workout is in progress.
abstract final class WorkoutForegroundService {
  static bool _initialized = false;

  /// Must be called once at app startup (before [startGym] / [startOutdoor]).
  static void init() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'training_timer_workout',
        channelName: 'Workout Timer',
        channelDescription:
            'Keeps the workout timer running when the screen is off.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: false,
        autoRunOnBoot: false,
      ),
    );
  }

  // ── Gym timer ──────────────────────────────────────────────────────────────

  /// Starts the foreground service with a gym-timer notification.
  /// Shows Pause/Resume + Stop action buttons.
  static Future<void> startGym({
    required String notificationText,
    required bool isPaused,
  }) async {
    await FlutterForegroundTask.startService(
      notificationTitle: 'Training Timer',
      notificationText: notificationText,
      callback: _foregroundTaskEntryPoint,
      notificationButtons: [
        NotificationButton(
            id: 'pause_resume', text: isPaused ? 'Resume' : 'Pause'),
        const NotificationButton(id: 'stop', text: 'Stop'),
      ],
    );
  }

  /// Updates the gym-timer notification text and button labels.
  static Future<void> updateGym({
    required String notificationText,
    required bool isPaused,
  }) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Training Timer',
      notificationText: notificationText,
      notificationButtons: [
        NotificationButton(
            id: 'pause_resume', text: isPaused ? 'Resume' : 'Pause'),
        const NotificationButton(id: 'stop', text: 'Stop'),
      ],
    );
  }

  // ── Outdoor timer ──────────────────────────────────────────────────────────

  /// Starts the foreground service with an outdoor-timer notification.
  /// Shows Pause/Resume + Stop action buttons.
  static Future<void> startOutdoor({
    required String notificationText,
    required bool isPaused,
  }) async {
    await FlutterForegroundTask.startService(
      notificationTitle: 'Outdoor Workout',
      notificationText: notificationText,
      callback: _foregroundTaskEntryPoint,
      notificationButtons: [
        NotificationButton(
            id: 'pause_resume', text: isPaused ? 'Resume' : 'Pause'),
        const NotificationButton(id: 'stop', text: 'Stop'),
      ],
    );
  }

  /// Updates the outdoor-timer notification text and button labels.
  static Future<void> updateOutdoor({
    required String notificationText,
    required bool isPaused,
  }) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Outdoor Workout',
      notificationText: notificationText,
      notificationButtons: [
        NotificationButton(
            id: 'pause_resume', text: isPaused ? 'Resume' : 'Pause'),
        const NotificationButton(id: 'stop', text: 'Stop'),
      ],
    );
  }

  // ── Shared ─────────────────────────────────────────────────────────────────

  /// Removes the notification and allows the OS to kill the process normally.
  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  // ── Notification text helpers ──────────────────────────────────────────────

  /// Formats a [WorkoutTimerState] into a compact notification line.
  /// e.g. "EMOM • 3:45 • Round 2/5" or "Paused — REST • 1:30"
  static String gymText(WorkoutTimerState s) {
    final label = s.currentSegment?.when(
          emom: (_) => 'EMOM',
          amrap: (_) => 'AMRAP',
          forTime: (_) => 'FOR TIME',
          rest: (_) => 'REST',
        ) ??
        'Workout';

    final mins = s.remaining.inMinutes;
    final secs =
        s.remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final time = '$mins:$secs';

    final gp = s.groupProgress;
    final round =
        gp != null ? ' • Round ${gp.round}/${gp.totalRounds}' : '';

    final prefix = s.isPaused ? 'Paused — ' : '';
    return '$prefix$label • $time$round';
  }

  /// Formats an [OutdoorWorkoutState] into a compact notification line.
  /// e.g. "Work • 3:45 remaining • 2.4 km" or "Work • 300 m to go"
  static String outdoorText(OutdoorWorkoutState s, {bool isPaused = false}) {
    final tag = s.currentSegment?.tag.displayLabel ?? 'Workout';

    final String timePart;
    if (s.timeRemaining != null) {
      final tr = s.timeRemaining!;
      final mins = tr.inMinutes;
      final secs = tr.inSeconds.remainder(60).toString().padLeft(2, '0');
      timePart = '$mins:$secs remaining';
    } else if (s.distanceRemainingMetres != null) {
      timePart = '${s.distanceRemainingMetres!.round()} m to go';
    } else {
      timePart = '';
    }

    final km = (s.totalDistanceMetres / 1000).toStringAsFixed(2);
    final distPart =
        s.totalDistanceMetres > 0 ? ' • ${km}km' : '';

    final pausedPrefix = isPaused ? 'Paused — ' : '';
    final sep = timePart.isNotEmpty ? ' • ' : '';
    return '$pausedPrefix$tag$sep$timePart$distPart';
  }
}
