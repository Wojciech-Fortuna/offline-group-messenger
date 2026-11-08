import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio_panel.dart';

const labChannel = MethodChannel('offline_transport_lab');
void main() => runApp(const MaterialApp(home: TransportLab()));

class TransportLab extends StatefulWidget {
  const TransportLab({super.key});
  @override
  State<TransportLab> createState() => _TransportLabState();
}

class _TransportLabState extends State<TransportLab>
    with WidgetsBindingObserver {
  Timer? _poll;
  Map<dynamic, dynamic> _ble = {};
  String? _error;
  bool _busy = false;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    _refresh();
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final state = await labChannel.invokeMapMethod('bleState');
      if (mounted) setState(() => _ble = state ?? {});
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _reading = false;
    }
  }

  Future<void> _run(String method, [Map<String, dynamic>? args]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await labChannel.invokeMethod<void>(method, args);
      await _refresh();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(labChannel.invokeMethod<void>('bleStop').catchError((_) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    unawaited(labChannel.invokeMethod<void>('bleStop').catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Transport Lab')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'C1 foreground radio experiments',
          style: TextStyle(fontSize: 22),
        ),
        const Text(
          'This separate app tests transport only. A probe is not a verified contact. '
          'Keep both labs open; BLE carries random test bytes only.',
        ),
        const SizedBox(height: 20),
        Text('BLE: ${_ble['state'] ?? 'Loading'}'),
        Text('Successful probes: ${_ble['successes'] ?? 0}'),
        if (_ble['elapsedMs'] != null)
          Text('Last connect + echo: ${_ble['elapsedMs']} ms'),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : () => _run('bleAdvertise'),
          child: const Text('Advertise GATT probe'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run('bleScan'),
          child: const Text('Find lab probes'),
        ),
        for (final id in (_ble['peers'] as List? ?? []))
          ListTile(
            title: Text('$id'),
            trailing: TextButton(
              onPressed: _busy ? null : () => _run('bleProbe', {'id': id}),
              child: const Text('Test echo'),
            ),
          ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run('bleStop'),
          child: const Text('Stop BLE'),
        ),
        const AudioPanel(),
      ],
    ),
  );
}
