import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../core/outdoor_audio_service.dart';
import '../../core/outdoor_workout_engine.dart';
import '../../data/models/outdoor_history_models.dart';
import '../../data/models/outdoor_models.dart';

const _uuid = Uuid();

class OutdoorTimerScreen extends ConsumerStatefulWidget {
  const OutdoorTimerScreen({
    required this.workout,
    this.workoutName = '',
    super.key,
  });

  final OutdoorWorkout workout;

  /// Name shown in history. Empty string for ad-hoc sessions.
  final String workoutName;

  @override
  ConsumerState<OutdoorTimerScreen> createState() => _OutdoorTimerScreenState();
}

class _OutdoorTimerScreenState extends ConsumerState<OutdoorTimerScreen> {
  late final OutdoorWorkoutEngine _engine;
  late final OutdoorAudioService _audio;
  StreamSubscription<OutdoorWorkoutState>? _stateSub;
  StreamSubscription<OutdoorAnnouncement>? _announcementSub;
  OutdoorWorkoutState _state = OutdoorWorkoutState.initial;
  String? _error;

  // ── History tracking ────────────────────────────────────────────────────────

  final List<OutdoorSegmentHistoryEntry> _completedSegments = [];
  bool _historySaved = false;
  late final int _startedAt;

  // Running max BPM — reset per segment and tracked overall.
  int? _segmentMaxBpm;
  int? _overallMaxBpm;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().ignore();
    _startedAt = DateTime.now().millisecondsSinceEpoch;
    _engine = ref.read(outdoorWorkoutEngineProvider);
    _audio = ref.read(outdoorAudioServiceProvider);

    _stateSub = _engine.stateStream.listen((s) {
      if (mounted) {
        // Track per-segment and overall max BPM.
        if (s.currentBpm != null) {
          final bpm = s.currentBpm!;
          if (_segmentMaxBpm == null || bpm > _segmentMaxBpm!) {
            _segmentMaxBpm = bpm;
          }
          if (_overallMaxBpm == null || bpm > _overallMaxBpm!) {
            _overallMaxBpm = bpm;
          }
        }
        // active → countdown: segment just completed — capture its stats.
        if (_state.phase == OutdoorWorkoutPhase.active &&
            s.phase == OutdoorWorkoutPhase.countdown) {
          _recordSegment(_state);
        }
        // Workout finished: navigate to results screen.
        if (s.phase == OutdoorWorkoutPhase.finished && !_historySaved) {
          _historySaved = true;
          final entry = _buildHistoryEntry(s);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.pushReplacement('/outdoor-results', extra: entry);
            }
          });
        }
        setState(() => _state = s);
      }
    });

    // Subscribe before starting so no announcements are missed.
    // handleAnnouncement is guarded by _initialized, so any that arrive
    // before init() completes are silently dropped.
    _announcementSub = _engine.announcementStream.listen(
      (a) => _audio.handleAnnouncement(a).ignore(),
    );

    _startWorkout();
  }

  Future<void> _startWorkout() async {
    try {
      // init() before start() so the first segment announcement is spoken.
      await _audio.init();
      await _engine.start(widget.workout);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _stop() async {
    await _engine.stop();
    if (mounted) context.pop();
  }

  Future<void> _confirmStop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Stop Workout?'),
        content: const Text('Your current progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Stop',
              style: TextStyle(color: Colors.red[300]),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await _stop();
  }

  // ── History helpers ─────────────────────────────────────────────────────────

  void _recordSegment(OutdoorWorkoutState state) {
    final seg = state.currentSegment;
    if (seg == null) return;
    _completedSegments.add(OutdoorSegmentHistoryEntry(
      tagLabel: seg.tag.displayLabel,
      name: seg.name,
      durationSeconds: state.segmentElapsed.inSeconds,
      distanceMetres: state.segmentDistanceMetres,
      avgBpm: state.segmentAvgBpm?.round(),
      maxBpm: _segmentMaxBpm,
    ));
    _segmentMaxBpm = null; // reset for the next segment
  }

  OutdoorWorkoutHistoryEntry _buildHistoryEntry(OutdoorWorkoutState finalState) {
    final bpms = _completedSegments
        .where((s) => s.avgBpm != null)
        .map((s) => s.avgBpm!)
        .toList();
    final overallAvgBpm = bpms.isEmpty
        ? null
        : (bpms.fold<int>(0, (sum, b) => sum + b) / bpms.length).round();

    return OutdoorWorkoutHistoryEntry(
      id: _uuid.v4(),
      workoutName: widget.workoutName,
      startedAt: _startedAt,
      durationSeconds: finalState.totalElapsed.inSeconds,
      totalDistanceMetres: finalState.totalDistanceMetres,
      segments: List.unmodifiable(_completedSegments),
      avgBpm: overallAvgBpm,
      maxBpm: _overallMaxBpm,
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable().ignore();
    _stateSub?.cancel();
    _announcementSub?.cancel();
    _engine.stop().ignore();
    _audio.dispose().ignore();
    super.dispose();
  }

  // ── Tag colour ─────────────────────────────────────────────────────────────

  static Color _tagColor(OutdoorSegmentTag tag) => tag.when(
        warmUp: () => AppColors.warmUp,
        work: () => AppColors.work,
        rest: () => AppColors.rest,
        coolDown: () => AppColors.coolDown,
        custom: (_) => AppColors.custom,
      );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(surface: Colors.black),
      ),
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmStop();
        },
        child: Scaffold(
          body: SafeArea(child: _buildBody()),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) return _buildError();

    return switch (_state.phase) {
      // Show spinner while the post-frame navigation to /outdoor-results fires.
      OutdoorWorkoutPhase.idle ||
      OutdoorWorkoutPhase.finished =>
        const Center(child: CircularProgressIndicator()),
      OutdoorWorkoutPhase.active ||
      OutdoorWorkoutPhase.countdown =>
        _buildActive(),
    };
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, size: 72, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              'GPS Unavailable',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Active / countdown ─────────────────────────────────────────────────────

  Widget _buildActive() {
    final state = _state;
    final tag = state.currentSegment?.tag ?? const OutdoorSegmentTag.work();
    final tagColor = _tagColor(tag);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(state: state, tagColor: tagColor, onStop: _confirmStop),
            if (state.isGpsLost)
              Container(
                color: Colors.orange.withValues(alpha: 0.15),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: const Row(
                  children: [
                    Icon(Icons.gps_off, size: 16, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'GPS signal lost — continuing on timer',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            _SegmentProgressBar(state: state, tagColor: tagColor),
            _SegmentMeta(state: state, tagColor: tagColor),
            Expanded(child: _HeroMetric(state: state, tagColor: tagColor)),
            _HrRow(state: state),
            const Divider(height: 1, color: Colors.white12),
            _StatsRow(state: state),
            _StopButton(onStop: _confirmStop),
          ],
        ),
        if (state.phase == OutdoorWorkoutPhase.countdown)
          _CountdownOverlay(value: state.countdownValue ?? 3),
      ],
    );
  }
}

