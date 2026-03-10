import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../data/models/workout_models.dart';
import '../../data/repositories/workout_preset_repository.dart';

// ─── Internal editor data model ──────────────────────────────────────────────

sealed class _EditorItem {
  const _EditorItem();
}

class _SegmentItem extends _EditorItem {
  _SegmentItem(this.segment);
  WorkoutSegment segment;
}

class _GroupItem extends _EditorItem {
  _GroupItem({required this.segments, required this.repeats});
  List<WorkoutSegment> segments;
  int repeats;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

enum _SegmentType { emom, amrap, forTime, rest }

extension _SegmentTypeLabel on _SegmentType {
  String get label => switch (this) {
        _SegmentType.emom => 'EMOM',
        _SegmentType.amrap => 'AMRAP',
        _SegmentType.forTime => 'FOR TIME',
        _SegmentType.rest => 'REST',
      };

  Color get color => switch (this) {
        _SegmentType.emom => AppColors.emom,
        _SegmentType.amrap => AppColors.amrap,
        _SegmentType.forTime => AppColors.forTime,
        _SegmentType.rest => AppColors.gymRest,
      };

  String get helperText => switch (this) {
        _SegmentType.emom => 'Timer fires every 1 minute',
        _SegmentType.amrap => 'As many rounds as possible',
        _SegmentType.forTime => 'Time cap — counts down to zero',
        _SegmentType.rest => 'Rest period',
      };

  String get durationLabel => switch (this) {
        _SegmentType.forTime => 'Time Cap',
        _ => 'Duration',
      };
}

_SegmentType _typeOfSegment(WorkoutSegment seg) => seg.when(
      emom: (_) => _SegmentType.emom,
      amrap: (_) => _SegmentType.amrap,
      forTime: (_) => _SegmentType.forTime,
      rest: (_) => _SegmentType.rest,
    );

Duration _durationOfSegment(WorkoutSegment seg) => seg.when(
      emom: (d) => d,
      amrap: (d) => d,
      forTime: (d) => d,
      rest: (d) => d,
    );

String _formatDuration(Duration d) {
  final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$min:$sec';
}

WorkoutSegment _buildSegment(_SegmentType type, Duration duration) =>
    switch (type) {
      _SegmentType.emom => WorkoutSegment.emom(duration: duration),
      _SegmentType.amrap => WorkoutSegment.amrap(duration: duration),
      _SegmentType.forTime => WorkoutSegment.forTime(duration: duration),
      _SegmentType.rest => WorkoutSegment.rest(duration: duration),
    };

// ─── Screen ──────────────────────────────────────────────────────────────────

class WorkoutEditorScreen extends ConsumerStatefulWidget {
  const WorkoutEditorScreen({super.key, this.initialPreset});

  /// When non-null the editor pre-fills all fields from this preset.
  /// Saving will overwrite it (same ID) rather than create a new entry.
  final WorkoutPreset? initialPreset;

