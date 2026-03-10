import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/theme/app_theme.dart';

import '../../data/models/outdoor_history_models.dart';
import '../../data/models/outdoor_models.dart';
import '../../data/repositories/outdoor_history_repository.dart';
import '../../data/repositories/outdoor_preset_repository.dart';

const _uuid = Uuid();

// ─── Screen ───────────────────────────────────────────────────────────────────

class OutdoorHomeScreen extends ConsumerStatefulWidget {
  const OutdoorHomeScreen({super.key});

  @override
  ConsumerState<OutdoorHomeScreen> createState() => _OutdoorHomeScreenState();
}

class _OutdoorHomeScreenState extends ConsumerState<OutdoorHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outdoor Training'),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/hr-connect'),
            icon: const Icon(Icons.bluetooth),
            label: const Text('HR Monitor'),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.directions_run_outlined), text: 'My Workouts'),
            Tab(icon: Icon(Icons.history_outlined), text: 'History'),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tabs.index,
        children: const [
          _WorkoutsTab(),
          _HistoryTab(),
        ],
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/outdoor-editor'),
              icon: const Icon(Icons.add),
              label: const Text('New Workout'),
            )
          : null,
    );
  }
}

// ─── My Workouts tab ──────────────────────────────────────────────────────────

class _WorkoutsTab extends ConsumerWidget {
  const _WorkoutsTab();

  // ── Built-in workout definitions ─────────────────────────────────────────

  static OutdoorWorkout _norwegian4x4() => const OutdoorWorkout(
        elements: [
          OutdoorElement.segment(OutdoorSegment.distance(
            metres: 2000,
            tag: OutdoorSegmentTag.warmUp(),
            name: 'Warm-up jog',
          )),
          OutdoorElement.group(OutdoorGroup(
            repeats: 4,
            segments: [
              OutdoorSegment.timed(
                seconds: 240, // 4 min
                tag: OutdoorSegmentTag.work(),
                name: 'Hard effort',
              ),
              OutdoorSegment.timed(
                seconds: 180, // 3 min
                tag: OutdoorSegmentTag.rest(),
                name: 'Active recovery',
              ),
            ],
          )),
          OutdoorElement.segment(OutdoorSegment.distance(
            metres: 2000,
            tag: OutdoorSegmentTag.coolDown(),
            name: 'Cool-down',
          )),
        ],
      );

  static OutdoorWorkout _classicIntervals() => const OutdoorWorkout(
        elements: [
          OutdoorElement.segment(OutdoorSegment.distance(
            metres: 1000,
            tag: OutdoorSegmentTag.warmUp(),
            name: 'Warm-up jog',
          )),
          OutdoorElement.group(OutdoorGroup(
            repeats: 8,
            segments: [
              OutdoorSegment.timed(
                seconds: 60, // 1 min
                tag: OutdoorSegmentTag.work(),
                name: 'Sprint',
              ),
              OutdoorSegment.timed(
                seconds: 60, // 1 min
                tag: OutdoorSegmentTag.rest(),
                name: 'Jog recovery',
              ),
            ],
          )),
          OutdoorElement.segment(OutdoorSegment.distance(
            metres: 1000,
            tag: OutdoorSegmentTag.coolDown(),
            name: 'Cool-down',
          )),
        ],
      );

