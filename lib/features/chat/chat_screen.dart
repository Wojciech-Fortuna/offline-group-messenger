import 'package:flutter/material.dart';

import '../../core/messaging/tcp_message_transport.dart';
import '../../core/messaging/chat_session_controller.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chat});
  final ChatSessionController chat;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.chat.draft);
    widget.chat.addListener(_syncDraft);
  }

  void _syncDraft() {
    if (_text.text != widget.chat.draft) {
      _text.value = TextEditingValue(
        text: widget.chat.draft,
        selection: TextSelection.collapsed(offset: widget.chat.draft.length),
      );
    }
  }

  Future<void> _startNewChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new chat?'),
        content: const Text(
          'This clears this phone\'s old history, draft and unconfirmed messages. They will not be sent to the new session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start new chat'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) widget.chat.startNewChat();
  }

  @override
  void dispose() {
    widget.chat.removeListener(_syncDraft);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.chat,
    builder: (context, _) {
      final chat = widget.chat;
      final ready = chat.status == ChatStatus.ready && !chat.sessionEnded;
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
                title: Text(
                  chat.sessionEnded
                      ? 'Chat session ended'
                      : switch (chat.status) {
                          ChatStatus.ready => 'Chat connected',
                          ChatStatus.connecting => 'Connecting to chat...',
                          ChatStatus.offline => 'Chat disconnected',
                        },
                ),
                subtitle: Text(
                  chat.error ??
                      'Prototype: no end-to-end encryption. History is kept in memory only.',
                ),
                trailing: chat.sessionEnded && chat.networkConnected
                    ? TextButton(
                        onPressed: _startNewChat,
                        child: const Text('Start new chat'),
                      )
                    : chat.status == ChatStatus.offline && !chat.sessionEnded
                    ? TextButton(
                        onPressed: chat.networkConnected ? chat.retry : null,
                        child: const Text('Retry chat'),
                      )
                    : null,
              ),
              if (chat.historyWarning != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(chat.historyWarning!),
                ),
              if (!chat.networkConnected)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Rejoin the host\'s Wi-Fi group to resume chat.'),
                ),
              Expanded(
                child: messages.isEmpty
                    ? const Center(child: Text('No messages yet. Say hello!'))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final entry = messages[messages.length - 1 - index];
                          final message = entry.message;
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
                                      if (mine) ...[
                                        const SizedBox(height: 4),
                                        if (entry.delivery ==
                                            DeliveryState.confirmed)
                                          Tooltip(
                                            message:
                                                'Accepted by host; not a read receipt',
                                            child: Icon(
                                              Icons.check,
                                              size: 14,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          )
                                        else
                                          Text(
                                            entry.delivery ==
                                                    DeliveryState.pending
                                                ? 'Sending…'
                                                : 'Not confirmed',
                                          ),
                                        if (entry.delivery ==
                                            DeliveryState.failed)
                                          TextButton(
                                            onPressed: ready && !chat.sending
                                                ? () => chat.retryMessage(
                                                    '${message.senderId}:${message.id}',
                                                  )
                                                : null,
                                            child: const Text('Retry message'),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (chat.sendError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    chat.sendError!,
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
                        enabled: !chat.sending,
                        onChanged: (value) => chat.draft = value,
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
                      tooltip: chat.sending
                          ? 'Waiting for host'
                          : 'Send message',
                      onPressed: ready && !chat.sending ? chat.sendDraft : null,
                      icon: Icon(
                        chat.sending ? Icons.hourglass_top : Icons.send,
                      ),
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