  @override
  ConsumerState<WorkoutEditorScreen> createState() =>
      _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends ConsumerState<WorkoutEditorScreen> {
  static const _uuid = Uuid();

  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  final List<_EditorItem> _items = [];
  final Set<int> _selectedIndices = {};
  bool _inSelectionMode = false;

  /// True when the editor content differs from the last save (or the initial
  /// empty state). Used to gate the unsaved-changes confirmation dialog.
  bool _isDirty = false;

  /// ID of the preset being edited, null until first save.
  String? _editingId;

  /// Epoch-ms timestamp preserved across saves so the card doesn't move.
  late final int _createdAt;

  @override
  void initState() {
    super.initState();
    final p = widget.initialPreset;
    _editingId = p?.id;
    _createdAt = p?.createdAt ?? DateTime.now().millisecondsSinceEpoch;
    _nameController = TextEditingController(text: p?.name ?? '');
    _notesController =
        TextEditingController(text: p?.workout.notes ?? '');
    if (p != null) _loadFromPreset(p);
    _nameController.addListener(_markDirty);
    _notesController.addListener(_markDirty);
  }

  void _loadFromPreset(WorkoutPreset preset) {
    for (final element in preset.workout.elements) {
      element.when(
        segment: (seg) => _items.add(_SegmentItem(seg)),
        group: (g) => _items.add(
          _GroupItem(segments: List.of(g.segments), repeats: g.repeats),
        ),
      );
    }
  }

  void _markDirty() {
    if (mounted && !_isDirty) setState(() => _isDirty = true);
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your unsaved changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Workout assembly ───────────────────────────────────────────────────────

  Workout _buildWorkout() {
    return Workout(
      elements: _items.map((item) => switch (item) {
            _SegmentItem(:final segment) => WorkoutElement.segment(segment),
            _GroupItem(:final segments, :final repeats) =>
              WorkoutElement.group(
                WorkoutGroup(segments: segments, repeats: repeats),
              ),
          }).toList(),
      notes: _notesController.text.trim(),
    );
  }

  void _startWorkout() {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one segment first')),
      );
      return;
    }
    final name = _nameController.text.trim();
    final id = _editingId ?? _uuid.v4();
    final preset = WorkoutPreset(
      id: id,
      name: name.isEmpty ? 'Quick Workout' : name,
      workout: _buildWorkout(),
      createdAt: _createdAt,
    );
    // pushReplacement removes the editor from the stack so back-navigation
    // from the timer returns to the home screen, not the editor.
    context.pushReplacement('/timer', extra: preset);
  }

