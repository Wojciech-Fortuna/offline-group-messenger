import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_group_messenger/core/messaging/tcp_message_transport.dart';
import 'session_recovery_test.dart' show until, texts, LostConfirmationProxy;

/// A recipient whose app receipts are controlled independently of TCP delivery.
class ReceiptPeer {
  ReceiptPeer(this.socket);
  final Socket socket;
  final frames = <Map<String, dynamic>>[];
  String get id =>
      frames.firstWhere((f) => f['type'] == 'welcome')['selfId'] as String;

  static Future<ReceiptPeer> join(int port, String name) async {
    final peer = ReceiptPeer(await Socket.connect('127.0.0.1', port));
    peer.socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => peer.frames.add(jsonDecode(line) as Map<String, dynamic>),
          onError: (Object _) {},
        );
    peer.send({'type': 'hello', 'name': name, 'after': 0});
    await until(() => peer.frames.any((f) => f['type'] == 'synced'));
    return peer;
  }

  void send(Map<String, Object?> frame) => socket.add(
    utf8.encode(
      '${jsonEncode({'v': TcpMessageTransport.protocolVersion, ...frame})}\n',
    ),
  );
  Future<void> receipt(
    String id,
    int sequence, {
    String? claimedIdentity,
  }) async {
    send({
      'type': 'received',
      'id': id,
      'sequence': sequence,
      if (claimedIdentity != null) 'participantId': claimedIdentity,
    });
    // A pong after the receipt establishes that the host processed it.
    final pongs = frames.where((f) => f['type'] == 'pong').length;
    send({'type': 'ping'});
    await until(() => frames.where((f) => f['type'] == 'pong').length > pongs);
  }
}

