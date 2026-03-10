import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../data/models/outdoor_history_models.dart';
import '../../data/repositories/outdoor_history_repository.dart';

// ─── Shared formatters ────────────────────────────────────────────────────────

String _fmtDuration(int seconds) {
  final d = Duration(seconds: seconds);
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '${h}h $m:$s' : '$m:$s';
}

String _fmtDistance(double metres) {
  if (metres >= 1000) return '${(metres / 1000).toStringAsFixed(2)} km';
  return '${metres.round()} m';
}

// Returns "5:30" without suffix — for compact use.
String _fmtPaceCompact(int durationSeconds, double distanceMetres) {
  if (distanceMetres < 10) return '--:--';
  final paceMinPerKm = durationSeconds / (distanceMetres / 1000) / 60;
  final mins = paceMinPerKm.floor();
  final secs = ((paceMinPerKm - mins) * 60).round();
  return '$mins:${secs.toString().padLeft(2, '0')}';
}

// Returns "5:30 /km".
String _fmtPace(int durationSeconds, double distanceMetres) {
  if (distanceMetres < 10) return '--:-- /km';
  return '${_fmtPaceCompact(durationSeconds, distanceMetres)} /km';
}

// Fractional minutes/km for numeric comparison; null when distance < 10 m.
double? _paceValue(int durationSeconds, double distanceMetres) {
  if (distanceMetres < 10 || durationSeconds == 0) return null;
  return durationSeconds / (distanceMetres / 1000) / 60;
}

Color _tagLabelColor(String tagLabel) => switch (tagLabel) {
      'Warm-up' => AppColors.warmUp,
      'Work' => AppColors.work,
      'Rest' => AppColors.rest,
      'Cool-down' => AppColors.coolDown,
      _ => AppColors.custom,
    };

// ─── Screen ───────────────────────────────────────────────────────────────────

class OutdoorResultsScreen extends ConsumerWidget {
  const OutdoorResultsScreen({required this.entry, super.key});

  final OutdoorWorkoutHistoryEntry entry;

  String get _displayName =>
      entry.workoutName.trim().isEmpty ? 'Outdoor Workout' : entry.workoutName;

