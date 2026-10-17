import '../models/chat_message.dart';

/// Messaging over an existing network, separate from native network formation.
/// A Dart TCP implementation can later serve both Android and iOS.
abstract interface class MessageTransport {
  Stream<ChatMessage> get incoming;

  Future<void> startHost({required int port});
  Future<void> connect({required String host, required int port});
  Future<void> send(ChatMessage message);
  Future<void> close();
}
