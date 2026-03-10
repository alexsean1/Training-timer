import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:training_timer/features/outdoor/core/gps_tracking_service.dart';
import 'package:training_timer/features/outdoor/core/heart_rate_service.dart';
import 'package:training_timer/features/outdoor/core/outdoor_workout_engine.dart';
import 'package:training_timer/features/outdoor/data/models/outdoor_models.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class _FakeGpsSource implements GpsPositionSource {
  final _ctrl = StreamController<Position>.broadcast();

  void emit(Position p) => _ctrl.add(p);
  void emitError(Object error) => _ctrl.addError(error);
  Future<void> close() => _ctrl.close();

  @override
  Future<GpsPermissionStatus> checkPermission() async =>
      GpsPermissionStatus.granted;

  @override
  Future<GpsPermissionStatus> requestPermission() async =>
      GpsPermissionStatus.granted;

  @override
  Stream<Position> getPositionStream() => _ctrl.stream;
}

class _FakeHrSource implements HrBluetoothSource {
  final _scanCtrl = StreamController<List<HrDevice>>.broadcast();
  StreamController<int>? _bpmCtrl;
  StreamController<bool>? _connCtrl;

  void emitBpm(int bpm) => _bpmCtrl?.add(bpm);

  @override
  Stream<List<HrDevice>> get scanResults => _scanCtrl.stream;

  @override
  Future<void> startScan(
          {Duration timeout = const Duration(seconds: 15)}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<Stream<int>> connectToDevice(HrDevice device) async {
    _bpmCtrl = StreamController<int>.broadcast();
    _connCtrl = StreamController<bool>.broadcast();
    return _bpmCtrl!.stream;
  }

  @override
  Future<void> disconnectDevice(HrDevice device) async {}

  @override
  Stream<bool> isConnected(HrDevice device) =>
      _connCtrl?.stream ?? const Stream.empty();

  Future<void> close() async {
    await _scanCtrl.close();
    await _bpmCtrl?.close();
    await _connCtrl?.close();
  }
}

class _FakeTicker implements EngineTicker {
  TickCallback? _callback;

  @override
  void start(Duration interval, TickCallback onTick) => _callback = onTick;

  @override
  void stop() => _callback = null;

  bool get isRunning => _callback != null;

