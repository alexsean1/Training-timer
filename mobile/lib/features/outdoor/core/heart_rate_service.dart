import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Value types ──────────────────────────────────────────────────────────────

/// A BLE device that advertises the heart rate service.
class HrDevice {
  const HrDevice({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is HrDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'HrDevice($name, $id)';
}

/// A single BPM reading with a wall-clock timestamp.
class HrDataPoint {
  const HrDataPoint({required this.timestamp, required this.bpm});

  final DateTime timestamp;
  final int bpm;
}

// ─── Connection status ────────────────────────────────────────────────────────

enum HrConnectionStatus {
  idle,
  scanning,
  connecting,
  connected,
  reconnecting,
  error,
}

// ─── Bluetooth source (injectable for tests) ──────────────────────────────────

/// Abstracts flutter_blue_plus so [HeartRateService] can be tested without a
/// real BLE stack.
abstract class HrBluetoothSource {
  /// Emits updated lists of discovered HR-capable devices while a scan is
  /// active.
  Stream<List<HrDevice>> get scanResults;

  /// Starts a BLE scan for heart rate monitors.
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)});

  /// Stops an active scan.
  Future<void> stopScan();

  /// Connects to [device], discovers the heart rate service, enables
  /// characteristic notifications, and returns a stream of BPM values.
  ///
  /// Throws if the device cannot be reached or does not expose a heart rate
  /// measurement characteristic.
  Future<Stream<int>> connectToDevice(HrDevice device);

  /// Disconnects from [device].
  Future<void> disconnectDevice(HrDevice device);

  /// Emits `true` while [device] is connected, `false` when it drops.
  Stream<bool> isConnected(HrDevice device);
}

// ─── Production implementation ────────────────────────────────────────────────

class _FlutterBluePlusSource implements HrBluetoothSource {
  static final _hrServiceGuid = Guid('180D');
  static final _hrMeasurementGuid = Guid('2A37');

  final _knownDevices = <String, BluetoothDevice>{};

