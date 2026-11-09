import 'package:flutter/material.dart';
import '../../core/calling/call_controller.dart';

class CallScreen extends StatelessWidget {
  const CallScreen({super.key, required this.calls});
  final CallController calls;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: calls,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Voice call')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.account_circle, size: 88),
          Text(
            calls.contactName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            switch (calls.state) {
              'outgoing' => 'Calling…',
              'ringing' => 'Ringing…',
              'incoming' => 'Incoming voice call',
              'connecting' => 'Connecting audio…',
              'active' => 'Connected',
              'reconnecting' => 'Reconnecting…',
              'ended' => 'Call ended',
              _ => 'No active call',
            },
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (calls.connectedAt != null)
            Text(
              '${calls.duration ~/ 60}:${(calls.duration % 60).toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
            ),
          if (calls.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(calls.error!, textAlign: TextAlign.center),
            ),
          const SizedBox(height: 24),
          if (calls.state == 'incoming')
            FilledButton.icon(
              onPressed: calls.answer,
              icon: const Icon(Icons.call),
              label: const Text('Answer'),
            ),
          if (calls.state == 'active' || calls.state == 'reconnecting') ...[
            OutlinedButton.icon(
              onPressed: calls.toggleMute,
              icon: Icon(calls.muted ? Icons.mic_off : Icons.mic),
              label: Text(calls.muted ? 'Unmute' : 'Mute'),
            ),
            OutlinedButton.icon(
              onPressed: calls.toggleSpeaker,
              icon: const Icon(Icons.volume_up),
              label: Text(calls.speaker ? 'Use earpiece' : 'Use speaker'),
            ),
          ],
          if (calls.hasCall)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => calls.end(
                calls.state == 'incoming' ? 'Call declined' : 'Call ended',
                kind: calls.state == 'incoming'
                    ? 'declined'
                    : ['outgoing', 'ringing'].contains(calls.state)
                    ? 'cancel'
                    : 'end',
              ),
              icon: const Icon(Icons.call_end),
              label: Text(calls.state == 'incoming' ? 'Decline' : 'Hang up'),
            ),
          if (calls.hasCall) ...[
            const SizedBox(height: 16),
            const Text(
              'Keep Messenger open. Leaving the app ends this call. You can return to chat while talking.',
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to Messenger'),
            ),
          ] else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
        ],
      ),
    ),
  );
}
