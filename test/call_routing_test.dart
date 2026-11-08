import 'package:flutter_test/flutter_test.dart';
import 'package:offline_group_messenger/core/messaging/tcp_message_transport.dart';
import 'tcp_message_transport_test.dart' show until;

void main() {
  test(
    'call relay directs only to selected peer and leaves history untouched',
    () async {
      final host = TcpMessageTransport();
      final a = TcpMessageTransport();
      final b = TcpMessageTransport();
      addTearDown(() {
        a.dispose();
        b.dispose();
        host.dispose();
      });
      await host.startHost(port: 0, address: '127.0.0.1');
      for (final client in [a, b]) {
        await client.connect(host: '127.0.0.1', port: host.listeningPort!);
      }
      await until(
        () => a.participants.length == 3 && b.status == ChatStatus.ready,
      );
      final delivered = <Map<String, dynamic>>[];
      final leaked = <Map<String, dynamic>>[];
      b.callFrames.listen(delivered.add);
      host.callFrames.listen(leaked.add);
      a.sendCall(b.selfId!, 'opaque-signed-payload');
      await until(() => delivered.isNotEmpty);
      expect(delivered.single, {
        'from': a.selfId,
        'token': 'opaque-signed-payload',
      });
      expect(leaked, isEmpty);
      expect(b.messages.where((m) => m.senderId.isNotEmpty), isEmpty);
      await a.sendText('ordinary chat');
      await until(() => b.messages.any((m) => m.text == 'ordinary chat'));
    },
  );
  test(
    'legacy host capability disables calls while chat remains usable',
    () async {
      final host = TcpMessageTransport(callCapable: false);
      final client = TcpMessageTransport();
      addTearDown(() {
        client.dispose();
        host.dispose();
      });
      await host.startHost(port: 0, address: '127.0.0.1');
      await client.connect(host: '127.0.0.1', port: host.listeningPort!);
      await until(() => client.status == ChatStatus.ready);
      expect(client.supportsCalls, isFalse);
      expect(() => client.sendCall(host.selfId!, 'token'), throwsStateError);
      await client.sendText('compatible');
      await until(() => host.messages.any((m) => m.text == 'compatible'));
    },
  );
}
