import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/workout_models.dart';

class WorkoutEditorScreen extends StatefulWidget {
  const WorkoutEditorScreen({super.key});

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _workController = TextEditingController(text: '30');
  final _restController = TextEditingController(text: '15');
  final _roundsController = TextEditingController(text: '8');

  @override
  void dispose() {
    _nameController.dispose();
    _workController.dispose();
    _restController.dispose();
    _roundsController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    final name = _nameController.text.isEmpty ? 'Workout' : _nameController.text;
    final work = int.tryParse(_workController.text) ?? 30;
    final rest = int.tryParse(_restController.text) ?? 15;
    final rounds = int.tryParse(_roundsController.text) ?? 1;

    final workout = Workout(
      name: name,
      intervals: [
        WorkoutInterval(
          workDuration: Duration(seconds: work),
          restDuration: Duration(seconds: rest),
          rounds: rounds,
        ),
      ],
    );

    // Navigate to timer screen with the workout as extra state
    context.go('/timer', extra: workout);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Workout')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextFormField(
                controller: _workController,
                decoration: const InputDecoration(labelText: 'Work (seconds)'),
                keyboardType: TextInputType.number,
                validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter a number' : null,
              ),
              TextFormField(
                controller: _restController,
                decoration: const InputDecoration(labelText: 'Rest (seconds)'),
                keyboardType: TextInputType.number,
                validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter a number' : null,
              ),
              TextFormField(
                controller: _roundsController,
                decoration: const InputDecoration(labelText: 'Rounds'),
                keyboardType: TextInputType.number,
                validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter a number' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _save, child: const Text('Start')),
            ],
          ),
        ),
      ),
    );
  }
}
