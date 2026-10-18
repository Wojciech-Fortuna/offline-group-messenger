import 'package:flutter/material.dart';

import '../../core/messaging/tcp_message_transport.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chat, required this.retry});
  final TcpMessageTransport chat;
  final VoidCallback retry;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    final draft = _text.text;
    if (draft.trim().isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.chat.sendText(draft);
      if (mounted && _text.text == draft) _text.clear();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Host confirmation not received. Your draft is kept; check the conversation before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.chat,
    builder: (context, _) {
      final chat = widget.chat;
      final ready = chat.status == ChatStatus.ready;
      final messages = chat.messages;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Group chat'),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.people_outline),
              label: Text('${chat.participants.length}'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => ListenableBuilder(
                  listenable: chat,
                  builder: (context, _) => SafeArea(
                    child: ListView(
                      children: [
                        const ListTile(title: Text('Participants')),
                        for (final p in chat.participants)
                          ListTile(
                            title: Text(p.displayName),
                            subtitle: Text(
                              p.id == chat.selfId ? 'You' : 'Connected',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: Text(switch (chat.status) {
                  ChatStatus.ready => 'Chat connected',
                  ChatStatus.connecting => 'Connecting to chat...',
                  ChatStatus.offline => 'Chat disconnected',
                }),
                subtitle: Text(
                  chat.error ??
                      'Prototype: no end-to-end encryption. History is kept in memory only.',
                ),
                trailing: chat.status == ChatStatus.offline
                    ? TextButton(
                        onPressed: widget.retry,
                        child: const Text('Retry chat'),
                      )
                    : null,
              ),
              Expanded(
                child: messages.isEmpty
                    ? const Center(child: Text('No messages yet. Say hello!'))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[messages.length - 1 - index];
                          if (message.senderId.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(8),
                              child: Center(child: Text(message.text)),
                            );
                          }
                          final mine = message.senderId == chat.selfId;
                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 340),
                              child: Card(
                                color: mine
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mine ? 'You' : message.senderName,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      SelectableText(message.text),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        enabled: ready && !_sending,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: TcpMessageTransport.maxTextLength,
                        decoration: const InputDecoration(
                          labelText: 'Message',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _sending ? 'Waiting for host' : 'Send message',
                      onPressed: ready && !_sending ? _send : null,
                      icon: Icon(_sending ? Icons.hourglass_top : Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
