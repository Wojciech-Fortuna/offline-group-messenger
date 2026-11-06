import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_group_messenger/core/messaging/chat_session_controller.dart';
import 'package:offline_group_messenger/core/messaging/tcp_message_transport.dart';
import 'package:offline_group_messenger/core/models/chat_message.dart';

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for recovery');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

List<ChatMessage> texts(TcpMessageTransport chat) =>
    chat.messages.where((m) => m.sequence > 0).toList();

/// Cuts the connection after the host accepts a send, before its sender sees it.
class LostConfirmationProxy {
  LostConfirmationProxy(this.server);
  final ServerSocket server;
  final sockets = <Socket>[];
  final accepted = Completer<void>();

  static Future<LostConfirmationProxy> start(int hostPort) async {
    final proxy = LostConfirmationProxy(
      await ServerSocket.bind('127.0.0.1', 0),
    );
    proxy.server.listen((client) async {
      final host = await Socket.connect('127.0.0.1', hostPort);
      proxy.sockets.addAll([client, host]);
      client.listen(
        host.add,
        onError: (Object _) => host.destroy(),
        onDone: host.destroy,
      );
      host
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final frame = jsonDecode(line) as Map<String, dynamic>;
              if (frame['type'] == 'message') {
                if (!proxy.accepted.isCompleted) proxy.accepted.complete();
                client.destroy();
                host.destroy();
              } else {
                client.add(utf8.encode('$line\n'));
              }
            },
            onError: (Object _) => client.destroy(),
            onDone: client.destroy,
          );
    });
    return proxy;
  }

  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  }
}

