import 'package:flutter_test/flutter_test.dart';
import 'package:offline_connectivity/offline_connectivity.dart';
import 'package:offline_group_messenger/core/messaging/chat_session_controller.dart';
import 'package:offline_group_messenger/core/messaging/tcp_message_transport.dart';
import 'session_recovery_test.dart' show until, texts;

GroupInvitation invitation(String token) => GroupInvitation.fromMap({
  'app': 'offline-group-messenger',
  'version': 2,
  'transport': 'wifi-direct',
  'networkName': 'DIRECT-ab-Private',
  'passphrase': 'password-123',
  'privateGroup': true,
  'admissionToken': token,
});

void main() {
  late ChatSessionController host;
  late String initialToken;
  final clients = <ChatSessionController>[];
  setUp(() async {
    host = ChatSessionController();
    initialToken = host.configureGroup(privateGroup: true)!;
    await host.transport.startHost(port: 0, address: '127.0.0.1');
  });
  tearDown(() {
    for (final client in clients) {
      client.dispose();
    }
    clients.clear();
    host.dispose();
  });
  Future<ChatSessionController> join({String? token}) async {
    final client = ChatSessionController();
    clients.add(client);
    client.prepareJoin(invitation: invitation(token ?? initialToken));
    await client.transport.connect(
      host: '127.0.0.1',
      port: host.transport.listeningPort!,
    );
    await until(() => client.status == ChatStatus.ready || client.sessionEnded);
    return client;
  }

  Future<void> reconnect(ChatSessionController client) async {
    client.prepareJoin(invitation: client.rememberedPrivateGroup);
    await client.transport.connect(
      host: '127.0.0.1',
      port: host.transport.listeningPort!,
    );
    await until(() => client.status == ChatStatus.ready || client.sessionEnded);
  }

  test(
    'successful NFC membership is remembered; leave/rejoin preserves identity and history',
    () async {
      final alice = await join();
      final id = alice.selfId;
      final remembered = alice.rememberedPrivateGroup;
      expect(remembered, isNotNull);
      await alice.transport.sendText('Keep me');
      alice.draft = 'Draft';
      await alice.leave();
      expect(alice.rememberedPrivateGroup, same(remembered));
      await host.transport.sendText('While away');
      await reconnect(alice);
      expect(alice.selfId, id);
      expect(texts(alice.transport).map((m) => m.text), [
        'Keep me',
        'While away',
      ]);
      expect(alice.draft, 'Draft');
      alice.beginNewSession();
      expect(alice.rememberedPrivateGroup, isNull);
    },
  );

  test(
    'online removal revokes resume and copied invitations; other members and fresh NFC work',
    () async {
      final alice = await join();
      final bob = await join();
      final bobId = bob.selfId;
      await alice.transport.sendText('Before removal');
      final aliceId = alice.selfId!;
      String? rotated;
      await host.removePrivateMember(
        aliceId,
        rotateInvitation: (previous, next) async {
          expect(previous, initialToken);
          rotated = next;
        },
      );
      await until(() => alice.sessionEnded);
      expect(alice.transport.membershipRevoked, isTrue);
      expect(alice.rememberedPrivateGroup, isNull);
      expect(host.members.any((p) => p.id == aliceId), isFalse);
      expect(texts(alice.transport).single.text, 'Before removal');
      await host.transport.sendText('After removal');
      await until(() => texts(bob.transport).length == 2);
      expect(texts(alice.transport).length, 1);
      final stale = await join();
      expect(stale.sessionEnded, isTrue);
      expect(stale.rememberedPrivateGroup, isNull);
      await bob.leave();
      await reconnect(bob);
      expect(bob.selfId, bobId);
      expect(bob.status, ChatStatus.ready);
      final newlyInvited = await join(token: rotated);
      expect(newlyInvited.status, ChatStatus.ready);
    },
  );

  test(
    'offline member is removable and cannot resume after a missed removal notification',
    () async {
      final alice = await join();
      final id = alice.selfId!;
      await alice.leave();
      await until(() => host.participants.length == 1);
      expect(host.members.any((p) => p.id == id), isTrue);
      await host.removePrivateMember(id, rotateInvitation: (_, _) async {});
      // Offline clients learn revocation on their next authenticated resume.
      expect(alice.rememberedPrivateGroup, isNotNull);
      await reconnect(alice);
      expect(alice.sessionEnded, isTrue);
      expect(alice.transport.membershipRevoked, isTrue);
      expect(alice.rememberedPrivateGroup, isNull);
      expect(host.participants.length, 1);
    },
  );

  test(
    'native rotation failure leaves membership and admission unchanged',
    () async {
      final alice = await join();
      await expectLater(
        host.removePrivateMember(
          alice.selfId!,
          rotateInvitation: (_, _) async {
            throw StateError('Native rotation failed');
          },
        ),
        throwsStateError,
      );
      expect(host.transport.hostAdmissionToken, initialToken);
      expect(host.members.length, 2);
      expect(host.removingMember, isFalse);
      await alice.transport.sendText('Still a member');
      expect(texts(host.transport).single.text, 'Still a member');
    },
  );

  test(
    'rotation completing after a new session cannot remove new members',
    () async {
      final alice = await join();
      await expectLater(
        host.removePrivateMember(
          alice.selfId!,
          rotateInvitation: (_, _) async {
            host.configureGroup(privateGroup: true);
          },
        ),
        throwsStateError,
      );
      expect(host.transport.hostAdmissionToken, isNot(initialToken));
      expect(host.removingMember, isFalse);
      expect(host.members, isEmpty);
    },
  );
}
