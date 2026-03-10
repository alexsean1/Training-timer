import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/theme/app_theme.dart';

import '../../data/models/workout_history.dart';
import '../../data/models/workout_models.dart';
import '../../data/repositories/workout_history_repository.dart';
import '../../data/repositories/workout_preset_repository.dart';

const _uuid = Uuid();

// ─── Screen ───────────────────────────────────────────────────────────────────

class MyWorkoutsScreen extends ConsumerStatefulWidget {
  const MyWorkoutsScreen({super.key});

  @override
  ConsumerState<MyWorkoutsScreen> createState() => _MyWorkoutsScreenState();
}

class _MyWorkoutsScreenState extends ConsumerState<MyWorkoutsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Rebuild on tab change so the FAB shows/hides correctly.
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
        title: const Text('Training Timer'),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(
              icon: Icon(Icons.fitness_center_outlined),
              text: 'My Workouts',
            ),
            Tab(
              icon: Icon(Icons.history_outlined),
              text: 'History',
            ),
          ],
        ),
      ),
      // IndexedStack preserves scroll position when switching tabs.
      body: IndexedStack(
        index: _tabs.index,
        children: const [
          _PresetsTab(),
          _HistoryTab(),
        ],
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/editor'),
              icon: const Icon(Icons.add),
              label: const Text('New Workout'),
            )
          : null,
    );
  }
}

// ─── My Workouts tab ──────────────────────────────────────────────────────────

class _PresetsTab extends ConsumerWidget {
  const _PresetsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presetsAsync = ref.watch(workoutPresetsProvider);

    return presetsAsync.when(
      data: (presets) => presets.isEmpty
          ? const _EmptyPresetsState()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: presets.length,
              itemBuilder: (_, i) => _PresetCard(preset: presets[i]),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
        child: Text(
          'Could not load workouts.\nPlease restart the app.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ─── History tab ──────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(workoutHistoryProvider);

    return historyAsync.when(
      data: (entries) => entries.isEmpty
          ? const _EmptyHistoryState()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              itemBuilder: (_, i) => _HistoryCard(entry: entries[i]),
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

// ─── Empty states ─────────────────────────────────────────────────────────────

class _EmptyPresetsState extends StatelessWidget {
  const _EmptyPresetsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.fitness_center,
            size: 72,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No saved workouts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "New Workout" to build your first one',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
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
            'No workout history yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete a workout to see it here',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Preset card ──────────────────────────────────────────────────────────────

class _PresetCard extends ConsumerWidget {
  const _PresetCard({required this.preset});
  final WorkoutPreset preset;

  // ── Display helpers ──────────────────────────────────────────────────────

  String get _displayName =>
      preset.name.trim().isEmpty ? 'Untitled Workout' : preset.name;

  static Duration _totalDuration(Workout workout) {
    var total = Duration.zero;
    for (final element in workout.elements) {
      element.when(
        segment: (seg) {
          total += seg.when(
            emom: (d) => d,
            amrap: (d) => d,
            forTime: (d) => d,
            rest: (d) => d,
          );
        },
        group: (g) {
          final groupDur = g.segments.fold<Duration>(
            Duration.zero,
            (sum, seg) =>
                sum +
                seg.when(
                  emom: (d) => d,
                  amrap: (d) => d,
                  forTime: (d) => d,
                  rest: (d) => d,
                ),
          );
          total += groupDur * g.repeats;
        },
      );
    }
    return total;
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h}h $m:$s' : '$m:$s';
  }

  static String _segmentSummary(Workout workout) {
    final labels = <String>[];
    for (final el in workout.elements) {
      el.when(
        segment: (seg) => labels.add(seg.when(
          emom: (_) => 'EMOM',
          amrap: (_) => 'AMRAP',
          forTime: (_) => 'FOR TIME',
          rest: (_) => 'REST',
        )),
        group: (g) => labels.add('GROUP ×${g.repeats}'),
      );
      if (labels.length >= 4) break;
    }
    final remaining = workout.elements.length - labels.length;
    if (remaining > 0) labels.add('+$remaining more');
    return labels.join(' · ');
  }

  // ── Actions ──────────────────────────────────────────────────────────────

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
              title: const Text('Run workout'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/timer', extra: preset);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/editor', extra: preset);
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
                style:
                    TextStyle(color: Theme.of(ctx).colorScheme.error),
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
      await ref.read(workoutPresetsProvider.notifier).save(copy);
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
              ref.read(workoutPresetsProvider.notifier).delete(preset.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final total = _totalDuration(preset.workout);
    final summary = _segmentSummary(preset.workout);
    final notes = preset.workout.notes;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => _showOptions(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _displayName,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(total),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  notes,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── History card ─────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});
  final WorkoutHistoryEntry entry;

  String get _displayName =>
      entry.workoutName.trim().isEmpty ? 'Quick Workout' : entry.workoutName;

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

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayName,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              _DetailRow(
                icon: Icons.calendar_today_outlined,
                label: _formatDate(entry.startedAt),
              ),
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.schedule_outlined,
                label: _formatTime(entry.startedAt),
              ),
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.timer_outlined,
                label: _formatDuration(entry.durationSeconds),
              ),
              const SizedBox(height: 20),
              // Completion badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: entry.completed
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.warning.withValues(alpha: 0.12),
                  border: Border.all(
                    color: entry.completed
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  entry.completed ? 'Completed' : 'Stopped early',
                  style: TextStyle(
                    color: entry.completed
                        ? AppColors.success
                        : AppColors.warning,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
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
                  _StatusBadge(completed: entry.completed),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.completed});
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: completed
            ? AppColors.success.withValues(alpha: 0.15)
            : AppColors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        completed ? 'Done' : 'Stopped',
        style: TextStyle(
          color: completed ? AppColors.success : AppColors.warning,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