void main() {
  late TcpMessageTransport host;
  late TcpMessageTransport alice;
  late TcpMessageTransport bob;
  setUp(() async {
    host = TcpMessageTransport()..displayName = 'Host';
    alice = TcpMessageTransport()..displayName = 'Alice';
    bob = TcpMessageTransport()..displayName = 'Bob';
    await host.startHost(port: 0, address: '127.0.0.1');
  });
  tearDown(() {
    alice.dispose();
    bob.dispose();
    host.dispose();
  });
  Future<void> join(TcpMessageTransport client, {int? port}) async {
    await client.connect(host: '127.0.0.1', port: port ?? host.listeningPort!);
    await until(() => client.status == ChatStatus.ready);
  }

  test(
    'three phones resume identity and replay only missed messages in order',
    () async {
      await join(alice);
      await join(bob);
      await alice.sendText('Before interruption');
      final identity = alice.selfId;
      final group = alice.groupId;
      await alice.close();
      await until(() => host.participants.length == 2);
      expect(texts(alice).single.text, 'Before interruption');
      await host.sendText('Missed one');
      await bob.sendText('Missed two');
      await join(alice);
      expect(alice.selfId, identity);
      expect(alice.groupId, group);
      expect(texts(alice).map((m) => m.text), [
        'Before interruption',
        'Missed one',
        'Missed two',
      ]);
      expect(texts(alice).map((m) => m.sequence), [1, 2, 3]);
      await alice.sendText('Returned');
      await until(() => texts(bob).length == 4);
      expect(texts(alice).map((m) => m.id), texts(host).map((m) => m.id));
      expect(host.participants.map((p) => p.id).toSet().length, 3);
      expect(alice.historyWarning, isNull);
    },
  );

  test(
    'lost confirmation is recovered and retry re-acks without rebroadcast',
    () async {
      await join(bob);
      final proxy = await LostConfirmationProxy.start(host.listeningPort!);
      addTearDown(proxy.close);
      await join(alice, port: proxy.server.port);
      final request = alice.createMessage('Accepted but confirmation lost');
      await expectLater(alice.send(request), throwsStateError);
      await proxy.accepted.future;
      await until(() => texts(bob).length == 1);
      expect(texts(alice), isEmpty);
      await join(alice);
      expect(texts(alice).single.text, request.text);
      await alice.send(request).timeout(const Duration(seconds: 2));
      await alice.send(request).timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (final chat in [host, alice, bob]) {
        expect(texts(chat).length, 1);
        expect(chat.status, ChatStatus.ready);
      }
    },
  );

  test(
    'session controller reconciles uncertain outbox and keeps edited draft',
    () async {
      final client = TcpMessageTransport()..displayName = 'Alice';
      final session = ChatSessionController(transport: client);
      addTearDown(session.dispose);
      final proxy = await LostConfirmationProxy.start(host.listeningPort!);
      addTearDown(proxy.close);
      await join(client, port: proxy.server.port);
      session.draft = 'Uncertain';
      await session.sendDraft();
      expect(session.messages.last.delivery, DeliveryState.failed);
      expect(session.draft, 'Uncertain');
      session.draft = 'A different draft';
      await join(client);
      await until(
        () => session.messages.any(
          (m) =>
              m.message.text == 'Uncertain' &&
              m.delivery == DeliveryState.confirmed,
        ),
      );
      expect(
        session.messages.where((m) => m.message.text == 'Uncertain').length,
        1,
      );
      expect(session.draft, 'A different draft');
      expect(session.sendError, isNull);
    },
  );

  test(
    'same request with different text is rejected without losing connection',
    () async {
      await join(alice);
      final request = alice.createMessage('Original');
      await alice.send(request);
      final changed = ChatMessage(
        id: request.id,
        groupId: request.groupId,
        senderId: request.senderId,
        text: 'Changed',
        sentAt: request.sentAt,
      );
      await expectLater(alice.send(changed), throwsStateError);
      expect(texts(host).single.text, 'Original');
      expect(alice.status, ChatStatus.ready);
    },
  );

  test(
    'bounded replay reports a gap and retains only the most recent history',
    () async {
      await join(alice);
      await alice.close();
      await until(() => host.participants.length == 1);
      for (var i = 1; i <= TcpMessageTransport.historyLimit + 5; i++) {
        await host.sendText('Message $i');
      }
      await join(alice);
      expect(texts(alice).length, TcpMessageTransport.historyLimit);
      expect(texts(alice).first.sequence, 6);
      expect(texts(alice).last.sequence, 505);
      expect(alice.historyWarning, contains('no longer available'));
      await alice.sendText('After gap');
      expect(texts(alice).last.sequence, 506);
    },
  );

  test(
    'evicted acceptance cannot turn an old retry into a new message',
    () async {
      await join(alice);
      final old = alice.createMessage('Old request');
      await alice.send(old);
      await alice.close();
      await until(() => host.participants.length == 1);
      for (var i = 0; i < TcpMessageTransport.acceptanceLimit; i++) {
        await host.sendText('Advance $i');
      }
      await join(alice);
      final lastSequence = texts(host).last.sequence;
      await expectLater(alice.send(old), throwsStateError);
      expect(texts(host).last.sequence, lastSequence);
      expect(alice.status, ChatStatus.ready);
      await alice.sendText('New request');
      expect(texts(host).last.sequence, lastSequence + 1);
    },
  );

  test(
    'host restart refuses resume and requires an explicit new session',
    () async {
      await join(alice);
      final old = alice.createMessage('Old session');
      await alice.send(old);
      final previousGroup = alice.groupId;
      await alice.close();
      await host.close();
      await host.startHost(port: 0, address: '127.0.0.1');
      await alice.connect(host: '127.0.0.1', port: host.listeningPort!);
      await until(() => alice.sessionEnded);
      expect(alice.status, ChatStatus.offline);
      expect(alice.groupId, previousGroup);
      expect(texts(alice).single.text, 'Old session');
      expect(host.participants.length, 1);
      await expectLater(alice.send(old), throwsStateError);
      alice.resetSession();
      await join(alice);
      expect(alice.groupId, isNot(previousGroup));
      expect(texts(alice), isEmpty);
      await expectLater(alice.send(old), throwsStateError);
    },
  );

  test('host departure explicitly ends a connected client session', () async {
    await join(alice);
    await host.close();
    await until(() => alice.sessionEnded);
    expect(alice.error, contains('host ended'));
    expect(alice.status, ChatStatus.offline);
  });

  test(
    'new participants do not receive conversations from before they joined',
    () async {
      await host.sendText('Before join');
      await join(alice);
      expect(texts(alice), isEmpty);
      await host.sendText('After join');
      await until(() => texts(alice).length == 1);
      expect(texts(alice).single.sequence, 2);
    },
  );

  test(
    'cancelling a handshake cannot overwrite a subsequent connection',
    () async {
      final silent = await ServerSocket.bind('127.0.0.1', 0);
      final sockets = <Socket>[];
      silent.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {});
      });
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
        await silent.close();
      });
      await alice.connect(host: '127.0.0.1', port: silent.port);
      expect(alice.status, ChatStatus.connecting);
      await alice.close();
      await join(alice);
      await alice.sendText('Only the new socket is active');
      expect(texts(host).single.text, 'Only the new socket is active');
    },
  );
}
