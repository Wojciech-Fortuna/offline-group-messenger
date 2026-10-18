import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_group_messenger/core/messaging/tcp_message_transport.dart';

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for chat state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
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
    expect(host.status, ChatStatus.ready);
  });
  tearDown(() {
    alice.dispose();
    bob.dispose();
    host.dispose();
  });

  Future<void> join(TcpMessageTransport client) async {
    await client.connect(host: '127.0.0.1', port: host.listeningPort!);
    await until(() => client.status == ChatStatus.ready);
  }

  test(
    'host and two clients exchange Unicode messages once with assigned identities',
    () async {
      await join(alice);
      await join(bob);
      await until(() => alice.participants.length == 3);
      expect(bob.participants.map((p) => p.displayName), [
        'Host',
        'Alice',
        'Bob',
      ]);
      await alice.sendText('Cześć 👋\nsecond line');
      await until(() => bob.messages.any((m) => m.senderId == alice.selfId));
      await bob.sendText('Hi Alice');
      await host.sendText('Welcome');
      await until(
        () =>
            alice.messages.where((m) => m.senderId.isNotEmpty).length == 3 &&
            bob.messages.where((m) => m.senderId.isNotEmpty).length == 3,
      );
      final expected = host.messages
          .where((m) => m.senderId.isNotEmpty)
          .map((m) => m.id)
          .toList();
      for (final client in [alice, bob]) {
        final messages = client.messages
            .where((m) => m.senderId.isNotEmpty)
            .toList();
        expect(messages.map((m) => m.id), expected);
        expect(messages.first.text, 'Cześć 👋\nsecond line');
        expect(messages.first.senderName, 'Alice');
      }
    },
  );

  test(
    'participant leave updates roster; host loss disables sending and supports retry',
    () async {
      await join(alice);
      await join(bob);
      await bob.close();
      await until(() => alice.participants.length == 2);
      expect(alice.messages.last.text, 'Bob left');
      await host.close();
      await until(() => alice.status == ChatStatus.offline);
      expect(alice.error, contains('Host disconnected'));
      await expectLater(alice.sendText('Lost'), throwsStateError);
      await host.startHost(port: 0, address: '127.0.0.1');
      await join(alice);
      await alice.sendText('Rejoined');
      expect(host.messages.last.text, 'Rejoined');
    },
  );

  test('malformed and oversized clients cannot take down the host', () async {
    await join(alice);
    for (final data in [
      utf8.encode('{bad json}\n'),
      List.filled(TcpMessageTransport.maxFrameBytes + 1, 65),
    ]) {
      final socket = await Socket.connect('127.0.0.1', host.listeningPort!);
      socket.add(data);
      await socket.drain<void>().timeout(const Duration(seconds: 3));
      socket.destroy();
      expect(host.status, ChatStatus.ready);
    }
    await alice.sendText('Still here');
    expect(host.messages.last.text, 'Still here');
    await expectLater(alice.sendText(' '), throwsFormatException);
    await expectLater(alice.sendText('x' * 2001), throwsFormatException);
  });

  test(
    'split and coalesced frames, duplicate sends and spoofed identity',
    () async {
      final socket = await Socket.connect('127.0.0.1', host.listeningPort!);
      socket.listen((_) {});
      addTearDown(socket.destroy);
      final hello = utf8.encode(
        '${jsonEncode({'v': 1, 'type': 'hello', 'name': 'Raw'})}\n',
      );
      socket.add(hello.sublist(0, 8));
      await socket.flush();
      socket.add(hello.sublist(8));
      await until(() => host.participants.length == 2);
      final frame =
          '${jsonEncode({'v': 1, 'type': 'send', 'id': 'request1', 'text': 'Hello', 'senderId': host.selfId})}\n';
      socket.add(utf8.encode('$frame$frame'));
      await until(() => host.messages.any((m) => m.text == 'Hello'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final messages = host.messages.where((m) => m.text == 'Hello');
      expect(messages.length, 1);
      expect(messages.single.senderId, isNot(host.selfId));
      expect(messages.single.senderName, 'Raw');
    },
  );

  test('closing while host starts prevents a stale listener', () async {
    final pending = bob.startHost(port: 0, address: '127.0.0.1');
    await bob.close();
    await pending;
    expect(bob.status, ChatStatus.offline);
    expect(bob.listeningPort, isNull);
  });
}
