class Workout {
  final String name;
  final List<Interval> intervals;

  Workout({required this.name, required this.intervals});
}

class Interval {
  final String label;
  final Duration duration;

  Interval({required this.label, required this.duration});
}