// ─── Top bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.tagColor,
    required this.onStop,
  });

  final OutdoorWorkoutState state;
  final Color tagColor;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final tag = state.currentSegment?.tag;
    final tagLabel = tag?.displayLabel.toUpperCase() ?? '';
    final segName = state.currentSegment?.name ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
      child: Row(
        children: [
          // Tag chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: tagColor.withAlpha(38),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tagColor, width: 1.5),
            ),
            child: Text(
              tagLabel,
              style: TextStyle(
                color: tagColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (segName.isNotEmpty)
            Expanded(
              child: Text(
                segName,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          // Minimal stop icon — pressing pops a confirm dialog
          IconButton(
            onPressed: onStop,
            icon: const Icon(Icons.stop_circle_outlined),
            color: Colors.white30,
            iconSize: 26,
            tooltip: 'Stop workout',
          ),
        ],
      ),
    );
  }
}

// ─── Segment progress bar ─────────────────────────────────────────────────────

class _SegmentProgressBar extends StatelessWidget {
  const _SegmentProgressBar({required this.state, required this.tagColor});

  final OutdoorWorkoutState state;
  final Color tagColor;

  @override
  Widget build(BuildContext context) {
    final total = state.totalSegments;
    final progress = total == 0 ? 0.0 : (state.segmentIndex + 1) / total;
    return LinearProgressIndicator(
      value: progress,
      backgroundColor: Colors.white12,
      valueColor: AlwaysStoppedAnimation<Color>(tagColor),
      minHeight: 3,
    );
  }
}

// ─── Segment meta row ─────────────────────────────────────────────────────────

class _SegmentMeta extends StatelessWidget {
  const _SegmentMeta({required this.state, required this.tagColor});

  final OutdoorWorkoutState state;
  final Color tagColor;