  Future<void> _savePreset() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one segment to save')),
      );
      return;
    }
    final id = _editingId ?? _uuid.v4();
    _editingId ??= id;
    final name = _nameController.text.trim();
    final preset = WorkoutPreset(
      id: id,
      name: name.isEmpty ? 'Untitled Workout' : name,
      workout: _buildWorkout(),
      createdAt: _createdAt,
    );
    try {
      await ref.read(workoutPresetsProvider.notifier).save(preset);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preset saved')),
        );
        setState(() => _isDirty = false);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not save preset. Try again.')),
        );
      }
    }
  }

  // ── Item mutation ──────────────────────────────────────────────────────────

  void _deleteItem(int index) {
    setState(() {
      _isDirty = true;
      _items.removeAt(index);
      _exitSelectionMode();
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      _isDirty = true;
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
      _exitSelectionMode();
    });
  }

  void _ungroup(int index) {
    final group = _items[index] as _GroupItem;
    setState(() {
      _isDirty = true;
      _items.replaceRange(
        index,
        index + 1,
        group.segments.map(_SegmentItem.new),
      );
    });
  }

  // ── Selection / group mode ─────────────────────────────────────────────────

  void _enterSelectionMode(int index) {
    if (_items[index] is _GroupItem) return;
    setState(() {
      _inSelectionMode = true;
      _selectedIndices.add(index);
    });
  }

  void _toggleSelection(int index) {
    if (_items[index] is _GroupItem) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Groups can't be selected — ungroup first"),
        ),
      );
      return;
    }
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        if (_selectedIndices.isEmpty) _exitSelectionMode();
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _exitSelectionMode() {
    _inSelectionMode = false;
    _selectedIndices.clear();
  }

  /// True when the selection is ≥2 adjacent `_SegmentItem`s.
  bool get _canGroup {
    if (_selectedIndices.length < 2) return false;
    final sorted = _selectedIndices.toList()..sort();
    for (var i = 0; i < sorted.length - 1; i++) {
      if (sorted[i + 1] != sorted[i] + 1) return false;
    }
    return true;
  }

  void _groupSelected() {
    if (!_canGroup) return;
    final sorted = _selectedIndices.toList()..sort();
    final segments =
        sorted.map((i) => (_items[i] as _SegmentItem).segment).toList();

    _showRepeatCountDialog(
      initialRepeats: 3,
      onConfirm: (repeats) {
        setState(() {
          _isDirty = true;
          _items.replaceRange(
            sorted.first,
            sorted.last + 1,
            [_GroupItem(segments: segments, repeats: repeats)],
          );
          _exitSelectionMode();
        });
      },
    );
  }

  // ── Bottom sheets / dialogs ────────────────────────────────────────────────

  void _showAddTypeSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Text(
                      'Add segment',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  for (final type in _SegmentType.values)
                    ListTile(
                      key: Key('type_${type.name}'),
                      leading: _TypeChip(type: type),
                      title: Text(type.label),
                      subtitle: Text(
                        type.helperText,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _showSegmentEditSheet(type: type);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSegmentEditSheet({
    required _SegmentType type,
    int? itemIndex,
    WorkoutSegment? existing,
  }) {
    final existingDur = existing != null ? _durationOfSegment(existing) : null;
    final minCtrl = TextEditingController(
      text: (existingDur?.inMinutes ?? 2).toString(),
    );
    final secCtrl = TextEditingController(
      text: (existingDur?.inSeconds.remainder(60) ?? 0)
          .toString()
          .padLeft(2, '0'),
    );
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _TypeChip(type: type),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          itemIndex == null
                              ? 'Add ${type.label}'
                              : 'Edit ${type.label}',
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type.helperText,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    type.durationLabel,
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  _DurationInput(
                    minController: minCtrl,
                    secController: secCtrl,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    child: Text(itemIndex == null ? 'Add' : 'Save'),
                    onPressed: () {
                      if (formKey.currentState?.validate() != true) return;
                      final min = int.tryParse(minCtrl.text) ?? 0;
                      final sec = int.tryParse(secCtrl.text) ?? 0;
                      final duration = Duration(minutes: min, seconds: sec);
                      if (duration == Duration.zero) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Duration must be greater than 0'),
                          ),
                        );
                        return;
                      }
                      final segment = _buildSegment(type, duration);
                      Navigator.of(ctx).pop();
                      setState(() {
                        _isDirty = true;
                        if (itemIndex == null) {
                          _items.add(_SegmentItem(segment));
                        } else {
                          (_items[itemIndex] as _SegmentItem).segment = segment;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showGroupEditSheet(int index, _GroupItem group) {
    final repeatsCtrl =
        TextEditingController(text: group.repeats.toString());
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Edit group',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${group.segments.length} segments',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: repeatsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Repeats',
                      helperText:
                          'How many times to cycle through this group',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1) return 'Enter a number ≥ 1';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    child: const Text('Save'),
                    onPressed: () {
                      if (formKey.currentState?.validate() != true) return;
                      final repeats = int.parse(repeatsCtrl.text);
                      Navigator.of(ctx).pop();
                      setState(() {
                        _isDirty = true;
                        group.repeats = repeats;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(ctx).colorScheme.error,
                    ),
                    child: const Text('Ungroup'),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _ungroup(index);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRepeatCountDialog({
    required int initialRepeats,
    required ValueChanged<int> onConfirm,
  }) {
    final ctrl = TextEditingController(text: initialRepeats.toString());
    final formKey = GlobalKey<FormState>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Repeat group'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Repeat count',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n < 2) return 'Enter a number ≥ 2';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final repeats = int.parse(ctrl.text);
              Navigator.of(ctx).pop();
              onConfirm(repeats);
            },
            child: const Text('Group'),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        final confirmed = await _confirmDiscard();
        if (confirmed && mounted) router.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Workout Editor'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save preset',
            onPressed: _savePreset,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'Workout name (optional)',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ),
          _NotesSection(
            controller: _notesController,
            initiallyExpanded: _notesController.text.isNotEmpty,
          ),
          Expanded(
            child: _items.isEmpty
                ? _EmptyState(onAdd: _showAddTypeSheet)
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: _items.length,
                    onReorder: _onReorder,
                    itemBuilder: (ctx, i) {
                      final item = _items[i];
                      return switch (item) {
                        _SegmentItem() => _buildSegmentCard(i, item),
                        _GroupItem() => _buildGroupCard(i, item),
                      };
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _inSelectionMode
              ? _SelectionBar(
                  selectedCount: _selectedIndices.length,
                  canGroup: _canGroup,
                  onGroup: _groupSelected,
                  onCancel: () => setState(_exitSelectionMode),
                )
              : _NormalBar(
                  onAdd: _showAddTypeSheet,
                  onStart: _startWorkout,
                ),
        ),
      ),
      ),
    );
  }

  // ── Card builders ──────────────────────────────────────────────────────────

  Widget _buildSegmentCard(int index, _SegmentItem item) {
    final type = _typeOfSegment(item.segment);
    final dur = _durationOfSegment(item.segment);
    final isSelected = _selectedIndices.contains(index);

    return Dismissible(
      key: ObjectKey(item),
      direction: DismissDirection.endToStart,
      background: _DismissBackground(),
      onDismissed: (_) => _deleteItem(index),
      child: Card(
        key: ValueKey(item),
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle, color: Colors.grey),
            ),
          ),
          title: Row(
            children: [
              _TypeChip(type: type),
              const SizedBox(width: 12),
              Text(
                _formatDuration(dur),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          onTap: _inSelectionMode
              ? () => _toggleSelection(index)
              : () => _showSegmentEditSheet(
                    type: type,
                    itemIndex: index,
                    existing: item.segment,
                  ),
          onLongPress:
              _inSelectionMode ? null : () => _enterSelectionMode(index),
          trailing: _inSelectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelection(index),
                )
              : IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit',
                  onPressed: () => _showSegmentEditSheet(
                    type: type,
                    itemIndex: index,
                    existing: item.segment,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildGroupCard(int index, _GroupItem group) {
    return Card(
      key: ValueKey(group),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            leading: ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle, color: Colors.grey),
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'GROUP × ${group.repeats}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context)
                          .colorScheme
                          .onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit group',
              onPressed: () => _showGroupEditSheet(index, group),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final seg in group.segments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        _TypeChip(type: _typeOfSegment(seg), small: true),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(_durationOfSegment(seg)),
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable sub-widgets ─────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type, this.small = false});
  final _SegmentType type;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 10,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.15),
        border: Border.all(color: type.color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          color: type.color.withValues(alpha: 0.9),
          fontSize: small ? 10 : 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DurationInput extends StatelessWidget {
  const _DurationInput({
    required this.minController,
    required this.secController,
  });

  final TextEditingController minController;
  final TextEditingController secController;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: minController,
            decoration: const InputDecoration(
              labelText: 'Min',
              border: OutlineInputBorder(),
              suffixText: 'min',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n < 0) return 'Invalid';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: secController,
            decoration: const InputDecoration(
              labelText: 'Sec',
              border: OutlineInputBorder(),
              suffixText: 'sec',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n < 0 || n > 59) return '0–59';
              return null;
            },
          ),
        ),
      ],
    );
  }
}