  static OutdoorWorkout _tempoRun() => const OutdoorWorkout(
        elements: [
          OutdoorElement.segment(OutdoorSegment.distance(
            metres: 2000,
            tag: OutdoorSegmentTag.warmUp(),
            name: 'Easy warm-up',
          )),
          OutdoorElement.segment(OutdoorSegment.timed(
            seconds: 1200, // 20 min
            tag: OutdoorSegmentTag.work(),
            name: 'Tempo effort',
          )),
          OutdoorElement.segment(OutdoorSegment.distance(
            metres: 2000,
            tag: OutdoorSegmentTag.coolDown(),
            name: 'Easy cool-down',
          )),
        ],
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presetsAsync = ref.watch(outdoorPresetsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── User saved presets ───────────────────────────────────────────────
        presetsAsync.when(
          data: (presets) => presets.isEmpty
              ? const SizedBox.shrink()
              : _PresetsSection(presets: presets),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Could not load workouts. Please restart the app.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),

        // ── Built-in workouts ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Built-in',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        _WorkoutCard(
          name: 'Norwegian 4×4',
          description:
              '2 km easy warm-up, then 4 rounds of 4 min hard effort + '
              '3 min active recovery, finishing with a 2 km cool-down.',
          tagSummary: const [
            (label: 'Warm-up', color: AppColors.warmUp),
            (label: '4× Work', color: AppColors.work),
            (label: '4× Rest', color: AppColors.rest),
            (label: 'Cool-down', color: AppColors.coolDown),
          ],
          totalTime: '~28 min intervals · ~4 km distance',
          onStart: () => context.push(
            '/outdoor-timer',
            extra: (workout: _norwegian4x4(), name: 'Norwegian 4×4'),
          ),
        ),
        const SizedBox(height: 8),
        _WorkoutCard(
          name: 'Classic Intervals',
          description:
              '1 km warm-up, then 8 rounds of 1 min sprint + 1 min jog '
              'recovery, finishing with a 1 km cool-down.',
          tagSummary: const [
            (label: 'Warm-up', color: AppColors.warmUp),
            (label: '8× Sprint', color: AppColors.work),
            (label: '8× Jog', color: AppColors.rest),
            (label: 'Cool-down', color: AppColors.coolDown),
          ],
          totalTime: '~16 min intervals · ~2 km distance',
          onStart: () => context.push(
            '/outdoor-timer',
            extra: (workout: _classicIntervals(), name: 'Classic Intervals'),
          ),
        ),
        const SizedBox(height: 8),
        _WorkoutCard(
          name: 'Tempo Run',
          description:
              '2 km easy warm-up, 20 min at comfortably hard tempo pace, '
              'then 2 km easy cool-down.',
          tagSummary: const [
            (label: 'Warm-up', color: AppColors.warmUp),
            (label: '20 min Tempo', color: AppColors.work),
            (label: 'Cool-down', color: AppColors.coolDown),
          ],
          totalTime: '20 min tempo · ~4+ km distance',
          onStart: () => context.push(
            '/outdoor-timer',
            extra: (workout: _tempoRun(), name: 'Tempo Run'),
          ),
        ),
      ],
    );
  }
}

