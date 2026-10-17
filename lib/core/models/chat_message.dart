/// Shared application model. Wire encoding will be specified before transport.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.text,
    required this.sentAt,
  });

  final String id;
  final String groupId;
  final String senderId;
  final String text;
  final DateTime sentAt;
}