  static String _formatDate(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _buildShareText() {
    final buf = StringBuffer();
    buf.writeln('$_displayName — ${_formatDate(entry.startedAt)}');
    buf.write(
        'Total: ${_fmtDistance(entry.totalDistanceMetres)} in ${_fmtDuration(entry.durationSeconds)}');
    buf.write(
        ' · Pace: ${_fmtPace(entry.durationSeconds, entry.totalDistanceMetres)}');
    if (entry.avgBpm != null) buf.write(' · Avg HR: ${entry.avgBpm} bpm');
    buf.writeln();

    final workSegs =
        entry.segments.where((s) => s.tagLabel == 'Work').toList();
    if (workSegs.isNotEmpty) {
      buf.writeln();
      for (var i = 0; i < workSegs.length; i++) {
        final s = workSegs[i];
        buf.write(
            'Interval ${i + 1}: ${_fmtDistance(s.distanceMetres)} @ ${_fmtPaceCompact(s.durationSeconds, s.distanceMetres)} /km');
        if (s.avgBpm != null) buf.write(' | HR avg ${s.avgBpm} bpm');
        buf.writeln();
      }
    }
    return buf.toString().trimRight();
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    await ref.read(outdoorHistoryRepositoryProvider).save(entry);
    if (context.mounted) context.go('/outdoor');
  }

  void _discard(BuildContext context) => context.go('/outdoor');

  void _share(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _buildShareText()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Summary copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workSegs =
        entry.segments.where((s) => s.tagLabel == 'Work').toList();
    final hasIntervalComparison = workSegs.length >= 2;

    return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
          title: const Text(
            'Workout Complete',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            TextButton(
              onPressed: () => _discard(context),
              child: const Text('Discard',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Workout name + date
              Text(
                _displayName,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              Text(
                _formatDate(entry.startedAt),
                style: const TextStyle(fontSize: 14, color: Colors.white54),
              ),
              const SizedBox(height: 20),

              // Overview
              _OverviewCard(entry: entry),
              const SizedBox(height: 24),

              // Segment breakdown
              _sectionLabel('SEGMENT BREAKDOWN'),
              const SizedBox(height: 12),
              _SegmentBreakdown(segments: entry.segments),

              // Interval comparison
              if (hasIntervalComparison) ...[
                const SizedBox(height: 24),
                _sectionLabel('INTERVAL COMPARISON'),
                const SizedBox(height: 12),
                _IntervalComparisonCard(workSegments: workSegs),
              ],

              const SizedBox(height: 16),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _share(context),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _save(context, ref),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save to History'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  static Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white38,
          letterSpacing: 1.2,
        ),
      );
}

// ─── Overview card ────────────────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.entry});

  final OutdoorWorkoutHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Big headline pair: time | distance
          Row(
            children: [
              Expanded(
                child: _BigStat(
                  label: 'TOTAL TIME',
                  value: _fmtDuration(entry.durationSeconds),
                ),
              ),
              Container(width: 1, height: 64, color: Colors.white12),
              Expanded(
                child: _BigStat(
                  label: 'DISTANCE',
                  value: _fmtDistance(entry.totalDistanceMetres),
                  align: TextAlign.center,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 16),

          // Secondary row: pace · avg HR · max HR
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SmallStat(
                icon: Icons.speed_outlined,
                label: 'AVG PACE',
                value:
                    _fmtPace(entry.durationSeconds, entry.totalDistanceMetres),
              ),
              if (entry.avgBpm != null)
                _SmallStat(
                  icon: Icons.favorite_outline,
                  label: 'AVG HR',
                  value: '${entry.avgBpm} bpm',
                  color: Colors.pinkAccent,
                ),
              if (entry.maxBpm != null)
                _SmallStat(
                  icon: Icons.favorite,
                  label: 'MAX HR',
                  value: '${entry.maxBpm} bpm',
                  color: Colors.redAccent,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.label,
    required this.value,
    this.align = TextAlign.left,
  });

  final String label;
  final String value;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: align == TextAlign.left
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white38,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w300,
              color: Colors.white,
              letterSpacing: -1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({
    required this.icon,
    required this.label,
    required this.value,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color.withAlpha(180)),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
              fontSize: 10, color: Colors.white38, letterSpacing: 1.0),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}

// ─── Segment breakdown ────────────────────────────────────────────────────────

class _SegmentBreakdown extends StatelessWidget {
  const _SegmentBreakdown({required this.segments});

  final List<OutdoorSegmentHistoryEntry> segments;

  // Returns "Work 1", "Work 2", "Warm-up" (no ordinal for singles).
  String _segmentTitle(int i) {
    final tag = segments[i].tagLabel;
    final totalForTag = segments.where((s) => s.tagLabel == tag).length;
    if (totalForTag == 1) return tag;
    var ordinal = 0;
    for (var j = 0; j <= i; j++) {
      if (segments[j].tagLabel == tag) ordinal++;
    }
    return '$tag $ordinal';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < segments.length; i++)
          _SegmentRow(
            number: i + 1,
            title: _segmentTitle(i),
            segment: segments[i],
          ),
      ],
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.number,
    required this.title,
    required this.segment,
  });

  final int number;
  final String title;
  final OutdoorSegmentHistoryEntry segment;

  @override
  Widget build(BuildContext context) {
    final color = _tagLabelColor(segment.tagLabel);
    final hasDist = segment.distanceMetres >= 10;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tag colour strip
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Number + tag chip + segment name
                    Row(
                      children: [
                        Text(
                          '$number.',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: color.withAlpha(80)),
                          ),
                          child: Text(
                            title,
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (segment.name.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              segment.name,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Stats pills
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        _StatPill(
                          icon: Icons.timer_outlined,
                          value: _fmtDuration(segment.durationSeconds),
                        ),
                        if (hasDist)
                          _StatPill(
                            icon: Icons.straighten_outlined,
                            value: _fmtDistance(segment.distanceMetres),
                          ),
                        if (hasDist)
                          _StatPill(
                            icon: Icons.speed_outlined,
                            value: _fmtPace(
                                segment.durationSeconds, segment.distanceMetres),
                          ),
                        if (segment.avgBpm != null)
                          _StatPill(
                            icon: Icons.favorite_outline,
                            value: 'avg ${segment.avgBpm} bpm',
                            color: Colors.pinkAccent,
                          ),
                        if (segment.maxBpm != null)
                          _StatPill(
                            icon: Icons.favorite,
                            value: 'max ${segment.maxBpm} bpm',
                            color: Colors.redAccent,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.value,
    this.color = Colors.white70,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color.withAlpha(160)),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }
}

// ─── Interval comparison ──────────────────────────────────────────────────────

class _IntervalComparisonCard extends StatelessWidget {
  const _IntervalComparisonCard({required this.workSegments});

  final List<OutdoorSegmentHistoryEntry> workSegments;

  static const _hStyle = TextStyle(
    fontSize: 10,
    color: Colors.white38,
    letterSpacing: 1.1,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          // Column headers
          const Row(
            children: [
              SizedBox(width: 88),
              Expanded(child: Text('DIST', style: _hStyle)),
              Expanded(child: Text('PACE', style: _hStyle)),
              Expanded(child: Text('AVG HR', style: _hStyle)),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12, height: 1),
          // Data rows
          for (var i = 0; i < workSegments.length; i++)
            _IntervalRow(
              index: i,
              segment: workSegments[i],
              prevSegment: i > 0 ? workSegments[i - 1] : null,
            ),
        ],
      ),
    );
  }
}

class _IntervalRow extends StatelessWidget {
  const _IntervalRow({
    required this.index,
    required this.segment,
    required this.prevSegment,
  });

  final int index;
  final OutdoorSegmentHistoryEntry segment;
  final OutdoorSegmentHistoryEntry? prevSegment;

  // null = first interval (no comparison), true = slower, false = faster.
  bool? get _isSlower {
    if (prevSegment == null) return null;
    final curr =
        _paceValue(segment.durationSeconds, segment.distanceMetres);
    final prev =
        _paceValue(prevSegment!.durationSeconds, prevSegment!.distanceMetres);
    if (curr == null || prev == null) return null;
    if (curr > prev + 0.1) return true;
    if (curr < prev - 0.1) return false;
    return null; // negligible difference
  }

  @override
  Widget build(BuildContext context) {
    final hasDist = segment.distanceMetres >= 10;
    final pace = hasDist
        ? _fmtPaceCompact(segment.durationSeconds, segment.distanceMetres)
        : '--:--';
    final slower = _isSlower;
    final paceColor = slower == null
        ? Colors.white
        : (slower ? Colors.orange : Colors.greenAccent);
    final arrow = slower == null ? '' : (slower ? ' ↓' : ' ↑');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              'Interval ${index + 1}',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              hasDist ? _fmtDistance(segment.distanceMetres) : '--',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              '$pace /km$arrow',
              style: TextStyle(
                  color: paceColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              segment.avgBpm != null ? '${segment.avgBpm} bpm' : '--',
              style: const TextStyle(color: Colors.pinkAccent, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
