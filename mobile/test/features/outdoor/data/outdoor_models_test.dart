import 'package:flutter_test/flutter_test.dart';
import 'package:training_timer/features/outdoor/data/models/outdoor_models.dart';

// ─── helpers ──────────────────────────────────────────────────────────────────

/// Round-trip an [OutdoorSegmentTag] through JSON and assert equality.
void _roundTripTag(OutdoorSegmentTag tag) {
  final parsed = OutdoorSegmentTag.fromJson(tag.toJson());
  expect(parsed, equals(tag));
}

/// Round-trip an [OutdoorSegment] through JSON and assert equality.
void _roundTripSegment(OutdoorSegment seg) {
  final parsed = OutdoorSegment.fromJson(seg.toJson());
  expect(parsed, equals(seg));
}

void main() {
  // ── OutdoorSegmentTag ───────────────────────────────────────────────────────

  group('OutdoorSegmentTag serialization', () {
    test('warmUp round-trips', () => _roundTripTag(const OutdoorSegmentTag.warmUp()));
    test('work round-trips', () => _roundTripTag(const OutdoorSegmentTag.work()));
    test('rest round-trips', () => _roundTripTag(const OutdoorSegmentTag.rest()));
    test('coolDown round-trips', () => _roundTripTag(const OutdoorSegmentTag.coolDown()));
    test('custom with label round-trips', () {
      _roundTripTag(const OutdoorSegmentTag.custom(label: 'Strides'));
    });

    test('custom preserves the exact label string', () {
      const tag = OutdoorSegmentTag.custom(label: 'Hill repeats × 8');
      final parsed = OutdoorSegmentTag.fromJson(tag.toJson());
      expect((parsed as OutdoorTagCustom).label, 'Hill repeats × 8');
    });
  });

  group('OutdoorSegmentTag.displayLabel', () {
    test('predefined tags return correct display strings', () {
      expect(const OutdoorSegmentTag.warmUp().displayLabel, 'Warm-up');
      expect(const OutdoorSegmentTag.work().displayLabel, 'Work');
      expect(const OutdoorSegmentTag.rest().displayLabel, 'Rest');
      expect(const OutdoorSegmentTag.coolDown().displayLabel, 'Cool-down');
    });

    test('custom tag returns the provided label', () {
      expect(
        const OutdoorSegmentTag.custom(label: 'Strides').displayLabel,
        'Strides',
      );
    });
  });

  group('OutdoorSegmentTag.isEffort', () {
    test('only work returns true', () {
      expect(const OutdoorSegmentTag.work().isEffort, isTrue);
      expect(const OutdoorSegmentTag.warmUp().isEffort, isFalse);
      expect(const OutdoorSegmentTag.rest().isEffort, isFalse);
      expect(const OutdoorSegmentTag.coolDown().isEffort, isFalse);
      expect(const OutdoorSegmentTag.custom(label: 'X').isEffort, isFalse);
    });
  });

  // ── OutdoorSegment ──────────────────────────────────────────────────────────

  group('OutdoorSegment serialization', () {
    test('distance segment round-trips', () {
      _roundTripSegment(const OutdoorSegment.distance(
        metres: 2000,
        tag: OutdoorSegmentTag.warmUp(),
        name: 'Warm-up jog',
      ));
    });

    test('timed segment round-trips', () {
      _roundTripSegment(const OutdoorSegment.timed(
        seconds: 240,
        tag: OutdoorSegmentTag.work(),
        name: 'Hard effort',
      ));
    });

    test('name defaults to empty string', () {
      const seg = OutdoorSegment.distance(
        metres: 1000,
        tag: OutdoorSegmentTag.rest(),
      );
      expect(seg.name, isEmpty);
      _roundTripSegment(seg);
    });

    test('custom tag round-trips inside a segment', () {
      _roundTripSegment(const OutdoorSegment.timed(
        seconds: 60,
        tag: OutdoorSegmentTag.custom(label: 'Strides'),
      ));
    });
  });

  group('OutdoorSegmentDisplay.displayValue', () {
    test('exact-kilometre distance formats as "N km"', () {
      const seg = OutdoorSegment.distance(
        metres: 2000,
        tag: OutdoorSegmentTag.warmUp(),
      );
      expect(seg.displayValue, '2 km');
    });

    test('sub-kilometre distance formats as "N m"', () {
      const seg = OutdoorSegment.distance(
        metres: 800,
        tag: OutdoorSegmentTag.work(),
      );
      expect(seg.displayValue, '800 m');
    });

    test('non-round kilometre distance formats with one decimal', () {
      const seg = OutdoorSegment.distance(
        metres: 2500,
        tag: OutdoorSegmentTag.coolDown(),
      );
      expect(seg.displayValue, '2.5 km');
    });

    test('timed segment with minutes formats as "M:SS"', () {
      const seg = OutdoorSegment.timed(
        seconds: 240,
        tag: OutdoorSegmentTag.work(),
      );
      expect(seg.displayValue, '4:00');
    });

    test('timed segment under a minute formats as "Ns"', () {
      const seg = OutdoorSegment.timed(
        seconds: 45,
        tag: OutdoorSegmentTag.rest(),
      );
      expect(seg.displayValue, '45s');
    });

    test('timed segment pads seconds to two digits', () {
      const seg = OutdoorSegment.timed(
        seconds: 65,
        tag: OutdoorSegmentTag.work(),
      );
      expect(seg.displayValue, '1:05');
    });
  });

  group('OutdoorSegmentDisplay.tag and .name accessors', () {
    test('distance segment tag accessor', () {
      const seg = OutdoorSegment.distance(
        metres: 500,
        tag: OutdoorSegmentTag.coolDown(),
        name: 'Jog',
      );
      expect(seg.tag, equals(const OutdoorSegmentTag.coolDown()));
      expect(seg.name, 'Jog');
    });

    test('timed segment tag accessor', () {
      const seg = OutdoorSegment.timed(
        seconds: 180,
        tag: OutdoorSegmentTag.rest(),
        name: 'Walk',
      );
      expect(seg.tag, equals(const OutdoorSegmentTag.rest()));
      expect(seg.name, 'Walk');
    });
  });

  // ── OutdoorGroup ────────────────────────────────────────────────────────────

  group('OutdoorGroup serialization', () {
    test('round-trips with multiple segments and explicit repeat count', () {
      const group = OutdoorGroup(
        segments: [
          OutdoorSegment.timed(seconds: 240, tag: OutdoorSegmentTag.work()),
          OutdoorSegment.timed(seconds: 180, tag: OutdoorSegmentTag.rest()),
        ],
        repeats: 4,
      );
      expect(OutdoorGroup.fromJson(group.toJson()), equals(group));
    });

    test('repeats defaults to 1', () {
      const group = OutdoorGroup(segments: [
        OutdoorSegment.timed(seconds: 60, tag: OutdoorSegmentTag.work()),
      ]);
      expect(group.repeats, 1);
      expect(OutdoorGroup.fromJson(group.toJson()), equals(group));
    });

    test('segments list is preserved in order', () {
      const group = OutdoorGroup(
        segments: [
          OutdoorSegment.distance(metres: 200, tag: OutdoorSegmentTag.work()),
          OutdoorSegment.timed(seconds: 90, tag: OutdoorSegmentTag.rest()),
          OutdoorSegment.distance(metres: 200, tag: OutdoorSegmentTag.work()),
        ],
        repeats: 6,
      );
      final parsed = OutdoorGroup.fromJson(group.toJson());
      expect(parsed.segments.length, 3);
      expect(parsed, equals(group));
    });
  });

  // ── OutdoorElement ──────────────────────────────────────────────────────────

  group('OutdoorElement serialization', () {
    test('segment variant round-trips', () {
      const el = OutdoorElement.segment(
        OutdoorSegment.distance(metres: 800, tag: OutdoorSegmentTag.work()),
      );
      expect(OutdoorElement.fromJson(el.toJson()), equals(el));
    });

    test('group variant round-trips', () {
      const el = OutdoorElement.group(
        OutdoorGroup(
          segments: [
            OutdoorSegment.timed(seconds: 120, tag: OutdoorSegmentTag.work()),
            OutdoorSegment.timed(seconds: 60, tag: OutdoorSegmentTag.rest()),
          ],
          repeats: 3,
        ),
      );
      expect(OutdoorElement.fromJson(el.toJson()), equals(el));
    });
  });

  // ── OutdoorWorkout ──────────────────────────────────────────────────────────

  group('OutdoorWorkout serialization', () {
    test('round-trips with mixed segment and group elements', () {
      const workout = OutdoorWorkout(
        elements: [
          OutdoorElement.segment(
            OutdoorSegment.distance(
              metres: 1000,
              tag: OutdoorSegmentTag.warmUp(),
            ),
          ),
          OutdoorElement.group(
            OutdoorGroup(
              segments: [
                OutdoorSegment.timed(
                    seconds: 120, tag: OutdoorSegmentTag.work()),
                OutdoorSegment.timed(
                    seconds: 60, tag: OutdoorSegmentTag.rest()),
              ],
              repeats: 5,
            ),
          ),
          OutdoorElement.segment(
            OutdoorSegment.distance(
              metres: 1000,
              tag: OutdoorSegmentTag.coolDown(),
            ),
          ),
        ],
        notes: 'Easy effort on the recovery intervals.',
      );
      expect(OutdoorWorkout.fromJson(workout.toJson()), equals(workout));
    });

    test('notes defaults to empty string', () {
      const workout = OutdoorWorkout(elements: []);
      expect(workout.notes, isEmpty);
      expect(OutdoorWorkout.fromJson(workout.toJson()), equals(workout));
    });

    test('element order is preserved', () {
      const workout = OutdoorWorkout(elements: [
        OutdoorElement.segment(
          OutdoorSegment.timed(seconds: 300, tag: OutdoorSegmentTag.warmUp()),
        ),
        OutdoorElement.segment(
          OutdoorSegment.timed(seconds: 60, tag: OutdoorSegmentTag.rest()),
        ),
      ]);
      final parsed = OutdoorWorkout.fromJson(workout.toJson());
      expect(parsed.elements.length, 2);
      expect(parsed, equals(workout));
    });
  });

  // ── OutdoorWorkoutPreset ────────────────────────────────────────────────────

  group('OutdoorWorkoutPreset serialization', () {
    test('round-trips with all fields', () {
      const preset = OutdoorWorkoutPreset(
        id: 'preset-abc',
        name: 'Fartlek',
        workout: OutdoorWorkout(elements: [
          OutdoorElement.segment(
            OutdoorSegment.timed(
                seconds: 300, tag: OutdoorSegmentTag.warmUp()),
          ),
        ]),
        createdAt: 1700000000000,
      );
      expect(OutdoorWorkoutPreset.fromJson(preset.toJson()), equals(preset));
    });

    test('createdAt defaults to 0', () {
      const preset = OutdoorWorkoutPreset(
        id: 'x',
        name: 'Test',
        workout: OutdoorWorkout(elements: []),
      );
      expect(preset.createdAt, 0);
    });
  });

  // ── Norwegian 4×4 integration example ──────────────────────────────────────

  test('Norwegian 4×4 workout round-trips and has correct structure', () {
    // Classic VO₂-max session:
    //   2 km warm-up jog
    //   4 × (4 min hard / 3 min easy jog)
    //   2 km cool-down jog
    const norwegian4x4 = OutdoorWorkout(
      elements: [
        OutdoorElement.segment(
          OutdoorSegment.distance(
            metres: 2000,
            tag: OutdoorSegmentTag.warmUp(),
            name: 'Warm-up',
          ),
        ),
        OutdoorElement.group(
          OutdoorGroup(
            segments: [
              OutdoorSegment.timed(
                seconds: 240, // 4 minutes
                tag: OutdoorSegmentTag.work(),
                name: 'Work interval',
              ),
              OutdoorSegment.timed(
                seconds: 180, // 3 minutes
                tag: OutdoorSegmentTag.rest(),
                name: 'Active rest',
              ),
            ],
            repeats: 4,
          ),
        ),
        OutdoorElement.segment(
          OutdoorSegment.distance(
            metres: 2000,
            tag: OutdoorSegmentTag.coolDown(),
            name: 'Cool-down',
          ),
        ),
      ],
      notes: 'Target HR 90–95% on work intervals.',
    );

    // Full round-trip
    final roundtrip = OutdoorWorkout.fromJson(norwegian4x4.toJson());
    expect(roundtrip, equals(norwegian4x4));

    // Structure assertions
    expect(norwegian4x4.elements.length, 3);
    expect(norwegian4x4.notes, contains('90–95%'));

    // First element is the warm-up distance segment
    final warmUp = norwegian4x4.elements.first as OutdoorElementSegment;
    expect((warmUp.segment as OutdoorDistanceSegment).metres, 2000);
    expect(warmUp.segment.tag, equals(const OutdoorSegmentTag.warmUp()));

    // Second element is the 4-round group
    final group = (norwegian4x4.elements[1] as OutdoorElementGroup).group;
    expect(group.repeats, 4);
    expect(group.segments.length, 2);
    expect((group.segments[0] as OutdoorTimedSegment).seconds, 240);
    expect(group.segments[0].tag, equals(const OutdoorSegmentTag.work()));
    expect((group.segments[1] as OutdoorTimedSegment).seconds, 180);
    expect(group.segments[1].tag, equals(const OutdoorSegmentTag.rest()));

    // Third element is the cool-down distance segment
    final coolDown = norwegian4x4.elements.last as OutdoorElementSegment;
    expect((coolDown.segment as OutdoorDistanceSegment).metres, 2000);
    expect(coolDown.segment.tag, equals(const OutdoorSegmentTag.coolDown()));
  });

  // ── Distance-only workout ───────────────────────────────────────────────────

  test('distance-only workout (e.g. 5 km with splits) round-trips', () {
    const fiveKm = OutdoorWorkout(
      elements: [
        OutdoorElement.segment(
          OutdoorSegment.distance(
            metres: 1000,
            tag: OutdoorSegmentTag.warmUp(),
            name: 'Easy km',
          ),
        ),
        OutdoorElement.group(
          OutdoorGroup(
            segments: [
              OutdoorSegment.distance(
                metres: 1000,
                tag: OutdoorSegmentTag.work(),
                name: 'Fast km',
              ),
            ],
            repeats: 3,
          ),
        ),
        OutdoorElement.segment(
          OutdoorSegment.distance(
            metres: 1000,
            tag: OutdoorSegmentTag.coolDown(),
            name: 'Cool-down km',
          ),
        ),
      ],
    );
    expect(OutdoorWorkout.fromJson(fiveKm.toJson()), equals(fiveKm));
  });

  // ── Mixed-type group ────────────────────────────────────────────────────────

  test('group with mixed distance and timed segments round-trips', () {
    // e.g. run 200 m hard, walk 90 s — repeat 6 times
    const session = OutdoorWorkout(
      elements: [
        OutdoorElement.group(
          OutdoorGroup(
            segments: [
              OutdoorSegment.distance(
                metres: 200,
                tag: OutdoorSegmentTag.work(),
                name: 'Sprint',
              ),
              OutdoorSegment.timed(
                seconds: 90,
                tag: OutdoorSegmentTag.rest(),
                name: 'Walk',
              ),
            ],
            repeats: 6,
          ),
        ),
      ],
    );
    final parsed = OutdoorWorkout.fromJson(session.toJson());
    expect(parsed, equals(session));

    final group = (parsed.elements.first as OutdoorElementGroup).group;
    expect(group.segments[0], isA<OutdoorDistanceSegment>());
    expect(group.segments[1], isA<OutdoorTimedSegment>());
  });
}