class _DismissBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.fitness_center,
            size: 64,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No segments yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Add Segment" to build your workout',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Segment'),
          ),
        ],
      ),
    );
  }
}

class _NormalBar extends StatelessWidget {
  const _NormalBar({required this.onAdd, required this.onStart});
  final VoidCallback onAdd;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Segment'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Workout'),
          ),
        ),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedCount,
    required this.canGroup,
    required this.onGroup,
    required this.onCancel,
  });

  final int selectedCount;
  final bool canGroup;
  final VoidCallback onGroup;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: canGroup ? onGroup : null,
          icon: const Icon(Icons.layers),
          label: Text(
            selectedCount > 0 ? 'Group $selectedCount selected' : 'Group',
          ),
        ),
      ],
    );
  }
}

/// Expandable "Workout Notes" tile with a multiline text field inside.
class _NotesSection extends StatefulWidget {
  const _NotesSection({
    required this.controller,
    this.initiallyExpanded = false,
  });
  final TextEditingController controller;
  final bool initiallyExpanded;

  @override
  State<_NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends State<_NotesSection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hasNotes = widget.controller.text.isNotEmpty;
    return ExpansionTile(
      initiallyExpanded: widget.initiallyExpanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      leading: Icon(
        Icons.notes_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: const Text('Workout Notes'),
      subtitle: hasNotes
          ? Text(
              widget.controller.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Text(
              'Tap to add notes',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
      children: [
        TextField(
          controller: widget.controller,
          decoration: const InputDecoration(
            hintText: 'Describe the exercises, weights, reps...',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(12),
          ),
          maxLines: null,
          minLines: 4,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }
}
