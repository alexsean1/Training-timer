import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/outdoor_models.dart';
import 'gps_tracking_service.dart';
import 'heart_rate_service.dart';

// ─── Phase ────────────────────────────────────────────────────────────────────

enum OutdoorWorkoutPhase { idle, active, countdown, finished }

// ─── Announcements ────────────────────────────────────────────────────────────

sealed class OutdoorAnnouncement {
  const OutdoorAnnouncement();
}

/// Spoken at the start of a segment: "Go!", "Rest!", "Cool down!", etc.
class SegmentStartAnnouncement extends OutdoorAnnouncement {
  const SegmentStartAnnouncement(this.text);
  final String text;
}

/// One beat of the 3-2-1 countdown between segments.
class CountdownAnnouncement extends OutdoorAnnouncement {
  const CountdownAnnouncement(this.value);
  final int value; // 3, 2, or 1
}

/// Distance milestone inside a distance-based segment.
class DistanceAnnouncement extends OutdoorAnnouncement {
  const DistanceAnnouncement(this.text);
  final String text; // e.g. "3 kilometres remaining", "500 metres remaining"
}

/// Fires at the halfway point of a timed segment (segment ≥ 60 s).
class HalfwayAnnouncement extends OutdoorAnnouncement {
  const HalfwayAnnouncement();
}

/// Fires at meaningful time-remaining milestones (e.g. "One minute remaining").
class TimeRemainingAnnouncement extends OutdoorAnnouncement {
  const TimeRemainingAnnouncement(this.text);
  final String text;
}

/// Fires every kilometre of total distance with the current pace.
class PaceAnnouncement extends OutdoorAnnouncement {
  const PaceAnnouncement(this.text);
  final String text; // e.g. "Current pace: 5 minutes 30 seconds per kilometre"
}

// ─── State ────────────────────────────────────────────────────────────────────

@immutable
class OutdoorWorkoutState {
  const OutdoorWorkoutState({
    required this.phase,
    required this.segmentIndex,
    required this.totalSegments,
    required this.currentSegment,
    required this.totalElapsed,
    required this.segmentElapsed,
    required this.timeRemaining,
    required this.totalDistanceMetres,
    required this.segmentDistanceMetres,
    required this.distanceRemainingMetres,
    required this.paceMinPerKm,
    required this.currentBpm,
    required this.segmentAvgBpm,
    required this.countdownValue,
    this.nextSegment,
    this.isGpsLost = false,
  });

  final OutdoorWorkoutPhase phase;

  /// Zero-based index into the flattened segment list.
  final int segmentIndex;
  final int totalSegments;
  final OutdoorSegment? currentSegment;

  // ── Time ───────────────────────────────────────────────────────────────────
  final Duration totalElapsed;
  final Duration segmentElapsed;

  /// Only non-null for [OutdoorTimedSegment]s; counts down to zero.
  final Duration? timeRemaining;

  // ── Distance ───────────────────────────────────────────────────────────────
  final double totalDistanceMetres;
  final double segmentDistanceMetres;

  /// Only non-null for [OutdoorDistanceSegment]s; counts down to zero.
  final double? distanceRemainingMetres;

  // ── Metrics ────────────────────────────────────────────────────────────────
  /// Current pace in min/km; `null` when the user is stationary.
  final double? paceMinPerKm;
  final int? currentBpm;
  final double? segmentAvgBpm;

  // ── Transition countdown ───────────────────────────────────────────────────
  /// 3 → 2 → 1 during segment transitions; `null` when not in [OutdoorWorkoutPhase.countdown].
  final int? countdownValue;

  /// The segment that follows [currentSegment] in the flat list; `null` if
  /// [currentSegment] is the last segment.
  final OutdoorSegment? nextSegment;

