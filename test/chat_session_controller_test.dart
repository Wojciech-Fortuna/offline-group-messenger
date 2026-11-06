import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_connectivity/offline_connectivity.dart';
import 'package:offline_group_messenger/core/messaging/chat_session_controller.dart';
import 'package:offline_group_messenger/core/messaging/tcp_message_transport.dart';
import 'package:offline_group_messenger/core/models/chat_message.dart';

class ControlledTransport extends TcpMessageTransport {
  int connects = 0;
  int starts = 0;
  int closes = 0;
  String? group;
  final requests = <ChatMessage>[];
  final results = <Completer<void>>[];
  @override
  String? get groupId => group;
  @override
  Future<void> connect({required String host, required int port}) async {
    connects++;
    group = 'original';
    selfId = 'self';
    status = ChatStatus.ready;
    notifyListeners();
  }

  @override
  Future<void> startHost({
    required int port,
    String address = '0.0.0.0',
  }) async {
    starts++;
    group = 'host-session';
    status = ChatStatus.ready;
    notifyListeners();
  }

  @override
  Future<void> close() async {
    closes++;
    if (group == 'host-session') sessionEnded = true;
    status = ChatStatus.offline;
    notifyListeners();
  }

  @override
  void resetSession() {
    group = null;
    super.resetSession();
  }

  @override
  ChatMessage createMessage(String text) => ChatMessage(
    id: '${requests.length + 1}',
    groupId: group!,
    senderId: selfId!,
    text: text,
    sentAt: DateTime(2026),
  );
  @override
  Future<void> send(ChatMessage message) {
    requests.add(message);
    final result = Completer<void>();
    results.add(result);
    return result.future;
  }
}

const connected = GroupConnectionState(
  status: GroupStatus.connected,
  hostAddress: '192.168.88.1',
);
const hosting = GroupConnectionState(
  status: GroupStatus.connected,
  hostAddress: '192.168.88.1',
  isHost: true,
);

void main() {
  late ControlledTransport transport;
  late ChatSessionController session;
  setUp(() {
    transport = ControlledTransport();
    session = ChatSessionController(transport: transport);
  });
  tearDown(() => session.dispose());

  test(
    'duplicate native snapshots do not restart; restored network resumes once',
    () {
      session.updateConnection(connected, displayName: 'Alice');
      session.updateConnection(connected, displayName: 'Alice');
      expect(transport.connects, 1);
      session.draft = 'Keep this';
      session.updateConnection(
        const GroupConnectionState(),
        displayName: 'Alice',
      );
      expect(transport.closes, 1);
      expect(session.draft, 'Keep this');
      expect(session.sessionEnded, isFalse);
      session.updateConnection(connected, displayName: 'Alice');
      expect(transport.connects, 2);
      expect(session.draft, 'Keep this');
    },
  );

  test('host network loss ends session until explicit new chat', () {
    session.updateConnection(hosting, displayName: 'Host');
    expect(transport.starts, 1);
    session.updateConnection(const GroupConnectionState(), displayName: 'Host');
    session.updateConnection(hosting, displayName: 'Host');
    expect(session.sessionEnded, isTrue);
    expect(transport.starts, 1);
    session.retry();
    expect(transport.starts, 1);
    session.startNewChat();
    expect(transport.starts, 2);
  });

  test(
    'manual leave pauses reconnect and explicit rejoin preserves the session',
    () async {
      session.updateConnection(connected, displayName: 'Alice');
      session.draft = 'Keep after leaving';
      await session.leave();
      session.updateConnection(
        const GroupConnectionState(),
        displayName: 'Alice',
      );
      session.updateConnection(connected, displayName: 'Alice');
      expect(transport.connects, 1);
      expect(session.sessionEnded, isFalse);
      session.retry();
      expect(transport.connects, 1);
      session.resumeJoining();
      session.updateConnection(connected, displayName: 'Alice');
      expect(transport.connects, 2);
      expect(session.draft, 'Keep after leaving');
      expect(transport.groupId, 'original');
    },
  );

  test(
    'late send failure cannot reappear after explicit session reset',
    () async {
      session.updateConnection(connected, displayName: 'Alice');
      session.draft = 'Old send';
      final send = session.sendDraft();
      expect(session.sending, isTrue);
      session.startNewChat();
      session.draft = 'New draft';
      transport.results.single.completeError(StateError('Old socket failed'));
      await send;
      expect(session.messages, isEmpty);
      expect(session.sendError, isNull);
      expect(session.draft, 'New draft');
    },
  );

  test('retrying failed composer keeps request identity', () async {
    session.updateConnection(connected, displayName: 'Alice');
    session.draft = 'Retry me';
    final first = session.sendDraft();
    transport.results.last.completeError(TimeoutException('No echo'));
    await first;
    expect(session.messages.single.delivery, DeliveryState.failed);
    final retry = session.sendDraft();
    expect(transport.requests.last, same(transport.requests.first));
    expect(session.messages.single.delivery, DeliveryState.pending);
    transport.results.last.completeError(TimeoutException('Still no echo'));
    await retry;
    expect(session.draft, 'Retry me');
    expect(session.messages.length, 1);
  });

  test('role changes cannot silently migrate a client session into a host', () {
    session.updateConnection(connected, displayName: 'Alice');
    session.updateConnection(
      const GroupConnectionState(),
      displayName: 'Alice',
    );
    session.updateConnection(hosting, displayName: 'Alice');
    expect(session.sessionEnded, isTrue);
    expect(transport.starts, 0);
  });

  test(
    'changed address cancels the old connection attempt before retrying',
    () {
      session.updateConnection(connected, displayName: 'Alice');
      transport.status = ChatStatus.connecting;
      session.updateConnection(
        const GroupConnectionState(
          status: GroupStatus.connected,
          hostAddress: '192.168.99.1',
        ),
        displayName: 'Alice',
      );
      expect(transport.closes, 1);
      expect(transport.connects, 2);
    },
  );
}
