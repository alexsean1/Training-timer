import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../core/heart_rate_service.dart';

class HrConnectScreen extends ConsumerStatefulWidget {
  const HrConnectScreen({super.key});

  @override
  ConsumerState<HrConnectScreen> createState() => _HrConnectScreenState();
}

class _HrConnectScreenState extends ConsumerState<HrConnectScreen> {
  late final HeartRateService _service;

  HrConnectionStatus _status = HrConnectionStatus.idle;
  int? _bpm;
  List<HrDevice> _devices = [];

  late final StreamSubscription<HrConnectionStatus> _statusSub;
  late final StreamSubscription<int> _bpmSub;
  late final StreamSubscription<List<HrDevice>> _devicesSub;

  @override
  void initState() {
    super.initState();
    _service = ref.read(heartRateServiceProvider);

    // Sync initial state (service may already be connected from a prior visit).
    _status = _service.status;
    _bpm = _service.currentBpm;

    _statusSub = _service.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _bpmSub = _service.bpmStream.listen((b) {
      if (mounted) setState(() => _bpm = b);
    });
    _devicesSub = _service.scanResultsStream.listen((d) {
      if (mounted) setState(() => _devices = d);
    });

    // Auto-start scanning unless already connected or scanning.
    if (_status == HrConnectionStatus.idle ||
        _status == HrConnectionStatus.error) {
      _service.startScan();
    }
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _bpmSub.cancel();
    _devicesSub.cancel();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _rescan() async {
    setState(() => _devices = []);
    await _service.startScan();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heart Rate Monitor'),
        centerTitle: false,
        actions: [
          if (_status == HrConnectionStatus.connected)
            TextButton(
              onPressed: _service.disconnect,
              child: const Text('Disconnect'),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusBanner(status: _status, bpm: _bpm),
          if (_status == HrConnectionStatus.connected)
            const _ConnectedBody()
          else
            Expanded(
              child: _ScanBody(
                status: _status,
                devices: _devices,
                onConnect: _service.connect,
                onRescan: _rescan,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Status banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.bpm});

  final HrConnectionStatus status;
  final int? bpm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon, label) = switch (status) {
      HrConnectionStatus.idle => (
          theme.colorScheme.surfaceContainerHighest,
          Icons.bluetooth_disabled,
          'Not connected',
        ),
      HrConnectionStatus.scanning => (
          theme.colorScheme.primaryContainer,
          Icons.bluetooth_searching,
          'Searching for heart rate monitors…',
        ),
      HrConnectionStatus.connecting => (
          theme.colorScheme.primaryContainer,
          Icons.bluetooth_connected,
          'Connecting…',
        ),
      HrConnectionStatus.connected => (
          theme.colorScheme.tertiaryContainer,
          Icons.favorite,
          bpm != null ? '$bpm BPM' : 'Connected',
        ),
      HrConnectionStatus.reconnecting => (
          theme.colorScheme.secondaryContainer,
          Icons.bluetooth_searching,
          'Reconnecting…',
        ),
      HrConnectionStatus.error => (
          theme.colorScheme.errorContainer,
          Icons.error_outline,
          'Connection failed — tap Scan Again',
        ),
    };

    final isScanning = status == HrConnectionStatus.scanning ||
        status == HrConnectionStatus.reconnecting;
    final isConnected = status == HrConnectionStatus.connected;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          if (isScanning)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Icon(
              icon,
              color: isConnected
                  ? AppColors.danger
                  : theme.colorScheme.onSurface,
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight:
                    isConnected ? FontWeight.bold : FontWeight.normal,
                fontSize: isConnected && bpm != null ? 28 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Connected body ────────────────────────────────────────────────────────────

class _ConnectedBody extends StatelessWidget {
  const _ConnectedBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite, size: 96, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(
              'Heart rate monitor active',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'The connection will stay active while you use the app.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Scan body ─────────────────────────────────────────────────────────────────

class _ScanBody extends StatelessWidget {
  const _ScanBody({
    required this.status,
    required this.devices,
    required this.onConnect,
    required this.onRescan,
  });

  final HrConnectionStatus status;
  final List<HrDevice> devices;
  final void Function(HrDevice) onConnect;
  final VoidCallback onRescan;

  bool get _isScanning =>
      status == HrConnectionStatus.scanning ||
      status == HrConnectionStatus.connecting ||
      status == HrConnectionStatus.reconnecting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (devices.isEmpty && _isScanning) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text(
            'Make sure your heart rate monitor is turned on and nearby.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        if (devices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Available devices',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: devices.length,
            itemBuilder: (context, i) => _DeviceTile(
              device: devices[i],
              onConnect: onConnect,
              isConnecting: status == HrConnectionStatus.connecting,
            ),
          ),
        ),
        if (!_isScanning ||
            status == HrConnectionStatus.error ||
            status == HrConnectionStatus.idle)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: FilledButton.icon(
              onPressed: onRescan,
              icon: const Icon(Icons.refresh),
              label: const Text('Scan Again'),
            ),
          ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.onConnect,
    required this.isConnecting,
  });

  final HrDevice device;
  final void Function(HrDevice) onConnect;
  final bool isConnecting;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.monitor_heart_outlined),
      title: Text(device.name),
      subtitle: Text(device.id, style: const TextStyle(fontSize: 11)),
      trailing: isConnecting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : FilledButton.tonal(
              onPressed: () => onConnect(device),
              child: const Text('Connect'),
            ),
    );
  }
}