void main() {
  late TcpMessageTransport host;
  final clients = <TcpMessageTransport>[];
  final raw = <ReceiptPeer>[];
  setUp(() async {
    host = TcpMessageTransport()..displayName = 'Host';
    await host.startHost(port: 0, address: '127.0.0.1');
  });
  tearDown(() {
    for (final peer in raw) {
      peer.socket.destroy();
    }
    for (final client in clients) {
      client.dispose();
    }
    raw.clear();
    clients.clear();
    host.dispose();
  });
  Future<ReceiptPeer> peer(String name) async {
    final value = await ReceiptPeer.join(host.listeningPort!, name);
    raw.add(value);
    return value;
  }

  Future<TcpMessageTransport> client() async {
    final value = TcpMessageTransport();
    clients.add(value);
    await value.connect(host: '127.0.0.1', port: host.listeningPort!);
    await until(() => value.status == ChatStatus.ready);
    return value;
  }

  test(
    'host checks require real, identity-bound receipts, with fixed targets',
    () async {
      final bob = await peer('Bob');
      final carol = await peer('Carol');
      await host.sendText('Delivery stages');
      final message = texts(host).single;
      expect(host.deliveryFor(message.id)!.checks, 1);
      await bob.receipt(message.id, message.sequence + 1);
      expect(host.deliveryFor(message.id)!.checks, 1);
      final late = await peer('Late joiner');
      await late.receipt(
        message.id,
        message.sequence,
        claimedIdentity: carol.id,
      );
      expect(host.deliveryFor(message.id)!.checks, 1);
      await bob.receipt(
        message.id,
        message.sequence,
        claimedIdentity: carol.id,
      );
      expect(host.deliveryFor(message.id)!.checks, 2);
      expect(host.deliveryFor(message.id)!.received, {bob.id});
      await bob.receipt(message.id, message.sequence);
      expect(host.deliveryFor(message.id)!.checks, 2);
      await carol.receipt(message.id, message.sequence);
      expect(host.deliveryFor(message.id)!.checks, 3);
      expect(host.deliveryFor(message.id)!.recipients.map((p) => p.id), [
        bob.id,
        carol.id,
      ]);
    },
  );

  test(
    'sender resumes receipt updates without replay; retry retains original targets',
    () async {
      final alice = await client();
      final bob = await peer('Bob');
      final carol = await peer('Carol');
      final request = alice.createMessage('Client send');
      await alice.send(request);
      final message = texts(alice).single;
      await until(() => alice.deliveryFor(message.id) != null);
      expect(alice.deliveryFor(message.id)!.checks, 1);
      await bob.receipt(message.id, message.sequence);
      await until(() => alice.deliveryFor(message.id)!.checks == 2);
      // Leaving cannot make the remaining target disappear.
      carol.socket.destroy();
      await until(() => host.participants.length == 3);
      expect(alice.deliveryFor(message.id)!.checks, 2);
      await alice.close();
      await until(() => host.participants.length == 2);
      final late = await peer('New participant');
      await late.receipt(message.id, message.sequence);
      expect(host.deliveryFor(message.id)!.checks, 2);
      // Resume Carol with her stable token and acknowledge the original message.
      final welcome = carol.frames.firstWhere((f) => f['type'] == 'welcome');
      final resumed = ReceiptPeer(
        await Socket.connect('127.0.0.1', host.listeningPort!),
      );
      raw.add(resumed);
      resumed.socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) =>
                resumed.frames.add(jsonDecode(line) as Map<String, dynamic>),
            onError: (Object _) {},
          );
      resumed.send({
        'type': 'hello',
        'name': 'Carol',
        'after': 0,
        'groupId': welcome['groupId'],
        'token': welcome['token'],
      });
      await until(() => resumed.frames.any((f) => f['type'] == 'synced'));
      await resumed.receipt(message.id, message.sequence);
      await alice.connect(host: '127.0.0.1', port: host.listeningPort!);
      await until(() => alice.status == ChatStatus.ready);
      expect(alice.deliveryFor(message.id)!.checks, 3);
      await alice.send(request);
      expect(texts(alice).length, 1);
      expect(alice.deliveryFor(message.id)!.recipients.map((p) => p.id), [
        bob.id,
        carol.id,
      ]);
      expect(late.frames.where((f) => f['type'] == 'delivery'), isEmpty);
    },
  );

  test(
    'recipient replay acknowledges a message lost before it reached the app',
    () async {
      final proxy = await LostConfirmationProxy.start(host.listeningPort!);
      addTearDown(proxy.close);
      final bob = TcpMessageTransport();
      clients.add(bob);
      await bob.connect(host: '127.0.0.1', port: proxy.server.port);
      await until(() => bob.status == ChatStatus.ready);
      await host.sendText('Replay me');
      await proxy.accepted.future;
      final message = texts(host).single;
      expect(host.deliveryFor(message.id)!.checks, 1);
      await until(() => bob.status == ChatStatus.offline);
      await bob.connect(host: '127.0.0.1', port: host.listeningPort!);
      await until(() => host.deliveryFor(message.id)!.checks == 3);
      expect(texts(bob).single.text, 'Replay me');
    },
  );

  test(
    'lost receipt is resent after resume even without message replay',
    () async {
      final gateway = await ServerSocket.bind('127.0.0.1', 0);
      final sockets = <Socket>[];
      var dropped = false;
      gateway.listen((clientSocket) async {
        final hostSocket = await Socket.connect(
          '127.0.0.1',
          host.listeningPort!,
        );
        sockets.addAll([clientSocket, hostSocket]);
        hostSocket.listen(
          clientSocket.add,
          onError: (Object _) {},
          onDone: clientSocket.destroy,
        );
        clientSocket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
                final frame = jsonDecode(line) as Map<String, dynamic>;
                if (frame['type'] == 'received') {
                  dropped = true;
                } else {
                  hostSocket.add(utf8.encode('$line\n'));
                }
              },
              onError: (Object _) {},
              onDone: hostSocket.destroy,
            );
      });
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
        await gateway.close();
      });
      final bob = TcpMessageTransport();
      clients.add(bob);
      await bob.connect(host: '127.0.0.1', port: gateway.port);
      await until(() => bob.status == ChatStatus.ready);
      await host.sendText('Receipt lost');
      await until(() => dropped);
      final message = texts(host).single;
      expect(texts(bob).single.id, message.id);
      expect(host.deliveryFor(message.id)!.checks, 1);
      await bob.close();
      await bob.connect(host: '127.0.0.1', port: host.listeningPort!);
      await until(() => host.deliveryFor(message.id)!.checks == 3);
      expect(texts(bob).length, 1);
    },
  );

  test(
    'no forwarded recipients stays at one; reset and retention bound receipts',
    () async {
      final alice = await client();
      await alice.sendText('Only host');
      final message = texts(host).single;
      await until(() => alice.deliveryFor(message.id) != null);
      expect(alice.deliveryFor(message.id)!.checks, 1);
      expect(alice.deliveryFor(message.id)!.recipients, isEmpty);
      alice.resetSession();
      expect(alice.deliveryFor(message.id), isNull);
      await until(() => host.participants.length == 1);
      for (var i = 0; i < TcpMessageTransport.acceptanceLimit; i++) {
        await host.sendText('Advance $i');
      }
      expect(host.deliveryFor(message.id), isNull);
      expect(host.deliveryFor(texts(host).last.id)!.checks, 1);
      final lastId = texts(host).last.id;
      host.resetSession();
      expect(host.deliveryFor(lastId), isNull);
    },
  );
}
