import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_audio/offline_audio.dart';
import 'package:offline_group_messenger/core/calling/call_controller.dart';
import 'package:offline_group_messenger/core/contacts/contact_repository.dart';
import 'package:offline_group_messenger/core/messaging/tcp_message_transport.dart';
import 'tcp_message_transport_test.dart' show until;

// Native signature/pinning is tested in ContactBookTest. This fake records opaque
// authenticated tokens so state-machine tests can replay but cannot edit them.
class CallContactsFake extends ContactRepository {
  CallContactsFake(this.self, this.other);
  final String self, other;
  static final tokens = <String, Map<String, dynamic>>{};
  final issued = <String>[];
  bool blocked = false;
  Completer<void>? acceptedGate;
  @override
  Future<ContactSnapshot> load() async => ContactSnapshot(self, [
    SavedContact(
      id: other,
      name: 'Saved contact',
      trust: blocked ? ContactTrust.blocked : ContactTrust.verified,
    ),
  ]);
  @override
  Future<String> signCall(Map<String, dynamic> body) async {
    if (body['kind'] == 'accepted') await acceptedGate?.future;
    if (blocked) throw StateError('Blocked');
    final token = 'signed-${tokens.length}';
    tokens[token] = {...body, 'from': self};
    issued.add(token);
    return token;
  }

  @override
  Future<Map<String, dynamic>> verifyCall(String token) async {
    final body = tokens[token];
    if (blocked ||
        body == null ||
        body['from'] != other ||
        body['to'] != self) {
      throw StateError('Untrusted');
    }
    return {...body};
  }
}

class CallMediaFake extends LocalAudioSession {
  CallMediaFake(
    Future<void> Function(Map<String, dynamic>) signal,
    void Function(String) state,
    void Function(String) error,
  ) : super(onSignal: signal, onState: state, onError: error);
  bool started = false;
  bool closed = false;
  @override
  Future<void> start(P2pNetwork network, {required bool initiator}) async {
    started = true;
    onState('active');
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  late TcpMessageTransport host, client;
  late CallController a, b;
  late CallContactsFake ar, br;
  late List<CallMediaFake> am, bm;
  setUp(() async {
    host = TcpMessageTransport();
    client = TcpMessageTransport();
    ar = CallContactsFake('a' * 64, 'b' * 64);
    br = CallContactsFake('b' * 64, 'a' * 64);
    am = [];
    bm = [];
    Future<P2pNetwork> network() async => P2pNetwork(
      host: '192.168.49.1',
      local: '192.168.49.2',
      prefix: 24,
      isHost: false,
    );
    a = CallController(
      host,
      contacts: ar,
      network: network,
      mediaFactory: (signal, state, error) {
        final media = CallMediaFake(signal, state, error);
        am.add(media);
        return media;
      },
    );
    b = CallController(
      client,
      contacts: br,
      network: network,
      mediaFactory: (signal, state, error) {
        final media = CallMediaFake(signal, state, error);
        bm.add(media);
        return media;
      },
    );
    await host.startHost(port: 0, address: '127.0.0.1');
    await client.connect(host: '127.0.0.1', port: host.listeningPort!);
    await until(() => a.peerFor(br.self) != null && b.peerFor(ar.self) != null);
  });
  tearDown(() {
    a.dispose();
    b.dispose();
    host.dispose();
    client.dispose();
  });
  test(
    'ringing does not capture; answer opens media; hang-up preserves chat',
    () async {
      await a.dial(br.self);
      await until(() => b.state == 'incoming');
      expect(am, isEmpty);
      expect(bm, isEmpty);
      await b.answer();
      await until(() => a.state == 'active');
      expect(am.single.started, isTrue);
      expect(bm.single.started, isTrue);
      await a.end('Call ended');
      await until(() => !b.hasCall);
      expect(am.single.closed, isTrue);
      expect(bm.single.closed, isTrue);
      await client.sendText('Chat still works');
      await until(() => host.messages.any((m) => m.text == 'Chat still works'));
      expect(host.status, ChatStatus.ready);
    },
  );
  test('replayed invite and unknown signatures cannot ring again', () async {
    await a.dial(br.self);
    await until(() => b.state == 'incoming');
    final token = ar.issued.lastWhere(
      (t) => CallContactsFake.tokens[t]!['kind'] == 'invite',
    );
    await b.end('Declined', kind: 'declined');
    await until(() => !a.hasCall);
    host.sendCall(client.selfId!, token);
    host.sendCall(client.selfId!, 'forged');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(b.hasCall, isFalse);
    expect(am, isEmpty);
    expect(bm, isEmpty);
  });
  test('cancel during delayed answer cannot start caller microphone', () async {
    br.acceptedGate = Completer<void>();
    await a.dial(br.self);
    await until(() => b.state == 'incoming');
    final answer = b.answer();
    await until(() => bm.isNotEmpty);
    await a.end('Cancelled', kind: 'cancel');
    await until(() => !b.hasCall);
    br.acceptedGate!.complete();
    await answer;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(am, isEmpty);
    expect(bm.single.closed, isTrue);
    expect(a.hasCall, isFalse);
  });
  test('blocking contact invalidates presence and ends active call', () async {
    await a.dial(br.self);
    await until(() => b.state == 'incoming');
    ar.blocked = true;
    await a.refreshContacts();
    expect(a.hasCall, isFalse);
    expect(a.peerFor(br.self), isNull);
  });
  test('simultaneous invites converge to one call without capture', () async {
    await Future.wait([a.dial(br.self), b.dial(ar.self)]);
    await until(
      () =>
          b.state == 'incoming' &&
          (a.state == 'outgoing' || a.state == 'ringing'),
    );
    expect(a.callId, b.callId);
    expect(am, isEmpty);
    expect(bm, isEmpty);
  });
  test(
    'foreground return renews mutual presence and permits another call',
    () async {
      await a.dial(br.self);
      await until(() => b.state == 'incoming');
      await b.answer();
      await until(() => a.state == 'active');
      b.foreground(false);
      await until(() => !a.hasCall && b.peerFor(ar.self) == null);
      b.foreground(true);
      await until(
        () => a.peerFor(br.self) != null && b.peerFor(ar.self) != null,
      );
      await b.dial(ar.self);
      await until(() => a.state == 'incoming');
      expect(am.length, 1);
      expect(bm.length, 1);
    },
  );
}