  @override
  Widget build(BuildContext context) {
    final next = state.nextSegment;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Text(
            'Segment ${state.segmentIndex + 1} of ${state.totalSegments}',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          if (next != null) ...[
            const SizedBox(width: 8),
            const Text('·', style: TextStyle(color: Colors.white24)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 12, color: Colors.white38),
            const SizedBox(width: 4),
            Text(
              next.tag.displayLabel,
              style: TextStyle(
                color: _nextTagColor(next.tag).withAlpha(180),
                fontSize: 13,
              ),
            ),
            if (next.name.isNotEmpty) ...[
              Text(
                ' · ${next.name}',
                style: const TextStyle(color: Colors.white30, fontSize: 13),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static Color _nextTagColor(OutdoorSegmentTag tag) => tag.when(
        warmUp: () => Colors.amber,
        work: () => Colors.greenAccent,
        rest: () => Colors.lightBlueAccent,
        coolDown: () => Colors.purpleAccent,
        custom: (_) => Colors.tealAccent,
      );
}

// ─── Hero metric ──────────────────────────────────────────────────────────────

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.state, required this.tagColor});

  final OutdoorWorkoutState state;
  final Color tagColor;

  @override
  Widget build(BuildContext context) {
    final String heroValue;
    final String heroLabel;
    final String? secondaryValue;

    final seg = state.currentSegment;
    if (seg is OutdoorTimedSegment) {
      final rem = state.timeRemaining ?? Duration.zero;
      heroValue = _fmtDuration(rem);
      heroLabel = 'remaining';
      secondaryValue = null;
    } else if (seg is OutdoorDistanceSegment) {
      final rem = state.distanceRemainingMetres ?? 0;
      heroValue = _fmtMetres(rem);
      heroLabel = 'remaining';
      secondaryValue = '${_fmtMetres(state.segmentDistanceMetres)} covered';
    } else {
      heroValue = '--:--';
      heroLabel = '';
      secondaryValue = null;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            heroValue,
            style: TextStyle(
              color: tagColor,
              fontSize: 96,
              fontWeight: FontWeight.w200,
              letterSpacing: -2,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            heroLabel,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 14,
              letterSpacing: 2,
            ),
          ),
          if (secondaryValue != null) ...[
            const SizedBox(height: 10),
            Text(
              secondaryValue,
              style: const TextStyle(color: Colors.white54, fontSize: 18),
            ),
          ],
        ],
      ),
    );
  }

  static String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String _fmtMetres(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(2)} km';
    return '${m.round()} m';
  }
}

// ─── HR row ───────────────────────────────────────────────────────────────────

class _HrRow extends StatelessWidget {
  const _HrRow({required this.state});

  final OutdoorWorkoutState state;

  static Color _hrColor(int bpm) {
    if (bpm < 130) return Colors.grey;
    if (bpm < 150) return Colors.lightBlueAccent;
    if (bpm < 170) return Colors.greenAccent;
    if (bpm < 185) return Colors.orange;
    return Colors.redAccent;
  }

  static String _hrZoneLabel(int bpm) {
    if (bpm < 130) return 'Zone 1';
    if (bpm < 150) return 'Zone 2';
    if (bpm < 170) return 'Zone 3';
    if (bpm < 185) return 'Zone 4';
    return 'Zone 5';
  }

  @override
  Widget build(BuildContext context) {
    final bpm = state.currentBpm;
    final avgBpm = state.segmentAvgBpm;
    final color = bpm != null ? _hrColor(bpm) : Colors.white12;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          Icon(Icons.favorite, color: color, size: 22),
          const SizedBox(width: 8),
          Text(
            bpm != null ? '$bpm' : '--',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: bpm != null ? color : Colors.white24,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'BPM',
            style: TextStyle(
              fontSize: 13,
              color: bpm != null ? color.withAlpha(180) : Colors.white24,
            ),
          ),
          if (bpm != null) ...[
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withAlpha(38),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _hrZoneLabel(bpm),
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (avgBpm != null)
            Text(
              'avg ${avgBpm.round()} BPM',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

// ─── Stats row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.state});

  final OutdoorWorkoutState state;

  static String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String _fmtMetres(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(2)} km';
    return '${m.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StatCell(label: 'PACE', value: state.formattedPace),
          _StatCell(
              label: 'SEGMENT', value: _fmtMetres(state.segmentDistanceMetres)),
          _StatCell(
              label: 'TOTAL', value: _fmtMetres(state.totalDistanceMetres)),
          _StatCell(label: 'ELAPSED', value: _fmtDuration(state.totalElapsed)),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Stop button ──────────────────────────────────────────────────────────────

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onStop,
          icon: const Icon(Icons.stop),
          label: const Text('Stop Workout'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red[300],
            side: BorderSide(color: Colors.red[900]!, width: 1),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}

// ─── Countdown overlay ────────────────────────────────────────────────────────

class _CountdownOverlay extends StatelessWidget {
  const _CountdownOverlay({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(178),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: child,
          ),
          child: Text(
            '$value',
            key: ValueKey(value),
            style: const TextStyle(
              fontSize: 200,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
