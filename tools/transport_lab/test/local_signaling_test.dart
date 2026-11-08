import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_transport_lab/local_signaling.dart';

void main() {
  test(
    'silent signaling server cannot leave setup pending indefinitely',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final subscription = server.listen(sockets.add);
      final client = LabSignaling();
      addTearDown(() async {
        client.close();
        for (final socket in sockets) {
          socket.destroy();
        }
        await subscription.cancel();
        await server.close();
      });
      await expectLater(
        client.connect(
          '127.0.0.1',
          '127.0.0.1',
          port: server.port,
          handshakeTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
  test(
    'decodes fragmented frames and rejects invalid/truncated/oversized input',
    () async {
      final bytes = utf8.encode(
        '{"v":1,"type":"ping"}\n{"v":1,"type":"end"}\n',
      );
      expect(
        await readFrames(Stream.fromIterable(bytes.map((b) => [b]))).toList(),
        [
          {'v': 1, 'type': 'ping'},
          {'v': 1, 'type': 'end'},
        ],
      );
      for (final invalid in [
        utf8.encode('{"v":2,"type":"ping"}\n'),
        utf8.encode('{"v":1,"type":"ping"}'),
        List.filled(maxFrameBytes + 1, 32),
        [0xff, 10],
      ]) {
        await expectLater(
          readFrames(Stream.value(invalid)).toList(),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'three-party local relay pins sender ID and forwards only to selected peer',
    () async {
      final relay = LabRelay();
      await relay.start(InternetAddress.loopbackIPv4, port: 0);
      final sockets = <Socket>[];
      final received = <List<Map<String, dynamic>>>[];
      final subscriptions = <StreamSubscription>[];
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        await relay.close();
      });
      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Local relay response timed out');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      for (var i = 0; i < 3; i++) {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          relay.port,
        );
        final messages = <Map<String, dynamic>>[];
        sockets.add(socket);
        received.add(messages);
        subscriptions.add(readFrames(socket).listen(messages.add));
      }
      await until(
        () => received.every(
          (messages) => messages.any(
            (m) => m['type'] == 'peers' && (m['ids'] as List).length == 3,
          ),
        ),
      );
      final ids = received
          .map(
            (messages) =>
                messages.firstWhere((m) => m['type'] == 'welcome')['id'],
          )
          .toList();
      writeFrame(sockets[1], {
        'type': 'offer',
        'to': ids[2],
        'from': 'forged',
        'call': 'test',
        'sdp': 'test SDP',
      });
      await until(() => received[2].any((m) => m['type'] == 'offer'));
      expect(
        received[2].singleWhere((m) => m['type'] == 'offer')['from'],
        ids[1],
      );
      expect(received[0].where((m) => m['type'] == 'offer'), isEmpty);
      sockets[1].destroy();
      await until(
        () =>
            (received[2].lastWhere((m) => m['type'] == 'peers')['ids'] as List)
                .length ==
            2,
      );
    },
  );
}
