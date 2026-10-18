import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_group_messenger/core/messaging/tcp_message_transport.dart';
import 'package:offline_group_messenger/core/models/chat_message.dart';
import 'package:offline_group_messenger/features/chat/chat_screen.dart';

class FakeChat extends TcpMessageTransport {
  final sent = <String>[];
  bool failSend = false;
  @override
  List<ChatMessage> get messages => [
    for (final text in sent)
      ChatMessage(
        id: text,
        groupId: 'g',
        senderId: 'me',
        text: text,
        sentAt: DateTime(2026),
        senderName: 'Me',
      ),
  ];
  @override
  Future<void> sendText(String text) async {
    if (failSend) throw StateError('Disconnected');
    sent.add(text);
    notifyListeners();
  }
}

void main() {
  testWidgets('send, preserve failed draft, disable on disconnect and retry', (
    tester,
  ) async {
    final chat = FakeChat()
      ..status = ChatStatus.ready
      ..selfId = 'me';
    addTearDown(chat.dispose);
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(chat: chat, retry: () => retries++),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    chat.failSend = true;
    await tester.enterText(find.byType(TextField), 'Keep draft');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep draft',
    );
    expect(
      find.textContaining('Host confirmation not received'),
      findsOneWidget,
    );
    await chat.close();
    await tester.pumpAndSettle();
    expect(find.text('Chat disconnected'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Retry chat'));
    expect(retries, 1);
  });
}