  /// True when GPS tracking was lost mid-workout; the timer continues but
  /// distance-based segments will not auto-complete.
  final bool isGpsLost;

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get formattedPace {
    final p = paceMinPerKm;
    if (p == null) return '--:--';
    final mins = p.floor();
    final secs = ((p - mins) * 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  static const initial = OutdoorWorkoutState(
    phase: OutdoorWorkoutPhase.idle,
    segmentIndex: 0,
    totalSegments: 0,
    currentSegment: null,
    totalElapsed: Duration.zero,
    segmentElapsed: Duration.zero,
    timeRemaining: null,
    totalDistanceMetres: 0,
    segmentDistanceMetres: 0,
    distanceRemainingMetres: null,
    paceMinPerKm: null,
    currentBpm: null,
    segmentAvgBpm: null,
    countdownValue: null,
  );
}

// ─── Ticker abstraction (injectable for tests) ───────────────────────────────

typedef TickCallback = void Function();

abstract class EngineTicker {
  void start(Duration interval, TickCallback onTick);
  void stop();
}

class _RealTicker implements EngineTicker {
  Timer? _timer;

  @override
  void start(Duration interval, TickCallback onTick) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => onTick());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

// ─── Engine ───────────────────────────────────────────────────────────────────

/// Executes an [OutdoorWorkout] in order, integrating GPS distance tracking
/// and optional heart rate monitoring.
///
/// Inject [ticker] in tests to control time without real timers.
class OutdoorWorkoutEngine {
  OutdoorWorkoutEngine({
    required GeolocatorGpsTrackingService gpsService,
    HeartRateService? hrService,
    EngineTicker? ticker,
  })  : _gpsService = gpsService,
        _hrService = hrService,
        _ticker = ticker ?? _RealTicker();

  final GeolocatorGpsTrackingService _gpsService;
  final HeartRateService? _hrService;
  final EngineTicker _ticker;

  // ── Streams ────────────────────────────────────────────────────────────────

  final _stateCtrl = StreamController<OutdoorWorkoutState>.broadcast();
  final _announcementCtrl =
      StreamController<OutdoorAnnouncement>.broadcast();

  Stream<OutdoorWorkoutState> get stateStream => _stateCtrl.stream;
  Stream<OutdoorAnnouncement> get announcementStream =>
      _announcementCtrl.stream;

  // ── Mutable state ──────────────────────────────────────────────────────────

  OutdoorWorkoutState _state = OutdoorWorkoutState.initial;
  OutdoorWorkoutState get currentState => _state;

  List<OutdoorSegment> _segments = const [];

  // Per-tick / per-GPS accumulators
  Duration _totalElapsed = Duration.zero;
  Duration _segmentElapsed = Duration.zero;
  Duration? _timeRemaining;
  double _totalDistance = 0;
  double _segmentDistance = 0;
  double? _distanceRemaining;
  double? _currentSpeedMs;
  int? _currentBpm;
  final List<int> _segmentBpmSamples = [];

  // Countdown
  int _countdownValue = 0;

  // Distance milestone set for the current segment (remaining metres).
  final Set<int> _pendingAnnouncements = {};

  // Guard: prevents double-completion when both ticker and GPS fire together.
  bool _segmentCompleted = false;

  // Set to true when the GPS stream emits an error; cleared on stop/restart.
  bool _isGpsLost = false;

  // ── Per-segment time-announcement state ────────────────────────────────────

  /// Half-way point in seconds elapsed; null for distance segments or segments < 60 s.
  int? _halfwaySeconds;
  bool _halfwayAnnounced = false;
  bool _oneMinuteAnnounced = false;

  /// Total km count at the last pace announcement (0 = none yet).
  int _lastPaceKmAnnounced = 0;

  // Subscriptions
  StreamSubscription<GpsSnapshot>? _gpsSub;
  StreamSubscription<int>? _bpmSub;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Starts executing [workout].
  ///
  /// Throws [StateError] if GPS permission is denied.
  Future<void> start(OutdoorWorkout workout) async {
    _segments = _flatten(workout);
    if (_segments.isEmpty) return;

    final gpsStream = await _gpsService.startTracking();
    if (gpsStream == null) {
      throw StateError('GPS permission denied — cannot start outdoor workout');
    }

    _gpsSub = gpsStream.listen(_onGpsSnapshot, onError: _onGpsError);
    _bpmSub = _hrService?.bpmStream.listen(_onBpm);

    _isGpsLost = false;
    _totalElapsed = Duration.zero;
    _totalDistance = 0;
    _lastPaceKmAnnounced = 0;

    _ticker.start(const Duration(seconds: 1), _onTick);
    _startSegment(0);
  }

  /// Stops the workout and resets to [OutdoorWorkoutPhase.idle].
  Future<void> stop() async {
    _isGpsLost = false;
    _ticker.stop();
    await _gpsSub?.cancel();
    _gpsSub = null;
    await _bpmSub?.cancel();
    _bpmSub = null;
    await _gpsService.stopTracking();
    _emit(OutdoorWorkoutState.initial);
  }

  Future<void> dispose() async {
    await stop();
    await _stateCtrl.close();
    await _announcementCtrl.close();
  }

  // ── Segment lifecycle ──────────────────────────────────────────────────────

  void _startSegment(int index) {
    _segmentCompleted = false;
    _segmentElapsed = Duration.zero;
    _segmentBpmSamples.clear();
    _halfwayAnnounced = false;
    _oneMinuteAnnounced = false;
    _gpsService.resetSegmentDistance();

    final segment = _segments[index];
    _setupDistanceAnnouncements(segment);

    // Halfway fires at the midpoint of timed segments ≥ 60 s.
    _halfwaySeconds = segment is OutdoorTimedSegment && segment.seconds >= 60
        ? segment.seconds ~/ 2
        : null;

    _timeRemaining =
        segment is OutdoorTimedSegment ? Duration(seconds: segment.seconds) : null;
    _segmentDistance = 0;
    _distanceRemaining =
        segment is OutdoorDistanceSegment ? segment.metres.toDouble() : null;

    _emitActive(
      index: index,
      segment: segment,
      countdownValue: null,
    );

    _announce(SegmentStartAnnouncement(_segmentStartText(segment)));
  }

  void _startCountdown() {
    _countdownValue = 3;
    _emitCountdown();
    _announce(const CountdownAnnouncement(3));
  }

  void _advanceSegment() {
    final next = _state.segmentIndex + 1;
    if (next >= _segments.length) {
      _ticker.stop();
      _emit(_state.copyWithPhase(OutdoorWorkoutPhase.finished));
    } else {
      _startSegment(next);
    }
  }

  // ── Tick handler ───────────────────────────────────────────────────────────

  void _onTick() {
    _totalElapsed += const Duration(seconds: 1);

    if (_state.phase == OutdoorWorkoutPhase.countdown) {
      _countdownValue--;
      if (_countdownValue > 0) {
        _emitCountdown();
        _announce(CountdownAnnouncement(_countdownValue));
      } else {
        _emitCountdown();
        _advanceSegment();
      }
      return;
    }

    if (_state.phase != OutdoorWorkoutPhase.active) return;

    _segmentElapsed += const Duration(seconds: 1);

    if (_timeRemaining != null) {
      final next = _timeRemaining! - const Duration(seconds: 1);
      _timeRemaining = next.isNegative ? Duration.zero : next;
      if (_timeRemaining!.inSeconds == 0 && !_segmentCompleted) {
        _segmentCompleted = true;
        _emitActive(
          index: _state.segmentIndex,
          segment: _state.currentSegment!,
          countdownValue: null,
        );
        _startCountdown();
        return;
      }
    }

    // ── Time-based announcements ──────────────────────────────────────────────

    // Halfway: fires once at the midpoint of timed segments ≥ 60 s.
    final hs = _halfwaySeconds;
    if (hs != null && !_halfwayAnnounced && _segmentElapsed.inSeconds == hs) {
      _halfwayAnnounced = true;
      _announce(const HalfwayAnnouncement());
    }

    // One minute remaining: fires once for timed segments longer than 90 s.
    final tr = _timeRemaining;
    if (tr != null && !_oneMinuteAnnounced && tr.inSeconds == 60) {
      final seg = _state.currentSegment;
      if (seg is OutdoorTimedSegment && seg.seconds > 90) {
        _oneMinuteAnnounced = true;
        _announce(const TimeRemainingAnnouncement('One minute remaining'));
      }
    }

    _emitActive(
      index: _state.segmentIndex,
      segment: _state.currentSegment!,
      countdownValue: null,
    );
  }

  // ── GPS handler ────────────────────────────────────────────────────────────

  void _onGpsSnapshot(GpsSnapshot snapshot) {
    _currentSpeedMs = snapshot.speedMetresPerSecond;
    _totalDistance = snapshot.totalDistanceMetres;

    if (_state.phase != OutdoorWorkoutPhase.active) return;

    _segmentDistance = snapshot.segmentDistanceMetres;

    // ── Pace announcement every km of total distance ──────────────────────────
    final currentKm = (_totalDistance / 1000).floor();
    if (currentKm > _lastPaceKmAnnounced) {
      _lastPaceKmAnnounced = currentKm;
      final pace = _pace();
      if (pace != null) {
        final mins = pace.floor();
        final secs = ((pace - mins) * 60).round();
        final minWord = mins == 1 ? 'minute' : 'minutes';
        final paceText = secs == 0
            ? 'Current pace: $mins $minWord per kilometre'
            : 'Current pace: $mins $minWord $secs '
                '${secs == 1 ? 'second' : 'seconds'} per kilometre';
        _announce(PaceAnnouncement(paceText));
      }
    }

    final segment = _state.currentSegment;
    if (segment is OutdoorDistanceSegment) {
      final remaining = (segment.metres - _segmentDistance).clamp(0.0, double.infinity);
      _distanceRemaining = remaining;

      _checkDistanceAnnouncements(remaining.toDouble());

      if (remaining <= 50 && !_segmentCompleted) {
        _segmentCompleted = true;
        _distanceRemaining = 0;
        _emitActive(
          index: _state.segmentIndex,
          segment: segment,
          countdownValue: null,
        );
        _startCountdown();
        return;
      }
    }

    _emitActive(
      index: _state.segmentIndex,
      segment: segment!,
      countdownValue: null,
    );
  }

  // ── GPS error handler ──────────────────────────────────────────────────────

  void _onGpsError(Object _) {
    if (_isGpsLost) return;
    _isGpsLost = true;
    // Cancel the GPS subscription; the workout continues driven by _onTick.
    // Distance segments won't auto-complete, but timed segments proceed normally.
    _gpsSub?.cancel();
    _gpsSub = null;
    _gpsService.stopTracking().ignore();
    // Re-emit so observers see isGpsLost = true immediately.
    if (_state.phase == OutdoorWorkoutPhase.active) {
      _emitActive(
        index: _state.segmentIndex,
        segment: _state.currentSegment!,
        countdownValue: null,
      );
    }
  }

  // ── HR handler ─────────────────────────────────────────────────────────────

  void _onBpm(int bpm) {
    _currentBpm = bpm;
    _segmentBpmSamples.add(bpm);
    if (_state.phase == OutdoorWorkoutPhase.active) {
      _emitActive(
        index: _state.segmentIndex,
        segment: _state.currentSegment!,
        countdownValue: null,
      );
    }
  }

  // ── State emission helpers ─────────────────────────────────────────────────

  void _emitActive({
    required int index,
    required OutdoorSegment segment,
    required int? countdownValue,
  }) {
    _emit(OutdoorWorkoutState(
      phase: OutdoorWorkoutPhase.active,
      segmentIndex: index,
      totalSegments: _segments.length,
      currentSegment: segment,
      totalElapsed: _totalElapsed,
      segmentElapsed: _segmentElapsed,
      timeRemaining: _timeRemaining,
      totalDistanceMetres: _totalDistance,
      segmentDistanceMetres: _segmentDistance,
      distanceRemainingMetres: _distanceRemaining,
      paceMinPerKm: _pace(),
      currentBpm: _currentBpm,
      segmentAvgBpm: _avgBpm(),
      countdownValue: countdownValue,
      nextSegment: _nextSegmentAt(index),
      isGpsLost: _isGpsLost,
    ));
  }

  void _emitCountdown() {
    _emit(OutdoorWorkoutState(
      phase: OutdoorWorkoutPhase.countdown,
      segmentIndex: _state.segmentIndex,
      totalSegments: _segments.length,
      currentSegment: _state.currentSegment,
      totalElapsed: _totalElapsed,
      segmentElapsed: _segmentElapsed,
      timeRemaining: _state.timeRemaining,
      totalDistanceMetres: _totalDistance,
      segmentDistanceMetres: _segmentDistance,
      distanceRemainingMetres: _distanceRemaining,
      paceMinPerKm: _pace(),
      currentBpm: _currentBpm,
      segmentAvgBpm: _avgBpm(),
      countdownValue: _countdownValue,
      nextSegment: _nextSegmentAt(_state.segmentIndex),
      isGpsLost: _isGpsLost,
    ));
  }

  void _emit(OutdoorWorkoutState state) {
    _state = state;
    if (!_stateCtrl.isClosed) _stateCtrl.add(state);
  }

  void _announce(OutdoorAnnouncement a) {
    if (!_announcementCtrl.isClosed) _announcementCtrl.add(a);
  }

  // ── Distance announcements ─────────────────────────────────────────────────

  void _setupDistanceAnnouncements(OutdoorSegment segment) {
    _pendingAnnouncements.clear();
    if (segment is! OutdoorDistanceSegment) return;

    final target = segment.metres;
    for (int km = 1; km * 1000 < target; km++) {
      _pendingAnnouncements.add(km * 1000);
    }
    for (final m in [500, 200, 100]) {
      if (m < target) _pendingAnnouncements.add(m);
    }
  }

  void _checkDistanceAnnouncements(double remainingMetres) {
    final crossed = _pendingAnnouncements
        .where((t) => remainingMetres <= t)
        .toList()
      ..sort((a, b) => b.compareTo(a));

    for (final threshold in crossed) {
      _pendingAnnouncements.remove(threshold);
      final text = threshold >= 1000
          ? '${threshold ~/ 1000} ${threshold == 1000 ? 'kilometre' : 'kilometres'} remaining'
          : '$threshold metres remaining';
      _announce(DistanceAnnouncement(text));
    }
  }

  // ── Calculations ───────────────────────────────────────────────────────────

  double? _pace() {
    final s = _currentSpeedMs;
    if (s == null || s <= 0) return null;
    return 1000 / (s * 60);
  }

  double? _avgBpm() {
    if (_segmentBpmSamples.isEmpty) return null;
    return _segmentBpmSamples.fold<int>(0, (sum, b) => sum + b) /
        _segmentBpmSamples.length;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  OutdoorSegment? _nextSegmentAt(int currentIndex) {
    final ni = currentIndex + 1;
    return ni < _segments.length ? _segments[ni] : null;
  }

  static List<OutdoorSegment> _flatten(OutdoorWorkout workout) {
    final result = <OutdoorSegment>[];
    for (final element in workout.elements) {
      element.when(
        segment: result.add,
        group: (g) {
          for (int i = 0; i < g.repeats; i++) {
            result.addAll(g.segments);
          }
        },
      );
    }
    return result;
  }

  static String _segmentStartText(OutdoorSegment segment) =>
      segment.tag.when(
        warmUp: () => 'Warm up!',
        work: () => 'Run!',
        rest: () => 'Rest!',
        coolDown: () => 'Cool down!',
        custom: (label) => label,
      );
}

// ─── State helper ─────────────────────────────────────────────────────────────

extension _StateX on OutdoorWorkoutState {
  OutdoorWorkoutState copyWithPhase(OutdoorWorkoutPhase p) =>
      OutdoorWorkoutState(
        phase: p,
        segmentIndex: segmentIndex,
        totalSegments: totalSegments,
        currentSegment: currentSegment,
        totalElapsed: totalElapsed,
        segmentElapsed: segmentElapsed,
        timeRemaining: timeRemaining,
        totalDistanceMetres: totalDistanceMetres,
        segmentDistanceMetres: segmentDistanceMetres,
        distanceRemainingMetres: distanceRemainingMetres,
        paceMinPerKm: paceMinPerKm,
        currentBpm: currentBpm,
        segmentAvgBpm: segmentAvgBpm,
        countdownValue: null,
        nextSegment: nextSegment,
        isGpsLost: isGpsLost,
      );
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final outdoorWorkoutEngineProvider = Provider<OutdoorWorkoutEngine>((ref) {
  final gps = ref.watch(gpsTrackingServiceProvider);
  final hr = ref.watch(heartRateServiceProvider);
  final engine = OutdoorWorkoutEngine(gpsService: gps, hrService: hr);
  ref.onDispose(engine.dispose);
  return engine;
});
