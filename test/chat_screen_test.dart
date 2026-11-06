import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_group_messenger/core/messaging/chat_session_controller.dart';
import 'package:offline_group_messenger/core/messaging/tcp_message_transport.dart';
import 'package:offline_group_messenger/core/models/chat_message.dart';
import 'package:offline_group_messenger/features/chat/chat_screen.dart';

class FakeTransport extends TcpMessageTransport {
  final events = StreamController<ChatMessage>.broadcast();
  final requests = <ChatMessage>[];
  bool failSend = false;
  int next = 0;
  @override
  String get groupId => 'g';
  @override
  Stream<ChatMessage> get incoming => events.stream;
  @override
  ChatMessage createMessage(String text) => ChatMessage(
    id: '${++next}',
    groupId: 'g',
    senderId: 'me',
    text: text.trim(),
    sentAt: DateTime(2026),
  );
  @override
  Future<void> send(ChatMessage message) async {
    requests.add(message);
    if (failSend) throw TimeoutException('Lost acknowledgement');
    events.add(
      ChatMessage(
        id: 'me:${message.id}',
        groupId: 'g',
        senderId: 'me',
        text: message.text,
        sentAt: DateTime(2026),
        sequence: int.parse(message.id),
      ),
    );
  }

  @override
  void dispose() {
    events.close();
    super.dispose();
  }
}

void main() {
  testWidgets(
    'confirmed messages, failed retry keeps ID, draft survives navigation',
    (tester) async {
      final transport = FakeTransport()
        ..status = ChatStatus.ready
        ..selfId = 'me';
      final chat = ChatSessionController(transport: transport);
      addTearDown(chat.dispose);
      Future<void> open() =>
          tester.pumpWidget(MaterialApp(home: ChatScreen(chat: chat)));
      await open();
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Host confirmed'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      transport.failSend = true;
      await tester.enterText(find.byType(TextField), 'Keep draft');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Failed / unconfirmed'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep draft',
      );
      final request = transport.requests.last.id;

      await tester.pumpWidget(const SizedBox());
      await open();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep draft',
      );
      transport.failSend = false;
      await tester.tap(find.text('Retry message'));
      await tester.pumpAndSettle();
      expect(transport.requests.last.id, request);
      expect(find.text('Host confirmed'), findsNWidgets(2));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      await transport.close();
      await tester.pumpAndSettle();
      expect(find.text('Chat disconnected'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Offline draft');
      expect(chat.draft, 'Offline draft');
    },
  );
}