  void tick() => _callback?.call();
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Position _pos(double lat, double lon, {double speed = 0}) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0,
    );

/// Drains the async event queue enough for stream events to propagate.
Future<void> pump() async {
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// Workouts used across tests.
const _timedSegment = OutdoorSegment.timed(
  seconds: 10,
  tag: OutdoorSegmentTag.work(),
);
const _restSegment = OutdoorSegment.timed(
  seconds: 5,
  tag: OutdoorSegmentTag.rest(),
);
const _distanceSegment = OutdoorSegment.distance(
  metres: 1000,
  tag: OutdoorSegmentTag.work(),
);

OutdoorWorkout _timedWorkout([List<OutdoorSegment> segs = const []]) =>
    OutdoorWorkout(elements: [
      for (final s in segs.isEmpty ? [_timedSegment] : segs)
        OutdoorElement.segment(s),
    ]);

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late _FakeGpsSource gpsSource;
  late _FakeHrSource hrSource;
  late _FakeTicker ticker;
  late GeolocatorGpsTrackingService gpsService;
  late HeartRateService hrService;
  late OutdoorWorkoutEngine engine;

  setUp(() {
    gpsSource = _FakeGpsSource();
    hrSource = _FakeHrSource();
    ticker = _FakeTicker();
    gpsService =
        GeolocatorGpsTrackingService(positionSource: gpsSource);
    hrService = HeartRateService(source: hrSource);
    engine = OutdoorWorkoutEngine(
      gpsService: gpsService,
      hrService: hrService,
      ticker: ticker,
    );
  });

  tearDown(() async {
    await engine.dispose();
    await gpsSource.close();
    await hrSource.close();
  });

  // ── Initial state ──────────────────────────────────────────────────────────

  group('initial state', () {
    test('phase is idle', () {
      expect(engine.currentState.phase, OutdoorWorkoutPhase.idle);
    });

    test('no current segment', () {
      expect(engine.currentState.currentSegment, isNull);
    });

    test('totals are zero', () {
      expect(engine.currentState.totalElapsed, Duration.zero);
      expect(engine.currentState.totalDistanceMetres, 0);
    });
  });

  // ── Start ──────────────────────────────────────────────────────────────────

  group('start', () {
    test('phase becomes active after start', () async {
      await engine.start(_timedWorkout());
      expect(engine.currentState.phase, OutdoorWorkoutPhase.active);
    });

    test('first segment is set', () async {
      await engine.start(_timedWorkout());
      expect(engine.currentState.currentSegment, _timedSegment);
    });

    test('total segments reflects flattened count', () async {
      await engine.start(_timedWorkout());
      expect(engine.currentState.totalSegments, 1);
    });

    test('timeRemaining initialised for timed segment', () async {
      await engine.start(_timedWorkout());
      expect(engine.currentState.timeRemaining,
          const Duration(seconds: 10));
    });

    test('timeRemaining is null for distance segment', () async {
      await engine.start(const OutdoorWorkout(elements: [
        OutdoorElement.segment(_distanceSegment),
      ]));
      expect(engine.currentState.timeRemaining, isNull);
    });

    test('distanceRemaining initialised for distance segment', () async {
      await engine.start(const OutdoorWorkout(elements: [
        OutdoorElement.segment(_distanceSegment),
      ]));
      expect(engine.currentState.distanceRemainingMetres, 1000.0);
    });

    test('start announcement emitted', () async {
      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      await engine.start(_timedWorkout());
      await pump();
      await sub.cancel();

      expect(announcements, hasLength(1));
      expect(announcements.first, isA<SegmentStartAnnouncement>());
      expect(
          (announcements.first as SegmentStartAnnouncement).text, 'Run!');
    });

    test('groups are flattened with repeats', () async {
      const workout = OutdoorWorkout(elements: [
        OutdoorElement.group(OutdoorGroup(
          segments: [_timedSegment, _restSegment],
          repeats: 3,
        )),
      ]);
      await engine.start(workout);
      expect(engine.currentState.totalSegments, 6);
    });
  });

  // ── Timed segment ──────────────────────────────────────────────────────────

  group('timed segment', () {
    setUp(() async => engine.start(_timedWorkout()));

    test('each tick decrements timeRemaining by 1 second', () {
      ticker.tick();
      expect(engine.currentState.timeRemaining,
          const Duration(seconds: 9));
      ticker.tick();
      expect(engine.currentState.timeRemaining,
          const Duration(seconds: 8));
    });

    test('each tick increments totalElapsed', () {
      ticker.tick();
      expect(engine.currentState.totalElapsed,
          const Duration(seconds: 1));
    });

    test('segment completes when timeRemaining hits zero', () {
      for (int i = 0; i < 10; i++) {
        ticker.tick();
      }
      expect(engine.currentState.timeRemaining, Duration.zero);
    });

    test('phase becomes countdown after segment completes', () {
      for (int i = 0; i < 10; i++) {
        ticker.tick();
      }
      expect(engine.currentState.phase, OutdoorWorkoutPhase.countdown);
    });

    test('countdownValue starts at 3', () {
      for (int i = 0; i < 10; i++) {
        ticker.tick();
      }
      expect(engine.currentState.countdownValue, 3);
    });
  });

  // ── Countdown and segment transition ──────────────────────────────────────

  group('countdown', () {
    test('countdown decrements 3 → 2 → 1, then next segment starts',
        () async {
      final workout = _timedWorkout([_timedSegment, _restSegment]);
      await engine.start(workout);

      // Run first segment to completion.
      for (int i = 0; i < 10; i++) {
        ticker.tick();
      }
      expect(engine.currentState.phase, OutdoorWorkoutPhase.countdown);
      expect(engine.currentState.countdownValue, 3);

      ticker.tick(); // countdown: 3 → 2
      expect(engine.currentState.countdownValue, 2);

      ticker.tick(); // countdown: 2 → 1
      expect(engine.currentState.countdownValue, 1);

      ticker.tick(); // countdown done → next segment
      expect(engine.currentState.phase, OutdoorWorkoutPhase.active);
      expect(engine.currentState.currentSegment, _restSegment);
      expect(engine.currentState.segmentIndex, 1);
    });

    test('countdown announcements emitted', () async {
      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      await engine.start(_timedWorkout());
      await pump();
      announcements.clear(); // discard start announcement

      for (int i = 0; i < 10; i++) {
        ticker.tick();
      }
      ticker.tick(); // 2
      ticker.tick(); // 1

      await pump();
      await sub.cancel();

      final countdown = announcements.whereType<CountdownAnnouncement>();
      expect(countdown.map((a) => a.value).toList(), [3, 2, 1]);
    });

    test('phase is finished after last segment countdown', () async {
      await engine.start(_timedWorkout());

      for (int i = 0; i < 10; i++) {
        ticker.tick();
      }
      ticker.tick(); // 2
      ticker.tick(); // 1
      ticker.tick(); // advance → finished

      expect(engine.currentState.phase, OutdoorWorkoutPhase.finished);
    });

    test('start announcement emitted for second segment', () async {
      final workout = _timedWorkout([_timedSegment, _restSegment]);
      await engine.start(workout);
      await pump();

      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      for (int i = 0; i < 10; i++) {
        ticker.tick();
      }
      ticker.tick();
      ticker.tick();
      ticker.tick(); // advance to rest segment

      await pump();
      await sub.cancel();

      final starts = announcements.whereType<SegmentStartAnnouncement>();
      expect(starts.map((a) => a.text), contains('Rest!'));
    });
  });

  // ── Distance segment ───────────────────────────────────────────────────────

  group('distance segment', () {
    setUp(() async => engine.start(const OutdoorWorkout(
          elements: [OutdoorElement.segment(_distanceSegment)],
        )));

    test('GPS snapshot updates segmentDistanceMetres', () async {
      gpsSource.emit(_pos(59.9139, 10.7522));
      gpsSource.emit(_pos(59.9149, 10.7522)); // ~111 m north
      await pump();

      expect(engine.currentState.segmentDistanceMetres,
          greaterThan(0));
    });

    test('distanceRemaining decreases as GPS distance grows', () async {
      gpsSource.emit(_pos(59.9139, 10.7522));
      gpsSource.emit(_pos(59.9229, 10.7522)); // ~1000 m north
      await pump();

      // Should be within 50 m of target — segment completes.
      expect(engine.currentState.phase, OutdoorWorkoutPhase.countdown);
    });

    test('phase becomes countdown when within 50 m of target', () async {
      // Emit position ~960 m from start (within 50 m of 1000 m target).
      gpsSource.emit(_pos(59.9139, 10.7522));
      gpsSource.emit(_pos(59.9225, 10.7522)); // ~960 m
      await pump();

      expect(engine.currentState.phase, OutdoorWorkoutPhase.countdown);
    });

    test('distanceRemaining set to 0 on completion', () async {
      gpsSource.emit(_pos(59.9139, 10.7522));
      gpsSource.emit(_pos(59.9229, 10.7522));
      await pump();

      if (engine.currentState.phase == OutdoorWorkoutPhase.countdown) {
        expect(engine.currentState.distanceRemainingMetres, 0.0);
      }
    });

    test('ticks accumulate totalElapsed during distance segment', () async {
      ticker.tick();
      ticker.tick();
      expect(engine.currentState.totalElapsed,
          const Duration(seconds: 2));
    });
  });

  // ── Distance announcements ─────────────────────────────────────────────────

  group('distance announcements', () {
    test('kilometre announcement for 5 km segment', () async {
      const seg = OutdoorSegment.distance(
          metres: 5000, tag: OutdoorSegmentTag.work());
      await engine.start(const OutdoorWorkout(
          elements: [OutdoorElement.segment(seg)]));

      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      // Jump from 0 to ~4000 m covered → 1000 m remaining.
      gpsSource.emit(_pos(59.9139, 10.7522)); // origin
      gpsSource.emit(_pos(59.9499, 10.7522)); // ~4000 m north
      await pump();
      await sub.cancel();

      final marks = announcements.whereType<DistanceAnnouncement>();
      expect(
        marks.any((a) => a.text.contains('1 kilometre remaining')),
        isTrue,
      );
    });

    test('500 m announcement triggered', () async {
      const seg = OutdoorSegment.distance(
          metres: 1000, tag: OutdoorSegmentTag.work());
      await engine.start(const OutdoorWorkout(
          elements: [OutdoorElement.segment(seg)]));

      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      // ~500 m covered → ~500 m remaining.
      gpsSource.emit(_pos(59.9139, 10.7522));
      gpsSource.emit(_pos(59.9184, 10.7522)); // ~500 m north
      await pump();
      await sub.cancel();

      final marks = announcements.whereType<DistanceAnnouncement>();
      expect(
        marks.any((a) => a.text.contains('500 metres remaining')),
        isTrue,
      );
    });

    test('each threshold announced only once', () async {
      const seg = OutdoorSegment.distance(
          metres: 2000, tag: OutdoorSegmentTag.work());
      await engine.start(const OutdoorWorkout(
          elements: [OutdoorElement.segment(seg)]));

      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      // Same position twice — distance stays the same; no double announce.
      gpsSource.emit(_pos(59.9139, 10.7522));
      gpsSource.emit(_pos(59.9229, 10.7522)); // ~1000 m remaining
      gpsSource.emit(_pos(59.9229, 10.7522)); // same position
      await pump();
      await sub.cancel();

      final marks = announcements.whereType<DistanceAnnouncement>();
      final kmCount =
          marks.where((a) => a.text.contains('1 kilometre')).length;
      expect(kmCount, 1);
    });
  });

  // ── GPS metrics ────────────────────────────────────────────────────────────

  group('GPS metrics', () {
    test('pace calculated from GPS speed', () async {
      await engine.start(_timedWorkout());

      // 3 m/s → pace = 1000 / (3 * 60) ≈ 5.56 min/km
      gpsSource.emit(_pos(59.9139, 10.7522, speed: 3.0));
      await pump();

      final pace = engine.currentState.paceMinPerKm;
      expect(pace, isNotNull);
      expect(pace!, moreOrLessEquals(5.56, epsilon: 0.1));
    });

    test('pace is null when speed is zero', () async {
      await engine.start(_timedWorkout());
      gpsSource.emit(_pos(59.9139, 10.7522, speed: 0));
      await pump();

      expect(engine.currentState.paceMinPerKm, isNull);
    });

    test('totalDistanceMetres updates from GPS', () async {
      await engine.start(_timedWorkout());
      gpsSource.emit(_pos(59.9139, 10.7522));
      gpsSource.emit(_pos(59.9229, 10.7522));
      await pump();

      expect(engine.currentState.totalDistanceMetres,
          moreOrLessEquals(1000.0, epsilon: 30.0));
    });
  });

  // ── Time-based announcements ───────────────────────────────────────────────

  group('time-based announcements', () {
    // A 120 s segment exercises both halfway (at 60 s) and 1-min-remaining.
    const longSeg = OutdoorSegment.timed(
      seconds: 120,
      tag: OutdoorSegmentTag.work(),
    );

    OutdoorWorkout longWorkout() => const OutdoorWorkout(
          elements: [OutdoorElement.segment(longSeg)],
        );

    test('HalfwayAnnouncement emitted at midpoint of 120 s segment', () async {
      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      await engine.start(longWorkout());
      await pump();
      announcements.clear(); // discard start announcement

      for (int i = 0; i < 60; i++) {
        ticker.tick();
      }
      await pump(); // drain async broadcast stream

      await sub.cancel();

      expect(announcements.whereType<HalfwayAnnouncement>(), hasLength(1));
    });

    test('HalfwayAnnouncement NOT emitted twice for same segment', () async {
      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      await engine.start(longWorkout());
      await pump();
      announcements.clear();

      for (int i = 0; i < 80; i++) {
        ticker.tick(); // past midpoint — halfway should still fire only once
      }
      await pump(); // drain async broadcast stream

      await sub.cancel();

      expect(announcements.whereType<HalfwayAnnouncement>(), hasLength(1));
    });

    test('HalfwayAnnouncement NOT emitted for segments < 60 s', () async {
      // _timedSegment is 10 s — below the 60 s threshold.
      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      await engine.start(_timedWorkout());
      await pump();
      announcements.clear();

      for (int i = 0; i < 5; i++) {
        ticker.tick(); // midpoint of 10 s segment
      }

      await sub.cancel();

      expect(announcements.whereType<HalfwayAnnouncement>(), isEmpty);
    });

    test('TimeRemainingAnnouncement emitted at 1 minute for 120 s segment',
        () async {
      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      await engine.start(longWorkout());
      await pump();
      announcements.clear();

      for (int i = 0; i < 60; i++) {
        ticker.tick(); // timeRemaining → 60 s
      }
      await pump(); // drain async broadcast stream

      await sub.cancel();

      expect(
        announcements
            .whereType<TimeRemainingAnnouncement>()
            .map((a) => a.text),
        contains('One minute remaining'),
      );
    });

    test('TimeRemainingAnnouncement NOT emitted for segments ≤ 90 s', () async {
      const shortSeg = OutdoorSegment.timed(
        seconds: 90,
        tag: OutdoorSegmentTag.work(),
      );
      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      await engine.start(const OutdoorWorkout(
          elements: [OutdoorElement.segment(shortSeg)]));
      await pump();
      announcements.clear();

      for (int i = 0; i < 30; i++) {
        ticker.tick(); // timeRemaining → 60 s
      }

      await sub.cancel();

      expect(announcements.whereType<TimeRemainingAnnouncement>(), isEmpty);
    });
  });

  // ── Pace announcements ─────────────────────────────────────────────────────

  group('pace announcements', () {
    test('PaceAnnouncement emitted when total distance crosses 1 km', () async {
      // Use a long timed segment so GPS updates don't trigger completion.
      const seg = OutdoorSegment.timed(
        seconds: 1000,
        tag: OutdoorSegmentTag.work(),
      );

      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      await engine.start(
          const OutdoorWorkout(elements: [OutdoorElement.segment(seg)]));
      await pump();
      announcements.clear();

      // Emit GPS positions ~1000 m apart at 5 m/s.
      gpsSource.emit(_pos(59.9139, 10.7522, speed: 5.0));
      gpsSource.emit(_pos(59.9229, 10.7522, speed: 5.0));
      await pump();

      await sub.cancel();

      final paceAnnouncements = announcements.whereType<PaceAnnouncement>();
      expect(paceAnnouncements, isNotEmpty);
      expect(paceAnnouncements.first.text, contains('Current pace:'));
      expect(paceAnnouncements.first.text, contains('per kilometre'));
    });

    test('PaceAnnouncement NOT emitted again at same km', () async {
      const seg = OutdoorSegment.timed(
        seconds: 1000,
        tag: OutdoorSegmentTag.work(),
      );

      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      await engine.start(
          const OutdoorWorkout(elements: [OutdoorElement.segment(seg)]));
      await pump();
      announcements.clear();

      // Three GPS updates — first two cross 1 km, third stays inside same km.
      gpsSource.emit(_pos(59.9139, 10.7522, speed: 5.0));
      gpsSource.emit(_pos(59.9229, 10.7522, speed: 5.0)); // ~1 km total
      gpsSource.emit(_pos(59.9229, 10.7522, speed: 5.0)); // same spot
      await pump();

      await sub.cancel();

      expect(announcements.whereType<PaceAnnouncement>(), hasLength(1));
    });

    test('PaceAnnouncement text includes minutes and seconds when applicable',
        () async {
      const seg = OutdoorSegment.timed(
        seconds: 1000,
        tag: OutdoorSegmentTag.work(),
      );

      final announcements = <OutdoorAnnouncement>[];
      final sub = engine.announcementStream.listen(announcements.add);

      await engine.start(
          const OutdoorWorkout(elements: [OutdoorElement.segment(seg)]));
      await pump();
      announcements.clear();

      // 5 m/s → pace = 1000/(5*60) = 3.33 min/km → 3 min 20 sec/km
      gpsSource.emit(_pos(59.9139, 10.7522, speed: 5.0));
      gpsSource.emit(_pos(59.9229, 10.7522, speed: 5.0));
      await pump();

      await sub.cancel();

      final text =
          announcements.whereType<PaceAnnouncement>().first.text;
      expect(text, contains('minute'));
      expect(text, contains('per kilometre'));
    });
  });

  // ── Heart rate ─────────────────────────────────────────────────────────────

  group('heart rate', () {
    setUp(() async {
      await engine.start(_timedWorkout());
      const device = HrDevice(id: 'test', name: 'Test HR');
      await hrService.connect(device);
    });

    test('currentBpm updated in state', () async {
      hrSource.emitBpm(72);
      await pump();
      expect(engine.currentState.currentBpm, 72);
    });

    test('segmentAvgBpm calculated from samples', () async {
      hrSource.emitBpm(60);
      hrSource.emitBpm(80);
      await pump();

      expect(engine.currentState.segmentAvgBpm, 70.0);
    });

    test('segmentAvgBpm is null before any HR reading', () async {
      expect(engine.currentState.segmentAvgBpm, isNull);
    });
  });

  // ── Stop ───────────────────────────────────────────────────────────────────

  group('stop', () {
    test('stop resets to idle phase', () async {
      await engine.start(_timedWorkout());
      await engine.stop();
      expect(engine.currentState.phase, OutdoorWorkoutPhase.idle);
    });

    test('ticker stopped after stop()', () async {
      await engine.start(_timedWorkout());
      await engine.stop();
      expect(ticker.isRunning, isFalse);
    });
  });

  // ── Announcement text ──────────────────────────────────────────────────────

  group('segment start announcement text', () {
    Future<String?> startTextFor(OutdoorSegmentTag tag) async {
      final seg = OutdoorSegment.timed(seconds: 5, tag: tag);
      final e = OutdoorWorkoutEngine(
        gpsService: GeolocatorGpsTrackingService(positionSource: _FakeGpsSource()),
        hrService: HeartRateService(source: _FakeHrSource()),
        ticker: _FakeTicker(),
      );
      String? text;
      final sub = e.announcementStream.listen((a) {
        if (a is SegmentStartAnnouncement) text = a.text;
      });
      await e.start(OutdoorWorkout(
          elements: [OutdoorElement.segment(seg)]));
      await pump();
      await sub.cancel();
      await e.dispose();
      return text;
    }

    test('work tag → "Run!"', () async {
      expect(await startTextFor(const OutdoorSegmentTag.work()), 'Run!');
    });

    test('rest tag → "Rest!"', () async {
      expect(
          await startTextFor(const OutdoorSegmentTag.rest()), 'Rest!');
    });

    test('warmUp tag → "Warm up!"', () async {
      expect(await startTextFor(const OutdoorSegmentTag.warmUp()),
          'Warm up!');
    });

    test('coolDown tag → "Cool down!"', () async {
      expect(await startTextFor(const OutdoorSegmentTag.coolDown()),
          'Cool down!');
    });

    test('custom tag → label', () async {
      expect(
          await startTextFor(
              const OutdoorSegmentTag.custom(label: 'Strides')),
          'Strides');
    });
  });

  // ── formattedPace ──────────────────────────────────────────────────────────

  group('formattedPace', () {
    test('returns "--:--" when pace is null', () {
      expect(OutdoorWorkoutState.initial.formattedPace, '--:--');
    });

    test('formats 5 min/km as "5:00"', () async {
      await engine.start(_timedWorkout());
      // 1000 / (x * 60) = 5 → x = 1000 / 300 ≈ 3.333 m/s
      gpsSource.emit(_pos(59.9139, 10.7522, speed: 1000 / 300));
      await pump();
      expect(engine.currentState.formattedPace, '5:00');
    });
  });

  // ── GPS error handling ─────────────────────────────────────────────────────

  group('GPS error handling', () {
    test('isGpsLost is false initially', () {
      expect(engine.currentState.isGpsLost, isFalse);
    });

    test('emitting GPS error sets isGpsLost true', () async {
      await engine.start(_timedWorkout());
      await pump();

      expect(engine.currentState.isGpsLost, isFalse);

      gpsSource.emitError(Exception('GPS unavailable'));
      await pump();

      expect(engine.currentState.isGpsLost, isTrue);
    });

    test('timer continues ticking after GPS error', () async {
      await engine.start(_timedWorkout());
      await pump();

      gpsSource.emitError(Exception('GPS unavailable'));
      await pump();

      final before = engine.currentState.totalElapsed;
      ticker.tick();
      await pump();

      expect(engine.currentState.totalElapsed, greaterThan(before));
    });

    test('phase remains active after GPS error during active segment',
        () async {
      await engine.start(_timedWorkout());
      await pump();

      gpsSource.emitError(Exception('GPS unavailable'));
      await pump();

      expect(engine.currentState.phase, OutdoorWorkoutPhase.active);
    });

    test('isGpsLost resets to false after stop() and restart', () async {
      await engine.start(_timedWorkout());
      await pump();

      gpsSource.emitError(Exception('GPS unavailable'));
      await pump();
      expect(engine.currentState.isGpsLost, isTrue);

      await engine.stop();
      expect(engine.currentState.isGpsLost, isFalse);
    });

    test('second GPS error after first is ignored (no double-stop)', () async {
      await engine.start(_timedWorkout());
      await pump();

      gpsSource.emitError(Exception('first error'));
      await pump();
      expect(engine.currentState.isGpsLost, isTrue);

      // Should not throw or change phase.
      gpsSource.emitError(Exception('second error'));
      await pump();
      expect(engine.currentState.phase, OutdoorWorkoutPhase.active);
    });
  });
}