  @override
  Stream<List<HrDevice>> get scanResults =>
      FlutterBluePlus.onScanResults.map((results) {
        for (final r in results) {
          _knownDevices[r.device.remoteId.str] = r.device;
        }
        return results
            .where((r) => r.device.platformName.isNotEmpty)
            .map((r) => HrDevice(
                  id: r.device.remoteId.str,
                  name: r.device.platformName,
                ))
            .toList();
      });

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
  }) =>
      FlutterBluePlus.startScan(
        timeout: timeout,
        withServices: [_hrServiceGuid],
      );

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<Stream<int>> connectToDevice(HrDevice device) async {
    final bt = _knownDevices[device.id] ??
        BluetoothDevice(remoteId: DeviceIdentifier(device.id));

    await bt.connect(
      autoConnect: false,
      timeout: const Duration(seconds: 10),
    );

    final services = await bt.discoverServices();

    BluetoothCharacteristic? hrChar;
    outer:
    for (final svc in services) {
      if (svc.serviceUuid == _hrServiceGuid) {
        for (final c in svc.characteristics) {
          if (c.characteristicUuid == _hrMeasurementGuid) {
            hrChar = c;
            break outer;
          }
        }
      }
    }

    if (hrChar == null) {
      await bt.disconnect();
      throw StateError(
          'Heart rate characteristic not found on "${device.name}"');
    }

    await hrChar.setNotifyValue(true);
    return hrChar.onValueReceived
        .map(_parseBpm)
        .where((bpm) => bpm > 0);
  }

  @override
  Future<void> disconnectDevice(HrDevice device) async {
    await _knownDevices[device.id]?.disconnect();
  }

  @override
  Stream<bool> isConnected(HrDevice device) {
    final bt = _knownDevices[device.id];
    if (bt == null) return Stream.value(false);
    return bt.connectionState
        .map((s) => s == BluetoothConnectionState.connected);
  }

  /// Parses a Heart Rate Measurement characteristic value (0x2A37).
  ///
  /// Flags byte bit 0: 0 → 8-bit BPM in byte 1, 1 → 16-bit BPM in bytes 1-2.
  static int _parseBpm(List<int> data) {
    if (data.isEmpty) return 0;
    final flags = data[0];
    if ((flags & 0x01) != 0 && data.length >= 3) {
      return data[1] | (data[2] << 8); // 16-bit format
    }
    return data.length >= 2 ? data[1] : 0; // 8-bit format
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

/// Manages Bluetooth heart rate monitor scanning, connection, streaming, and
/// automatic reconnection.
///
/// The service is long-lived (see [heartRateServiceProvider]) so the HR
/// connection persists while the user navigates between screens.
class HeartRateService {
  HeartRateService({HrBluetoothSource? source})
      : _source = source ?? _FlutterBluePlusSource();

  final HrBluetoothSource _source;

  // ── State ──────────────────────────────────────────────────────────────────

  HrConnectionStatus _status = HrConnectionStatus.idle;
  HrConnectionStatus get status => _status;

  HrDevice? _connectedDevice;
  HrDevice? get connectedDevice => _connectedDevice;

  int? _currentBpm;
  int? get currentBpm => _currentBpm;

  final List<HrDataPoint> _dataPoints = [];
  List<HrDataPoint> get dataPoints => List.unmodifiable(_dataPoints);

  // ── Streams ────────────────────────────────────────────────────────────────

  final _statusCtrl =
      StreamController<HrConnectionStatus>.broadcast();
  final _bpmCtrl = StreamController<int>.broadcast();
  final _devicesCtrl = StreamController<List<HrDevice>>.broadcast();

  Stream<HrConnectionStatus> get statusStream => _statusCtrl.stream;
  Stream<int> get bpmStream => _bpmCtrl.stream;
  Stream<List<HrDevice>> get scanResultsStream => _devicesCtrl.stream;

  // ── Subscriptions ──────────────────────────────────────────────────────────

  StreamSubscription<List<HrDevice>>? _scanSub;
  StreamSubscription<int>? _bpmSub;
  StreamSubscription<bool>? _connectionSub;

  static const _maxReconnectAttempts = 3;
  int _reconnectAttempts = 0;
  bool _disposed = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    _setStatus(HrConnectionStatus.scanning);
    await _scanSub?.cancel();
    _scanSub = _source.scanResults.listen((devices) {
      if (!_devicesCtrl.isClosed) _devicesCtrl.add(devices);
    });
    await _source.startScan();
  }

  Future<void> stopScan() async {
    await _source.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    if (_status == HrConnectionStatus.scanning) {
      _setStatus(HrConnectionStatus.idle);
    }
  }

  /// Stops any active scan then connects to [device].
  Future<void> connect(HrDevice device) async {
    await stopScan();
    _reconnectAttempts = 0;
    _setStatus(HrConnectionStatus.connecting);
    await _doConnect(device);
  }

  Future<void> disconnect() async {
    final device = _connectedDevice;
    _clearConnectionState();
    if (device != null) await _source.disconnectDevice(device);
    _setStatus(HrConnectionStatus.idle);
  }

  /// Average BPM over the last [window] of recorded data points.
  ///
  /// Returns `null` when no data points fall inside the window.
  double? averageBpm(Duration window) {
    final cutoff = DateTime.now().subtract(window);
    final recent =
        _dataPoints.where((p) => p.timestamp.isAfter(cutoff)).toList();
    if (recent.isEmpty) return null;
    final sum = recent.fold<int>(0, (s, p) => s + p.bpm);
    return sum / recent.length;
  }

  void clearDataPoints() => _dataPoints.clear();

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _scanSub?.cancel();
    await _statusCtrl.close();
    await _bpmCtrl.close();
    await _devicesCtrl.close();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _setStatus(HrConnectionStatus s) {
    _status = s;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  Future<void> _doConnect(HrDevice device) async {
    try {
      final bpmStream = await _source.connectToDevice(device);
      _connectedDevice = device;
      _setStatus(HrConnectionStatus.connected);

      await _bpmSub?.cancel();
      _bpmSub = bpmStream.listen((bpm) {
        _currentBpm = bpm;
        _dataPoints.add(HrDataPoint(timestamp: DateTime.now(), bpm: bpm));
        if (!_bpmCtrl.isClosed) _bpmCtrl.add(bpm);
      });

      await _connectionSub?.cancel();
      _connectionSub = _source.isConnected(device).listen((connected) {
        if (!connected && _status == HrConnectionStatus.connected) {
          _handleUnexpectedDisconnect(device);
        }
      });
    } catch (_) {
      _setStatus(HrConnectionStatus.error);
    }
  }

  void _handleUnexpectedDisconnect(HrDevice device) {
    _bpmSub?.cancel();
    _bpmSub = null;
    _currentBpm = null;

    if (_reconnectAttempts < _maxReconnectAttempts && !_disposed) {
      _reconnectAttempts++;
      _setStatus(HrConnectionStatus.reconnecting);
      Future.delayed(const Duration(seconds: 2), () {
        if (!_disposed && _status == HrConnectionStatus.reconnecting) {
          _doConnect(device);
        }
      });
    } else {
      _connectedDevice = null;
      _setStatus(HrConnectionStatus.idle);
    }
  }

  void _clearConnectionState() {
    _connectedDevice = null;
    _currentBpm = null;
    _bpmSub?.cancel();
    _bpmSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    _reconnectAttempts = 0;
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

/// Long-lived provider — the service is NOT auto-disposed so the HR connection
/// persists while the user navigates between screens.
final heartRateServiceProvider = Provider<HeartRateService>((ref) {
  final service = HeartRateService();
  ref.onDispose(service.dispose);
  return service;
});
