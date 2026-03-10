import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:training_timer/features/outdoor/core/gps_tracking_service.dart';

// ─── Fake position source ──────────────────────────────────────────────────────

class FakeGpsPositionSource implements GpsPositionSource {
  GpsPermissionStatus checkResult;
  GpsPermissionStatus requestResult;

  final _controller = StreamController<Position>.broadcast();

  FakeGpsPositionSource({
    this.checkResult = GpsPermissionStatus.granted,
    this.requestResult = GpsPermissionStatus.granted,
  });

  void emit(Position position) => _controller.add(position);
  void emitError(Object error) => _controller.addError(error);

  @override
  Future<GpsPermissionStatus> checkPermission() async => checkResult;

  @override
  Future<GpsPermissionStatus> requestPermission() async => requestResult;

  @override
  Stream<Position> getPositionStream() => _controller.stream;

  Future<void> close() => _controller.close();
}

// ─── Position helper ──────────────────────────────────────────────────────────

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

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late FakeGpsPositionSource source;
  late GeolocatorGpsTrackingService service;

  setUp(() {
    source = FakeGpsPositionSource();
    service = GeolocatorGpsTrackingService(positionSource: source);
  });

  tearDown(() async {
    await service.stopTracking();
    await source.close();
  });

  // ── Permission handling ────────────────────────────────────────────────────

  group('permission handling', () {
    test('returns null when permission is permanently denied', () async {
      source.checkResult = GpsPermissionStatus.deniedForever;
      final stream = await service.startTracking();
      expect(stream, isNull);
      expect(service.isTracking, isFalse);
    });

    test('requests permission when status is denied then succeeds', () async {
      source.checkResult = GpsPermissionStatus.denied;
      source.requestResult = GpsPermissionStatus.granted;
      final stream = await service.startTracking();
      expect(stream, isNotNull);
      expect(service.isTracking, isTrue);
    });

    test('requests permission when status is notDetermined then succeeds',
        () async {
      source.checkResult = GpsPermissionStatus.notDetermined;
      source.requestResult = GpsPermissionStatus.granted;
      final stream = await service.startTracking();
      expect(stream, isNotNull);
    });

    test('returns null when request is denied after prompt', () async {
      source.checkResult = GpsPermissionStatus.denied;
      source.requestResult = GpsPermissionStatus.denied;
      final stream = await service.startTracking();
      expect(stream, isNull);
    });

    test('returns null when request ends up deniedForever', () async {
      source.checkResult = GpsPermissionStatus.denied;
      source.requestResult = GpsPermissionStatus.deniedForever;
      final stream = await service.startTracking();
      expect(stream, isNull);
    });
  });

  // ── isTracking ─────────────────────────────────────────────────────────────

  group('isTracking', () {
    test('is false before startTracking', () {
      expect(service.isTracking, isFalse);
    });

    test('is true after startTracking with permission granted', () async {
      await service.startTracking();
      expect(service.isTracking, isTrue);
    });

    test('is false after stopTracking', () async {
      await service.startTracking();
      await service.stopTracking();
      expect(service.isTracking, isFalse);
    });

    test('calling startTracking twice returns the same stream', () async {
      final s1 = await service.startTracking();
      final s2 = await service.startTracking();
      expect(identical(s1, s2), isTrue);
    });
  });

  // ── Snapshot emission ──────────────────────────────────────────────────────

  group('snapshot emission', () {
    test('first position emits snapshot with zero distances', () async {
      final stream = (await service.startTracking())!;
      final snapshotFuture = stream.first;

      source.emit(_pos(59.9139, 10.7522, speed: 3.5));

      final snap = await snapshotFuture;
      expect(snap.segmentDistanceMetres, 0.0);
      expect(snap.totalDistanceMetres, 0.0);
      expect(snap.speedMetresPerSecond, 3.5);
      expect(snap.latitude, 59.9139);
      expect(snap.longitude, 10.7522);
    });

    test('second position accumulates distance', () async {
      final stream = (await service.startTracking())!;
      final snapshots = <GpsSnapshot>[];
      final sub = stream.listen(snapshots.add);

      // ~111 m north (1 arc-second ≈ 30.9 m per 0.001 degree at 60°N)
      source.emit(_pos(59.9139, 10.7522));
      source.emit(_pos(59.9149, 10.7522));

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots, hasLength(2));
      expect(snapshots[0].segmentDistanceMetres, 0.0);
      expect(snapshots[1].segmentDistanceMetres, greaterThan(0));
      expect(snapshots[1].segmentDistanceMetres,
          moreOrLessEquals(111.0, epsilon: 20.0));
      expect(snapshots[1].totalDistanceMetres,
          snapshots[1].segmentDistanceMetres);
    });

    test('totalDistance accumulates across resetSegmentDistance', () async {
      final stream = (await service.startTracking())!;
      final snapshots = <GpsSnapshot>[];
      final sub = stream.listen(snapshots.add);

      source.emit(_pos(59.9139, 10.7522));
      source.emit(_pos(59.9149, 10.7522));
      await Future<void>.delayed(Duration.zero);

      service.resetSegmentDistance();

      source.emit(_pos(59.9159, 10.7522));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      final last = snapshots.last;
      expect(last.segmentDistanceMetres,
          moreOrLessEquals(111.0, epsilon: 20.0));
      expect(last.totalDistanceMetres,
          moreOrLessEquals(222.0, epsilon: 40.0));
      expect(last.totalDistanceMetres,
          greaterThan(last.segmentDistanceMetres));
    });

    test('resetSegmentDistance resets segment counter to zero', () async {
      final stream = (await service.startTracking())!;
      final snapshots = <GpsSnapshot>[];
      final sub = stream.listen(snapshots.add);

      source.emit(_pos(59.9139, 10.7522));
      source.emit(_pos(59.9149, 10.7522));
      await Future<void>.delayed(Duration.zero);

      service.resetSegmentDistance();

      // Re-emit same position so delta is 0 (haversine of identical coords)
      source.emit(_pos(59.9149, 10.7522));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots.last.segmentDistanceMetres,
          moreOrLessEquals(0.0, epsilon: 1.0));
    });

    test('negative speed from GPS is clamped to zero', () async {
      final stream = (await service.startTracking())!;
      final snapshotFuture = stream.first;

      source.emit(_pos(59.9139, 10.7522, speed: -1.0));

      final snap = await snapshotFuture;
      expect(snap.speedMetresPerSecond, 0.0);
    });

    test('speedKmh getter converts correctly', () async {
      final stream = (await service.startTracking())!;
      final snapshotFuture = stream.first;

      source.emit(_pos(59.9139, 10.7522, speed: 10.0 / 3.6));

      final snap = await snapshotFuture;
      expect(snap.speedKmh, moreOrLessEquals(10.0, epsilon: 0.01));
    });
  });

  // ── Distance accuracy ──────────────────────────────────────────────────────

  group('haversine distance accuracy', () {
    test('Oslo city centre → 1 km north is approx 1000 m', () async {
      final stream = (await service.startTracking())!;
      final snapshots = <GpsSnapshot>[];
      final sub = stream.listen(snapshots.add);

      // Oslo (59.9139°N, 10.7522°E) + ~0.009° latitude ≈ 1 km
      source.emit(_pos(59.9139, 10.7522));
      source.emit(_pos(59.9229, 10.7522));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots[1].totalDistanceMetres,
          moreOrLessEquals(1000.0, epsilon: 30.0));
    });

    test('same position emits zero delta distance', () async {
      final stream = (await service.startTracking())!;
      final snapshots = <GpsSnapshot>[];
      final sub = stream.listen(snapshots.add);

      source.emit(_pos(59.9139, 10.7522));
      source.emit(_pos(59.9139, 10.7522));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots[1].totalDistanceMetres,
          moreOrLessEquals(0.0, epsilon: 0.001));
    });
  });

  // ── Stream lifecycle ───────────────────────────────────────────────────────

  group('stream lifecycle', () {
    test('stream is a broadcast stream — multiple listeners allowed', () async {
      final stream = (await service.startTracking())!;
      final results1 = <GpsSnapshot>[];
      final results2 = <GpsSnapshot>[];
      final sub1 = stream.listen(results1.add);
      final sub2 = stream.listen(results2.add);

      source.emit(_pos(59.9139, 10.7522));
      await Future<void>.delayed(Duration.zero);

      await sub1.cancel();
      await sub2.cancel();

      expect(results1, hasLength(1));
      expect(results2, hasLength(1));
    });

    test('errors from source are forwarded to stream', () async {
      final stream = (await service.startTracking())!;
      final errorFuture = stream.first.catchError((e) => const GpsSnapshot(
            speedMetresPerSecond: -1,
            segmentDistanceMetres: 0,
            totalDistanceMetres: 0,
            latitude: 0,
            longitude: 0,
          ));

      source.emitError(Exception('GPS unavailable'));

      final snap = await errorFuture;
      expect(snap.speedMetresPerSecond, -1); // sentinel from catchError
    });

    test('stopTracking can be called safely when not tracking', () async {
      await expectLater(service.stopTracking(), completes);
    });
  });
}
