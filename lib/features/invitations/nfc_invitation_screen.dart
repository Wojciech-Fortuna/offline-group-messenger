import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offline_connectivity/offline_connectivity.dart';

/// Explicit foreground-only NFC session. Returning a payload never joins directly.
class NfcInvitationScreen extends StatefulWidget {
  const NfcInvitationScreen({
    super.key,
    required this.connectivity,
    required this.sharing,
  });
  final OfflineConnectivity connectivity;
  final bool sharing;

  @override
  State<NfcInvitationScreen> createState() => _NfcInvitationScreenState();
}

class _NfcInvitationScreenState extends State<NfcInvitationScreen>
    with WidgetsBindingObserver {
  bool _active = false;
  bool _starting = false;
  bool _foreground = true;
  bool _ended = false;
  String? _error;
  int _generation = 0;
  Timer? _expiry;
  StreamSubscription<GroupConnectionState>? _connection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.sharing) {
      _connection = widget.connectivity.states.listen(
        (state) {
          if (state.status != GroupStatus.connected || !state.isHost) {
            _stop(
              'The host group is no longer available. Return and create a group.',
            );
          }
        },
        onError: (Object _) =>
            _stop('Connection updates stopped. Return and retry.'),
      );
    }
    _start();
  }

  Future<void> _start() async {
    final token = ++_generation;
    setState(() {
      _starting = true;
      _active = false;
      _error = null;
    });
    try {
      if (widget.sharing) {
        await widget.connectivity.startNfcSharing();
        if (!mounted || token != _generation) return;
        setState(() {
          _starting = false;
          _active = true;
        });
        _expiry = Timer(
          const Duration(seconds: 60),
          () => _stop('Sharing expired. Enable it again to invite someone.'),
        );
      } else {
        setState(() {
          _starting = false;
          _active = true;
        });
        final invitation = await widget.connectivity.readNfcInvitation();
        if (!mounted || token != _generation) return;
        // Native reading has already stopped. Home owns the confirmation dialog.
        Navigator.of(context).pop(invitation);
      }
    } on PlatformException catch (error) {
      if (mounted && token == _generation) {
        setState(() {
          _starting = false;
          _active = false;
          _error = error.message ?? 'NFC is unavailable. Use QR instead.';
        });
      }
    } catch (_) {
      if (mounted && token == _generation) {
        setState(() {
          _starting = false;
          _active = false;
          _error = 'Not a supported NFC invitation. Retry or use QR.';
        });
      }
    }
  }

  Future<void> _stopNative() async {
    try {
      await widget.connectivity.stopNfc();
    } catch (_) {
      /* Native lifecycle also revokes access. */
    }
  }

  void _stop(String message) {
    if (_ended) return;
    _generation++;
    _expiry?.cancel();
    unawaited(_stopNative());
    if (mounted) {
      setState(() {
        _active = false;
        _starting = false;
        _error = message;
      });
    }
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _generation++;
    _expiry?.cancel();
    unawaited(_stopNative());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stop(
        'NFC stopped when the app lost focus. Retry with both phones unlocked.',
      );
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _end();
    WidgetsBinding.instance.removeObserver(this);
    _connection?.cancel();
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<GroupInvitation>(
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) _end();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.sharing ? 'Share via NFC' : 'Join via NFC'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.nfc, size: 80),
            const SizedBox(height: 24),
            Text(
              widget.sharing ? 'Invite a nearby phone' : 'Tap the host phone',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              widget.sharing
                  ? 'On the other phone, open Join via NFC. Hold the backs of the phones together near their NFC antennas. Keep both phones unlocked.'
                  : 'Ask the host to open Share via NFC. Hold the backs of the phones together near their NFC antennas until the invitation appears.',
            ),
            const SizedBox(height: 16),
            if (_starting) const Text('Preparing NFC...'),
            if (_active)
              Text(
                widget.sharing
                    ? 'Sharing enabled for up to 60 seconds.'
                    : 'Waiting for an invitation (up to 30 seconds)...',
              ),
            if (widget.sharing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'This shares the group Wi-Fi password with nearby NFC readers. Only enable it when inviting someone you trust.',
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            if (!_active && !_starting)
              FilledButton(
                onPressed: _foreground ? _start : null,
                child: const Text('Retry NFC'),
              ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Stop and go back'),
            ),
            const SizedBox(height: 12),
            const Text(
              'NFC disabled? Enable it in system settings, return here and retry. You can also go back and use QR instead.',
            ),
          ],
        ),
      ),
    ),
  );
}
