import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/workout_models.dart';

/// A simple countdown timer screen used as the starting point for workouts.
///
/// Accepts an optional [workout]; if none is provided it falls back to a
/// single 30‑second interval.
class TimerScreen extends StatefulWidget {
  final Workout? workout;
  const TimerScreen({super.key, this.workout});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  static const Duration _initialDuration = Duration(seconds: 30);

  late Duration _remaining;
  Timer? _timer;
  bool _running = false;

  // workout state
  int _intervalIndex = 0;
  bool _inWork = true;
  int _roundsLeft = 0;

  // visual cues
  Color _backgroundColor = Colors.white;

  @override
  void initState() {
    super.initState();
    if (widget.workout != null && widget.workout!.intervals.isNotEmpty) {
      _setupInterval(widget.workout!.intervals.first);
    } else {
      _remaining = _initialDuration;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        if (_remaining > Duration.zero) {
          _remaining -= const Duration(seconds: 1);
        } else {
          _beep();
          t.cancel();
          _nextPhase();
        }
      });
    });
  }

  void _pause() {
    _timer?.cancel();
    _running = false;
  }

  void _reset() {
    _timer?.cancel();
    _running = false;
    if (widget.workout != null && widget.workout!.intervals.isNotEmpty) {
      _intervalIndex = 0;
      _inWork = true;
      _setupInterval(widget.workout!.intervals.first);
    } else {
      setState(() {
        _remaining = _initialDuration;
        _backgroundColor = Colors.white;
      });
    }
  }

  void _setupInterval(WorkoutInterval interval) {
    _roundsLeft = interval.rounds;
    _inWork = true;
    _remaining = interval.workDuration;
    _backgroundColor = Colors.green.shade200;
  }

  void _nextPhase() {
    final workout = widget.workout;
    if (workout == null || workout.intervals.isEmpty) return;

    final current = workout.intervals[_intervalIndex];

    if (_inWork) {
      // finished work, go to rest
      if (current.restDuration > Duration.zero) {
        _inWork = false;
        _remaining = current.restDuration;
        _backgroundColor = Colors.orange.shade200;
        _start();
        return;
      }
    }

    // either coming from rest or no rest defined
    _roundsLeft--;
    if (_roundsLeft > 0) {
      // start another round of work
      _inWork = true;
      _remaining = current.workDuration;
      _backgroundColor = Colors.green.shade200;
      _start();
      return;
    }

    // move to next interval
    _intervalIndex++;
    if (_intervalIndex < workout.intervals.length) {
      _setupInterval(workout.intervals[_intervalIndex]);
      _start();
    } else {
      // workout finished
      _running = false;
    }
  }

  void _beep() {
    SystemSound.play(SystemSoundType.click);
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(title: const Text('Timer')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$minutes:$seconds', style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _running ? _pause : _start,
                  child: Text(_running ? 'Pause' : 'Start'),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
