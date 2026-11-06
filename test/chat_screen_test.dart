import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_group_messenger/core/messaging/chat_session_controller.dart';
import 'package:offline_group_messenger/core/messaging/tcp_message_transport.dart';
import 'package:offline_group_messenger/core/models/chat_message.dart';
import 'package:offline_group_messenger/core/models/message_delivery.dart';
import 'package:offline_group_messenger/core/models/participant.dart';
import 'package:offline_group_messenger/features/chat/chat_screen.dart';

class FakeTransport extends TcpMessageTransport {
  final events = StreamController<ChatMessage>.broadcast();
  final requests = <ChatMessage>[];
  bool failSend = false;
  int next = 0;
  MessageDelivery? delivery;
  @override
  MessageDelivery? deliveryFor(String messageId) => delivery;
  void updateDelivery(Set<String> received) {
    delivery = MessageDelivery(
      sequence: 1,
      recipients: const [
        Participant(id: 'bob', displayName: 'Bob'),
        Participant(id: 'carol', displayName: 'Carol'),
      ],
      received: received,
    );
    notifyListeners();
  }

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
  testWidgets('one, two and three checks expose live recipient details', (
    tester,
  ) async {
    final transport = FakeTransport()
      ..status = ChatStatus.ready
      ..selfId = 'me';
    final chat = ChatSessionController(transport: transport);
    addTearDown(chat.dispose);
    await tester.pumpWidget(MaterialApp(home: ChatScreen(chat: chat)));
    await tester.enterText(find.byType(TextField), 'Check delivery');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    transport.updateDelivery({});
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Accepted by host; not a read receipt'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
    transport.updateDelivery({'bob'});
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Someone else received it; not a read receipt'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNWidgets(2));
    await tester.tap(
      find.byTooltip('Someone else received it; not a read receipt'),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 other phones received it'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('Awaiting confirmation'), findsOneWidget);
    transport.updateDelivery({'bob', 'carol'});
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 other phones received it'), findsOneWidget);
    expect(find.text('Awaiting confirmation'), findsNothing);
    Navigator.of(tester.element(find.text('Message delivery'))).pop();
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Everyone received it; not a read receipt'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNWidgets(3));
  });

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
      expect(find.text('Host confirmed'), findsNothing);
      expect(
        find.byTooltip('Accepted by host; not a read receipt'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      transport.failSend = true;
      await tester.enterText(find.byType(TextField), 'Keep draft');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Not confirmed'), findsOneWidget);
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
      expect(
        find.byTooltip('Accepted by host; not a read receipt'),
        findsNWidgets(2),
      );
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
