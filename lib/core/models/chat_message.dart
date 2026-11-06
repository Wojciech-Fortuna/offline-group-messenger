/// A host-accepted message. IDs and timestamps are scoped to a chat session.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.senderName = '',
    this.sequence = 0,
  });

  final String id;
  final String groupId;
  final String senderId;
  final String text;
  final DateTime sentAt;
  final String senderName;

  /// Host ordering cursor; zero for local notices and unsent messages.
  final int sequence;
}
