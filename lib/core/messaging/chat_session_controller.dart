import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:offline_connectivity/offline_connectivity.dart';

import '../models/chat_message.dart';
import '../models/participant.dart';
import 'tcp_message_transport.dart';

enum DeliveryState { pending, confirmed, failed }

class SessionMessage {
  SessionMessage(this.message, this.delivery, {this.failure});
  final ChatMessage message;
  DeliveryState delivery;
  String? failure;
}

/// Conversation/UI state outlives sockets and navigation. All storage is in memory.
class ChatSessionController extends ChangeNotifier {
  ChatSessionController({TcpMessageTransport? transport})
    : transport = transport ?? TcpMessageTransport() {
    this.transport.addListener(_changed);
    _incoming = this.transport.incoming.listen(_receive);
  }

  final TcpMessageTransport transport;
  late final StreamSubscription<ChatMessage> _incoming;
  final _history = <ChatMessage>[];
  final _outbox = <String, SessionMessage>{};
  GroupConnectionState _connection = const GroupConnectionState();
  String? _connectionKey;
  bool? _sessionRole;
  ChatMessage? _draftRequest;
  bool _left = false;
  bool _disposed = false;
  int _generation = 0;
  String draft = '';
  String? sendError;

  ChatStatus get status => transport.status;
  String? get selfId => transport.selfId;
  String? get error => transport.error;
  String? get historyWarning => transport.historyWarning;
  bool get sessionEnded => _left || transport.sessionEnded;
  bool get hasConversation => transport.groupId != null || _history.isNotEmpty;
  bool get sending =>
      _outbox.values.any((e) => e.delivery == DeliveryState.pending);
  bool get networkConnected =>
      _connection.status == GroupStatus.connected &&
      _connection.hostAddress != null;
  List<Participant> get participants => transport.participants;
  List<SessionMessage> get messages => [
    for (final message in _history)
      SessionMessage(message, DeliveryState.confirmed),
    ..._outbox.values,
  ];

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _receive(ChatMessage message) {
    if (_disposed || message.groupId != transport.groupId) return;
    _outbox.remove(message.id);
    if (!_history.any((m) => m.id == message.id)) {
      final index = message.sequence == 0
          ? -1
          : _history.indexWhere((m) => m.sequence > message.sequence);
      if (index < 0) {
        _history.add(message);
      } else {
        _history.insert(index, message);
      }
      if (_history.length > TcpMessageTransport.historyLimit) {
        _history.removeAt(0);
      }
    }
    final request = _draftRequest;
    if (request != null && '${request.senderId}:${request.id}' == message.id) {
      if (draft.trim() == request.text) draft = '';
      _draftRequest = null;
      sendError = null;
    }
    _changed();
  }

  /// Native loss suspends clients; the next connected snapshot resumes them.
  void updateConnection(
    GroupConnectionState connection, {
    required String displayName,
  }) {
    _connection = connection;
    transport.displayName = displayName;
    final key = networkConnected
        ? '${connection.isHost}:${connection.hostAddress}'
        : null;
    if (key == _connectionKey) return;
    final previousKey = _connectionKey;
    _connectionKey = key;
    if (key != null && previousKey != null) {
      // Cancel a handshake/socket for an obsolete address before starting another.
      unawaited(transport.close());
    }
    if (key == null) {
      unawaited(transport.close());
    } else if (!sessionEnded) {
      if (transport.groupId != null && _sessionRole != connection.isHost) {
        // A native role change does not migrate a conversation to a new host.
        _left = true;
        unawaited(transport.close());
      } else {
        _sessionRole = connection.isHost;
        retry();
      }
    }
    _changed();
  }

  void retry() {
    if (!networkConnected || sessionEnded || status == ChatStatus.connecting) {
      return;
    }
    if (_connection.isHost) {
      // A host whose listener existed must start a new session explicitly.
      if (transport.groupId != null) return;
      unawaited(
        transport.startHost(
          port: TcpMessageTransport.defaultPort,
          address: _connection.hostAddress!,
        ),
      );
    } else {
      unawaited(
        transport.connect(
          host: _connection.hostAddress!,
          port: TcpMessageTransport.defaultPort,
        ),
      );
    }
  }

  /// Explicit user action; never invoked as a side effect of reconnecting.
  void beginNewSession() {
    _generation++;
    _history.clear();
    _outbox.clear();
    draft = '';
    _draftRequest = null;
    sendError = null;
    _left = false;
    _connectionKey = null;
    _sessionRole = null;
    transport.resetSession();
    _changed();
  }

  void startNewChat() {
    beginNewSession();
    _sessionRole = _connection.isHost;
    _connectionKey = networkConnected
        ? '${_connection.isHost}:${_connection.hostAddress}'
        : null;
    retry();
  }

  Future<void> leave() async {
    _left = true;
    await transport.close();
    _changed();
  }

  Future<void> sendDraft() async {
    if (draft.trim().isEmpty ||
        sending ||
        status != ChatStatus.ready ||
        sessionEnded) {
      return;
    }
    var request = _draftRequest;
    if (request == null || request.text != draft.trim()) {
      if (_outbox.length >= 50) {
        sendError =
            'Too many unconfirmed messages. Retry existing messages first.';
        _changed();
        return;
      }
      request = transport.createMessage(draft);
      _draftRequest = request;
    }
    final id = '${request.senderId}:${request.id}';
    final entry = _outbox.putIfAbsent(
      id,
      () => SessionMessage(request!, DeliveryState.pending),
    );
    await _attempt(id, entry);
  }

  Future<void> retryMessage(String id) async {
    final entry = _outbox[id];
    if (entry == null ||
        sending ||
        status != ChatStatus.ready ||
        sessionEnded) {
      return;
    }
    await _attempt(id, entry);
  }

  Future<void> _attempt(String id, SessionMessage entry) async {
    final generation = _generation;
    entry.delivery = DeliveryState.pending;
    entry.failure = null;
    sendError = null;
    _changed();
    try {
      await transport.send(entry.message);
      if (_disposed || generation != _generation) return;
      entry.delivery = DeliveryState.confirmed;
    } catch (e) {
      if (_disposed || generation != _generation || !_outbox.containsKey(id)) {
        return;
      }
      entry.delivery = DeliveryState.failed;
      entry.failure = e is StateError
          ? e.message.toString()
          : 'Host confirmation not received. Retry this message after reconnecting.';
      sendError = entry.failure;
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _incoming.cancel();
    transport.removeListener(_changed);
    transport.dispose();
    super.dispose();
  }
}
