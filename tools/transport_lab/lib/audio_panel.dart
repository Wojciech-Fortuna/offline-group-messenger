import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio_lab.dart';

class AudioPanel extends StatefulWidget {
  const AudioPanel({super.key});
  @override
  State<AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends State<AudioPanel> with WidgetsBindingObserver {
  final lab = AudioLab();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    lab.addListener(_update);
  }

  void _update() {
    if (mounted) setState(() {});
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lab operation failed; stop and retry')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(lab.disconnect());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    lab.removeListener(_update);
    lab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(height: 36),
      const Text('Local audio experiment', style: TextStyle(fontSize: 22)),
      const Text(
        'Start local signaling on the Wi-Fi Direct host first, then its clients. '
        'Lab signaling is unauthenticated: use test audio only. Enable the microphone on both phones '
        'to arm a test; it stays off until you press the button. Backgrounding stops audio.',
      ),
      Text(lab.state),
      if (lab.error != null)
        Text(lab.error!, style: const TextStyle(color: Colors.red)),
      if (lab.id != null)
        Text(
          'This lab: peer ${lab.id}; ${lab.network!.isHost ? 'host' : 'client'}',
        ),
      FilledButton(
        onPressed: busy || lab.id != null ? null : () => run(lab.connect),
        child: const Text('Connect local signaling'),
      ),
      OutlinedButton(
        onPressed: busy || lab.id == null || lab.micEnabled || lab.capturing
            ? null
            : () => run(lab.enableMicrophone),
        child: Text(
          lab.micEnabled ? 'Microphone ON' : 'Enable microphone for test',
        ),
      ),
      for (final peer in lab.peers)
        ListTile(
          title: Text('Peer $peer'),
          trailing: TextButton(
            onPressed: busy || !lab.micEnabled || lab.hasCall
                ? null
                : () => run(() => lab.startAudio(peer)),
            child: const Text('Start audio test'),
          ),
        ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: lab.micEnabled ? lab.toggleMute : null,
            child: Text(lab.muted ? 'Unmute' : 'Mute'),
          ),
          OutlinedButton(
            onPressed: lab.micEnabled ? () => run(lab.toggleSpeaker) : null,
            child: Text(lab.speaker ? 'Use earpiece' : 'Use speaker'),
          ),
          OutlinedButton(
            onPressed: () => run(lab.stopAudio),
            child: const Text('Stop audio / microphone'),
          ),
        ],
      ),
      if (lab.samples.isNotEmpty)
        Text('Latest stats: ${jsonEncode(lab.samples.last)}'),
      const Text(
        'Stats contain counters, jitter and RTT, not a one-way audio latency measurement.',
      ),
      TextButton(
        onPressed: lab.samples.isEmpty
            ? null
            : () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: jsonEncode({'lab': 1, 'samples': lab.samples}),
                  ),
                );
              },
        child: const Text('Copy sanitized test stats'),
      ),
      TextButton(
        onPressed: () => run(lab.disconnect),
        child: const Text('Disconnect lab signaling'),
      ),
    ],
  );
}
