import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../data/models/outdoor_models.dart';
import '../../data/repositories/outdoor_preset_repository.dart';

// ─── Internal editor data model ──────────────────────────────────────────────

sealed class _EditorItem {
  const _EditorItem();
}

class _SegmentItem extends _EditorItem {
  _SegmentItem(this.segment);
  OutdoorSegment segment;
}

class _GroupItem extends _EditorItem {
  _GroupItem({required this.segments, required this.repeats});
  List<OutdoorSegment> segments;
  int repeats;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Whether a segment is distance-based or time-based.
enum _SegType { distance, timed }

enum _DistUnit {
  km,
  mi;

  String get label => name; // 'km' or 'mi'
}

Color _tagColor(OutdoorSegmentTag tag) => tag.when(
      warmUp: () => AppColors.warmUp,
      work: () => AppColors.work,
      rest: () => AppColors.rest,
      coolDown: () => AppColors.coolDown,
      custom: (_) => AppColors.custom,
    );

IconData _segTypeIcon(OutdoorSegment seg) => seg.when(
      distance: (_, __, ___) => Icons.straighten_outlined,
      timed: (_, __, ___) => Icons.timer_outlined,
    );

_SegType _segTypeOf(OutdoorSegment seg) => seg.when(
      distance: (_, __, ___) => _SegType.distance,
      timed: (_, __, ___) => _SegType.timed,
    );

/// Default duration in seconds for a new timed segment with the given tag.
int _defaultSeconds(OutdoorSegmentTag tag) => tag.when(
      warmUp: () => 5 * 60,
      work: () => 4 * 60,
      rest: () => 1 * 60,
      coolDown: () => 5 * 60,
      custom: (_) => 2 * 60,
    );

/// Default distance string (in the given unit) for a new distance segment.
String _defaultDistStr(OutdoorSegmentTag tag, _DistUnit unit) {
  final km = tag.when(
    warmUp: () => 1.0,
    work: () => 1.0,
    rest: () => 0.5,
    coolDown: () => 1.0,
    custom: (_) => 1.0,
  );
  final value = unit == _DistUnit.km ? km : km / 1.609;
  if (value == value.floorToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class OutdoorEditorScreen extends ConsumerStatefulWidget {
  const OutdoorEditorScreen({super.key, this.initialPreset});

  /// When non-null the editor pre-fills all fields from this preset.
  /// Saving will overwrite it (same ID) rather than create a new entry.
  final OutdoorWorkoutPreset? initialPreset;

  @override
  ConsumerState<OutdoorEditorScreen> createState() =>
      _OutdoorEditorScreenState();
}

class _OutdoorEditorScreenState extends ConsumerState<OutdoorEditorScreen> {
  static const _uuid = Uuid();

  late final TextEditingController _nameController;
  final List<_EditorItem> _items = [];
  final Set<int> _selectedIndices = {};
  bool _inSelectionMode = false;
  bool _isDirty = false;

  /// ID of the preset being edited — null until first save.
  String? _editingId;

  /// Epoch-ms timestamp preserved across saves.
  late final int _createdAt;

  @override
  void initState() {
    super.initState();
    final p = widget.initialPreset;
    _editingId = p?.id;
    _createdAt = p?.createdAt ?? DateTime.now().millisecondsSinceEpoch;
    _nameController = TextEditingController(text: p?.name ?? '');
    if (p != null) _loadFromPreset(p);
    _nameController.addListener(_markDirty);
  }

  void _loadFromPreset(OutdoorWorkoutPreset preset) {
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
    super.dispose();
  }

  // ── Workout assembly ───────────────────────────────────────────────────────

  OutdoorWorkout _buildWorkout() {
    return OutdoorWorkout(
      elements: _items
          .map((item) => switch (item) {
                _SegmentItem(:final segment) =>
                  OutdoorElement.segment(segment),
                _GroupItem(:final segments, :final repeats) =>
                  OutdoorElement.group(
                    OutdoorGroup(segments: segments, repeats: repeats),
                  ),
              })
          .toList(),
    );
  }

  void _startWorkout() {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one segment first')),
      );
      return;
    }
    context.pushReplacement(
      '/outdoor-timer',
      extra: (workout: _buildWorkout(), name: _nameController.text.trim()),
    );
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
    final preset = OutdoorWorkoutPreset(
      id: id,
      name: name.isEmpty ? 'Untitled Workout' : name,
      workout: _buildWorkout(),
      createdAt: _createdAt,
    );
    try {
      await ref.read(outdoorPresetsProvider.notifier).save(preset);
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
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Add segment',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  key: const Key('type_distance'),
                  leading: const Icon(Icons.straighten_outlined),
                  title: const Text('Distance'),
                  subtitle: const Text(
                    'GPS tracks distance — segment ends when target reached',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showSegmentEditSheet(segType: _SegType.distance);
                  },
                ),
                ListTile(
                  key: const Key('type_timed'),
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Time'),
                  subtitle: const Text(
                    'Countdown timer — distance covered is recorded',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showSegmentEditSheet(segType: _SegType.timed);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSegmentEditSheet({
    required _SegType segType,
    int? itemIndex,
    OutdoorSegment? existing,
  }) {
    final isNew = existing == null;
    var selectedTag = existing?.tag ?? const OutdoorSegmentTag.work();
    var unit = _DistUnit.km;

    final minCtrl = TextEditingController();
    final secCtrl = TextEditingController();
    final distCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    void initControllers(OutdoorSegmentTag tag) {
      if (segType == _SegType.timed) {
        final secs = existing is OutdoorTimedSegment
            ? existing.seconds
            : _defaultSeconds(tag);
        minCtrl.text = (secs ~/ 60).toString();
        secCtrl.text = (secs % 60).toString().padLeft(2, '0');
      } else {
        if (existing is OutdoorDistanceSegment) {
          final km = existing.metres / 1000.0;
          distCtrl.text = km == km.floorToDouble()
              ? km.toInt().toString()
              : km.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
        } else {
          distCtrl.text = _defaultDistStr(tag, unit);
        }
      }
    }

    initControllers(selectedTag);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
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
                    // Header
                    Row(
                      children: [
                        Icon(segType == _SegType.timed
                            ? Icons.timer_outlined
                            : Icons.straighten_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            itemIndex == null
                                ? 'Add ${segType == _SegType.timed ? 'Time' : 'Distance'} Segment'
                                : 'Edit Segment',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Tag selector
                    Text(
                      'Tag',
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    _TagChipSelector(
                      selected: selectedTag,
                      onChanged: (tag) {
                        setSheetState(() {
                          selectedTag = tag;
                          if (isNew) initControllers(tag);
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Duration or distance input
                    if (segType == _SegType.timed) ...[
                      Text(
                        'Duration',
                        style: Theme.of(ctx).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      _DurationInput(
                        minController: minCtrl,
                        secController: secCtrl,
                      ),
                    ] else ...[
                      Text(
                        'Distance',
                        style: Theme.of(ctx).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      _DistanceInput(
                        controller: distCtrl,
                        unit: unit,
                        onUnitChanged: (newUnit) {
                          setSheetState(() {
                            final val = double.tryParse(distCtrl.text) ?? 0;
                            final metres = unit == _DistUnit.km
                                ? (val * 1000).round()
                                : (val * 1609).round();
                            unit = newUnit;
                            if (metres > 0) {
                              final converted = newUnit == _DistUnit.km
                                  ? metres / 1000.0
                                  : metres / 1609.0;
                              distCtrl.text = converted
                                  .toStringAsFixed(2)
                                  .replaceAll(RegExp(r'\.?0+$'), '');
                            }
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 24),

                    FilledButton(
                      child: Text(itemIndex == null ? 'Add' : 'Save'),
                      onPressed: () {
                        if (formKey.currentState?.validate() != true) return;
                        OutdoorSegment segment;
                        if (segType == _SegType.timed) {
                          final mins = int.tryParse(minCtrl.text) ?? 0;
                          final secs = int.tryParse(secCtrl.text) ?? 0;
                          final totalSecs = mins * 60 + secs;
                          if (totalSecs == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Duration must be greater than 0'),
                              ),
                            );
                            return;
                          }
                          segment = OutdoorSegment.timed(
                            seconds: totalSecs,
                            tag: selectedTag,
                          );
                        } else {
                          final val = double.tryParse(distCtrl.text) ?? 0;
                          final metres = unit == _DistUnit.km
                              ? (val * 1000).round()
                              : (val * 1609).round();
                          if (metres == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Distance must be greater than 0'),
                              ),
                            );
                            return;
                          }
                          segment = OutdoorSegment.distance(
                            metres: metres,
                            tag: selectedTag,
                          );
                        }
                        Navigator.of(ctx).pop();
                        setState(() {
                          _isDirty = true;
                          if (itemIndex == null) {
                            _items.add(_SegmentItem(segment));
                          } else {
                            (_items[itemIndex] as _SegmentItem).segment =
                                segment;
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
      ),
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
          title: const Text('Outdoor Editor'),
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
    final seg = item.segment;
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
              Icon(_segTypeIcon(seg), size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                seg.displayValue,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              _TagLabel(tag: seg.tag),
            ],
          ),
          onTap: _inSelectionMode
              ? () => _toggleSelection(index)
              : () => _showSegmentEditSheet(
                    segType: _segTypeOf(seg),
                    itemIndex: index,
                    existing: seg,
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
                    segType: _segTypeOf(seg),
                    itemIndex: index,
                    existing: seg,
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
                    color:
                        Theme.of(context).colorScheme.secondaryContainer,
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
                        Icon(
                          _segTypeIcon(seg),
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          seg.displayValue,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        _TagLabel(tag: seg.tag, small: true),
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

/// Coloured tag label chip.
class _TagLabel extends StatelessWidget {
  const _TagLabel({required this.tag, this.small = false});
  final OutdoorSegmentTag tag;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final color = _tagColor(tag);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        tag.displayLabel,
        style: TextStyle(
          color: color,
          fontSize: small ? 10 : 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Row of selectable tag chips used inside the segment edit sheet.
class _TagChipSelector extends StatelessWidget {
  const _TagChipSelector({
    required this.selected,
    required this.onChanged,
  });

  final OutdoorSegmentTag selected;
  final ValueChanged<OutdoorSegmentTag> onChanged;

  static const _tags = [
    OutdoorSegmentTag.warmUp(),
    OutdoorSegmentTag.work(),
    OutdoorSegmentTag.rest(),
    OutdoorSegmentTag.coolDown(),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: _tags.map((tag) {
        final color = _tagColor(tag);
        final isSelected = selected == tag;
        return FilterChip(
          label: Text(tag.displayLabel),
          selected: isSelected,
          showCheckmark: false,
          backgroundColor: Colors.transparent,
          selectedColor: color.withValues(alpha: 0.15),
          side: BorderSide(
            color: isSelected
                ? color
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
          ),
          labelStyle: TextStyle(
            color: isSelected ? color : null,
            fontWeight: isSelected ? FontWeight.bold : null,
          ),
          onSelected: (_) => onChanged(tag),
        );
      }).toList(),
    );
  }
}

/// MM : SS duration input — identical to the gym editor widget.
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

/// Decimal distance field with km / mi unit toggle.
class _DistanceInput extends StatelessWidget {
  const _DistanceInput({
    required this.controller,
    required this.unit,
    required this.onUnitChanged,
  });

  final TextEditingController controller;
  final _DistUnit unit;
  final ValueChanged<_DistUnit> onUnitChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Distance',
              border: const OutlineInputBorder(),
              suffixText: unit.label,
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            ],
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n <= 0) return 'Enter a positive distance';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          // Align vertically with the text field
          padding: const EdgeInsets.only(top: 8),
          child: SegmentedButton<_DistUnit>(
            segments: const [
              ButtonSegment(value: _DistUnit.km, label: Text('km')),
              ButtonSegment(value: _DistUnit.mi, label: Text('mi')),
            ],
            selected: {unit},
            onSelectionChanged: (s) => onUnitChanged(s.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
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
            Icons.directions_run,
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
