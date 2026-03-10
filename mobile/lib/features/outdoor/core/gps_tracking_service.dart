import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

// ─── Permission status ────────────────────────────────────────────────────────

enum GpsPermissionStatus {
  granted,
  denied,
  deniedForever,
  notDetermined,
}

// ─── Snapshot ─────────────────────────────────────────────────────────────────

/// Immutable snapshot of GPS state emitted by [GeolocatorGpsTrackingService].
class GpsSnapshot {
  const GpsSnapshot({
    required this.speedMetresPerSecond,
    required this.segmentDistanceMetres,
    required this.totalDistanceMetres,
    required this.latitude,
    required this.longitude,
  });

  final double speedMetresPerSecond;

  /// Distance accumulated since the last call to [GeolocatorGpsTrackingService.resetSegmentDistance].
  final double segmentDistanceMetres;

  /// Total distance accumulated since [GeolocatorGpsTrackingService.startTracking] was called.
  final double totalDistanceMetres;

  final double latitude;
  final double longitude;

  double get speedKmh => speedMetresPerSecond * 3.6;

  @override
  String toString() => 'GpsSnapshot('
      'speed=${speedMetresPerSecond.toStringAsFixed(2)} m/s, '
      'segment=${segmentDistanceMetres.toStringAsFixed(1)} m, '
      'total=${totalDistanceMetres.toStringAsFixed(1)} m)';
}

// ─── Position source (injectable for tests) ───────────────────────────────────

/// Abstracts geolocator calls so the service can be tested without platform plugins.
abstract class GpsPositionSource {
  Future<GpsPermissionStatus> checkPermission();
  Future<GpsPermissionStatus> requestPermission();
  Stream<Position> getPositionStream();
}

/// Production implementation backed by the `geolocator` package.
class _GeolocatorPositionSource implements GpsPositionSource {
  @override
  Future<GpsPermissionStatus> checkPermission() async {
    final perm = await Geolocator.checkPermission();
    return _map(perm);
  }

  @override
  Future<GpsPermissionStatus> requestPermission() async {
    final perm = await Geolocator.requestPermission();
    return _map(perm);
  }

  @override
  Stream<Position> getPositionStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  GpsPermissionStatus _map(LocationPermission perm) => switch (perm) {
        LocationPermission.always ||
        LocationPermission.whileInUse =>
          GpsPermissionStatus.granted,
        LocationPermission.denied => GpsPermissionStatus.denied,
        LocationPermission.deniedForever =>
          GpsPermissionStatus.deniedForever,
        LocationPermission.unableToDetermine =>
          GpsPermissionStatus.notDetermined,
      };
}

// ─── Service ──────────────────────────────────────────────────────────────────

/// Continuously tracks the user's GPS position and emits [GpsSnapshot]s.
///
/// Typical usage:
/// ```dart
/// final stream = await service.startTracking();
/// stream.listen((snap) { ... });
/// // When a new segment starts:
/// service.resetSegmentDistance();
/// // When the workout ends:
/// await service.stopTracking();
/// ```
class GeolocatorGpsTrackingService {
  GeolocatorGpsTrackingService({GpsPositionSource? positionSource})
      : _source = positionSource ?? _GeolocatorPositionSource();

  final GpsPositionSource _source;

  StreamController<GpsSnapshot>? _controller;
  Stream<GpsSnapshot>? _stream;
  StreamSubscription<Position>? _positionSub;

  Position? _lastPosition;
  double _segmentDistance = 0;
  double _totalDistance = 0;

  bool get isTracking => _stream != null;

  /// Requests permission if needed, then begins streaming [GpsSnapshot]s.
  ///
  /// Returns `null` if permission was denied; in that case no tracking starts.
  Future<Stream<GpsSnapshot>?> startTracking() async {
    if (isTracking) return _stream;

    var status = await _source.checkPermission();
    if (status == GpsPermissionStatus.notDetermined ||
        status == GpsPermissionStatus.denied) {
      status = await _source.requestPermission();
    }
    if (status != GpsPermissionStatus.granted) return null;

    _segmentDistance = 0;
    _totalDistance = 0;
    _lastPosition = null;

    _controller = StreamController<GpsSnapshot>.broadcast();
    _stream = _controller!.stream;

    _positionSub = _source.getPositionStream().listen(
      _onPosition,
      onError: (Object e, StackTrace s) => _controller?.addError(e, s),
      onDone: () => _controller?.close(),
    );

    return _stream;
  }

  /// Resets the segment-distance accumulator to zero.
  ///
  /// Call this when a new outdoor segment begins (e.g. switching from warm-up
  /// to the first work interval). Total distance is unaffected.
  void resetSegmentDistance() => _segmentDistance = 0;

  /// Stops tracking and releases resources.
  Future<void> stopTracking() async {
    await _positionSub?.cancel();
    _positionSub = null;
    await _controller?.close();
    _controller = null;
    _stream = null;
    _lastPosition = null;
  }

  void _onPosition(Position position) {
    if (_lastPosition != null) {
      final delta = _haversineMetres(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      _segmentDistance += delta;
      _totalDistance += delta;
    }
    _lastPosition = position;

    final speed = position.speed < 0 ? 0.0 : position.speed;

    _controller?.add(GpsSnapshot(
      speedMetresPerSecond: speed,
      segmentDistanceMetres: _segmentDistance,
      totalDistanceMetres: _totalDistance,
      latitude: position.latitude,
      longitude: position.longitude,
    ));
  }

  /// Haversine great-circle distance between two GPS coordinates, in metres.
  static double _haversineMetres(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0; // Earth's mean radius in metres
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final gpsTrackingServiceProvider = Provider<GeolocatorGpsTrackingService>(
  (ref) => GeolocatorGpsTrackingService(),
);