// ─── History tab ──────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(outdoorHistoryProvider);

    return historyAsync.when(
      data: (entries) => entries.isEmpty
          ? const _EmptyHistoryState()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              itemBuilder: (_, i) => _OutdoorHistoryCard(entry: entries[i]),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
        child: Text(
          'Could not load history.\nPlease restart the app.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history,
            size: 72,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No outdoor history yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete an outdoor workout to see it here',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Outdoor history card ─────────────────────────────────────────────────────

class _OutdoorHistoryCard extends StatelessWidget {
  const _OutdoorHistoryCard({required this.entry});
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

  static String _formatTime(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final rawHour = dt.hour;
    final h = rawHour == 0 ? 12 : (rawHour > 12 ? rawHour - 12 : rawHour);
    final m = dt.minute.toString().padLeft(2, '0');
    final period = rawHour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }

  static String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h}h $m:$s' : '$m:$s';
  }

  static String _formatDistance(double metres) {
    if (metres >= 1000) return '${(metres / 1000).toStringAsFixed(2)} km';
    return '${metres.round()} m';
  }

  static String _formatPace(int durationSeconds, double distanceMetres) {
    if (distanceMetres < 10) return '--:--';
    final paceMinPerKm = durationSeconds / (distanceMetres / 1000) / 60;
    final mins = paceMinPerKm.floor();
    final secs = ((paceMinPerKm - mins) * 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')} /km';
  }

  static Color _tagColor(String tagLabel) => switch (tagLabel) {
        'Warm-up' => AppColors.warmUp,
        'Work' => AppColors.work,
        'Rest' => AppColors.rest,
        'Cool-down' => AppColors.coolDown,
        _ => AppColors.custom,
      };

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            // Title
            Text(
              _displayName,
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatDate(entry.startedAt)} · ${_formatTime(entry.startedAt)}',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),

            // Summary row
            _SummaryRow(
              duration: _formatDuration(entry.durationSeconds),
              distance: _formatDistance(entry.totalDistanceMetres),
              avgBpm: entry.avgBpm,
            ),

            const SizedBox(height: 24),
            if (entry.segments.isNotEmpty) ...[
              Text(
                'Segments',
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              ...entry.segments.map(
                (seg) => _SegmentDetailRow(
                  segment: seg,
                  tagColor: _tagColor(seg.tagLabel),
                  formatDuration: _formatDuration,
                  formatDistance: _formatDistance,
                  formatPace: _formatPace,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatDate(entry.startedAt)} · ${_formatTime(entry.startedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatDuration(entry.durationSeconds),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDistance(entry.totalDistanceMetres),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── History detail widgets ───────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.duration,
    required this.distance,
    required this.avgBpm,
  });

  final String duration;
  final String distance;
  final int? avgBpm;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SummaryCell(icon: Icons.timer_outlined, value: duration, label: 'Time'),
        const SizedBox(width: 24),
        _SummaryCell(
            icon: Icons.straighten_outlined,
            value: distance,
            label: 'Distance'),
        if (avgBpm != null) ...[
          const SizedBox(width: 24),
          _SummaryCell(
              icon: Icons.favorite_outline,
              value: '$avgBpm',
              label: 'Avg BPM'),
        ],
      ],
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _SegmentDetailRow extends StatelessWidget {
  const _SegmentDetailRow({
    required this.segment,
    required this.tagColor,
    required this.formatDuration,
    required this.formatDistance,
    required this.formatPace,
  });

  final OutdoorSegmentHistoryEntry segment;
  final Color tagColor;
  final String Function(int) formatDuration;
  final String Function(double) formatDistance;
  final String Function(int, double) formatPace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDist = segment.distanceMetres >= 10;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tag colour strip
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: tagColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: tagColor.withAlpha(100)),
                      ),
                      child: Text(
                        segment.tagLabel,
                        style: TextStyle(
                          color: tagColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (segment.name.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          segment.name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  children: [
                    Text(
                      formatDuration(segment.durationSeconds),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (hasDist)
                      Text(
                        formatDistance(segment.distanceMetres),
                        style: theme.textTheme.bodySmall,
                      ),
                    if (hasDist)
                      Text(
                        formatPace(
                            segment.durationSeconds, segment.distanceMetres),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (segment.avgBpm != null)
                      Text(
                        '♥ ${segment.avgBpm} BPM',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.pinkAccent,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── User preset card ─────────────────────────────────────────────────────────

class _PresetsSection extends StatelessWidget {
  const _PresetsSection({required this.presets});
  final List<OutdoorWorkoutPreset> presets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'My Workouts',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        ...presets.map((p) => _OutdoorPresetCard(preset: p)),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _OutdoorPresetCard extends ConsumerWidget {
  const _OutdoorPresetCard({required this.preset});
  final OutdoorWorkoutPreset preset;

  String get _displayName =>
      preset.name.trim().isEmpty ? 'Untitled Workout' : preset.name;

  static String _segmentSummary(OutdoorWorkout workout) {
    final labels = <String>[];
    for (final el in workout.elements) {
      el.when(
        segment: (seg) => labels.add(seg.displayValue),
        group: (g) => labels.add('${g.repeats}× group'),
      );
      if (labels.length >= 4) break;
    }
    final remaining = workout.elements.length - labels.length;
    if (remaining > 0) labels.add('+$remaining more');
    return labels.join(' · ');
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                _displayName,
                style: Theme.of(ctx).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.play_arrow_outlined),
              title: const Text('Start workout'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/outdoor-timer',
                    extra: (workout: preset.workout, name: preset.name));
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/outdoor-editor', extra: preset);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Duplicate'),
              onTap: () {
                Navigator.of(ctx).pop();
                _duplicate(context, ref);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDelete(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
    final copy = preset.copyWith(
      id: _uuid.v4(),
      name: '$_displayName (copy)',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await ref.read(outdoorPresetsProvider.notifier).save(copy);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not duplicate workout. Try again.')),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete workout?'),
        content: Text('Delete "$_displayName"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(outdoorPresetsProvider.notifier).delete(preset.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = _segmentSummary(preset.workout);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => _showOptions(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.directions_run, size: 20, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (summary.isNotEmpty)
                      Text(
                        summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Start',
                onPressed: () => context.push('/outdoor-timer',
                    extra: (workout: preset.workout, name: preset.name)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Built-in workout card ────────────────────────────────────────────────────

typedef _TagSummary = ({String label, Color color});

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({
    required this.name,
    required this.description,
    required this.tagSummary,
    required this.totalTime,
    required this.onStart,
  });

  final String name;
  final String description;
  final List<_TagSummary> tagSummary;
  final String totalTime;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name + icon
            Row(
              children: [
                const Icon(Icons.directions_run, size: 22),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Segment tag chips
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: tagSummary
                  .map((t) => _TagChip(label: t.label, color: t.color))
                  .toList(),
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              totalTime,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),

            // Start button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Workout'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
