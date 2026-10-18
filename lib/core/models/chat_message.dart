/// A host-accepted message. IDs and timestamps are scoped to a chat session.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.senderName = '',
  });

  final String id;
  final String groupId;
  final String senderId;
  final String text;
  final DateTime sentAt;
  final String senderName;
}
